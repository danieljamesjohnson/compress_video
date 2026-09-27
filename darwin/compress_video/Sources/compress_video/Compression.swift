import Foundation

#if os(iOS)
  import Flutter
  import UIKit
#elseif os(macOS)
  import FlutterMacOS
#endif

#if os(iOS)
  /// Wraps one iOS background task for the lifetime of a single running compression job (D-11,
  /// D-12): begun on the main actor immediately before `engine.compress` starts, ended from
  /// exactly one call path -- `end()` -- covering every terminal path (success, typed failure,
  /// cancellation) via a `defer` at the call site. `end()` is idempotent and safe to call twice
  /// (once from the expiration handler below, once from that `defer`) and guards against ending
  /// an identifier the system declined to grant (`UIBackgroundTaskIdentifier.invalid`), so a
  /// short-lived job that never gets backgrounded, or a device that refuses the request outright,
  /// is handled rather than crashing on an invalid identifier.
  ///
  /// `UIApplication.beginBackgroundTask`/`endBackgroundTask` are documented safe to call from any
  /// thread; only the expiration handler itself is guaranteed by the system to run on the main
  /// thread -- the same thread `JobRegistry`'s own main-queue-confinement discipline assumes, so
  /// `JobRegistry.cancel` is called directly from it with no further hop. A plain `NSLock`, not
  /// an actor: `end()` must be callable synchronously from that handler and from `defer`, neither
  /// of which can `await`.
  ///
  /// macOS applications are never suspended, so this whole type -- and every `UIApplication`/
  /// `UIKit` reference in this file -- exists only inside `#if os(iOS)`; macOS compiles to
  /// exactly the code it ran before this plan.
  private final class IOSBackgroundTaskGuard {
    private let lock = NSLock()
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private var ended = false

    /// Begins the background task under `name`, wiring `onExpiration` to run when the system
    /// revokes the extra execution time. Must be called on the main actor (`beginBackgroundTask`
    /// itself is thread-safe, but the plan calls for beginning it there explicitly).
    func begin(name: String, onExpiration: @escaping () -> Void) {
      let id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
        onExpiration()
        self?.end()
      }
      lock.lock()
      identifier = id
      lock.unlock()
    }

    /// Ends the background task exactly once, no matter how many times this is called or from
    /// which of the two call sites (the expiration handler, or the normal `defer` unwind) --
    /// a no-op if it was already ended or if the system never granted a valid identifier.
    func end() {
      lock.lock()
      guard !ended, identifier != .invalid else {
        ended = true
        lock.unlock()
        return
      }
      ended = true
      let id = identifier
      identifier = .invalid
      lock.unlock()
      UIApplication.shared.endBackgroundTask(id)
    }
  }
#endif

/// `CompressHostApi` implementation -- the counterpart of Android's `Compression.kt`.
///
/// Unlike Android, which must assert it is running on the main Looper before touching
/// `Transformer` (Media3's own constraint), Pigeon delivers every call here already on the
/// `MainActor` (`CompressHostApiSetup.setUp` wraps every handler in `Task { @MainActor in ...
/// }`, confirmed in `Messages.g.swift`) -- so `startCompress` instead hops OFF the `MainActor`
/// by `await`ing `runCompress` (nonisolated), whose engine's own copy loop runs on a job-scoped
/// serial queue (03-RESEARCH.md Pattern 1).
///
/// `startCompress` and `awaitCompressResult` are themselves `@MainActor`, and `startCompress`
/// registers its jobId SYNCHRONOUSLY, before its first suspension point (quick task 260927-r4k).
/// A caller on a background isolate fires `startCompress` without awaiting it and immediately
/// calls `awaitCompressResult` for the same jobId; when both methods were nonisolated, each
/// hopped off the `MainActor` the moment Pigeon called it and then hopped back for its own
/// `JobRegistry` access, so nothing ordered `registerJob` before `isKnownJobId` and the second
/// call could win, failing a perfectly good job with "unknown jobId" (CI run 36349558026).
/// Staying on the `MainActor` with no suspension before `registerJob` makes registration
/// complete before the next channel message's handler can run at all -- the same ordering
/// Android's `Compression.kt` gets from the main Looper. Every other `JobRegistry` access
/// happens via explicit `MainActor` hops, both here (`cancel`) and inside `CompressionEngine`.
final class Compression: CompressHostApi {
  private let flutterApi: CompressVideoFlutterApi
  private let engine: CompressionEngine

  init(flutterApi: CompressVideoFlutterApi, engine: CompressionEngine = CompressionEngine()) {
    self.flutterApi = flutterApi
    self.engine = engine
  }

  @MainActor
  func startCompress(path: String, jobId: String, request: CompressRequestMessage) async throws
    -> CompressResultMessage
  {
    // Stays outside the do/catch below: a jobId that fails this format check is never used as
    // a registry key or a filename stem, so it cannot be registered at all.
    try Self.requireValidJobId(jobId)
    // CR-02: registered synchronously, on the MainActor, BEFORE this method's first suspension
    // point and before request validation (260927-r4k) -- mirroring Android's Compression.kt
    // (`JobRegistry.resultDeferredFor(jobId)` ahead of its own first suspension) -- so a
    // concurrent awaitCompressResult(jobId) call, issued by a caller on a background isolate
    // right after this call fires, always finds the jobId known. No `await` here on purpose:
    // an `await` is a suspension point, and a suspension point is exactly where the second
    // call's handler used to overtake this one.
    JobRegistry.registerJob(jobId: jobId)
    do {
      // Inside the do/catch so a request that fails validation is still a known job whose
      // typed failure completeResult records, rather than an "unknown jobId".
      try Arguments.requireValidCompressRequest(request)
      // runCompress is nonisolated, so awaiting it hops OFF the MainActor: none of the probing,
      // free-space or engine work moves onto the main thread because this method is isolated.
      let result = try await Self.runCompress(
        path: path, jobId: jobId, request: request, flutterApi: flutterApi, engine: engine)
      JobRegistry.completeResult(jobId: jobId, result: .success(result))
      return result
    } catch {
      // Every path through runCompress below reaches this catch without depending on any
      // Dart-side acknowledgement (this engine's onProgress push is already fire-and-forget --
      // see the AsyncStream comment below), so this outer wrapper alone is sufficient to make
      // the outcome available to awaitCompressResult; no further per-branch hook is needed
      // (05-02, mirrors Compression.kt's identical outer catch-all).
      JobRegistry.completeResult(jobId: jobId, result: .failure(error))
      throw error
    }
  }

  /// Resolves once the job identified by `jobId` reaches a terminal outcome, per
  /// `CompressHostApi.awaitCompressResult`'s contract (05-02) -- see that Pigeon dartdoc for the
  /// full rationale. On this platform `startCompress`'s own reply was never blocked on any
  /// Dart-side acknowledgement in the first place (unlike Android, whose native progress push
  /// IS awaited directly before returning) -- this exists as the documented, symmetric escape
  /// hatch Pigeon's cross-platform contract promises regardless.
  ///
  /// `@MainActor` so the consumed/known checks below run in channel-handler order with no hop
  /// (260927-r4k) -- see this class's own doc comment.
  @MainActor
  func awaitCompressResult(jobId: String) async throws -> CompressResultMessage {
    try Self.requireValidJobId(jobId)
    // CR-02: requireValidJobId only checks the <counter>-<hex> FORMAT, not whether
    // startCompress was ever called for this jobId. Without this guard, a well-formed but
    // unknown or already-consumed jobId would fall straight into JobRegistry.awaitResult's
    // `withCheckedThrowingContinuation`, appending a continuation nothing will ever resume --
    // an unbounded hang with no typed error, directly contradicting this project's "never
    // hangs, never returns null" core value.
    if JobRegistry.isConsumedJobId(jobId) {
      throw CompressVideoError(
        code: "unknown",
        message:
          "awaitCompressResult called again for jobId \"\(jobId)\", whose result was already "
          + "consumed by an earlier awaitCompressResult call",
        details: nil
      )
    }
    // Belt and braces (260927-r4k): startCompress's synchronous MainActor registration already
    // orders itself ahead of this call whenever the two messages arrive in the order Dart sent
    // them. Should anything in the messenger ever deliver them the other way round, wait a
    // bounded 2 s (40 x 50 ms) for the registration to land before concluding the jobId is
    // genuinely unknown -- still typed, still never a hang.
    var known = JobRegistry.isKnownJobId(jobId)
    var remainingPolls = Self.knownJobIdGracePolls
    while !known && remainingPolls > 0 {
      try await Task.sleep(nanoseconds: Self.knownJobIdGracePollNanoseconds)
      known = JobRegistry.isKnownJobId(jobId)
      remainingPolls -= 1
    }
    if !known {
      throw CompressVideoError(
        code: "unknown",
        message:
          "awaitCompressResult called for unknown jobId \"\(jobId)\": startCompress was never "
          + "called for it",
        details: nil
      )
    }
    return try await JobRegistry.awaitResult(jobId: jobId)
  }

  private static func runCompress(
    path: String, jobId: String, request: CompressRequestMessage,
    flutterApi: CompressVideoFlutterApi, engine: CompressionEngine
  ) async throws -> CompressResultMessage {
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
    try await Self.requireSufficientFreeSpace(
      inputURL: URL(fileURLWithPath: standardizedPath), inputInfo: inputInfo, request: request,
      destinationURL: destinationURL, engine: engine)

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

    #if os(iOS)
      // iOS-only background task (D-11/D-12): asks the system for extra execution time so a job
      // that is still running when the app is backgrounded gets a chance to finish. When that
      // time runs out, the expiration handler cancels THIS job through the existing
      // cancellation path with the retryable "interrupted" reason -- the suspended
      // `engine.compress` call below then resolves with a typed, retryable failure instead of
      // hanging or being killed mid-write. macOS is never suspended, so none of this exists
      // there.
      let backgroundTaskGuard = IOSBackgroundTaskGuard()
      await MainActor.run {
        backgroundTaskGuard.begin(name: "compress_video.job.\(jobId)") {
          JobRegistry.cancel(jobId: jobId, reason: "interrupted")
        }
      }
      defer { backgroundTaskGuard.end() }
    #endif

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
  private static func requireSufficientFreeSpace(
    inputURL: URL, inputInfo: MediaInfoMessage, request: CompressRequestMessage,
    destinationURL: URL, engine: CompressionEngine
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

  /// `awaitCompressResult`'s bounded grace for a jobId `startCompress` has not registered yet:
  /// 40 polls 50 ms apart, 2 s in total. Mirrors `Compression.kt`'s
  /// `KNOWN_JOB_ID_GRACE_POLLS`/`KNOWN_JOB_ID_GRACE_POLL_MS` exactly.
  private static let knownJobIdGracePolls = 40
  private static let knownJobIdGracePollNanoseconds: UInt64 = 50_000_000

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
