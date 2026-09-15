# Stack Research — compress_video

**Researched:** 2026-09-14 (from `sources/competitors-and-native-apis.md`, official docs, cloned competitor source)
**Confidence:** HIGH for engines and versions (official docs read on 2026-09-14); MEDIUM for Pigeon/CI details (standard practice, not re-verified this week)

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
