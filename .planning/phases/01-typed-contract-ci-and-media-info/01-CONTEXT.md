# Phase 1: Typed Contract, CI and Media Info - Context

**Gathered:** 2026-09-15
**Status:** Ready for planning
**Mode:** Smart discuss, autonomous run — recommended answers auto-accepted (unattended). Every decision below is a default Dan can override; none is irreversible.

<domain>
## Phase Boundary

Deliver a Flutter plugin package `compress_video` (Android, iOS, macOS) whose only working
calls are media info and thumbnails, going end to end through a Pigeon typed contract, with a
committed starter corpus and green CI on a Linux runner and a macOS runner. Compression itself,
presets, jobs, progress and cancel are later phases; this phase may reserve names for them in the
contract but must not implement them.

Requirements in scope: BULD-03 (Pigeon, one unit per quantity), BULD-05 (CI), INFO-01 (media
info), INFO-02 (thumbnails).

Environment facts fixed at discuss time (2026-09-15):
- Flutter 3.44.1 stable / Dart 3.12.1 at `~/development/flutter/bin`.
- No Java, no Android SDK on danserver. `/dev/kvm` exists; `dan` is in `render` but **not**
  `kvm` — the plan must add the group (or `sudo chmod`/udev) before the emulator will accelerate.
- `ssh dans-macbook-air` is refused (QUESTIONS.md #1). Apple verification in this phase runs
  only on the GitHub Actions macOS runner.
- `gh` is authenticated as `danieljamesjohnson` (GitHub **free** plan). No GitHub repository
  exists yet; origin is the danserver bare repo. Free plan: 2,000 Actions minutes/month on
  private repos, macOS billed at 10×; public repos are unlimited.
- ffmpeg is installed on danserver. No phone-recorded clips exist on the box.

</domain>

<decisions>
## Implementation Decisions

### Dart API surface (info + thumbnails)
- Entry point is a `CompressVideo` class with a `const CompressVideo()` constructor and an
  optional `BinaryMessenger` parameter (for background isolates in Phase 5). No static singleton,
  no global state. Methods in this phase: `getMediaInfo(String path)`, `getThumbnail(String path,
  {int positionMs = 0, int quality = 80, int? maxDimensionPx})` and `getThumbnailFile(... ,
  {String? outputPath})`. Verb names deliberately echo `video_compress` for migrants.
- Public model types (`MediaInfo`, `Thumbnail`/thumbnail file result) are hand-written immutable
  Dart classes with dartdoc on every field, mapped from the Pigeon-generated classes. Generated
  classes stay private in `lib/src/messages.g.dart`. Reason: the public API must stay stable and
  documented independently of the wire format, and pub.dev scores documented public members.
- `getThumbnail` returns `Uint8List` JPEG bytes. `getThumbnailFile` writes a JPEG with a unique
  name in the app cache directory (or at `outputPath` if given) and returns its path.
  `quality` is 1-100 JPEG quality; `maxDimensionPx` caps the longer side, never upscales.
- Failures complete the Future with a typed `CompressVideoException` carrying a `reason` enum
  (at least `fileNotFound`, `unsupportedInput`, `decoderUnavailable`, `io`, `cancelled`,
  `unknown` — later phases add `encoderUnavailable`, `outOfSpace`, `interrupted`), a
  human-readable `message` and an optional `platformDetail` string. No call ever resolves to
  `null`; a raw `PlatformException` never escapes the public API.

### Pigeon contract conventions
- Every numeric quantity crossing the channel has its unit in the field name: `durationMs`,
  `positionMs`, `sizeBytes`, `widthPx`, `heightPx`, `videoBitrateBps`, `frameRateFps`,
  `rotationDegrees`. Width/height describe the **displayed** (rotation-corrected) orientation.
  Every field has a dartdoc line stating the unit and the sentinel for unknown (nullable, not 0).
- Single source of truth `pigeons/messages.dart`. Generated outputs: `lib/src/messages.g.dart`,
  Kotlin under `android/src/main/kotlin/com/danjjohnson/compress_video/Messages.g.kt`, Swift in
  the shared `darwin/` tree. Android namespace `com.danjjohnson.compress_video`. A CI step
  regenerates and fails on any diff. Pigeon version pinned in `dev_dependencies` (verify latest
  during research; note its Swift/Kotlin generator options).
- Error transport: native code throws `FlutterError(code: <reason enum name>, message, details)`;
  the Dart wrapper maps `PlatformException.code` to `CompressVideoException.reason`, falling back
  to `unknown` with the original code preserved in `platformDetail`. Success replies contain only
  success data.
- All host methods are `@async`. Native work (metadata read, frame decode, JPEG encode) runs off
  the main/platform thread (Kotlin executor or coroutine; Swift `DispatchQueue`) and replies on
  the platform thread. This is the shape later compression jobs will reuse.

### Repository layout, Apple packaging, corpus
- Plugin lives at the repository root (pub-ready `pubspec.yaml`), with `example/`, `pigeons/`,
  `test/`, `example/integration_test/`, and `corpus/`. `corpus/` and `.planning/` are excluded
  from the published package via `.pubignore`. Corpus clips are committed directly (each under
  ~2 MB); no git LFS.
- Apple code lives once in `darwin/` using Flutter's `sharedDarwinSource: true` for both `ios`
  and `macos` in the pubspec plugin block, with one podspec and one `Package.swift` so both
  CocoaPods and Swift Package Manager install from the same sources. Verify during research that
  Flutter 3.44's plugin template supports this for SPM; if not, fall back to `ios/` + `macos/`
  with a shared `darwin/Sources` referenced by both.
- Phase 1 corpus is generated by ffmpeg on danserver to mirror phone output structurally:
  (a) `portrait_rot90.mp4` — frames encoded 1920×1080 with a 90° display matrix (as phones do),
  H.264 + AAC stereo, ~4 s, moving pattern with a burnt-in millisecond timecode so a thumbnail at
  1500 ms is visually checkable; (b) `small_480p.mp4` — an already-small, low-bitrate clip;
  (c) `noaudio_720p.mp4` — no audio track. Each clip ships with a sidecar `*.expected.json`
  holding the ground-truth `MediaInfo` values produced by ffprobe, which the integration tests
  assert against. Real phone clips (iPhone Dolby Vision, Pixel HLG) are requested from Dan in
  QUESTIONS.md and join the corpus in Phase 4; the generation script is committed so clips are
  reproducible.
- Local Android toolchain on danserver: `openjdk-17-jdk-headless` via apt (passwordless sudo),
  Android cmdline-tools into `~/Android/Sdk` with `platform-tools`, `platforms;android-36`,
  matching `build-tools`, `emulator`, and one `system-images;android-35;google_apis;x86_64`
  image (fallback to 36 if 35 is unavailable). `ANDROID_HOME`/`ANDROID_SDK_ROOT` exported from
  `~/.profile` and `~/.bashrc`, plus `flutter config --android-sdk`. Emulator runs headless
  (`-no-window -gpu swiftshader_indirect -no-audio -no-boot-anim`) with KVM. Record every install
  step in the project `.claude/CLAUDE.md` lane notes so the next agent does not re-derive it.

### CI design
- Create a **private** GitHub repository `danieljamesjohnson/compress_video` with `gh`, add it as
  the `github` remote, keep the danserver bare repo as `origin`, and push `main` to both. Making
  the repo public is Dan's call (record in QUESTIONS.md: it is the intended MIT end state and
  would lift the Actions minute cap).
- Workflow `.github/workflows/ci.yml` triggers on `push` (main), `pull_request`, and
  `workflow_dispatch`, with `paths-ignore` for `.planning/**`, `**/*.md`, `QUESTIONS.md`, and a
  `concurrency` group per ref with `cancel-in-progress: true`. The macOS job is additionally
  gated to run only when Apple-relevant paths change (`darwin/**`, `pigeons/**`, `lib/**`,
  `example/**`, `pubspec.yaml`, the workflow file) to protect the 10× macOS minute multiplier
  while the repo is private.
- Linux job (`ubuntu-latest`): checkout, Flutter stable via `subosito/flutter-action`, JDK 17,
  `flutter pub get`, `dart format --output=none --set-exit-if-changed .`, `flutter analyze
  --fatal-infos --fatal-warnings`, Pigeon regeneration + `git diff --exit-code`, `flutter test`,
  `dart pub publish --dry-run`, `flutter build apk --debug` in `example/`, Gradle unit tests for
  the plugin module, then an emulator step (`reactivecircus/android-emulator-runner`, API 35
  x86_64 google_apis) running `flutter test integration_test` in `example/` against the corpus.
- macOS job (`macos-latest`): Flutter stable, `flutter build ios --simulator --no-codesign`
  (CocoaPods path), `flutter build macos --debug`, a second build with
  `flutter config --enable-swift-package-manager` to prove the SPM path, XCTest native unit tests
  via `xcodebuild test` on the example's iOS Runner scheme, and `flutter test integration_test`
  on a booted iOS simulator. Analyzer strictness comes from `analysis_options.yaml`
  (`flutter_lints` plus `strict-casts`, `strict-inference`, `strict-raw-types`).

### Claude's Discretion
- Exact enum names, file names within `lib/src/`, the JPEG encoder call on each platform, the
  choice of Pigeon generator options, the emulator API level if 35 is unavailable, and the
  ffmpeg filter graph for the corpus clips.
- Whether `MediaInfo` exposes an `hdrFormat` enum in this phase or only `isHdr` (it must at least
  expose `isHdr`; the detection method per platform is research territory).

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- None — the repository contains only planning documents, `README.md`, `QUESTIONS.md`,
  `.gitignore` and Mission Control lane config. Phase 1 creates the package from the Flutter
  plugin template.

### Established Patterns
- None in code yet. The research (`.planning/research/ARCHITECTURE.md`) fixes the intended
  layout: `lib/compress_video.dart` public API, `lib/src/*` models, `pigeons/messages.dart`
  contract, `android/.../Probe.kt` and `Thumbnails.kt`, Swift `Probe.swift` and
  `Thumbnails.swift` in the shared Apple core.
- Planner and executors must read `.planning/research/sources/VIDEO_COMPRESS_BRIEF.md` (per the
  project CLAUDE.md) and `.planning/research/PITFALLS.md` before planning; pitfalls 1, 2, 7, 14,
  15, 21 and 24 are the ones this phase must design against.

### Integration Points
- `.claude/CLAUDE.md` lane notes must gain the Android SDK / JDK / emulator facts once installed.
- `QUESTIONS.md` gains: #4 real phone clips for the corpus; #5 flip the GitHub repo public.
- `.planning/STATE.md` blockers: Android SDK item clears in this phase; Mac SSH item stays.

</code_context>

<specifics>
## Specific Ideas

- Success criterion 1 requires the same `MediaInfo` values from the Android emulator and the iOS
  simulator. Encode the expectations once in the corpus sidecar JSON and run the same
  `integration_test` on both, so parity is asserted by one test file rather than two.
- Success criterion 2 (thumbnail "from the same moment on every platform") is why the corpus
  clip carries a burnt-in timecode: the test can OCR-free check by sampling a pixel region whose
  colour changes every 500 ms, which is cheaper and deterministic.
- Keep "compress" names out of the public API in this phase except as reserved dartdoc mentions;
  the compat shim (`video_compress` verbs) is Phase 6.
- The plan should include a standing "toolchain pins" note (Flutter, AGP, Kotlin, Gradle, Pigeon,
  media3, Xcode) written to `.planning/research/` or `docs/` so the quarterly toolchain-rot check
  has a baseline.

</specifics>

<deferred>
## Deferred Ideas

- Pre-flight `estimate()` (INFO-03) — Phase 2.
- Compression result/error union shape for jobs — Phase 2 (this phase only fixes the exception
  type and reason enum that jobs will extend).
- Real iPhone/Pixel HDR corpus clips — Phase 4, pending Dan (QUESTIONS.md).
- Making the GitHub repository public — Dan's decision; recorded in QUESTIONS.md.
- Verifying on the MacBook Air simulator/device — blocked on QUESTIONS.md #1; Phase 3 starts with
  a Mac-readiness check.

</deferred>
