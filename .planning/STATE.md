---
gsd_state_version: '1.0'
status: executing
progress:
  total_phases: 6
  completed_phases: 0
  total_plans: 7
  completed_plans: 4
  percent: 57
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-09-15)

**Core value:** One call turns a phone video into a smaller MP4 that plays everywhere, and it never makes the file bigger, never returns null, and builds on today's Flutter toolchain.
**Current focus:** Phase 1 — Typed Contract, CI and Media Info

## Current Position

Phase: 1 of 6 (Typed Contract, CI and Media Info)
Plan: 4 of 7 in current phase
Status: Executing (wave 3 of 5 complete; wave 4 next)
Last activity: 2026-09-15 — Plan 01-04 complete: full INFO-01 media-info contract (Pigeon-generated typed channel, Kotlin Probe/MediaMath/Arguments) proven end-to-end on the real Android emulator; CI now regenerates the Pigeon contract, runs native Gradle unit tests, and runs the emulator integration suite on every push (green after 4 CI-only fix iterations)

Progress: [██████░░░░] 57%

## Performance Metrics

**Velocity:**
- Total plans completed: 4
- Average duration: 50 min
- Total execution time: 3.4 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1 | 4 | 202 min | 50 min |

**Recent Trend:**
- Last 5 plans: 35 min, 25 min, 50 min, 92 min
- Trend: up (01-04 needed 4 CI-only fix iterations to reach a real green run — regeneration diff scope, gitignored Gradle wrapper, emulator disk space, then a self-inflicted toolcache-deletion regression from the disk-space fix itself)

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

### Pending Todos

None yet.

### Blockers/Concerns

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
Stopped at: Completed 01-04-PLAN.md
Resume file: None
