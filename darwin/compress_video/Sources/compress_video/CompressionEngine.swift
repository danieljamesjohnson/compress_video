import AVFoundation
import AudioToolbox
import CoreMedia
import CoreVideo
import Foundation

/// Builds and drives one `AVAssetReader`/`AVAssetWriter` pipeline per compression job -- the
/// counterpart of Android's `TransformerEngine.kt`.
///
/// Every quantity the writer uses (target dimensions, bitrate, frame rate) comes from a single
/// `SizeGuard.resolve` call; this file performs no scaling arithmetic of its own. Rotation
/// stays metadata (`AVAssetWriterInput.transform`), never baked into pixels via a video
/// composition (03-RESEARCH.md Pattern 2/Pitfall 3) -- `grep -c VideoComposition` on this
/// directory must stay `0`.
///
/// The copy loop runs on a job-scoped serial `DispatchQueue`, never on the `MainActor` Pigeon
/// delivers `startCompress` on (03-RESEARCH.md Pattern 1, the inverse of Android's
/// main-Looper-confined `Transformer`): a concurrent `cancel`/`estimate` call must be able to
/// answer while a job is running. `JobRegistry` access happens only via explicit `MainActor`
/// hops.
///
/// This plan implements the real-encode branch only (D-01's transmux fast path via
/// `AVAssetExportSession` is out of scope here -- a later plan owns it); the never-larger
/// PRE-check (`SizeGuard.Plan.wouldUseOriginal`) still applies, skipping the encode entirely
/// when the resolver already knows it would not help. Audio is passthrough-or-strip only in
/// this plan; a `reencode` request throws a typed `unsupportedInput` error until a later plan
/// implements it.
final class CompressionEngine {
  /// Minimum wall-clock gap between two `onProgress` calls for the same job, mirroring
  /// Android's own poll interval (`TransformerEngine.PROGRESS_POLL_INTERVAL_MS`) even though
  /// this engine derives progress from the copy loop itself rather than polling.
  private static let progressThrottleSeconds: TimeInterval = 0.25

  /// Compresses the media at `inputURL` (already probed as `inputInfo`) per `request`, writing
  /// to a temp file beside `destinationURL` and moving it into place on success -- or copying
  /// the original there instead, on either the pre- or post-check never-larger path. Every
  /// field of the returned message is read from a re-probe of the finished output file via
  /// `Probe`, never from the writer's own settings (03-RESEARCH.md Pitfall analogous to
  /// 02-RESEARCH.md Pitfall 4).
  func compress(
    jobId: String,
    inputURL: URL,
    inputInfo: MediaInfoMessage,
    request: CompressRequestMessage,
    destinationURL: URL,
    onProgress: @escaping (Double) -> Void
  ) async throws -> CompressResultMessage {
    let startedAt = Date()
    let inputBytes = (try? Self.fileSize(of: inputURL)) ?? inputInfo.sizeBytes

    let asset = AVURLAsset(url: inputURL)
    let videoTrack: AVAssetTrack
    let audioTrack: AVAssetTrack?
    do {
      if #available(iOS 16, macOS 13, *) {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = videoTracks.first else {
          throw CompressVideoError(code: "unsupportedInput", message: "No video track found", details: nil)
        }
        videoTrack = track
        audioTrack = try await asset.loadTracks(withMediaType: .audio).first
      } else {
        try await Self.awaitLegacyLoad(asset, keys: ["tracks"])
        guard let track = asset.tracks(withMediaType: .video).first else {
          throw CompressVideoError(code: "unsupportedInput", message: "No video track found", details: nil)
        }
        videoTrack = track
        audioTrack = asset.tracks(withMediaType: .audio).first
      }
    } catch let error as CompressVideoError {
      throw error
    } catch {
      throw CompressVideoError(
        code: "unsupportedInput", message: "Could not read the video track",
        details: error.localizedDescription)
    }

    let naturalSize: CGSize
    let preferredTransform: CGAffineTransform
    do {
      if #available(iOS 16, macOS 13, *) {
        naturalSize = try await videoTrack.load(.naturalSize)
        preferredTransform = try await videoTrack.load(.preferredTransform)
      } else {
        try await Self.awaitLegacyLoad(videoTrack, keys: ["naturalSize", "preferredTransform"])
        naturalSize = videoTrack.naturalSize
        preferredTransform = videoTrack.preferredTransform
      }
    } catch let error as CompressVideoError {
      throw error
    } catch {
      throw CompressVideoError(
        code: "unsupportedInput", message: "Could not read the video track's geometry",
        details: error.localizedDescription)
    }

    var audioFormatDescription: CMFormatDescription?
    if let audioTrack {
      if #available(iOS 16, macOS 13, *) {
        audioFormatDescription = (try? await audioTrack.load(.formatDescriptions))?.first
      } else {
        try? await Self.awaitLegacyLoad(audioTrack, keys: ["formatDescriptions"])
        audioFormatDescription = (audioTrack.formatDescriptions as? [CMFormatDescription])?.first
      }
    }
    let inputAudioCodec = audioFormatDescription.map {
      Self.normalizedAudioCodec(fourCC: CMFormatDescriptionGetMediaSubType($0))
    }

    let plan = resolvePlan(inputInfo: inputInfo, request: request, audioCodec: inputAudioCodec)

    // Never-larger PRE-check (D-11, mirrors TransformerEngine.compress): when the resolver
    // already knows encoding would not help, skip building a reader/writer at all.
    if plan.wouldUseOriginal {
      try Self.copyOriginalAtomically(from: inputURL, to: destinationURL)
      onProgress(100.0)
      return try await buildResult(
        destinationURL: destinationURL, inputBytes: inputBytes, startedAt: startedAt,
        transmuxed: false, usedOriginal: true, audioReencoded: false)
    }

    if request.audioMode == .reencode {
      throw CompressVideoError(
        code: "unsupportedInput",
        message: "Audio re-encode is not yet implemented on Apple platforms in this phase",
        details: nil)
    }

    let includeAudio = inputInfo.hasAudio && audioTrack != nil && request.audioMode != .strip

    // Coded/displayed swap (D-03): SizeGuard's plan speaks in DISPLAYED dimensions (the same
    // space `inputInfo.widthPx`/`heightPx` are already in); both AVFoundation surfaces this
    // engine touches -- the reader's resize keys and the writer's dimension keys -- speak in
    // CODED (pre-rotation) ones. Swap back for a 90/270-degree source before either sees it.
    let rotationDegrees = Int(inputInfo.rotationDegrees)
    let codedTargetWidth: Int
    let codedTargetHeight: Int
    if rotationDegrees == 90 || rotationDegrees == 270 {
      codedTargetWidth = plan.targetHeightPx
      codedTargetHeight = plan.targetWidthPx
    } else {
      codedTargetWidth = plan.targetWidthPx
      codedTargetHeight = plan.targetHeightPx
    }

    let inputCodedWidth = Int(naturalSize.width.rounded())
    let inputCodedHeight = Int(naturalSize.height.rounded())
    let needsResize = codedTargetWidth != inputCodedWidth || codedTargetHeight != inputCodedHeight

    var videoReaderSettings: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
    // Only add the resize keys when a resize is actually needed (03-RESEARCH.md Pattern 2) --
    // mirrors Android's "only add the effect if it changes something" rule.
    if needsResize {
      videoReaderSettings[kCVPixelBufferWidthKey as String] = codedTargetWidth
      videoReaderSettings[kCVPixelBufferHeightKey as String] = codedTargetHeight
    }

    // The resolved bitrate is set both as the writer input's own top-level average-bit-rate
    // key and inside the compression-properties dictionary (03-RESEARCH.md Code Examples) --
    // belt-and-suspenders so the resolved number unambiguously reaches the encoder.
    let videoOutputSettings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: codedTargetWidth,
      AVVideoHeightKey: codedTargetHeight,
      AVVideoAverageBitRateKey: plan.videoBitrateBps,
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: plan.videoBitrateBps,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        // A hint only -- the reader loop below still drops frames by presentation timestamp;
        // this key does not cap the frame rate by itself (D-04).
        AVVideoExpectedSourceFrameRateKey: plan.effectiveFps,
      ] as [String: Any],
    ]

    let tempURL = PluginFiles.tempFileBeside(destinationURL)
    let reader: AVAssetReader
    let writer: AVAssetWriter
    do {
      reader = try AVAssetReader(asset: asset)
      writer = try AVAssetWriter(url: tempURL, fileType: .mp4)
    } catch {
      throw Self.mapToCompressVideoError(error)
    }

    // Pre-flight validation, turning a rejected settings combination into a typed error rather
    // than a mid-encode failure.
    guard writer.canApply(outputSettings: videoOutputSettings, forMediaType: .video) else {
      throw CompressVideoError(
        code: "encoderUnavailable",
        message: "This device's H.264 encoder does not support the requested output settings",
        details: nil)
    }

    let trimStartMs = request.trimStartMs ?? 0
    let trimEndMs = request.trimEndMs ?? inputInfo.durationMs
    let sessionStartTime = CMTime(value: trimStartMs, timescale: 1000)
    if request.trimStartMs != nil || request.trimEndMs != nil {
      // Pattern 3: a reader-level timeRange (shared by both the video and audio outputs added
      // below, so A/V stay aligned) plus a writer session start at the same time -- no manual
      // sample retiming.
      reader.timeRange = CMTimeRange(start: sessionStartTime, end: CMTime(value: trimEndMs, timescale: 1000))
    }

    let videoReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: videoReaderSettings)
    videoReaderOutput.alwaysCopiesSampleData = false
    reader.add(videoReaderOutput)

    var audioReaderOutput: AVAssetReaderTrackOutput?
    if includeAudio, let audioTrack {
      // outputSettings: nil -- passthrough, compressed samples (D-07).
      let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
      output.alwaysCopiesSampleData = false
      reader.add(output)
      audioReaderOutput = output
    }

    let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoOutputSettings)
    videoWriterInput.transform = preferredTransform
    videoWriterInput.expectsMediaDataInRealTime = false
    writer.add(videoWriterInput)

    var audioWriterInput: AVAssetWriterInput?
    if includeAudio {
      let input = AVAssetWriterInput(
        mediaType: .audio, outputSettings: nil, sourceFormatHint: audioFormatDescription)
      input.expectsMediaDataInRealTime = false
      writer.add(input)
      audioWriterInput = input
    }

    guard writer.startWriting() else {
      throw Self.mapToCompressVideoError(
        writer.error
          ?? CompressVideoError(code: "io", message: "Could not start the writer session", details: nil))
    }
    writer.startSession(atSourceTime: sessionStartTime)
    guard reader.startReading() else {
      throw Self.mapToCompressVideoError(
        reader.error
          ?? CompressVideoError(code: "unsupportedInput", message: "Could not start reading the input", details: nil)
      )
    }

    let jobQueue = DispatchQueue(label: "com.danjjohnson.compress_video.job.\(jobId)")
    let cancelState = CancelState()

    await MainActor.run {
      JobRegistry.register(
        jobId: jobId,
        cancel: {
          cancelState.markCancelled()
          reader.cancelReading()
        },
        tempFile: tempURL
      )
    }

    // Frame-rate cap (D-04): only added when the source is genuinely above the resolved cap --
    // never upscales, and never an unnecessary decimation pass when it would be a no-op.
    let frameInterval: CMTime?
    if let inputFps = inputInfo.frameRateFps, Double(plan.effectiveFps) < inputFps {
      frameInterval = CMTime(value: 1, timescale: CMTimeScale(plan.effectiveFps))
    } else {
      frameInterval = nil
    }

    do {
      try await Self.runCopyLoop(
        reader: reader,
        writer: writer,
        videoOutput: videoReaderOutput,
        videoInput: videoWriterInput,
        audioOutput: audioReaderOutput,
        audioInput: audioWriterInput,
        jobQueue: jobQueue,
        frameInterval: frameInterval,
        sessionStartTime: sessionStartTime,
        outputDurationMs: plan.outputDurationMs,
        cancelState: cancelState,
        onProgress: onProgress
      )
    } catch {
      await MainActor.run { JobRegistry.markTerminal(jobId: jobId) }
      reader.cancelReading()
      writer.cancelWriting()
      PluginFiles.quietDelete(tempURL)
      await MainActor.run { JobRegistry.remove(jobId: jobId) }
      if cancelState.isCancelled {
        throw CompressVideoError(code: "cancelled", message: "The compression job was cancelled", details: nil)
      }
      throw Self.mapToCompressVideoError(error)
    }

    if cancelState.isCancelled {
      await MainActor.run { JobRegistry.markTerminal(jobId: jobId) }
      writer.cancelWriting()
      PluginFiles.quietDelete(tempURL)
      await MainActor.run { JobRegistry.remove(jobId: jobId) }
      throw CompressVideoError(code: "cancelled", message: "The compression job was cancelled", details: nil)
    }

    let finishResult: Result<Void, Error> = await withCheckedContinuation { continuation in
      writer.finishWriting {
        if writer.status == .completed {
          continuation.resume(returning: .success(()))
        } else {
          continuation.resume(
            returning: .failure(
              writer.error ?? CompressVideoError(code: "io", message: "The writer failed to finish", details: nil)))
        }
      }
    }

    await MainActor.run { JobRegistry.markTerminal(jobId: jobId) }

    if case .failure(let error) = finishResult {
      PluginFiles.quietDelete(tempURL)
      await MainActor.run { JobRegistry.remove(jobId: jobId) }
      throw Self.mapToCompressVideoError(error)
    }

    onProgress(100.0)

    // Never-larger POST-check (D-11): unconditional, on every produced file.
    let tempBytes = (try? Self.fileSize(of: tempURL)) ?? Int64.max
    let usedOriginal = tempBytes >= inputBytes
    if usedOriginal {
      PluginFiles.quietDelete(tempURL)
      try Self.copyOriginalAtomically(from: inputURL, to: destinationURL)
    } else {
      try PluginFiles.moveIntoPlace(tempFile: tempURL, destination: destinationURL)
    }
    await MainActor.run { JobRegistry.remove(jobId: jobId) }

    return try await buildResult(
      destinationURL: destinationURL, inputBytes: inputBytes, startedAt: startedAt,
      transmuxed: false, usedOriginal: usedOriginal, audioReencoded: false)
  }

  /// Resolves `request` against `inputInfo` (plus the separately-read `audioCodec`, which
  /// `MediaInfoMessage` has no field for) into a `SizeGuard.Plan` -- the single call every
  /// geometry and bitrate number in `compress` comes from.
  private func resolvePlan(
    inputInfo: MediaInfoMessage, request: CompressRequestMessage, audioCodec: String?
  ) -> SizeGuard.Plan {
    let input = SizeGuard.InputInfo(
      displayedWidthPx: Int(inputInfo.widthPx),
      displayedHeightPx: Int(inputInfo.heightPx),
      rotationDegrees: Int(inputInfo.rotationDegrees),
      durationMs: inputInfo.durationMs,
      sizeBytes: inputInfo.sizeBytes,
      videoCodec: inputInfo.videoCodec ?? "unknown",
      videoBitrateBps: inputInfo.videoBitrateBps,
      frameRateFps: inputInfo.frameRateFps,
      hasAudio: inputInfo.hasAudio,
      audioCodec: audioCodec,
      audioBitrateBps: nil
    )
    let options = SizeGuard.Options(
      maxLongSidePx: request.maxLongSidePx,
      videoBitrateBps: request.videoBitrateBps,
      targetSizeMb: request.targetSizeMb,
      presetMaxLongSidePx: request.presetMaxLongSidePx,
      presetVideoBitrateBps: request.presetVideoBitrateBps,
      maxFps: request.maxFps,
      audioStripped: request.audioMode == .strip,
      audioPassthroughRequested: request.audioMode == .passthrough,
      requestedAudioBitrateBps: request.audioBitrateBps,
      trimStartMs: request.trimStartMs,
      trimEndMs: request.trimEndMs
    )
    return SizeGuard.resolve(input: input, options: options)
  }

  /// Re-probes `destinationURL` via `Probe` for every field but the three passed in, never
  /// from the writer's own approximate settings.
  private func buildResult(
    destinationURL: URL, inputBytes: Int64, startedAt: Date, transmuxed: Bool, usedOriginal: Bool,
    audioReencoded: Bool
  ) async throws -> CompressResultMessage {
    let outputInfo = try await Probe().getMediaInfo(destinationURL.path)
    let outputBytes = (try? Self.fileSize(of: destinationURL)) ?? 0
    let audioCodec: String?
    if outputInfo.hasAudio {
      audioCodec = await Self.readAudioCodec(at: destinationURL)
    } else {
      audioCodec = nil
    }
    let elapsedMs = Int64((Date().timeIntervalSince(startedAt) * 1000).rounded())

    return CompressResultMessage(
      outputPath: destinationURL.path,
      inputBytes: inputBytes,
      outputBytes: outputBytes,
      widthPx: outputInfo.widthPx,
      heightPx: outputInfo.heightPx,
      durationMs: outputInfo.durationMs,
      videoCodec: outputInfo.videoCodec ?? "unknown",
      audioCodec: audioCodec,
      transmuxed: transmuxed,
      usedOriginal: usedOriginal,
      toneMapped: false,
      hevcFallback: false,
      audioReencoded: audioReencoded,
      elapsedMs: elapsedMs
    )
  }

  /// Drives the reader/writer copy loop to completion on `jobQueue` -- never the caller's own
  /// context -- resuming the returned continuation exactly once, whether the loop finishes,
  /// fails, or observes `cancelState`. Both inputs share the same serial queue: correctness
  /// over parallelism for this phase's tracer, and it removes the need for a separate lock
  /// around the shared completion state below (every mutation happens on `jobQueue`).
  private static func runCopyLoop(
    reader: AVAssetReader,
    writer: AVAssetWriter,
    videoOutput: AVAssetReaderTrackOutput,
    videoInput: AVAssetWriterInput,
    audioOutput: AVAssetReaderTrackOutput?,
    audioInput: AVAssetWriterInput?,
    jobQueue: DispatchQueue,
    frameInterval: CMTime?,
    sessionStartTime: CMTime,
    outputDurationMs: Int64,
    cancelState: CancelState,
    onProgress: @escaping (Double) -> Void
  ) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      var videoDone = false
      var audioDone = audioInput == nil
      var settled = false
      var nextKeepVideoTime = sessionStartTime
      var lastSentProgress: Double = 0
      var lastProgressWallClock = Date.distantPast

      func settle(_ result: Result<Void, Error>) {
        guard !settled else { return }
        settled = true
        switch result {
        case .success:
          continuation.resume(returning: ())
        case .failure(let error):
          continuation.resume(throwing: error)
        }
      }

      func maybeFinish() {
        if videoDone && audioDone {
          settle(.success(()))
        }
      }

      func failAndCancel(_ error: Error) {
        guard !settled else { return }
        reader.cancelReading()
        settle(.failure(error))
      }

      videoInput.requestMediaDataWhenReady(on: jobQueue) {
        while videoInput.isReadyForMoreMediaData {
          if settled { return }
          if cancelState.isCancelled {
            videoInput.markAsFinished()
            videoDone = true
            maybeFinish()
            return
          }
          if reader.status == .failed {
            failAndCancel(
              reader.error
                ?? CompressVideoError(code: "io", message: "The reader failed", details: nil))
            return
          }
          guard let sampleBuffer = videoOutput.copyNextSampleBuffer() else {
            videoInput.markAsFinished()
            videoDone = true
            maybeFinish()
            return
          }
          let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
          let shouldKeep = frameInterval == nil || pts >= nextKeepVideoTime
          if !shouldKeep {
            continue
          }
          guard videoInput.append(sampleBuffer) else {
            failAndCancel(
              writer.error
                ?? CompressVideoError(code: "io", message: "Failed to append a video sample", details: nil))
            return
          }
          if let frameInterval {
            nextKeepVideoTime = CMTimeAdd(pts, frameInterval)
          }
          if outputDurationMs > 0 {
            let elapsedMs = CMTimeGetSeconds(CMTimeSubtract(pts, sessionStartTime)) * 1000
            let clamped = min(max(elapsedMs / Double(outputDurationMs) * 100, 0), 99)
            let forwarded = max(clamped, lastSentProgress)
            let now = Date()
            if forwarded > lastSentProgress
              && now.timeIntervalSince(lastProgressWallClock) >= progressThrottleSeconds
            {
              lastSentProgress = forwarded
              lastProgressWallClock = now
              onProgress(forwarded)
            }
          }
        }
      }

      if let audioOutput, let audioInput {
        audioInput.requestMediaDataWhenReady(on: jobQueue) {
          while audioInput.isReadyForMoreMediaData {
            if settled { return }
            if cancelState.isCancelled {
              audioInput.markAsFinished()
              audioDone = true
              maybeFinish()
              return
            }
            if reader.status == .failed {
              failAndCancel(
                reader.error
                  ?? CompressVideoError(code: "io", message: "The reader failed", details: nil))
              return
            }
            guard let sampleBuffer = audioOutput.copyNextSampleBuffer() else {
              audioInput.markAsFinished()
              audioDone = true
              maybeFinish()
              return
            }
            guard audioInput.append(sampleBuffer) else {
              failAndCancel(
                writer.error
                  ?? CompressVideoError(code: "io", message: "Failed to append an audio sample", details: nil))
              return
            }
          }
        }
      }
    }
  }

  /// A tiny cross-queue cancellation flag: `JobRegistry.cancel(jobId:)`'s closure sets it from
  /// the main queue; the copy loop above reads it from `jobQueue`. A plain `NSLock` rather than
  /// an actor -- this needs to be checked synchronously from inside a non-`async`
  /// `requestMediaDataWhenReady` callback, where `await`ing an actor is not an option.
  private final class CancelState {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
      lock.lock()
      defer { lock.unlock() }
      return cancelled
    }

    func markCancelled() {
      lock.lock()
      cancelled = true
      lock.unlock()
    }
  }

  /// Awaits legacy (`loadValuesAsynchronously`) loading of `keys` on `keyValueLoadable` (the
  /// iOS-13/macOS-11-compatible path below the modern `load(_:)` floor), throwing if any key
  /// fails to load. Copied from `Probe.swift`'s own private helper of the same shape
  /// (03-RESEARCH.md/03-PATTERNS.md: copy verbatim rather than share, to keep each file's
  /// dependency surface self-contained).
  private static func awaitLegacyLoad(
    _ keyValueLoadable: AVAsynchronousKeyValueLoading, keys: [String]
  ) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      keyValueLoadable.loadValuesAsynchronously(forKeys: keys) {
        for key in keys {
          var error: NSError?
          let status = keyValueLoadable.statusOfValue(forKey: key, error: &error)
          if status != .loaded {
            continuation.resume(
              throwing: CompressVideoError(
                code: "unsupportedInput", message: "Could not load '\(key)'",
                details: error?.localizedDescription))
            return
          }
        }
        continuation.resume(returning: ())
      }
    }
  }

  /// Copies `source` to `destination` atomically (temp file beside the destination, then
  /// rename) -- for the never-larger path, where the original's own bytes become the output.
  /// Never opens `source` for writing.
  private static func copyOriginalAtomically(from source: URL, to destination: URL) throws {
    let temp = PluginFiles.tempFileBeside(destination)
    do {
      try FileManager.default.copyItem(at: source, to: temp)
      try PluginFiles.moveIntoPlace(tempFile: temp, destination: destination)
    } catch let error as CompressVideoError {
      PluginFiles.quietDelete(temp)
      throw error
    } catch {
      PluginFiles.quietDelete(temp)
      throw CompressVideoError(
        code: "io", message: "Failed to copy the original file", details: error.localizedDescription)
    }
  }

  private static func fileSize(of url: URL) throws -> Int64 {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.size] as? NSNumber)?.int64Value ?? 0
  }

  /// Reads the normalised codec of `url`'s first audio track, or `nil` if it has none --
  /// mirrors `TransformerEngine.readAudioCodec` (Android), since `MediaInfoMessage` has no
  /// audio-codec field of its own.
  private static func readAudioCodec(at url: URL) async -> String? {
    let asset = AVURLAsset(url: url)
    do {
      let track: AVAssetTrack?
      if #available(iOS 16, macOS 13, *) {
        track = try await asset.loadTracks(withMediaType: .audio).first
      } else {
        try await awaitLegacyLoad(asset, keys: ["tracks"])
        track = asset.tracks(withMediaType: .audio).first
      }
      guard let track else { return nil }
      let formatDescription: CMFormatDescription?
      if #available(iOS 16, macOS 13, *) {
        formatDescription = try await track.load(.formatDescriptions).first
      } else {
        try await awaitLegacyLoad(track, keys: ["formatDescriptions"])
        formatDescription = (track.formatDescriptions as? [CMFormatDescription])?.first
      }
      guard let formatDescription else { return nil }
      return normalizedAudioCodec(fourCC: CMFormatDescriptionGetMediaSubType(formatDescription))
    } catch {
      return nil
    }
  }

  /// Normalises an audio track's format description media subtype into a wire-contract codec
  /// token. Mirrors `TransformerEngine.normalizeAudioCodec` (Android) -- `MediaMath
  /// .normalizeCodec` only recognises video tokens, so this is not reused as-is (same
  /// documented limitation as the Kotlin original).
  private static func normalizedAudioCodec(fourCC: FourCharCode) -> String {
    fourCC == kAudioFormatMPEG4AAC ? "aac" : "unknown"
  }

  /// Maps a thrown error to a `CompressVideoError`, via `ErrorMapping` for an `AVError`- or
  /// `NSError`-typed underlying failure, passing an already-typed `CompressVideoError` through
  /// unchanged.
  private static func mapToCompressVideoError(_ error: Error) -> CompressVideoError {
    if let compressVideoError = error as? CompressVideoError {
      return compressVideoError
    }
    let nsError = error as NSError
    if nsError.domain == AVFoundationErrorDomain, let code = AVError.Code(rawValue: nsError.code) {
      return CompressVideoError(
        code: ErrorMapping.reasonForAVError(code),
        message: "AVFoundation error \(nsError.code): \(nsError.localizedDescription)",
        details: nsError.localizedDescription
      )
    }
    return CompressVideoError(
      code: ErrorMapping.reasonForNSError(nsError),
      message: ErrorMapping.messageForNSError(nsError),
      details: nil
    )
  }
}
