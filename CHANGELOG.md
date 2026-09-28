## 1.0.0

The first release on pub.dev. `compress_video` is the drop-in successor to `video_compress`: one
call turns a phone video into a smaller H.264/AAC MP4 on Android, iOS and macOS, the output is
never larger than the input, no call ever returns `null`, and an app that still uses the old
package can switch by changing one import.

### Breaking changes (since 0.1.0)

0.1.0 was a development version and was never published, so these matter only to an app that
depended on this repository by git. Each item says what to change.

* **`CompressVideo`'s constructor is no longer `const`.** The job queue is state that belongs to
  one instance. Fix: remove `const` from every `const CompressVideo(...)`, and declare a shared
  instance as `final` instead of `const`.
* **Jobs beyond `maxConcurrentJobs` now wait in a queue.** The default is 1, so two `compress()`
  calls on the same `CompressVideo` run one after the other, not at the same time.
  `CompressJob.isQueued` says whether a job has started. Fix: pass
  `CompressVideo(maxConcurrentJobs: n)` to run `n` jobs at once, or use one instance per job.
* **`CompressVideoErrorReason.encoderUnavailable`, `outOfSpace` and `interrupted` are now real
  outcomes.** A `switch` over the reason must handle all three; `interrupted` means the system
  stopped the job and the same call can be tried again. Fix: add the three cases, or a default
  branch.
* **`CompressOptions.validate()` no longer rejects `VideoCodec.hevc` or `HdrMode.keepHdr`.** Both
  are now supported options. A device that cannot do either still returns a file, and reports it
  with `CompressResult.hevcFallback` and `CompressResult.toneMapped`. Fix: check those two flags
  instead of catching the rejection.
* **`CompressResult.toneMapped`, `hevcFallback` and `audioReencoded` can now be `true`.** They
  were always `false` while HDR, HEVC and unusual audio were not supported. When
  `usedOriginal` is `true`, all of them are `false`. Fix: nothing, unless the app assumed they
  were constant.
* **An unexpected error is now a `CompressVideoException` with reason `unknown`.** Before, a
  non-platform error from `getMediaInfo`, `getThumbnail`, `getThumbnailFile`, `estimate` or
  `clearCache` could escape as its own type. Fix: catch `CompressVideoException`; the original
  error is in `platformDetail`.
* **Waiting on a job that was never started fails after about 2 seconds, not at once.** This
  applies to the platform method `awaitCompressResult`, which the package calls for a job started
  from a background isolate. The wait closes a race on Apple where the result was requested
  before the job was registered. An app that uses only the public API does not reach this case.
  Fix: nothing.

`CompressResult` and `CompressEstimate` have no new required constructor parameters.

### Added in 1.0.0

* **The compatibility import.** `package:compress_video/video_compress_compat.dart` has the
  documented surface of `video_compress` 3.1.4 (`VideoCompress`, `VideoQuality`, `MediaInfo`,
  `compressProgress$`) on the new engine; `MIGRATION.md` lists the few names that are not
  provided. Every symbol is marked `@Deprecated` and names its
  replacement. A failure throws a typed exception where the old package returned `null`.
* **`MIGRATION.md`.** Every old name next to its new call, the `MediaInfo` fields, and what each
  `VideoQuality` value maps to. A test keeps the guide in agreement with the code.
* **A generated preset table in the README.** "Presets at a glance" is built from the preset
  constants and the measurements in `doc/PRESETS.md` by
  `flutter test tool/generate_preset_table.dart`. A CI gate fails when the table is out of date.
* **A pub.dev score gate.** CI runs `pana` and fails unless the package is granted every point,
  and a second gate fails on any dartdoc warning.
* **`doc/RELEASE.md`.** The release procedure, starting with the hardware checklist. It is in
  the repository and is not part of the published package.

### Everything else since 0.1.0

* **Jobs, isolates and background execution (Phase 5)** — three additions, landed together and
  documented together in the README's "Jobs beyond the foreground" section, in the order a caller
  runs into them:
  * **Job queue (JOBS-03)** — `CompressVideo({int maxConcurrentJobs = 1})` and
    `CompressJob.isQueued` are new: submitting more jobs than `maxConcurrentJobs` now queues the
    extras in FIFO order on the Dart side instead of requiring the caller to serialise calls
    manually, with each job's `progress`/`result` staying fully independent regardless of queue
    position and cancelling a still-queued job resolving the same typed `cancelled` failure a
    cancelled running job produces, without ever reaching the platform. `maxConcurrentJobs` must
    be at least 1; the native engines are unchanged — the queue is Dart-only.
    **Breaking:** `CompressVideo`'s constructor is no longer `const` (the queue is per-instance
    mutable state, and Dart's `const` canonicalisation would otherwise make two `const
    CompressVideo()` expressions silently share one queue, contradicting per-instance
    independence). Any `const CompressVideo(...)` call site needs to drop the `const`.
  * **Background isolates (JOBS-04)** — `CompressVideo.ensureInitializedInBackgroundIsolate
    (RootIsolateToken)` is new: call it as the first statement inside an `Isolate.run`/`compute`
    closure and every call in this package, including `compress()`, works from that isolate.
    Progress is never delivered to a background isolate's job (a permanent Flutter engine
    constraint, not a bug here); `result` resolves normally. Skipping the call fails the first
    platform call with a typed `CompressVideoException` rather than a hang or `null`. Closes the
    incumbent `video_compress`'s issue #242 ("cannot run in a background isolate").
  * **Background execution and app suspension (JOBS-05)** —
    `CompressVideoErrorReason.interrupted` (reserved since Phase 3) is now a real outcome on both
    native engines, both retryable: on Android, opting a job into
    `CompressOptions.androidForegroundService` runs it inside a real `mediaProcessing` foreground
    service (Android 15+ only; inert below that) that survives the app moving to the background,
    ended honestly with `interrupted` if the system's own six-hour-per-24-hour quota for that
    service type ever expires mid-job; on iOS, every running job now holds a system background
    task (`beginBackgroundTask`) so a short export usually finishes after the app is backgrounded,
    and resolves with `interrupted` — its partial output deleted — when that extra time runs out
    or AVFoundation itself reports the interruption. Neither platform requests a background
    entitlement or capability the host app did not already have; macOS is unaffected (it is never
    suspended).
* **Codecs, HDR and hard inputs (Phase 4)** — HEVC is now an opt-in (`VideoCodec.hevc`), used
  only when the device has a hardware HEVC encoder and falling back to H.264 with
  `hevcFallback: true` reported otherwise, on both Android (`CodecCapabilities`/`EncoderUtil`)
  and Apple (`CodecCapabilities`/`VTCopyVideoEncoderList`). HDR input (Dolby Vision profile 8,
  HLG, HDR10) is tone-mapped to SDR by default (`toneMapped: true`), with an `HdrMode.keepHdr`
  opt-in that outputs HEVC Main10 HDR (HLG or PQ transfer, BT.2020 primaries) on a capable device
  and falls back to tone-mapped SDR, reported via both flags, on one that isn't. Sources with 5.1
  audio, PCM/uncompressed audio, or no audio track at all compress successfully by downmixing or
  re-encoding to 2-channel AAC (`audioReencoded: true`) rather than failing. A committed corpus of
  HDR, unusual-audio and 4K60 clips runs through `example/integration_test/hard_inputs_test.dart`
  on the Android emulator, the iOS simulator and the macOS host in CI, with cross-platform
  compression parity records for every case proven identical across all three; the macOS CI
  runner's real Apple Silicon Media Engine is the first place this project's own CI has proven the
  HEVC-success and keep-HDR-success paths. `doc/HARDWARE_CHECKLIST.md` documents what only a
  physical Android phone and a real Dolby Vision clip can still prove.
* **Apple compression engine** — `AVAssetReader`/`AVAssetWriter` on iOS (13+) and macOS (11+),
  sharing one Swift core with the media-info/thumbnail code from the initial release:
  presets and explicit targets (max long side, bitrate, target file size), never-larger,
  transmux fast path, frame-rate cap, audio passthrough/re-encode/strip, per-job progress and
  cancel, typed errors, and the pre-flight `estimate()` — the same observable behaviour Android
  already had, proven by the same integration-test suites running unmodified on the iOS
  simulator and the macOS host in CI.
* **Trim on all three platforms** — `trimStartMs`/`trimEndMs`, honoured within one output frame
  on Android, iOS and macOS alike.
* **Both install paths on Apple** — the package installs through CocoaPods and through Swift
  Package Manager on iOS and macOS from the same shared `darwin/` source tree, both proven by CI
  builds of the example app.
* **A real example app** — pick a video, choose options, compress with live progress and cancel,
  see a result card (bytes saved, dimensions, codec, transmux/never-larger/re-encode badges,
  elapsed time), and play the output back — on Android, iOS and macOS.
* **Cross-platform parity gate widened to compression** — the same `PARITY_JSON` mechanism that
  already compared media-info and thumbnail values now diffs compression results (dimensions,
  codecs, the three shortcut flags, duration) between Android, iOS and macOS in CI, with output
  bytes and elapsed time deliberately excluded as platform-dependent by design (see the README's
  "What 'the same on every platform' means" section and `doc/PRESETS.md`'s measured tables).

## 0.1.0

Initial unreleased development version. Not yet published to pub.dev.

* Plugin scaffold for Android, iOS and macOS with a shared `darwin/` Apple source tree.
* Typed error taxonomy (`CompressVideoException`, `CompressVideoErrorReason`).
* Typed Pigeon contract for every Dart-native call; no hand-written channel map anywhere in the
  package, enforced by a dedicated CI check.
* `CompressVideo.getMediaInfo(path)` — duration, displayed (rotation-corrected) dimensions,
  rotation, size, codec, bitrate, frame rate, audio presence and HDR-ness, on Android
  (`MediaMetadataRetriever`) and Apple (`AVFoundation`).
* `CompressVideo.getThumbnail` / `getThumbnailFile` — a rotation-correct poster frame as JPEG
  bytes or written to a file, at any millisecond, with quality and max-dimension controls that
  never upscale.
* CI on a Linux runner (Android) and a macOS runner (iOS + macOS), path-gated.
* A cross-platform parity gate (`tool/check_parity.sh`): a dedicated CI job diffs the
  `crossPlatform` media-info and thumbnail values the Android emulator and the iOS simulator
  each actually observed, so "the two platforms agree" is a diff, not an inference from running
  the same test file on both.
* CI is green on both runners plus the parity gate (run 35631865999).
