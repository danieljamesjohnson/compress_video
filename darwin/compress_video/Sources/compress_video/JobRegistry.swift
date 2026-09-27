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
  ///
  /// WR-02: also resets every CR-02 bookkeeping collection (`resultOutcomes`, `resultWaiters`,
  /// `knownJobIds`, `consumedJobIds`) the same way Android's `JobRegistry.kt` `cancelAll()` does
  /// (D-17) -- without this, `knownJobIds`/`consumedJobIds` and any stashed `resultOutcomes` grow
  /// for the entire process lifetime across every `FlutterEngine` attach/detach cycle (a Swift
  /// `enum`'s `static` state persists across engine teardown, unlike a process exit). These four
  /// collections are `@MainActor`-isolated (unlike `jobs`, plain `nonisolated` state), so the
  /// reset runs inside a `Task { @MainActor in ... }` -- the same fire-and-forget hop-to-MainActor
  /// pattern this package already uses from a synchronous call site (`Compression.swift`'s
  /// progress-forwarding `Task { @MainActor [flutterApi] in ... }`) -- rather than making
  /// `cancelAll()` itself `async`/`@MainActor`, which would force the synchronous, non-`async`
  /// `FlutterPlugin` override points that call it (`detachFromEngine(for:)`,
  /// `handleWillTerminate(_:)`) to become `@MainActor`-isolated too, a change outside this fix's
  /// scope. Every continuation in `resultWaiters` is resumed with a typed cancellation error
  /// before the dictionary is cleared -- an unresumed `CheckedContinuation` is a Swift Concurrency
  /// runtime misuse (it must be resumed exactly once), so silently dropping it the way
  /// `.removeAll()` alone would is not an option here the way it is for Android's plain,
  /// continuation-free bookkeeping.
  ///
  /// WR-04: records every jobId being cancelled into `tornDownJobIds` BEFORE the enqueued
  /// `Task` clears the other four collections -- mirrors Android's `JobRegistry.kt` `cancelAll()`
  /// recording into its own `tornDownJobIds` before its `.clear()` calls (WR-01). `cancel(jobId:)`
  /// only synchronously flips a flag / invokes the cancel closure; the suspended
  /// `Compression.startCompress` call's own catch block, which actually calls `completeResult`,
  /// always resumes on a LATER main-queue turn, after this function (and its enqueued `Task`)
  /// have already run. Without `tornDownJobIds`, that belated `completeResult` call would find no
  /// waiters (already cleared) and silently stash a fresh, never-to-be-read `resultOutcomes`
  /// entry for a job that no longer exists in any other bookkeeping -- the same leak WR-01 closed
  /// on Android.
  static func cancelAll() {
    let jobIdsBeingCancelled = Array(jobs.keys)
    for jobId in jobIdsBeingCancelled {
      cancel(jobId: jobId)
    }
    Task { @MainActor in
      tornDownJobIds.formUnion(jobIdsBeingCancelled)
      resultOutcomes.removeAll()
      let pendingWaiters = resultWaiters
      resultWaiters.removeAll()
      for waiters in pendingWaiters.values {
        for waiter in waiters {
          waiter.resume(
            throwing: CompressVideoError(
              code: "unknown",
              message: "The plugin detached before this job's outcome could be delivered",
              details: nil))
        }
      }
      knownJobIds.removeAll()
      consumedJobIds.removeAll()
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

  /// Every job id `registerJob` has ever been called for (CR-02), kept even after its outcome
  /// is delivered and consumed -- mirrors Android's `JobRegistry.kt` `knownJobIds`. Backs
  /// `isKnownJobId`: the guard `Compression.awaitCompressResult` checks before ever calling
  /// `awaitResult`, which would otherwise happily append a continuation to `resultWaiters` that
  /// nothing will ever resume for a jobId nothing ever started.
  @MainActor private static var knownJobIds: Set<String> = []

  /// Every job id whose outcome has already been delivered to a caller once -- either via
  /// `awaitResult` removing it from `resultOutcomes`, or via `completeResult` resuming an
  /// already-registered waiter (CR-02). Mirrors Android's `JobRegistry.kt` `consumedJobIds`.
  /// Backs `isConsumedJobId`: a second `awaitCompressResult` call for the same jobId fails typed
  /// instead of appending a continuation nothing will ever resume a second time.
  @MainActor private static var consumedJobIds: Set<String> = []

  /// WR-04: jobIds `cancelAll()` has cancelled whose belated `completeResult` call (from the
  /// suspended `Compression.startCompress` call's own catch block, resumed on a LATER main-queue
  /// turn than `cancelAll()`'s own call stack) has not yet arrived. Mirrors Android's
  /// `JobRegistry.kt` `tornDownJobIds` exactly, including self-cleaning: `completeResult` removes
  /// a jobId the instant that belated call arrives and is discarded, so this only ever holds
  /// entries for jobs currently unwinding from the MOST RECENT `cancelAll()` -- never growing
  /// across the plugin's lifetime the way an undrained `resultOutcomes` would.
  @MainActor private static var tornDownJobIds: Set<String> = []

  /// Registers `jobId` as known -- must be called by `Compression.startCompress` before any
  /// async work begins (mirrors Android's `resultDeferredFor` pre-registration, called at the
  /// same point in `Compression.kt`), so a concurrent `awaitCompressResult` call for this jobId
  /// is told apart from one for a jobId nothing ever started (CR-02).
  @MainActor static func registerJob(jobId: String) {
    knownJobIds.insert(jobId)
  }

  /// True if `registerJob` was ever called for `jobId` -- i.e. one `Compression.startCompress`
  /// pre-registered -- regardless of whether its outcome has since been consumed. `false` for a
  /// jobId nothing ever started, the CR-02 guard `Compression.awaitCompressResult` checks before
  /// ever calling `awaitResult`.
  @MainActor static func isKnownJobId(_ jobId: String) -> Bool {
    knownJobIds.contains(jobId)
  }

  /// True once `jobId`'s outcome has already been delivered to a caller once (CR-02) -- i.e. a
  /// second `awaitCompressResult` call for the same jobId. Checked before `isKnownJobId` so the
  /// two cases get distinct, diagnosable error messages instead of both silently hanging.
  @MainActor static func isConsumedJobId(_ jobId: String) -> Bool {
    consumedJobIds.contains(jobId)
  }

  /// Completes `jobId`'s outcome with `result` -- delivered immediately to every continuation
  /// already waiting (`awaitResult` called first), or stashed for a not-yet-arrived
  /// `awaitResult` call to claim (the job finished first) -- a no-op if `jobId`'s outcome was
  /// already recorded once. Callers hop to `MainActor` explicitly (matching every other
  /// `JobRegistry` access in this file, e.g. `Compression.cancel`), since `Compression
  /// .startCompress` itself is not `MainActor`-isolated.
  @MainActor static func completeResult(jobId: String, result: Result<CompressResultMessage, Error>)
  {
    if tornDownJobIds.remove(jobId) != nil {
      // WR-04: this jobId was cancelled by a PRIOR cancelAll() call, and this is that
      // cancellation's belated completion finally unwinding back through
      // Compression.startCompress's catch block -- after cancelAll()'s enqueued Task already
      // cleared resultWaiters/knownJobIds/consumedJobIds for it. The plugin has detached; nothing
      // is ever going to call awaitCompressResult for this jobId again, and there is no
      // guaranteed future cancelAll() to sweep a fresh resultOutcomes entry. Discard the outcome
      // here instead of letting the resultOutcomes stash below resurrect it. Mirrors Android's
      // JobRegistry.kt completeResult's tornDownJobIds check exactly (WR-01).
      return
    }
    if let waiters = resultWaiters.removeValue(forKey: jobId), !waiters.isEmpty {
      // CR-02: this jobId's outcome is delivered exactly once here -- nothing will ever call
      // completeResult for it again, so mark it consumed the same way the resultOutcomes path
      // below does, rather than leaving a later awaitCompressResult call free to register a
      // waiter that will never be resumed.
      consumedJobIds.insert(jobId)
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
  /// for it, otherwise suspending until it does. Backs `Compression.awaitCompressResult`, which
  /// must confirm `isKnownJobId`/`isConsumedJobId` (CR-02) before ever calling this -- unlike
  /// those checks, this method itself still has no way to distinguish "known, not yet finished"
  /// from "unknown" once it reaches the continuation branch.
  @MainActor static func awaitResult(jobId: String) async throws -> CompressResultMessage {
    if let outcome = resultOutcomes.removeValue(forKey: jobId) {
      consumedJobIds.insert(jobId)
      return try outcome.get()
    }
    return try await withCheckedThrowingContinuation { continuation in
      resultWaiters[jobId, default: []].append(continuation)
    }
  }
}
