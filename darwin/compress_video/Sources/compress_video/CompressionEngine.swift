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
/// The transmux fast path (`AVAssetExportSession` with `AVAssetExportPresetPassthrough`, D-05)
/// and a real encode both funnel through `finishJob`, the ONE never-larger POST-check site in
/// this file (D-06/D-11): unconditional, on every produced temp file, comparing real measured
/// bytes with a greater-than-or-equal comparison so an exactly-equal size still counts as "not
/// smaller" -- matching Android's `TransformerEngine.finishSuccess` exactly. The never-larger
/// PRE-check (`SizeGuard.Plan.wouldUseOriginal`) is a separate, earlier decision: it skips
/// attempting anything at all when the resolver already knows encoding would not help.
///
/// Audio (D-07) is passthrough only for an AAC-compatible source track; anything else under a
/// passthrough request falls back to an AAC re-encode rather than muxing an incompatible codec
/// into the container, and reports `audioReencoded` from whichever branch actually ran, never
/// from the request.
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
    // The source track's own channel count/sample rate, read once here for the audio-reencode
    // fallback branch below (D-07: a passthrough request against a non-AAC source preserves the
    // source's own channel count -- no channel change was asked for, only a codec change).
    let sourceAudioStreamDescription = audioFormatDescription.flatMap {
      CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee
    }
    let sourceAudioChannelCount = sourceAudioStreamDescription.map { Int($0.mChannelsPerFrame) }
    let sourceAudioSampleRate = sourceAudioStreamDescription?.mSampleRate

    // outputCodecIsHevc is always false until task 2 adds the hardware-HEVC/keep-HDR probe --
    // wired as a real parameter now so task 2 is a value change here, not another signature
    // change (04-04 task 1).
    let plan = resolvePlan(
      inputInfo: inputInfo, request: request, audioCodec: inputAudioCodec,
      audioChannelCount: sourceAudioChannelCount, outputCodecIsHevc: false)

    // Never-larger PRE-check (D-11, mirrors TransformerEngine.compress): when the resolver
    // already knows encoding would not help, skip building a reader/writer at all.
    if plan.wouldUseOriginal {
      try Self.copyOriginalAtomically(from: inputURL, to: destinationURL)
      onProgress(100.0)
      // No encode ever runs on this fast path -- nothing could have been tone-mapped or have
      // fallen back to anything; buildResult's own !usedOriginal guard forces both flags false
      // regardless of the literals passed here.
      return try await buildResult(
        destinationURL: destinationURL, inputBytes: inputBytes, startedAt: startedAt,
        transmuxed: false, usedOriginal: true, audioReencoded: false,
        inputWasHdr: inputInfo.isHdr, hevcFallback: false)
    }

    // Transmux (D-05): when the resolver says a remux would satisfy the request, attempt an
    // AVAssetExportSession passthrough instead of building a reader/writer pipeline at all.
    // `wouldTransmux` already implies an audio-passthrough request with no trim (SizeGuard's
    // own predicate), so this branch and the audio-mode resolution below never compete for the
    // same job. Routes through `finishJob`, the SAME completion function the real-encode branch
    // uses below it -- see that function's own doc comment for why.
    if plan.wouldTransmux {
      return try await runTransmux(
        jobId: jobId,
        asset: asset,
        inputURL: inputURL,
        destinationURL: destinationURL,
        inputBytes: inputBytes,
        startedAt: startedAt,
        inputWasHdr: inputInfo.isHdr,
        onProgress: onProgress
      )
    }

    // Audio mode resolution (D-07): passthrough is attempted ONLY for an AAC-compatible source
    // track -- anything else (a non-AAC source under a passthrough request) falls back to an
    // AAC re-encode rather than muxing an incompatible codec into an MP4 container, exactly as
    // an explicit `reencode` request does. `audioWillReencode` is decided once, here, before
    // the reader/writer pipeline is built, and is what `finishJob` below reports as
    // `audioReencoded` -- from the branch that actually ran, never from the request.
    let sourceIsAAC = inputAudioCodec == "aac"
    let includeAudio = inputInfo.hasAudio && audioTrack != nil && request.audioMode != .strip
    let audioWillReencode = includeAudio && (request.audioMode == .reencode || !sourceIsAAC)

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

    // AVFoundation only accepts AVVideoAverageBitRateKey INSIDE
    // AVVideoCompressionPropertiesKey -- it is not a recognised top-level video output settings
    // key. An earlier revision of this code also set it at the top level as
    // "belt-and-suspenders"; that extra, unrecognised key made every H.264 request fail
    // `writer.canApply(outputSettings:forMediaType:)` below (CI run 35765529347, diagnosed
    // 2026-09-22: 21/22 compress_test.dart cases threw `encoderUnavailable`, the one pass being
    // the transmux case that never touches AVAssetWriter). Do NOT re-add a top-level
    // AVVideoAverageBitRateKey -- keep it only inside AVVideoCompressionPropertiesKey below.
    let videoOutputSettings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: codedTargetWidth,
      AVVideoHeightKey: codedTargetHeight,
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
      // outputSettings: nil for passthrough (compressed samples, D-07); a plain linear-PCM
      // decode request (native channel count/sample rate, no explicit downmix at the reader)
      // for a re-encode -- the writer's own AAC outputSettings below (channel count, bitrate)
      // is what actually drives any channel up/downmix, via AVAssetWriterInput's documented
      // ability to mix appended PCM samples up or down to the channel count named in its own
      // compression settings dictionary.
      let readerSettings: [String: Any]? =
        audioWillReencode ? [AVFormatIDKey: kAudioFormatLinearPCM] : nil
      let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerSettings)
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
      let input: AVAssetWriterInput
      if audioWillReencode {
        // An explicit `reencode` request uses the caller's own channel count (validated
        // non-nil, 1 or 2, by Arguments.requireValidCompressRequest before this engine is ever
        // called); the AAC fallback for a non-AAC source under a passthrough request preserves
        // the source's own channel count instead -- no channel change was asked for there, only
        // a codec change (D-07).
        let targetChannels =
          request.audioMode == .reencode
          ? Int(request.audioChannels!)
          : (sourceAudioChannelCount ?? 2)
        // iOS/macOS's built-in AAC-LC encoder rejects (-11861 AVError.unsupportedOutputSettings
        // / "Cannot Encode Media", confirmed live in CI run 35809012150) a bitrate far below its
        // own practical per-channel minimum, even though writer.canApply(...) below -- a
        // coarser, static compatibility check -- accepted the dictionary shape. SizeGuard's
        // shared 8,000-960,000bps range mirrors Android's own measured c2.android.aac.encoder
        // floor and is too low for Apple's encoder, so an ADDITIONAL platform-specific floor is
        // applied here on top of SizeGuard's resolution (plan.audioBitrateBps), never by
        // changing the shared cross-platform port. The same CI run also measured the requested
        // bitrate going un-honoured (e.g. 64,000bps requested, ~24,182bps measured) whenever no
        // AVSampleRateKey/AVChannelLayoutKey was supplied -- both are now always set below.
        let targetBitrate = max(
          plan.audioBitrateBps, Self.appleAacMinBitratePerChannelBps * Int64(targetChannels))
        let aacOutputSettings: [String: Any] = [
          AVFormatIDKey: kAudioFormatMPEG4AAC,
          AVNumberOfChannelsKey: targetChannels,
          AVSampleRateKey: Self.normalizedAacSampleRate(sourceAudioSampleRate),
          AVEncoderBitRateKey: Int(targetBitrate),
          // Without an explicit strategy, the AAC-LC encoder was measured (CI run 35821995638)
          // to silently ignore AVEncoderBitRateKey and settle on its own ~24,182bps default
          // regardless of the requested value -- constant is what the requested bitrate is
          // actually FOR. Never combined with AVEncoderAudioQualityKey or any other
          // quality-strategy key -- the two are mutually exclusive and their combination is a
          // separate, documented cause of the same -11861 error; this dictionary carries only
          // this one, explicit bitrate strategy.
          AVEncoderBitRateStrategyKey: AVAudioBitRateStrategy_Constant,
          // An explicit channel layout, not just a channel COUNT -- AAC-LC's encoder needs
          // this to avoid ambiguity and to genuinely downmix rather than silently keep the
          // source's own channel count.
          AVChannelLayoutKey: Self.audioChannelLayoutData(channelCount: targetChannels),
        ]
        guard writer.canApply(outputSettings: aacOutputSettings, forMediaType: .audio) else {
          throw CompressVideoError(
            code: "encoderUnavailable",
            message: "This device's AAC encoder does not support the requested output settings",
            details: nil)
        }
        input = AVAssetWriterInput(mediaType: .audio, outputSettings: aacOutputSettings)
      } else {
        // outputSettings: nil -- passthrough, compressed samples (D-07).
        input = AVAssetWriterInput(
          mediaType: .audio, outputSettings: nil, sourceFormatHint: audioFormatDescription)
      }
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

    // hevcFallback is always false until task 2 adds the hardware-HEVC/keep-HDR gate -- wired
    // as a real parameter now so task 2 is a value change here, not another signature change
    // (04-04 task 1).
    let result = try await finishJob(
      tempURL: tempURL, inputURL: inputURL, destinationURL: destinationURL,
      inputBytes: inputBytes, startedAt: startedAt, attemptedTransmux: false,
      audioReencoded: audioWillReencode, inputWasHdr: inputInfo.isHdr, hevcFallback: false)
    await MainActor.run { JobRegistry.remove(jobId: jobId) }
    return result
  }

  /// Attempts a passthrough remux via `AVAssetExportSession` (D-05, 03-RESEARCH.md Pattern 4)
  /// instead of building a reader/writer pipeline -- taken only when `SizeGuard.Plan
  /// .wouldTransmux` is `true`. `shouldOptimizeForNetworkUse = false`: no moov-first rewrite
  /// pads a short remux past its own input size, mirroring Android's own muxer
  /// `setAttemptStreamableOutputEnabled(false)` fix for exactly this never-larger reason
  /// (`.claude/CLAUDE.md` lane note). Progress is reported 0 then a terminal 100 at completion
  /// (D-05) -- the deprecated `.progress` property is never polled for intermediate values.
  ///
  /// This project's deployment floor (iOS 13/macOS 11) is nine major versions below the modern
  /// async `export(to:as:)` API's own floor (iOS 18/macOS 15) -- the deprecated
  /// `exportAsynchronously`/`.status` pair below is the PRIMARY path for this project, not a
  /// legacy fallback (03-RESEARCH.md Pitfall 4).
  ///
  /// Routes through `finishJob`, the SAME completion function the real-encode branch above
  /// uses, so the never-larger post-check, move-into-place/substitution, re-probe and result
  /// construction cannot diverge between the two branches.
  private func runTransmux(
    jobId: String,
    asset: AVAsset,
    inputURL: URL,
    destinationURL: URL,
    inputBytes: Int64,
    startedAt: Date,
    inputWasHdr: Bool,
    onProgress: @escaping (Double) -> Void
  ) async throws -> CompressResultMessage {
    guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)
    else {
      throw CompressVideoError(
        code: "unsupportedInput",
        message: "This input cannot be exported with the passthrough preset",
        details: nil)
    }
    let tempURL = PluginFiles.tempFileBeside(destinationURL)
    // shouldOptimizeForNetworkUse is not deprecated and applies to both the modern and legacy
    // export paths below; outputURL/outputFileType ARE deprecated properties of the legacy
    // path only -- the modern export(to:as:) call takes its destination as parameters instead,
    // so they are set inside the legacy branch, not unconditionally here.
    session.shouldOptimizeForNetworkUse = false

    onProgress(0.0)

    await MainActor.run {
      JobRegistry.register(jobId: jobId, cancel: { session.cancelExport() }, tempFile: tempURL)
    }

    do {
      if #available(iOS 18, macOS 15, *) {
        try await session.export(to: tempURL, as: .mp4)
      } else {
        session.outputURL = tempURL
        session.outputFileType = .mp4
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
          session.exportAsynchronously { continuation.resume() }
        }
        if session.status != .completed {
          throw session.error
            ?? CompressVideoError(
              code: "io", message: "The export session failed to finish", details: nil)
        }
      }
    } catch {
      await MainActor.run { JobRegistry.markTerminal(jobId: jobId) }
      PluginFiles.quietDelete(tempURL)
      await MainActor.run { JobRegistry.remove(jobId: jobId) }
      if session.status == .cancelled {
        throw CompressVideoError(code: "cancelled", message: "The compression job was cancelled", details: nil)
      }
      throw Self.mapToCompressVideoError(error)
    }

    await MainActor.run { JobRegistry.markTerminal(jobId: jobId) }
    onProgress(100.0)

    let result = try await finishJob(
      tempURL: tempURL, inputURL: inputURL, destinationURL: destinationURL,
      inputBytes: inputBytes, startedAt: startedAt, attemptedTransmux: true, audioReencoded: false,
      // A transmux never touches the codec/HDR decision -- SizeGuard.Options.outputCodecIsHevc
      // already disqualifies a genuinely-HEVC-bound request from transmuxing at all, so a
      // transmux attempt can never itself be the thing that fell back from HEVC or kept HDR.
      inputWasHdr: inputWasHdr, hevcFallback: false)
    await MainActor.run { JobRegistry.remove(jobId: jobId) }
    return result
  }

  /// Runs the never-larger POST-check (D-06, D-11): unconditional, on every produced temp file,
  /// whether it came from a real encode or an attempted transmux. Compares REAL measured bytes,
  /// never the plan's prediction. `>=`, not `>`: equality counts as "not smaller", matching
  /// Android's `TransformerEngine.finishSuccess` (`usedOriginal = tempBytes >= inputBytes`)
  /// exactly -- do not "fix" this to a strict `>`. This is the ONE post-check site in this
  /// file; both the real-encode branch above and `runTransmux` above it funnel through here so
  /// the check, the move-into-place/substitution and the re-probe result construction can never
  /// diverge between branches.
  ///
  /// A discarded transmux attempt was never transmuxed as far as the caller is concerned: the
  /// file they actually receive is a copy of the original, not the remuxed temp file this
  /// discarded -- `transmuxed` is therefore `attemptedTransmux && !usedOriginal`, describing the
  /// file returned, not the operation attempted (mirrors `TransformerEngine.finishSuccess`'s own
  /// documented reasoning).
  private func finishJob(
    tempURL: URL,
    inputURL: URL,
    destinationURL: URL,
    inputBytes: Int64,
    startedAt: Date,
    attemptedTransmux: Bool,
    audioReencoded: Bool,
    inputWasHdr: Bool,
    hevcFallback: Bool
  ) async throws -> CompressResultMessage {
    let tempBytes = (try? Self.fileSize(of: tempURL)) ?? Int64.max
    let usedOriginal = tempBytes >= inputBytes
    if usedOriginal {
      PluginFiles.quietDelete(tempURL)
      try Self.copyOriginalAtomically(from: inputURL, to: destinationURL)
    } else {
      try PluginFiles.moveIntoPlace(tempFile: tempURL, destination: destinationURL)
    }
    let transmuxed = attemptedTransmux && !usedOriginal
    return try await buildResult(
      destinationURL: destinationURL, inputBytes: inputBytes, startedAt: startedAt,
      transmuxed: transmuxed, usedOriginal: usedOriginal, audioReencoded: audioReencoded,
      inputWasHdr: inputWasHdr, hevcFallback: hevcFallback)
  }

  /// Resolves `request` against `inputInfo` into a `SizeGuard.Plan`, reading `inputURL`'s own
  /// audio codec first when it has an audio track (needed by `SizeGuard.Plan.wouldTransmux`'s
  /// audio-codec condition, D-10) -- mirrors `TransformerEngine.resolvePlan` (Android). Exposed
  /// (not `private`) so `Compression`'s pre-flight free-space check can predict the SAME plan
  /// `compress` itself resolves, before a reader/writer or export session is ever built: both
  /// call sites must resolve identically, or the free-space check could pass or fail against a
  /// prediction the real encode does not honour.
  func resolvePlan(
    inputURL: URL, inputInfo: MediaInfoMessage, request: CompressRequestMessage
  ) async -> SizeGuard.Plan {
    let audioCodec = inputInfo.hasAudio ? await Self.readAudioCodec(at: inputURL) : nil
    let audioChannelCount = inputInfo.hasAudio ? await Self.readAudioChannelCount(at: inputURL) : nil
    // outputCodecIsHevc is always false until task 2 adds the hardware-HEVC/keep-HDR probe --
    // wired as a real parameter now (rather than hardcoded inside the private overload below)
    // so task 2 is a value change here, not another signature change (04-04 task 1).
    return resolvePlan(
      inputInfo: inputInfo, request: request, audioCodec: audioCodec,
      audioChannelCount: audioChannelCount, outputCodecIsHevc: false)
  }

  /// Resolves `request` against `inputInfo` (plus the separately-read `audioCodec`/
  /// `audioChannelCount`, which `MediaInfoMessage` has no fields for, and the already-resolved
  /// `outputCodecIsHevc` decision) into a `SizeGuard.Plan` -- the single call every geometry and
  /// bitrate number in `compress` comes from.
  private func resolvePlan(
    inputInfo: MediaInfoMessage, request: CompressRequestMessage, audioCodec: String?,
    audioChannelCount: Int?, outputCodecIsHevc: Bool
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
      audioBitrateBps: nil,
      audioChannelCount: audioChannelCount
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
      trimEndMs: request.trimEndMs,
      outputCodecIsHevc: outputCodecIsHevc
    )
    return SizeGuard.resolve(input: input, options: options)
  }

  /// Re-probes `destinationURL` via `Probe` for every field but the three passed in, never
  /// from the writer's own approximate settings.
  ///
  /// `destinationURL.path` is re-normalised to NFC (`precomposedStringWithCanonicalMapping`)
  /// for the reported `CompressResultMessage.outputPath` -- confirmed on CI (runs 36176323945,
  /// 36181752118) that `Arguments.standardizedAbsolutePath`'s own NFC normalisation does not
  /// survive being re-wrapped in `URL(fileURLWithPath:)` (`Compression.swift`'s
  /// `destinationURL = URL(fileURLWithPath: standardizedOutputPath)`): on Darwin, ANY
  /// `URL(fileURLWithPath:)` construction stores its path via the POSIX file-system
  /// representation, which is NFD by long-standing Apple convention, and `.path` reconstructs
  /// the Swift `String` FROM that decomposed representation regardless of what Unicode form
  /// went in -- this happens on construction alone, with no real filesystem I/O required, so
  /// normalising upstream in `Arguments.swift` alone cannot fix it. This is therefore the
  /// correct, single choke point for the fix: every caller-visible path this file reports
  /// (real encode, transmux, and both never-larger branches) builds its `CompressResultMessage`
  /// through this one function.
  private func buildResult(
    destinationURL: URL, inputBytes: Int64, startedAt: Date, transmuxed: Bool, usedOriginal: Bool,
    audioReencoded: Bool, inputWasHdr: Bool, hevcFallback: Bool
  ) async throws -> CompressResultMessage {
    let outputInfo = try await Probe().getMediaInfo(path: destinationURL.path)
    let outputBytes = (try? Self.fileSize(of: destinationURL)) ?? 0
    let audioCodec: String?
    if outputInfo.hasAudio {
      audioCodec = await Self.readAudioCodec(at: destinationURL)
    } else {
      audioCodec = nil
    }
    let elapsedMs = Int64((Date().timeIntervalSince(startedAt) * 1000).rounded())

    // toneMapped/hevcFallback (D-04, D-06): both guarded by !usedOriginal exactly like
    // transmuxed/audioReencoded already are -- a substituted original never "fell back" to or
    // "tone-mapped" anything, whatever the raw request or a real re-probe says. toneMapped is
    // computed here, at the one place that already holds both the input's own HDR flag and a
    // fresh re-probe of the produced file's own HDR flag -- the input was HDR, the output is
    // not (mirrors `TransformerEngine.finishSuccess`'s own `ColorInfo.isTransferHdr`-derived
    // computation exactly). Phase 3's D-08 reader path (8-bit BGRA, the system tone-maps) is
    // unchanged; this is new REPORTING of a mechanism that already existed, not a new one.
    let toneMapped = !usedOriginal && inputWasHdr && !outputInfo.isHdr
    let resolvedHevcFallback = !usedOriginal && hevcFallback

    return CompressResultMessage(
      outputPath: destinationURL.path.precomposedStringWithCanonicalMapping,
      inputBytes: inputBytes,
      outputBytes: outputBytes,
      widthPx: outputInfo.widthPx,
      heightPx: outputInfo.heightPx,
      durationMs: outputInfo.durationMs,
      videoCodec: outputInfo.videoCodec ?? "unknown",
      audioCodec: audioCodec,
      transmuxed: transmuxed,
      usedOriginal: usedOriginal,
      toneMapped: toneMapped,
      hevcFallback: resolvedHevcFallback,
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
            // Clamped to 99, never 100: the last video sample's own presentation time can
            // legitimately reach (or pass, on a trimmed job) the output duration several ticks
            // before `writer.finishWriting` actually completes the file -- Android's
            // TransformerEngine hit the exact same thing and clamps identically
            // (02-06-SUMMARY.md Deviations). The single, real 100 is sent explicitly, once, right
            // before the result reply (03-06-PLAN.md task 1) -- never derived here.
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
  /// audio-codec field of its own. Not `private`: also called from the `resolvePlan` overload
  /// above, which `Compression`'s pre-flight free-space check uses.
  static func readAudioCodec(at url: URL) async -> String? {
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

  /// Reads the channel count of `url`'s first audio track, or `nil` if it has none or the
  /// stream description could not be read -- mirrors `readAudioCodec` above and
  /// `TransformerEngine.readAudioChannelCount` (Android), feeding
  /// `SizeGuard.InputInfo.audioChannelCount` (AUDO-03) the same way `readAudioCodec` feeds
  /// `audioCodec`. Not `private`: also called from the `resolvePlan` overload above.
  static func readAudioChannelCount(at url: URL) async -> Int? {
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
      guard let formatDescription,
        let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee
      else { return nil }
      return Int(streamDescription.mChannelsPerFrame)
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

  /// Apple's built-in AAC-LC encoder's own practical per-channel minimum bitrate -- an
  /// ADDITIONAL floor applied on top of SizeGuard's shared, Android-derived 8,000bps floor
  /// (see the call site's comment). Not independently re-verified beyond the one failure this
  /// floor was sized to fix (CI run 35809012150's 1000bps/2-channel case); a lower value that
  /// still succeeds on real hardware may exist.
  private static let appleAacMinBitratePerChannelBps: Int64 = 32000

  /// Sample rates AAC-LC actually supports (ISO/IEC 14496-3 Table 1.16, the standard AAC
  /// sampling-frequency table). `AVSampleRateKey` must be one of these -- an arbitrary value
  /// read from a source track (which can legitimately report something else, or nothing at
  /// all) is normalised to the nearest common default (44,100 Hz) rather than passed through.
  private static let aacLegalSampleRates: Set<Double> = [
    8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000, 64000, 88200, 96000,
  ]

  /// Returns `rate` unchanged when it is one of `aacLegalSampleRates`, else the standard
  /// 44,100 Hz default.
  private static func normalizedAacSampleRate(_ rate: Double?) -> Double {
    guard let rate, Self.aacLegalSampleRates.contains(rate) else { return 44100 }
    return rate
  }

  /// Builds the `AVChannelLayoutKey` value for `channelCount` (1 or 2) -- an explicit channel
  /// LAYOUT, not just a channel count, which AAC-LC's encoder needs to avoid ambiguity
  /// (confirmed necessary live in CI run 35809012150: the requested bitrate went un-honoured
  /// without one, even though `writer.canApply(...)` accepted the dictionary either way).
  private static func audioChannelLayoutData(channelCount: Int) -> Data {
    var layout = AudioChannelLayout()
    layout.mChannelLayoutTag =
      channelCount == 1 ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_Stereo
    return withUnsafeBytes(of: &layout) { Data($0) }
  }

  /// Maps a thrown error to a `CompressVideoError`, via `ErrorMapping` for an `AVError`- or
  /// `NSError`-typed underlying failure, passing an already-typed `CompressVideoError` through
  /// unchanged.
  private static func mapToCompressVideoError(_ error: Error) -> CompressVideoError {
    if let compressVideoError = error as? CompressVideoError {
      return compressVideoError
    }
    let nsError = error as NSError
    // AVError.Code(rawValue:) IS failable (confirmed live in CI run 35764281991, correcting
    // this file's own prior in-code claim otherwise) -- an out-of-range Int (any domain-correct
    // but currently-unlisted code) falls through to the generic "io" branch below rather than
    // crashing on a forced unwrap.
    if nsError.domain == AVFoundationErrorDomain, let code = AVError.Code(rawValue: nsError.code) {
      // "code \(magnitude)" (positive, no sign) is a SEPARATE, deliberately-shaped phrase from
      // the signed raw value earlier in the same string -- CompressVideoException's own
      // codeIsObservable contract (compress_jobs_test.dart, mirroring 02-06's
      // numeric-code-in-message rule) greps the message for the literal pattern `code \d+`,
      // which a bare negative AVFoundation code (`error -11880`) never matches (the `-` sits
      // between "code " and the digits). This is what makes a RECOGNISED reason's numeric code
      // observable from Dart even though CompressVideoException.platformDetail is reserved for
      // an UNRECOGNISED reason string instead (see ErrorMapping's own doc comment).
      // `.magnitude` (not `abs(_:)`) because `abs(Int.min)` traps -- its positive counterpart
      // is not representable as an `Int` -- and this whole function's purpose is to turn every
      // underlying failure into a typed `CompressVideoError` rather than crash (WR-02).
      // `UInt.magnitude` can never trap for any `Int` input, including `Int.min`.
      let magnitude = nsError.code.magnitude
      return CompressVideoError(
        code: ErrorMapping.reasonForAVError(code),
        message:
          "AVFoundation error \(nsError.code) (code \(magnitude)): \(nsError.localizedDescription)",
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
