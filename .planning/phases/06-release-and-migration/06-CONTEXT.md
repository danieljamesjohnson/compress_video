# Phase 6: Release and Migration - Context

**Gathered:** 2026-09-27
**Status:** Ready for planning
**Mode:** Smart discuss, recommended answers AUTO-ACCEPTED (Dan's 2026-09-25 "go full auto"
instruction). Every decision below is the orchestrator's recommendation and can be overridden.

<domain>
## Phase Boundary

A developer on `video_compress` can switch to `compress_video` from pub.dev by changing one
import, and the documentation says exactly what each preset does and what the plugin will not
do. Requirements: RELS-01, RELS-02, RELS-03 (read their exact text in REQUIREMENTS.md).

Two steps are Dan-only and are NOT executor work: the actual `dart pub publish` (needs the
publisher decision in QUESTIONS.md #2 and is an outward, irreversible action) and the hardware
checklist re-run on physical devices (QUESTIONS.md #3, #4, #8). The phase delivers a
publish-ready package proven by `dart pub publish --dry-run` at 0 warnings and a documented,
one-command release procedure for Dan.

</domain>

<decisions>
## Implementation Decisions

### Compatibility import (RELS-03)
- A single library `package:compress_video/video_compress_compat.dart` exposes the incumbent's
  surface: `VideoCompress.compressVideo(...)`, `getMediaInfo`, `getFileThumbnail`,
  `getByteThumbnail`, `cancelCompression`, `deleteAllCache`, `compressProgress$`,
  `isCompressing`, and `VideoQuality` — implemented on top of the new API, deprecated with
  `@Deprecated` pointers to the replacements, and typed (no `Map<String, dynamic>`).
- `VideoQuality` maps to presets per a documented table (e.g. LowQuality -> p360,
  MediumQuality -> p480, DefaultQuality/HighestQuality -> p720/p1080, Res* -> maxLongSidePx),
  recorded in MIGRATION.md with every old API next to its new call.
- The shim keeps the incumbent's single-in-flight semantics for `compressProgress$`/`isCompressing`
  by delegating to the default `CompressVideo` queue with `maxConcurrentJobs = 1`; documented.
- Proof: a Dart unit test file exercising every shim method through the fake host API, plus an
  integration case per shim entry point on the Android emulator and iOS simulator (same suite
  runs on macOS), and a "switch-the-import" example in MIGRATION.md verified by a test that
  compiles the incumbent's documented snippet against the shim.

### Documentation (RELS-02)
- `tool/generate_preset_table.dart` renders the README preset table from the measured preset
  constants and doc/PRESETS.md's Android/Apple measurements; a CI step regenerates and diffs it
  so the table can never drift from the constants.
- A README section "What this plugin will not do" lists the deliberate non-goals (web, FFmpeg,
  filters/overlays, keep-HDR on hardware without HEVC 10-bit, progress off the root isolate,
  `dataSync` fallback below Android 15, background on iOS beyond the short task).

### pub.dev readiness (RELS-01)
- Target 160/160 pub points: `dart pub publish --dry-run` at 0 warnings in CI (already a step),
  `pana` run locally in CI against the package and its score asserted >= 160 (or the maximum the
  installed pana reports), platform declarations for android/ios/macos, example/ present, dartdoc
  coverage for every public symbol (a CI check), CHANGELOG with the 1.0.0 entry, LICENSE.
- Version 1.0.0 in pubspec.yaml; the CHANGELOG documents the `const` constructor removal and every
  breaking change since 0.x under the 1.0.0 entry.
- `doc/RELEASE.md` gives Dan the exact publish procedure (publisher choice per QUESTIONS.md #2,
  `dart pub publish`, tag, GitHub release); the executor never runs `dart pub publish` without
  `--dry-run`.

### Hardware checklist before publishing (criterion 4)
- Not runnable here: recorded as a Deferred Item and as the first line of doc/RELEASE.md's
  pre-publish checklist; QUESTIONS.md #2/#3/#4/#8 updated with what is needed, one notify to
  Dan only when the package is dry-run clean and ready for his decision.

### Claude's Discretion
- Exact VideoQuality-to-preset mapping values within the documented rationale.
- Preset table layout.

</decisions>

<code_context>
## Existing Code Insights
- Public API in lib/compress_video.dart and lib/src/ (CompressVideo with queue, CompressJob,
  CompressOptions/presets, CompressResult, MediaInfo, thumbnails, estimate, clearCache,
  typed exceptions). doc/PRESETS.md holds measured tables for Android and Apple.
- CI: `dart pub publish --dry-run` step in the Android job; format/analyze gates; the corpus and
  parity gates; the runner script for Apple suites (add any new suite there).
- Never-larger unconditional; typed errors; no hand-written channels in plugin code.
</code_context>

<specifics>
## Specific Ideas
- The incumbent's API shapes are in .planning/research/sources/VIDEO_COMPRESS_BRIEF.md and the
  cloned competitor sources referenced there; the planner must read the incumbent's actual
  signatures rather than guess.
</specifics>

<deferred>
## Deferred Ideas
- The actual pub.dev publish and GitHub release (Dan; QUESTIONS.md #2).
- Hardware checklist re-run on the release build (Dan; QUESTIONS.md #3, #4, #8).
</deferred>
