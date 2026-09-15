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
- **Apple builds need the MacBook Air over SSH** (`dans-macbook-air` on the tailnet). Until Dan authorizes danserver's key (`QUESTIONS.md` #1), verify Apple code on the GitHub Actions macOS runner and record device checks as outstanding.
- **Android SDK is not installed on danserver yet.** Phase 1 installs cmdline-tools + platform-tools + an x86_64 emulator image under `~/Android/Sdk` and sets `ANDROID_HOME`; the AMD 780M iGPU with KVM is fine for the emulator. Flutter is at `~/development/flutter/bin`.
- **Do not use `gsd-tools` state/phase WRITE subcommands** (`state.advance-plan`, `state.begin-phase`, `phase.complete`): known data-loss bug; hand-edit `STATE.md`, `cp` first and `diff` after. Read-only `gsd-tools query` verbs are fine.
- **Blockers only Dan can clear live in `QUESTIONS.md`.** Record there and keep working on unblocked phases; push a notification only for something he can act on in the next five minutes.
- **Research that led here:** `.planning/research/sources/VIDEO_COMPRESS_BRIEF.md` (read it before planning any phase; it links every claim).
