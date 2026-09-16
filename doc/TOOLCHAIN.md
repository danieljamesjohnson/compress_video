# Toolchain Pin Baseline

Standing quarterly toolchain-rot baseline for `compress_video`. Toolchain rot (plugin pins
Kotlin/AGP/JVM target and breaks on every Flutter release) is the incumbent `video_compress`'s
largest complaint cluster (`PITFALLS.md` #1) — this document exists so that cluster does not
recur here. Re-check every pin quarterly; the research this table is drawn from
(`.planning/phases/01-typed-contract-ci-and-media-info/01-RESEARCH.md`) expires ~2026-10-15.

| Component | Version | Source of truth | Verified on |
|---|---|---|---|
| Flutter | 3.44.1 stable | Installed and running on danserver, `flutter --version` | 2026-09-15 |
| Dart | 3.12.1 | Bundled with Flutter 3.44.1 | 2026-09-15 |
| JDK | Temurin/OpenJDK 17 (17.0.20+8-1-24.04-Ubuntu) | `apt-get install openjdk-17-jdk-headless`, `java -version` on danserver | 2026-09-15 |
| AGP (Android Gradle Plugin) | 9.0.1 | Freshly generated `android/build.gradle.kts` and `example/android/settings.gradle.kts` (`flutter create --template=plugin`) | 2026-09-15 |
| Kotlin (Gradle plugin) | 2.3.20, applied via `org.jetbrains.kotlin.android` (classic external plugin, not AGP's built-in Kotlin path) | Same generated files | 2026-09-15 |
| Gradle wrapper | 9.1.0 | `example/android/gradle/wrapper/gradle-wrapper.properties` in a freshly generated plugin | 2026-09-15 |
| compileSdk | 36 | Same generated `android/build.gradle.kts` | 2026-09-15 |
| minSdk | 23 | Project constraint (`.claude/CLAUDE.md`, `REQUIREMENTS.md`) — the Flutter template default is 24; a later plan lowers it to 23 for Media3 Transformer's floor | 2026-09-15 |
| JVM target | 17 | Same generated `android/build.gradle.kts` (`compileOptions` / `kotlin { compilerOptions { jvmTarget } }`); also the AGP 9.0.1 + Gradle 9 minimum | 2026-09-15 |
| `pigeon` | 29.0.1, published 2026-09-12 | pub.dev API, verified publisher `flutter.dev`, repo `github.com/flutter/packages` | 2026-09-15 |
| `flutter_lints` | 6.0.0, published 2025-05-27 | pub.dev API + verified publisher `flutter.dev`; matches the fresh plugin template's `^6.0.0` pin | 2026-09-15 |
| `plugin_platform_interface` | 2.1.8 latest (template pins `^2.0.2`) | pub.dev API | 2026-09-15 |
| `kotlinx-coroutines-android` | 1.10.2 latest | Maven Central search API; new dependency, not in the template — must be added for off-main-thread host methods | 2026-09-15 |
| `mockito-core` | 5.18.0 latest (template pins `5.0.0`, which is old — bump recommended) | Maven Central search API | 2026-09-15 |
| `androidx.media3` | 1.11.1 (2026-09-11) | `android/build.gradle.kts` (`media3-transformer`/`media3-effect`/`media3-common`/`media3-muxer`, all four on the same release train); verified against `dl.google.com/android/maven2/androidx/media3/media3-transformer/maven-metadata.xml`'s `lastUpdated` timestamp (02-RESEARCH.md) | 2026-09-16 |
| GitHub Actions runner (Linux) | `ubuntu-latest` | GitHub Actions default runner images | 2026-09-15 |
| GitHub Actions runner (Apple) | `macos-latest` — macOS 26.6.2, Xcode 26.6 (build 17F113) default, CocoaPods 1.17.0 preinstalled | `actions/runner-images` README, `images/macos/macos-26-arm64-Readme.md`, fetched live | 2026-09-15 |
| `subosito/flutter-action` | `@v2` (major-version floating tag; latest tagged release `v2.23.0`, 2026-03-25) | `gh api repos/subosito/flutter-action/releases/latest` + raw README | 2026-09-15 |
| `reactivecircus/android-emulator-runner` | `@v2` (latest tagged release `v2.38.0`, 2026-07-05) | `gh api` + raw README | 2026-09-15 |
| `actions/checkout` | `@v6` | GitHub Actions marketplace | 2026-09-15 |
| `actions/setup-java` | `@v4` | GitHub Actions marketplace | 2026-09-15 |

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
