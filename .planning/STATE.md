---
gsd_state_version: '1.0'
status: executing
progress:
  total_phases: 6
  completed_phases: 0
  total_plans: 7
  completed_plans: 5
  percent: 71
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-09-15)

**Core value:** One call turns a phone video into a smaller MP4 that plays everywhere, and it never makes the file bigger, never returns null, and builds on today's Flutter toolchain.
**Current focus:** Phase 1 — Typed Contract, CI and Media Info

## Current Position

Phase: 1 of 6 (Typed Contract, CI and Media Info)
Plan: 6 of 7 in current phase (code-complete, halted on external blocker — see below)
Status: Blocked (wave 4 of 5 — 01-06's Swift/Dart code is written and committed, but its own CI-green verification is halted on a GitHub Actions billing block; 01-07 must not start until this is resolved)
Last activity: 2026-09-15 — Plan 01-06 (Apple core: Probe, Thumbnails, XCTest on iOS/macOS) is code-complete: all three tasks committed, matching every acceptance criterion locally, with two real platform-quirk bugs found and fixed via live CI evidence (AVAssetImageGenerator.maximumSize fit-within-box mirroring 01-05's Android finding; a shared-test Android-only cache-path assertion). The fix itself is unverified by a fresh CI run: GitHub Actions stopped starting the apple job mid-session ("recent account payments have failed or your spending limit needs to be increased"). Recorded QUESTIONS.md #6, notified Dan. See 01-06-SUMMARY.md (status: halted).

Progress: [███████░░░] 71% (unchanged until 01-06 re-verifies green and is re-summarized as complete)

## Performance Metrics

**Velocity:**
- Total plans completed: 5
- Average duration: 50 min
- Total execution time: 4.2 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1 | 5 | 249 min | 50 min |

**Recent Trend:**
- Last 5 plans: 35 min, 25 min, 50 min, 92 min, 47 min
- Trend: down from 01-04's spike (01-05 hit one real platform quirk — getScaledFrameAtTime's fit-within-box dst dimensions — caught by its own test and fixed within the same task; no CI-only fix iterations were needed this time)
- 01-06 (not yet counted as completed — halted, see Blockers/Concerns): 166 min elapsed, almost entirely CI wall-clock across 8 macOS-runner attempts; code-complete with two real platform-quirk fixes found via live CI, final fix unverified due to a GitHub Actions billing block

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap]: Research's "contract/skeleton" and "probe/info/thumbnails" phases merged into Phase 1 (standard granularity; a contract phase alone had only 2 requirements)
- [Roadmap]: Android (Phase 2) before Apple (Phase 3). Phase 3 starts with a Mac-readiness check, and Phases 2 and 3 can run in parallel once the Mac is reachable.
- [Roadmap]: Behaviour requirements are mapped to Phase 2, where they are first delivered. Phase 3 owns the cross-platform parity requirements (CORE-01, CORE-07) and must pass the same corpus tests.
- [01-01]: Android SDK + headless emulator installed on danserver (JDK 17, cmdline-tools, platform-tools, platforms;android-36, build-tools;36.1.0, system-images;android-35;google_apis;x86_64); `dan` added to `kvm` group, requires `sg kvm -c` until next full re-login. Recipe recorded in `.claude/CLAUDE.md` lane notes.
- [01-01]: `github.com/danieljamesjohnson/compress_video` created private, added as `github` remote alongside danserver `origin`; default Actions workflow token permission set to `read`.
- [01-01]: 01-VALIDATION.md's Per-Task Verification Map has 20 rows (matching the actual total task count across all 7 phase-1 plans), not the 21 the plan's own acceptance criteria expected — an off-by-one authoring bug in the plan text, not a missing task. See 01-01-SUMMARY.md Deviations.
- [01-02]: Corpus clips generated with ffmpeg on danserver; portrait rotation done via a direct `tkhd`-matrix byte patch (`corpus/patch_rotation.py`) because `ffmpeg -metadata:s:v:0 rotate=` is a verified no-op on the installed ffmpeg 6.1.1. Sidecars record rotation as unsigned clockwise degrees and dimensions as displayed (post-rotation), not ffprobe's raw signed/coded values — see `corpus/README.md`.
- [01-02]: Added `-threads 1 -x264-params threads=1:sliced_threads=0` to every libx264 encode in `generate_corpus.sh` after discovering the default multi-threaded rate control made regenerated clips non-byte-identical, violating the plan's reproducibility must-have. See 01-02-SUMMARY.md Deviations.
- [01-03]: Renamed `docs/` to `doc/` (pub layout convention — a plural directory name makes `dart pub publish --dry-run` report a non-zero exit) and updated every `docs/TOOLCHAIN.md` cross-reference across the phase's planning documents.
- [01-03]: `darwin/compress_video/Sources/compress_video/CompressVideoPlugin.swift` merged from separate iOS/macOS template sources using `#if os(iOS)/#elseif os(macOS)` conditional imports and messenger access, verified against `flutter/packages`' `shared_preferences_foundation` live source rather than guessed.
- [01-03]: CI's floating `channel: stable` resolves ahead of `doc/TOOLCHAIN.md`'s locally-pinned Flutter 3.44.1 (CI run picked up 3.47.4) — Flutter's own project migrators silently rewrite committed scaffold files (`Podfile`, `project.pbxproj`, `analysis_options.yaml`) the first time a newer tool touches them. CI now resets tracked files via `git checkout -- .` immediately before the `dart pub publish --dry-run` cleanliness check, and forces `flutter config --no-enable-swift-package-manager` before the CocoaPods-path Apple builds (our plugin ships both a podspec and a `Package.swift`, so recent Flutter defaults to preferring SPM once it sees an all-SPM-capable plugin set, which conflicts with the app project's committed Podfile-based CocoaPods integration).
- [01-04]: `MediaMetadataRetriever.METADATA_KEY_COLOR_TRANSFER`/`_COLOR_STANDARD`/`_COLOR_RANGE` were confirmed live (via the "Added in API level" badges on developer.android.com) to be API level 30, not the 24/29 secondary-source guesses in 01-RESEARCH.md's Open Questions — HDR detection is gated on `Build.VERSION.SDK_INT >= 30`. `METADATA_KEY_ROTATION` does not exist; the correct constant is `METADATA_KEY_VIDEO_ROTATION` (confirmed via `javap` against the android-36 platform jar).
- [01-04]: Pigeon's own generated Dart output is not `dart format`-clean. Both the local workflow and CI's regeneration step now run `dart format lib/src/messages.g.dart` immediately after `dart run pigeon`, and the contract's regeneration diff check in CI is scoped to only its own four files (not a bare `git diff --exit-code`, which also caught Flutter's unrelated `analysis_options.yaml` migrator rewrites).
- [01-04]: CI's `android` job now regenerates and diff-gates the Pigeon contract, runs the plugin module's native Gradle unit tests, and runs a real `reactivecircus/android-emulator-runner` (API 35, google_apis, x86_64) integration suite on every push — reached green (run 34997517360) after fixing the diff scope, the gitignored `example/android/gradlew` wrapper not existing on a fresh checkout, the emulator's userdata partition not fitting `ubuntu-latest`'s free disk space, and a regression where the disk-space fix's own deletion list included the hosted toolcache (Flutter SDK + JDK) the job still needed.
- [01-05]: `MediaMetadataRetriever.getScaledFrameAtTime`'s `dstWidth`/`dstHeight` are a fit-within bounding box (scaled by whichever dimension is more constraining), not independent exact targets — confirmed live on the emulator (a `maxDimensionPx=1919` request returned height 1918, not 1919) rather than from documentation. Every decoded thumbnail frame is now unconditionally snapped to the exact `MediaMath.scaledSize` target with one `Bitmap.createScaledBitmap` pass, on every API level, so the pure-math contract is exactly what callers observe.
- [01-05]: `INFO-02` stays unchecked in `REQUIREMENTS.md` — also declared by 01-06 and 01-07, both still pending in this phase; `gsd-tools query requirements.ready-ids` reports it `blocked`, not `ready`. Same shared-ID gate pattern as `BULD-03`/`INFO-01`/`BULD-05` in 01-04.
- [01-06]: Gated the modern AVFoundation `load(_:)` API on `#available(iOS 16, macOS 13, *)` — the more conservative of 01-RESEARCH.md's two conflicting sourced minimums — since gating on the lower bound would crash at runtime if wrong, not just skip an optimisation.
- [01-06]: `videoCodec` degrades to `unknown` on the legacy (pre-iOS-16/macOS-13) AVFoundation path only: casting `AVAssetTrack.formatDescriptions: [Any]` to `[CMFormatDescription]` has no permitted Swift spelling here — `as?` is a hard compiler error under this project's warnings-as-errors build ("conditional downcast will always succeed"), and `as!` is banned by the threat model.
- [01-06]: `AVAssetImageGenerator.maximumSize` is a fit-within bounding box, not independent exact output dimensions — confirmed live in CI, the Apple-side twin of 01-05's Android `getScaledFrameAtTime` finding. Thumbnails.swift now snaps the decoded `CGImage` to the exact `MediaMath.scaledSize` target via one `CGContext` draw pass, mirroring Android's `Bitmap.createScaledBitmap` fix.

### Pending Todos

- [01-06]: Once GitHub Actions billing is resolved (QUESTIONS.md #6), re-run CI for `main` HEAD and confirm the `apple` job concludes `success` end-to-end (including the iOS-simulator integration step with the current Thumbnails.swift/thumbnail_test.dart fixes). No further code changes are expected. Re-summarize 01-06 as `status: complete` once confirmed, then proceed to 01-07.

### Blockers/Concerns

- [01-06 / Phase 1]: **GitHub Actions billing block (QUESTIONS.md #6, notified via notify-dan 2026-09-15)** — the `apple` CI job stopped starting entirely mid-session: "recent account payments have failed or your spending limit needs to be increased." This blocks re-verifying 01-06's final fix and blocks 01-07 (cross-platform parity gate) from starting until resolved and CI is confirmed green again.
- [Phase 3]: SSH to `dans-macbook-air` is refused, which blocks Apple device/simulator verification (QUESTIONS.md #1). Phase 1 uses the GitHub Actions macOS runner meanwhile.
- [Phase 4]: HEVC/HDR hardware checks need a physical Android phone (QUESTIONS.md #3).
- [Phase 6]: No verified pub.dev publisher yet (QUESTIONS.md #2).

## Deferred Items

Items acknowledged and deferred at milestone close, most recent first:

| Category | Item | Status | Deferred At | Milestone |
|----------|------|--------|-------------|-----------|
| *(none)* | | | | |

## Session Continuity

Last session: 2026-09-15
Stopped at: 01-06-PLAN.md code-complete and committed; CI verification halted on GitHub Actions billing block (QUESTIONS.md #6)
Resume file: None — resume by re-running CI once billing is resolved; no PLAN.md re-execution needed
