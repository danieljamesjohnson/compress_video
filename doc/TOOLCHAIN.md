# Toolchain Pin Baseline

Standing quarterly toolchain-rot baseline for `compress_video`. Toolchain rot (plugin pins
Kotlin/AGP/JVM target and breaks on every Flutter release) is the incumbent `video_compress`'s
largest complaint cluster (`PITFALLS.md` #1) — this document exists so that cluster does not
recur here. Re-check every pin quarterly; the research this table is drawn from
(`.planning/phases/01-typed-contract-ci-and-media-info/01-RESEARCH.md`) expires ~2026-10-15.

| Component | Version | Source of truth | Verified on |
|---|---|---|---|
| Flutter (local dev, danserver) | 3.44.1 stable | Installed and running on danserver, `flutter --version` | 2026-09-15 |
| Flutter (CI, `channel: stable`) | 3.47.5 (resolves ahead of the local pin every run — `subosito/flutter-action@v2` tracks the moving `stable` channel; see 01-03-SUMMARY.md's migrator-rewrite finding) | Live CI run 35615277549's "Flutter version" step | 2026-09-21 |
| Dart | 3.12.1 (local, bundled with Flutter 3.44.1) / 3.13.4 (CI, bundled with Flutter 3.47.5) | `dart --version` on each toolchain | 2026-09-21 |
| JDK | Temurin/OpenJDK 17 (17.0.20+8-1-24.04-Ubuntu) | `apt-get install openjdk-17-jdk-headless`, `java -version` on danserver | 2026-09-15 |
| AGP (Android Gradle Plugin) | 9.0.1 | Freshly generated `android/build.gradle.kts` and `example/android/settings.gradle.kts` (`flutter create --template=plugin`) | 2026-09-15 |
| Kotlin (Gradle plugin) | 2.3.20, applied via `org.jetbrains.kotlin.android` (classic external plugin, not AGP's built-in Kotlin path) | Same generated files | 2026-09-15 |
| Gradle wrapper | 9.1.0 | `example/android/gradle/wrapper/gradle-wrapper.properties` in a freshly generated plugin | 2026-09-15 |
| compileSdk | 36 | Same generated `android/build.gradle.kts` | 2026-09-15 |
| minSdk | 23 | Project constraint (`.claude/CLAUDE.md`, `REQUIREMENTS.md`) — the Flutter template default is 24; a later plan lowers it to 23 for Media3 Transformer's floor | 2026-09-15 |
| JVM target | 17 | Same generated `android/build.gradle.kts` (`compileOptions` / `kotlin { compilerOptions { jvmTarget } }`); also the AGP 9.0.1 + Gradle 9 minimum | 2026-09-15 |
| `pigeon` | 29.0.2 (bumped from 29.0.1 in commit 921bdb6 to fix a regeneration drift under Flutter 3.47.5) | `pubspec.yaml`, pub.dev API, verified publisher `flutter.dev`, repo `github.com/flutter/packages` | 2026-09-21 |
| `flutter_lints` | 6.0.0, published 2025-05-27 | pub.dev API + verified publisher `flutter.dev`; matches the fresh plugin template's `^6.0.0` pin | 2026-09-15 |
| `plugin_platform_interface` | 2.1.8 latest (template pins `^2.0.2`) | pub.dev API | 2026-09-15 |
| `kotlinx-coroutines-android` | 1.10.2 latest | Maven Central search API; new dependency, not in the template — must be added for off-main-thread host methods | 2026-09-15 |
| `mockito-core` | 5.18.0 latest (template pins `5.0.0`, which is old — bump recommended) | Maven Central search API | 2026-09-15 |
| `androidx.media3` | 1.11.1 (2026-09-11) | `android/build.gradle.kts` (`media3-transformer`/`media3-effect`/`media3-common`/`media3-muxer`, all four on the same release train); verified against `dl.google.com/android/maven2/androidx/media3/media3-transformer/maven-metadata.xml`'s `lastUpdated` timestamp (02-RESEARCH.md) | 2026-09-16 |
| GitHub Actions runner (Linux) | `ubuntu-latest` | GitHub Actions default runner images | 2026-09-15 |
| GitHub Actions runner (Apple) | `macos-latest` → image `macos-26-arm64`, macOS 26.6.2, Xcode 26.6 (build 17F113) default, CocoaPods 1.17.0 preinstalled | `actions/runner-images` README, `images/macos/macos-26-arm64-Readme.md`; the "Operating System"/"Runner Image" groups of live CI run 35615277549's job log confirm macOS 26.6.2 / image `macos-26-arm64` | 2026-09-21 |
| Android emulator (CI) | API 35, `google_apis`, `x86_64` (AVD `test`, created fresh per job) | `.github/workflows/ci.yml`'s `reactivecircus/android-emulator-runner` step — same `api-level`/`target`/`arch` as danserver's local `compress_video_api35` AVD (`.claude/CLAUDE.md` lane notes) | 2026-09-21 |
| `subosito/flutter-action` | `@v2` (major-version floating tag; latest tagged release `v2.23.0`, 2026-03-25) | `gh api repos/subosito/flutter-action/releases/latest` + raw README | 2026-09-15 |
| `reactivecircus/android-emulator-runner` | `@v2` (latest tagged release `v2.38.0`, 2026-07-05) | `gh api` + raw README | 2026-09-15 |
| `actions/checkout` | `@v6` | GitHub Actions marketplace | 2026-09-15 |
| `actions/setup-java` | `@v4` | GitHub Actions marketplace | 2026-09-15 |
| `actions/upload-artifact` / `actions/download-artifact` | `@v4` (both, added 01-07 for the cross-platform parity gate) | GitHub Actions marketplace, first-party `actions/*` | 2026-09-21 |
| Flutter (Mac build host, `dans-macbook-air`) | Second SDK at `~/development/flutter-stable`, `3.47.5` stable — matches CI's floating `channel: stable` pin above; Dan's own `~/flutter` (3.41.2, below this package's pubspec floor) is never touched | `tool/mac_sync.sh`/`tool/mac_run.sh`, installed 2026-09-22/25 (03-01 task 1) | 2026-09-25 |
| Xcode (Mac build host) | 26.2 | `xcodebuild -version` over `ssh dans-macbook-air` | 2026-09-22 |
| iOS simulator runtime (Mac build host) | iOS 26.2 (iPhone 17 / 17 Pro / Air / 16e, iPad simulators available) | `xcrun simctl list` over `ssh dans-macbook-air` | 2026-09-22 |
| CocoaPods (Mac build host) | 1.17.0 via Homebrew 5.1.15 at `/opt/homebrew/bin/pod` — resolved 2026-09-25 (QUESTIONS.md #7); non-interactive SSH does not put `/opt/homebrew/bin` on `PATH`, `tool/mac_run.sh` exports it | Dan installed it; confirmed live via `flutter build ios` completing `pod install` | 2026-09-25 |
| Apple install-path proof, CocoaPods | Proven on the GitHub Actions `macos-latest` runner only (CocoaPods 1.17.0 preinstalled there); the Mac build host uses the SPM path locally since it has no CocoaPods gems path proven for `flutter build` yet | CI `apple` job's "Build iOS (CocoaPods)" / "Build macOS" steps | 2026-09-26 (CI run 36202392709) |
| Apple install-path proof, Swift Package Manager | Proven both on the GitHub Actions `macos-latest` runner and, for the build (not the full `tool/verify_fresh_app.sh` fresh-app proof — that remains Mac-blocked, see `QUESTIONS.md` #8), on the Mac build host itself via `tool/mac_run.sh` | CI `apple` job's "Build iOS via Swift Package Manager" / "Build macOS via Swift Package Manager" steps; `tool/mac_run.sh build-ios` locally (03-01) | 2026-09-26 (CI run 36202392709) |

**last verified:** 2026-09-21, against CI run 35615277549 (both platform jobs `success`) and, for
the added `parity` job, run 35631865999 (`android`, `apple` and `parity` all `success`). Every
row above marked `2026-09-21` was re-confirmed live in real run logs rather than carried forward
from 01-01/01-02's original research pass.

## androidx.media3 bump policy

Per 02-CONTEXT.md's BULD-01 decision: bump `androidx.media3` only within the `1.11.x` patch
train (e.g. `1.11.1` -> a later `1.11.z`), never to a new minor/major version, without a
dedicated research pass first — `SizeGuard.kt`'s resolution contract and `TransformerEngine.kt`'s
Media3 usage (transmux/never-larger decision order, `InAppMp4Muxer` streamable-output handling)
were verified against `1.11.1`'s exact behaviour (02-04-SUMMARY.md), and a minor/major bump could
change either without warning.

## AGP 9 built-in Kotlin — deliberately not used yet

AGP 9 ships a built-in Kotlin compilation path that could replace the classic external
`org.jetbrains.kotlin.android` Gradle plugin. This is **not** used in Phase 1: the Flutter 3.44
plugin template still applies Kotlin through the classic external plugin (verified by generating
a fresh plugin and reading its `android/build.gradle.kts` directly — see the row above), and
moving to the built-in path is out of scope here. It is tracked as Phase 2 (BULD-01) investigation
work, not a Phase 1 blocker.
