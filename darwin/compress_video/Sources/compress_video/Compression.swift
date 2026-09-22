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

    return try await engine.compress(
      jobId: jobId,
      inputURL: URL(fileURLWithPath: standardizedPath),
      inputInfo: inputInfo,
      request: request,
      destinationURL: destinationURL,
      onProgress: { [flutterApi] percent in
        Task { @MainActor in
          try? await flutterApi.onProgress(jobId: jobId, percent: percent)
        }
      }
    )
  }

  func cancel(jobId: String) async throws {
    try Self.requireValidJobId(jobId)
    await MainActor.run {
      JobRegistry.cancel(jobId: jobId)
    }
  }

  /// Not yet implemented on Apple platforms in this phase -- lands in 03-07, mirroring
  /// `Compression.kt`'s `estimate()`, which resolves the same `SizeGuard.Plan` the real job
  /// would use.
  func estimate(path: String, request: CompressRequestMessage) async throws -> EstimateMessage {
    throw CompressVideoError(
      code: "unknown",
      message: "CompressHostApi.estimate is not yet implemented on Apple platforms; lands in 03-07",
      details: nil
    )
  }

  /// Not yet implemented on Apple platforms in this phase -- lands in 03-07, mirroring
  /// `Compression.kt`'s `clearCache()`, which sweeps `PluginFiles.cacheSubDir()` excluding
  /// every live job's temp file.
  func clearCache() async throws {
    throw CompressVideoError(
      code: "unknown",
      message: "CompressHostApi.clearCache is not yet implemented on Apple platforms; lands in 03-07",
      details: nil
    )
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
