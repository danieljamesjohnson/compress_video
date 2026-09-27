import Foundation

/// Main-queue-confined registry of live compression jobs, keyed by job id.
///
/// Mirrors Android's `JobRegistry.kt`: every method here must be called from the main queue --
/// the same discipline Kotlin's version applies to the main Looper. Main-queue confinement is
/// the synchronization here: there is no lock and no cross-thread mutable state, matching the
/// Kotlin original exactly (it has none either).
///
/// `LiveJob` holds a `cancel` closure rather than a direct `AVAssetReader`/`AVAssetWriter`
/// reference -- the same reasoning as `JobRegistry.kt`'s own doc comment: this keeps the whole
/// object exercisable from plain XCTest with no simulator and no real AVFoundation objects in
/// scope at all (`RunnerTests.swift`'s `// MARK: - JobRegistry` section constructs a `LiveJob`
/// with a plain closure, no `AVAssetReader`/`AVAssetWriter` in sight).
enum JobRegistry {
  /// One job's live state: how to cancel the operation driving it, and the temp file it is
  /// writing to. A class (not a struct) so mutating `cancelled`/`terminal` through a dictionary
  /// lookup is visible to every holder of the same instance, mirroring Kotlin's `LiveJob` class.
  final class LiveJob {
    /// Cancels the operation driving this job, given the reason the caller cancelled it for --
    /// mirrors Kotlin's `LiveJob.onCancelled: (reason: String) -> Unit` (05-04, D-11): the
    /// reason rides the same closure that already existed rather than a second parallel one.
    let cancel: (String) -> Void
    let tempFile: URL

    /// Set the instant `JobRegistry.cancel(jobId:)` actually cancels this job -- guards against
    /// invoking `cancel` a second time.
    fileprivate(set) var cancelled = false

    /// Set by `markTerminal(jobId:)` the instant `CompressionEngine`'s copy loop resolves this
    /// job's outcome (success or failure) -- BEFORE the suspended `compress()` call itself has
    /// resumed and called `remove(jobId:)` (mirrors `JobRegistry.kt`'s own WR-01 race-window
    /// note). A job that is `terminal` has already resolved its outcome on the native side;
    /// `cancel(jobId:)` must treat it exactly like an already-cancelled job and no-op, rather
    /// than deleting a temp file the still-suspended `compress()` call may be about to move
    /// into place.
    fileprivate(set) var terminal = false

    init(cancel: @escaping (String) -> Void, tempFile: URL) {
      self.cancel = cancel
      self.tempFile = tempFile
    }
  }

  private static var jobs: [String: LiveJob] = [:]

  /// Registers `job` under `jobId`. Must be called on the main queue.
  static func register(jobId: String, cancel: @escaping (String) -> Void, tempFile: URL) {
    jobs[jobId] = LiveJob(cancel: cancel, tempFile: tempFile)
  }

  /// Returns the live job for `jobId`, or `nil` if it is unknown or already finished.
  static func find(jobId: String) -> LiveJob? {
    jobs[jobId]
  }

  /// Forgets `jobId` -- the normal path once a job's own completion has already resolved it
  /// and moved (or discarded) its temp file. Does not touch any file itself.
  static func remove(jobId: String) {
    jobs.removeValue(forKey: jobId)
  }

  /// Marks `jobId` `LiveJob.terminal` WITHOUT forgetting it or touching its files -- called by
  /// `CompressionEngine`'s copy loop the instant a job's outcome (success or failure) resolves,
  /// closing the same race window `JobRegistry.kt`'s `stopPolling` closes (WR-01): a `cancel`
  /// call arriving after this point sees a job whose outcome is already decided and no-ops,
  /// rather than deleting a temp file the still-suspended `compress()` call may be about to move
  /// into place. A no-op if `jobId` is unknown.
  static func markTerminal(jobId: String) {
    jobs[jobId]?.terminal = true
  }

  /// Cancels the job identified by `jobId`: marks it cancelled, invokes its cancel closure with
  /// `reason` (which `CompressionEngine` wires to flip its own local flag -- recording `reason`
  /// into the same job-scoped state its copy loop already polls -- and call
  /// `reader.cancelReading()` -- observed by the copy loop on its next sample, per-sample
  /// latency being an accepted bound, D-08), and forgets it. A no-op if `jobId` is unknown,
  /// already cancelled, or already `terminal` -- so cancelling twice, or cancelling after the
  /// job's own outcome already resolved (successfully or not), invokes nothing and does not
  /// throw. Deletes no file itself -- `CompressionEngine`'s own copy loop, which alone holds
  /// the temp file's actual write handle, is responsible for that once it observes the flag
  /// and unwinds; touching the file from here (a different queue than the copy loop runs on)
  /// would race the writer still appending to it.
  ///
  /// `reason` defaults to `"cancelled"` -- an ordinary cancel, from `Compression.cancel` or
  /// `cancelAll` on plugin detach. `Compression`'s iOS-only background-task expiration handler
  /// (D-11) is the only other call site, passing `"interrupted"` for the system taking the
  /// job's execution time away, which the typed error the suspended `startCompress` call throws
  /// then names as retryable -- mirrors Android's `JobRegistry.cancel(jobId, reason)` (05-03)
  /// exactly, including the default.
  static func cancel(jobId: String, reason: String = "cancelled") {
    guard let job = jobs[jobId], !job.cancelled, !job.terminal else { return }
    job.cancelled = true
    job.cancel(reason)
    jobs.removeValue(forKey: jobId)
  }

  /// Cancels every live job -- used by both platforms' teardown paths (iOS's
  /// `detachFromEngine(for:)`, macOS's `handleWillTerminate(_:)`) so no job outlives the plugin.
  static func cancelAll() {
    for jobId in Array(jobs.keys) {
      cancel(jobId: jobId)
    }
  }

  /// The temp file path of every currently-live job -- used by `PluginFiles.sweep` to skip a
  /// file a still-running job is currently writing to, even when `clearCache()` runs mid-job.
  /// Must be called on the main queue, exactly like every other method here.
  static func liveTempFilePaths() -> Set<String> {
    Set(jobs.values.map { $0.tempFile.resolvingSymlinksInPath().path })
  }

  // MARK: - Result deferred (05-02, backs CompressHostApi.awaitCompressResult)

  /// A job's outcome once known but not yet claimed by `awaitResult`, or the continuations
  /// already waiting for a job whose outcome is not yet known -- never both at once for the
  /// same `jobId`. Backs `CompressHostApi.awaitCompressResult`, added because a background
  /// isolate can never receive `CompressVideoFlutterApi.onProgress`'s push -- Kotlin's mirror
  /// (`JobRegistry.kt`'s `resultDeferreds`) needed this for the different reason that its own
  /// `startCompress` blocks on that push before returning; this Swift engine's `onProgress` is
  /// already fire-and-forget (`Compression.swift`'s `AsyncStream`-fed `Task`), so
  /// `startCompress`'s own reply was never blocked here -- `awaitCompressResult` exists purely
  /// as the documented, symmetric escape hatch Pigeon's contract promises on every platform.
  @MainActor private static var resultOutcomes: [String: Result<CompressResultMessage, Error>] =
    [:]
  @MainActor private static var resultWaiters:
    [String: [CheckedContinuation<CompressResultMessage, Error>]] = [:]

  /// Completes `jobId`'s outcome with `result` -- delivered immediately to every continuation
  /// already waiting (`awaitResult` called first), or stashed for a not-yet-arrived
  /// `awaitResult` call to claim (the job finished first) -- a no-op if `jobId`'s outcome was
  /// already recorded once. Callers hop to `MainActor` explicitly (matching every other
  /// `JobRegistry` access in this file, e.g. `Compression.cancel`), since `Compression
  /// .startCompress` itself is not `MainActor`-isolated.
  @MainActor static func completeResult(jobId: String, result: Result<CompressResultMessage, Error>)
  {
    if let waiters = resultWaiters.removeValue(forKey: jobId), !waiters.isEmpty {
      for waiter in waiters {
        waiter.resume(with: result)
      }
      return
    }
    if resultOutcomes[jobId] == nil {
      resultOutcomes[jobId] = result
    }
  }

  /// Awaits `jobId`'s terminal outcome, returning immediately if `completeResult` already ran
  /// for it, otherwise suspending until it does. Backs `Compression.awaitCompressResult`.
  @MainActor static func awaitResult(jobId: String) async throws -> CompressResultMessage {
    if let outcome = resultOutcomes.removeValue(forKey: jobId) {
      return try outcome.get()
    }
    return try await withCheckedThrowingContinuation { continuation in
      resultWaiters[jobId, default: []].append(continuation)
    }
  }
}
