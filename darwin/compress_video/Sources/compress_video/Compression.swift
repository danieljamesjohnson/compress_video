import Foundation

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

/// `CompressHostApi` implementation -- the counterpart of Android's `Compression.kt`.
///
/// Unlike Android, which must assert it is running on the main Looper before touching
/// `Transformer` (Media3's own constraint), Pigeon delivers every call here already on the
/// `MainActor` (`CompressHostApiSetup.setUp` wraps every handler in `Task { @MainActor in ...
/// }`, confirmed in `Messages.g.swift`) -- so `startCompress` instead hops OFF the `MainActor`
/// by `await`ing `engine.compress`, whose own copy loop runs on a job-scoped serial queue
/// (03-RESEARCH.md Pattern 1). `JobRegistry` access happens only via explicit `MainActor` hops,
/// both here (`cancel`) and inside `CompressionEngine`.
final class Compression: CompressHostApi {
  private let flutterApi: CompressVideoFlutterApi
  private let engine: CompressionEngine

  init(flutterApi: CompressVideoFlutterApi, engine: CompressionEngine = CompressionEngine()) {
    self.flutterApi = flutterApi
    self.engine = engine
  }

  func startCompress(path: String, jobId: String, request: CompressRequestMessage) async throws
    -> CompressResultMessage
  {
    try Self.requireValidJobId(jobId)
    try Arguments.requireValidCompressRequest(request)

    let standardizedPath = try Arguments.requireReadableMediaFile(path)
    let inputInfo = try await Probe().getMediaInfo(path: standardizedPath)

    let cacheDir = try PluginFiles.cacheSubDir()
    let destinationURL: URL
    if let outputPath = request.outputPath {
      let standardizedOutputPath = try Arguments.requireWritableOutputParent(outputPath)
      destinationURL = URL(fileURLWithPath: standardizedOutputPath)
    } else {
      destinationURL = cacheDir.appendingPathComponent("\(jobId).mp4")
    }

    // Pre-flight space check (D-10): after validation and probing, before a reader, writer or
    // export session is ever built -- a job that cannot possibly fit is never even attempted.
    try await requireSufficientFreeSpace(
      inputURL: URL(fileURLWithPath: standardizedPath), inputInfo: inputInfo, request: request,
      destinationURL: destinationURL)

    // WR-01: a fresh unstructured `Task` per `onProgress` call has no ordering guarantee
    // relative to any other such `Task` -- if an earlier call's `await flutterApi.onProgress`
    // suspends longer than a later call's, the later percentage can reach Dart first even
    // though the native copy loop's own `lastSentProgress` gate emitted them in order.
    // `AsyncStream` is a strict FIFO queue with exactly one reader below, so funnelling every
    // call through `progressContinuation.yield(percent)` (a synchronous, ordering-preserving
    // enqueue) and delivering them from that single consuming task removes the race instead of
    // merely relying on scheduling happening to preserve order.
    var progressContinuation: AsyncStream<Double>.Continuation!
    let progressStream = AsyncStream<Double> { progressContinuation = $0 }
    Task { @MainActor [flutterApi] in
      for await percent in progressStream {
        try? await flutterApi.onProgress(jobId: jobId, percent: percent)
      }
    }
    defer { progressContinuation.finish() }

    return try await engine.compress(
      jobId: jobId,
      inputURL: URL(fileURLWithPath: standardizedPath),
      inputInfo: inputInfo,
      request: request,
      destinationURL: destinationURL,
      onProgress: { percent in
        progressContinuation.yield(percent)
      }
    )
  }

  func cancel(jobId: String) async throws {
    try Self.requireValidJobId(jobId)
    await MainActor.run {
      JobRegistry.cancel(jobId: jobId)
    }
  }

  /// Returns a pre-flight `EstimateMessage` for `request` against `path`, without decoding a
  /// single frame and without building an `AVAssetReader`/`AVAssetWriter` or export session at
  /// all.
  ///
  /// Validates and probes exactly like `startCompress` does, then resolves the SAME
  /// `SizeGuard.Plan` via `engine.resolvePlan(inputURL:inputInfo:request:)` that
  /// `engine.compress` itself resolves internally -- the identical resolver call `03-06`
  /// already added for the free-space pre-check above -- so this path and a subsequent real
  /// job can never disagree about the predicted bytes, dimensions, or whether
  /// `wouldTransmux`/`wouldUseOriginal` would apply (D-11, INFO-03 parity). Mirrors
  /// `Compression.kt`'s `estimate()`.
  func estimate(path: String, request: CompressRequestMessage) async throws -> EstimateMessage {
    try Arguments.requireValidCompressRequest(request)
    let standardizedPath = try Arguments.requireReadableMediaFile(path)
    let inputInfo = try await Probe().getMediaInfo(path: standardizedPath)

    let plan = await engine.resolvePlan(
      inputURL: URL(fileURLWithPath: standardizedPath), inputInfo: inputInfo, request: request)

    return EstimateMessage(
      outputBytes: plan.predictedOutputBytes,
      durationMs: plan.outputDurationMs,
      widthPx: Int64(plan.targetWidthPx),
      heightPx: Int64(plan.targetHeightPx),
      wouldTransmux: plan.wouldTransmux,
      wouldUseOriginal: plan.wouldUseOriginal
    )
  }

  /// Deletes every file this plugin has written to its own cache directory, except a file a
  /// still-running job is currently writing to -- succeeds as a no-op when the directory is
  /// empty or does not exist yet. Mirrors `Compression.kt`'s `clearCache()`: sweeps
  /// `PluginFiles.cacheSubDir()` via `PluginFiles.sweep`, excluding every live job's resolved
  /// temp path (`JobRegistry.liveTempFilePaths()`, read via an explicit `MainActor` hop like
  /// every other `JobRegistry` access in this file).
  func clearCache() async throws {
    let cacheDir = try PluginFiles.cacheSubDir()
    let skip = await MainActor.run { JobRegistry.liveTempFilePaths() }
    PluginFiles.sweep(cacheDir: cacheDir, skipResolvedPaths: skip)
  }

  /// Throws a `CompressVideoError` with reason `"outOfSpace"` when the destination filesystem's
  /// free space is less than 1.2x `engine`'s own predicted output size for `request` against
  /// `inputInfo` -- computed via `CompressionEngine.resolvePlan`, the SAME resolution
  /// `engine.compress` itself will use, so this pre-flight check can never disagree with what
  /// the real encode attempts (mirrors Android's `Compression.requireSufficientFreeSpace`, D-10).
  /// `destinationURL`'s parent directory is guaranteed to already exist by this point --
  /// `Arguments.requireWritableOutputParent` already validated it for a caller-supplied
  /// `outputPath`, and the plugin's own cache subdirectory always exists once
  /// `PluginFiles.cacheSubDir()` returns.
  ///
  /// The 1.2x safety margin (not a bare 1.0x) leaves headroom for the destination filesystem's
  /// own block-size rounding and any other concurrent writer, mirroring Android's own
  /// `FREE_SPACE_SAFETY_FACTOR` exactly.
  private func requireSufficientFreeSpace(
    inputURL: URL, inputInfo: MediaInfoMessage, request: CompressRequestMessage,
    destinationURL: URL
  ) async throws {
    let plan = await engine.resolvePlan(inputURL: inputURL, inputInfo: inputInfo, request: request)
    let requiredBytes = Int64(
      (Double(plan.predictedOutputBytes) * Self.freeSpaceSafetyFactor).rounded(.up))
    let freeBytes = try Self.availableCapacityBytes(
      forDirectory: destinationURL.deletingLastPathComponent())
    if freeBytes < requiredBytes {
      throw CompressVideoError(
        code: "outOfSpace",
        message:
          "Not enough free space to compress: predicted output is \(plan.predictedOutputBytes) "
          + "bytes, requiring approximately \(requiredBytes) bytes with a "
          + "\(Self.freeSpaceSafetyFactor) safety margin, but only \(freeBytes) bytes are free "
          + "on the destination filesystem",
        details: nil
      )
    }
  }

  private static let freeSpaceSafetyFactor: Double = 1.2

  /// Reads the available capacity of the volume containing `directory`, preferring the
  /// "important usage" key (the one that accounts for space the system could reclaim if asked,
  /// e.g. purgeable cache) and falling back to the general available-capacity key when the
  /// important-usage key reports zero.
  ///
  /// `volumeAvailableCapacityForImportantUsageKey` is an APFS-only feature (03-RESEARCH.md
  /// Pitfall 5): on a directory that lives on a non-APFS filesystem -- a caller-supplied macOS
  /// `outputPath` can legitimately point at one -- it reports exactly `0` even though the
  /// directory demonstrably exists and is writable (`Arguments.requireWritableOutputParent`
  /// already proved that before this ever runs). Treating that `0` as a real answer would refuse
  /// every job pointed at such a volume with a false `outOfSpace`; re-reading the general
  /// `volumeAvailableCapacityKey` in that case is the defensive fallback 03-01's discretion list
  /// committed to.
  private static func availableCapacityBytes(forDirectory directory: URL) throws -> Int64 {
    let values: URLResourceValues
    do {
      values = try directory.resourceValues(forKeys: [
        .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
      ])
    } catch {
      throw CompressVideoError(
        code: "io",
        message: "Could not determine free space on the destination volume",
        details: error.localizedDescription)
    }
    if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 {
      return important
    }
    if let general = values.volumeAvailableCapacity {
      return Int64(general)
    }
    throw CompressVideoError(
      code: "io",
      message: "Could not determine free space on the destination volume",
      details: nil)
  }

  /// Validates `jobId` against the documented `<counter>-<16 lowercase hex characters>` format
  /// before it is ever used as a filename stem (mirrors Android's `Compression
  /// .requireValidJobId`, T-03-14).
  private static func requireValidJobId(_ jobId: String) throws {
    guard jobId.range(of: "^[0-9]+-[0-9a-f]{16}$", options: .regularExpression) != nil else {
      throw CompressVideoError(
        code: "unsupportedInput",
        message: "jobId does not match the required <counter>-<16 lowercase hex characters> pattern",
        details: nil
      )
    }
  }
}
