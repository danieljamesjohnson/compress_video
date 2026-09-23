<!-- GSD:project-start source:PROJECT.md -->

## Project

**compress_video**

A Flutter plugin that takes a video the user just recorded or picked, makes it much smaller,
and hands back the new file, on Android, iOS and macOS. It also reads media info and makes
poster-frame thumbnails. It is the drop-in successor to `video_compress` (170k downloads/30d,
abandoned since 2025-02 with 176 open issues), built on Google's and Apple's current media
APIs (Media3 Transformer, AVAssetReader/AVAssetWriter) instead of a dead third-party
transcoder and preset-only export sessions. Audience: Flutter apps where a phone video leaves
the phone (chat clients, short-video feeds, KYC selfie videos, inspection and incident
reporting, marketplace listings) and the SDKs they embed.

**Core Value:** One call turns a phone video into a smaller MP4 that plays everywhere, and it **never makes the
file bigger, never returns null, and builds on today's Flutter toolchain**.

### Constraints

- **Tech stack**: Dart/Flutter plugin; Kotlin + Media3 Transformer on Android; Swift +
  AVFoundation on iOS/macOS; typed platform channels via Pigeon — because the incumbent's
  worst bugs were untyped-channel unit mismatches and swallowed errors

- **Dependencies**: no native `.so` code and no FFmpeg — 16 KB page-size compliance for free,
  small binary, permissive licence

- **Compatibility**: minSdk 23 (Media3 ≥ 1.9), iOS 13+, macOS 11+; Flutter stable; both
  CocoaPods and SPM — because SPM is the incumbent's newest 21-reaction complaint

- **Toolchain**: must build on the *current* Flutter/AGP/Kotlin/Xcode every quarter; a CI matrix
  is a requirement, not a nicety — toolchain rot is the incumbent's largest complaint cluster

- **Verification**: Android on the danserver emulator plus a physical phone for hardware
  encoder/HDR checks; Apple on the MacBook Air (simulator + device); real clips, not synthetic

- **Timeline**: v1 on pub.dev within ~8 weeks of starting; six-month adoption targets above

<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->

## Technology Stack

## Recommended stack

| Layer | Choice | Version (2026-09-14) | Why |
|---|---|---|---|
| Plugin shape | Single Flutter plugin package, `platforms: android, ios, macos`; Swift core shared between ios/ and macos/ | Flutter 3.44 stable | Matches the incumbent's surface; a federated split can come with web in v2 |
| Dart ↔ native | **Pigeon** typed messages | latest stable pigeon | The incumbent's worst bugs were unit mismatches on an untyped `MethodChannel` (thumbnail `position` = ms/µs/s on three platforms) and errors swallowed into `null`. Pigeon gives typed requests, typed results, typed errors, and an event channel for progress |
| Android engine | **androidx.media3:media3-transformer** (+ `-effect`, `-common`, `-muxer`) | **1.11.0** (2026-08-05); minSdk 23 since 1.9.0 | Google-maintained; `setVideoMimeType` H.264/H.265, `VideoEncoderSettings.setBitrate`, `Presentation` resize, `ClippingConfiguration` trim, automatic transmux when input matches, landscape+rotation-metadata handling, `Composition.setHdrMode` tone-mapping (OpenGL path API 29+), `getProgress`/`cancel()`, `InAppMp4Muxer` default. Pure JVM ≈ 4 MB of AARs, no `.so`, so 16 KB pages are a non-issue |
| Android audio | Media3 default audio pipeline; `setAudioMimeType(AUDIO_AAC)` for re-encode, transmux otherwise | same | Passthrough is automatic when formats match |
| Android background | `FOREGROUND_SERVICE_MEDIA_PROCESSING` typed service, opt-in | Android 15+ type, permission `FOREGROUND_SERVICE_MEDIA_PROCESSING` | The dedicated type for "converting media to different formats"; 6 h per 24 h cap; `dataSync` is being restricted further |
| Android build | AGP 8.x current stable with `org.jetbrains.kotlin.android` replaced by AGP's built-in Kotlin where available (AGP 9 path); compileSdk 36; JVM 17 | verify at Phase 1 | The incumbent's largest complaint cluster (64 reactions) is toolchain rot: Kotlin plugin version, `namespace`, JVM target, AGP 9 |
| Apple engine | **AVAssetReader + AVAssetWriter** for encode; `AVAssetExportSession` with `AVAssetExportPresetPassthrough` for remux | iOS 13+ / macOS 11+ | Export presets cannot set a bitrate (only `fileLengthLimit`), don't document resolution/bitrate, and `progress` is deprecated in iOS 27. Writer gives `AVVideoAverageBitRateKey`, `AVVideoCodecType.hevc`, `AVVideoColorPropertiesKey` (HDR), `AVAssetWriterInput.transform`, `outputSettings: nil` + `sourceFormatHint` audio passthrough |
| Apple packaging | CocoaPods podspec **and** `Package.swift` (SPM) | Flutter's SPM plugin support | SPM is the incumbent's newest 21-reaction complaint (#322/#328) |
| Apple HDR | Reader outputs 8-bit BGRA for SDR path (system tone-maps); HEVC Main10 + `AVVideoColorPropertiesKey` HLG/PQ for keep-HDR | WWDC20 10010 | Apple: H.264 presets tone-map to SDR; HEVC presets preserve HDR |
| Thumbnails / info | Android `MediaMetadataRetriever` (+ rotation), Apple `AVAssetImageGenerator` with `appliesPreferredTrackTransform` | platform | Rotation-correct by construction |
| Tests | Dart unit tests; Android instrumentation tests on emulator; XCTest on simulator; committed real-clip corpus | — | Every competitor shipped a regression that a clip corpus would have caught |
| CI | GitHub Actions: `ubuntu-latest` (Android build + emulator integration test), `macos-latest` (iOS simulator + macOS build) | — | Toolchain rot is caught by a green/red build, not by users |
| Docs | dartdoc, README preset tables, `MIGRATION.md`, `example/` | pub.dev scoring | 160/160 points requires all of it |

## What NOT to use, and why

- **otaliastudios / deepmedia Transcoder** (what the incumbent uses): H.264-only, no HDR tone-mapping (open issue #191), last commit 2024-11-05, artifact moved coordinates once already (the JCenter disaster, 24 reactions). It is the dependency to leave behind.
- **Raw MediaCodec + OpenGL surfaces** (what `light_compressor_v2` does): ~4,000 lines of Kotlin to reimplement what Transformer ships; you own colour-format negotiation, HDR shaders, muxer timestamp rules, OEM encoder quirks.
- **FFmpeg / ffmpeg-kit**: 108.9 MB full-GPL Android AAR, 22–29 MB iOS frameworks, effectively GPL v3, software encode is slow and hot. Out of scope by decision.
- **AVAssetExportSession as the primary engine** (what the incumbent and `v_video_compressor` do): no bitrate control, undocumented preset behaviour, deprecated progress API.
- **Untyped `MethodChannel` with `Map<String, dynamic>`**: the unit-mismatch bug class.
- **A global progress stream / single in-flight job** (the incumbent's `compressProgress$` + `isCompressing`): breaks batch and concurrent use (#317, #307).

## Version pins to verify at Phase 1 (do not trust training data)

- media3 latest stable (was 1.11.0 on 2026-08-05); check https://developer.android.com/jetpack/androidx/releases/media3
- AGP / Gradle / Kotlin versions in Flutter 3.44's plugin template; whether AGP 9 built-in Kotlin is stable
- Pigeon latest and its Swift/Kotlin generator options
- Flutter's SPM plugin template and minimum Flutter version for SPM
- Xcode version on the MacBook Air and its iOS SDK

## Sources

- Media3 Transformer: getting-started, transformations, supported-formats pages; `Transformer.java`, `VideoEncoderSettings.java`, `DefaultEncoderFactory.java`, `Composition.java` (mirrors read 2026-09-14)
- Apple: AVAssetExportSession, export-presets, AVAssetWriter/Reader/WriterInput, AVVideoAverageBitRateKey, AVVideoColorPropertiesKey docs; WWDC20 session 10010; forum thread 672056 (background interruption)
- Android page-sizes guide; FGS service-types page
- Competitor source: `light_compressor_v2`, `v_video_compressor`, `flutter_compress`, `ffmpeg_kit_flutter` (cloned 2026-09-14)
- Full detail: `sources/competitors-and-native-apis.md`

<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->

## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->

## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->

## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->

## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:

- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->

## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->

<!-- lane notes (hand-written, outside GSD markers; gsd-update leaves this alone) -->

## Lane notes (danserver)

- **Folder is `compress-video`, package is `compress_video`.** Mission Control lane ids must match `^[a-z0-9][a-z0-9-]{0,39}$`; Dart package names need the underscore. Never rename either.
- **Origin** is the box-hosted bare repo `git@danserver.tailc2efd2.ts.net:danserver/compress-video.git`. Push freely.
- **Mac facts learned 2026-09-22/23 (Phase 3):** a second Flutter SDK is installed on the Mac at `~/development/flutter-stable` (stable 3.47.5, matches CI) — put `$HOME/development/flutter-stable/bin` on `PATH` in remote commands and NEVER touch Dan's `~/flutter` (3.41.2, below this package's pubspec floor). The Mac cannot reach danserver's git remote (only GitHub over https); sync with rsync from danserver (excluding `.git`, `build/`, `.dart_tool/`, `.planning/`, `**/Pods`). It sleeps ~10 min after each wake when on battery with the lid closed and `caffeinate` does not stop that; probe with `timeout 15 ssh -o ConnectTimeout=8 -o BatchMode=yes dans-macbook-air true` before planning any Mac work and never loop on it (QUESTIONS.md #8). CocoaPods cannot be installed on its system Ruby 2.6 by any route (QUESTIONS.md #7 — Homebrew is the fix, needs Dan), and the example's committed Podfiles mean `flutter build ios/macos` there fails with "CocoaPods not installed" even under SPM. Until both are fixed, the GitHub Actions `apple` job is the Apple verifier: ~35-60 min per push, the hosted simulator hangs at app launch on roughly half of all launches (the ci.yml suite step now prebuilds the app, kills a launch with no test output after 150 s and retries up to 5×; runs 35765529347, 35776724779, 35799608545, 35807149965, 35809012150, 35812499597, 35821995638, 35826458554 document the pattern), and the hosted Android emulator occasionally stalls its step for an hour (cancel + `gh run rerun --failed`) or fails the concurrent-cancel case in `compress_jobs_test.dart` (flake — re-run). AVFoundation rules that cost CI attempts: `AVVideoAverageBitRateKey` is only valid INSIDE `AVVideoCompressionPropertiesKey` (a top-level copy makes `canApply(outputSettings:)` reject every H.264 request); AVError -11861 is `unsupportedOutputSettings` (mapped to `encoderUnavailable`); Apple's muxer writes `channelcount=2` in the `mp4a` sample entry even for mono AAC — read the `esds` AudioSpecificConfig instead.
- **Apple builds run on the MacBook Air over SSH: `ssh dans-macbook-air`** (tailnet, user `danjohnson`, configured in `~/.ssh/config` on 2026-09-21). Mac: macOS 26.6.2 arm64, Xcode 26.2, iOS 26.2 simulator runtime, Flutter at `~/flutter/bin` (add to PATH in remote commands). **No CocoaPods and no Homebrew** (QUESTIONS.md #7; agents cannot sudo there) — use the SPM path locally, CocoaPods via CI. The GitHub Actions macOS runner remains the second Apple verifier.
- **Android SDK is installed on danserver** (2026-09-15, phase 1 plan 01-01). `~/Android/Sdk`, `ANDROID_HOME`/`ANDROID_SDK_ROOT` exported from both `~/.profile` and `~/.bashrc`; `flutter config --android-sdk` has been run. `openjdk-17-jdk-headless` (17.0.20) installed via apt. Packages: `platform-tools` (37.0.1), `platforms;android-36`, `emulator` (37.1.11), `build-tools;36.1.0`, `system-images;android-35;google_apis;x86_64`. AVD `compress_video_api35` (device profile `pixel_6`) created with `avdmanager`. `dan` was added to the `kvm` group with `sudo usermod -aG kvm dan` — **this does not apply to sessions started before 2026-09-15; until Dan's next full re-login, run every emulator/adb command through `sg kvm -c '<cmd>'`**, exactly like the `sg docker` pattern in the global CLAUDE.md. Boot headless with: `emulator -avd compress_video_api35 -no-window -gpu swiftshader_indirect -no-audio -no-boot-anim -no-snapshot` (wrap in `sg kvm -c`), then poll `adb shell getprop sys.boot_completed` until `1` (booted in ~10s in testing). Do not `chmod 666 /dev/kvm`. AGP 9.0.1 with Gradle 9 requires JDK 17 minimum, which is why 17 (not a newer LTS) was installed. The AVD is `--force`-recreatable from this same command if it's ever deleted.
- **Do not use `gsd-tools` state/phase WRITE subcommands** (`state.advance-plan`, `state.begin-phase`, `phase.complete`): known data-loss bug; hand-edit `STATE.md`, `cp` first and `diff` after. Read-only `gsd-tools query` verbs are fine.
- **Blockers only Dan can clear live in `QUESTIONS.md`.** Record there and keep working on unblocked phases; push a notification only for something he can act on in the next five minutes.
- **Two Flutter SDKs on danserver.** `~/development/flutter` (3.44.1) is shared with the `canopy` lane — never upgrade it while that lane runs. `~/development/flutter-stable` (3.47.5, created 2026-09-21) tracks the `stable` channel CI uses; run `dart format` with THAT one before pushing (`PATH=$HOME/development/flutter-stable/bin:$PATH dart format .`), because the formatter output differs between minor Dart versions and CI's format check is authoritative. Builds/tests still use 3.44.1 until the shared SDK is upgraded.
- **Autonomous runs here use `workflow.use_worktrees=false`** (executors commit on the main tree so `git push` to `github` from a plan actually pushes `main`). The Agent isolation-guard hook reads `.gsd/dispatch-isolation-sentinel.json`; before dispatching `gsd-executor` run `gsd-tools query dispatch-isolation --raw --phase <NN> --force-isolation none` or the hook rejects the spawn with "missing isolation=\"worktree\"".
- **GitHub Actions is billing-blocked as of 2026-09-16** (free plan minutes exhausted; repo private). Every job, Linux included, is refused with "spending limit needs to be increased". Until Dan clears QUESTIONS.md #6 (or flips the repo public, #5), the local emulator is the only gate; treat a refused CI run as an external blocker, never a task failure.
- **Never-larger applies to EVERY delivered file, remux included** (`TransformerEngine.finishSuccess`: `usedOriginal = tempBytes >= inputBytes`, unconditional). The in-app muxer runs with `setAttemptStreamableOutputEnabled(false)` because streamable mode pads a ~395 KB `free` box into short remuxes. Do not "optimise" either away.
- **Research that led here:** `.planning/research/sources/VIDEO_COMPRESS_BRIEF.md` (read it before planning any phase; it links every claim).
- **Android SDK, JDK 17 and the headless emulator are installed on danserver (01-01, confirmed still working 2026-09-21).** AVD name `compress_video_api35` (device profile `pixel_6`, API 35 `google_apis` x86_64). Boot with: `sg kvm -c '$ANDROID_HOME/emulator/emulator -avd compress_video_api35 -no-window -gpu swiftshader_indirect -no-audio -no-boot-anim -no-snapshot'`, then poll `adb shell getprop sys.boot_completed` until `1`. `sg kvm -c` is still required until Dan's next full re-login (unchanged from 01-01). **The emulator segfaulted once under memory pressure on 2026-09-21** (`Segmentation fault (core dumped)` mid-session, no repro found) — if a local run segfaults, don't loop retrying it locally; CI's own fresh `reactivecircus/android-emulator-runner` emulator is the real gate and is unaffected by danserver's local memory pressure.
- **CI lives on the `github` remote; the macOS job is path-gated** (`.github/workflows/ci.yml`'s `changes` job) to protect Actions minutes — it only runs when a push/PR touches `darwin/`, `pigeons/`, `lib/`, `example/`, `pubspec.yaml`, or the workflow file itself. A Markdown-only or `.planning/`-only push creates no CI run at all (`paths-ignore`). The repo is now **public** (QUESTIONS.md #5), so Actions minutes are uncapped either way, but the path gate stays as a courtesy against unnecessary macOS runner time.
- **The corpus is generated, not recorded.** `corpus/*.mp4` and `corpus/*.expected.json` are reproducible from `corpus/generate_corpus.sh` + `corpus/verify_corpus.sh --write` — never hand-edit either. CI's "Verify corpus has not drifted" step (`corpus/verify_corpus.sh`, no `--write`) fails the build if the committed sidecars disagree with what a fresh regeneration would produce.
- **`reactivecircus/android-emulator-runner`'s `script:` input runs each line as its own separate `sh -c` call, not a persistent shell.** A multi-line block's `cd` does not carry to the next line, and dash's `sh` rejects `set -o pipefail` outright ("Illegal option -o pipefail") — confirmed live in CI run 35623448167. Wrap anything needing `cd`/`set -o pipefail`/a pipe together in one `bash -c '...'` line, as `.github/workflows/ci.yml`'s emulator-integration step now does.
