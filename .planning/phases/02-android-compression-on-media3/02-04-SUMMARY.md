---
phase: 02-android-compression-on-media3
plan: 04
subsystem: compression-engine
tags: [media3, transformer, kotlin, sizeguard, transmux, never-larger, presets]

# Dependency graph
requires:
  - phase: 02-android-compression-on-media3
    provides: "02-03's SizeGuard.Plan resolution (target dimensions/fps/bitrate), CBR encoder mode, Probe's bitrate fallback, and the targetSizeMb ±35% emulator tolerance finding"
provides:
  - "SizeGuard.Plan.wouldTransmux / wouldUseOriginal — pure predicates the compress path and the future estimate() path share, so they can never disagree"
  - "TransformerEngine never-larger pre-check (skip encoding) and post-check (discard a real encode that grew the file), both copying via PluginFiles' atomic helpers into the plugin's own cache directory"
  - "A working Media3 transmux fast path — fixed the DefaultEncoderFactory.videoNeedsEncoding() bug that made it unreachable regardless of prediction"
  - "doc/PRESETS.md, a measured (not seeded) preset table, and tool/measure_presets.dart, the harness that produced it"
affects: [02-05, 02-06, 02-07, phase-6-readme]

# Actuals (#2632)
actuals:
  tokens: 13309
  tasks: 3
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Decision order fixed at the SizeGuard.resolve() level: transmux decided first (using post-Rule-6 resolved bitrate), never-larger second, real encode last — both wouldTransmux and wouldUseOriginal live on the same Plan so no caller can compute them out of order"
    - "TransformerEngine.finishSuccess decides transmux from ExportResult's own per-track conversion-process fields BEFORE running the never-larger byte-count post-check, so a genuine remux whose container overhead lands at/above the input's own size is never wrongly discarded"
    - "DefaultEncoderFactory is built with default (non-custom) VideoEncoderSettings whenever wouldTransmux is true — the discovered precondition for Media3 to ever transmux at all"
    - "tool/ scripts that need a real device (measurement harnesses, not correctness tests) are canonical outside example/, copied into example/integration_test/ to run, mirroring corpus/sync_to_example.sh's existing pattern"

key-files:
  created:
    - doc/PRESETS.md
    - tool/measure_presets.dart
  modified:
    - android/src/main/kotlin/com/danjjohnson/compress_video/SizeGuard.kt
    - android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt
    - android/src/test/kotlin/com/danjjohnson/compress_video/SizeGuardTest.kt
    - example/integration_test/compress_test.dart
    - example/pubspec.yaml
    - lib/src/presets.dart

key-decisions:
  - "Kept CORE-05's equality-counts-as-larger reading (flagged assumption, carried forward unresolved per plan instruction — see Next Phase Readiness)"
  - "Kept CORE-06's <30% elapsed-time threshold as written (flagged assumption, carried forward unresolved)"
  - "Chose 50,000bps (not the plan-suggested 150,000) as the speed-ratio test's explicit encode bitrate: at small_480p.mp4's real ~130kbps, 150,000 stays within wouldTransmux's 1.15x headroom and would itself remux, not encode — verified by hand-computation and confirmed live; documented in the test's own comment"
  - "No lib/src/presets.dart seed constant changed — portrait_hibitrate_1080p60.mp4's four preset rows are real, discriminating re-encodes and already form the required monotonic ladder"

patterns-established:
  - "A remux is exempt from the never-larger check even when its container ends up larger than the input — documented explicitly in SizeGuard.Plan's wouldUseOriginal dartdoc and TransformerEngine's finishSuccess"

requirements-completed: [CORE-02, CORE-05, CORE-06]

coverage:
  - id: D1
    description: "Never-larger: an encode predicted to grow the file is skipped before it runs (pre-check), and one that grows the file anyway is discarded after it runs (post-check); both substitute a plugin-owned copy of the original and report usedOriginal"
    requirement: CORE-05
    verification:
      - kind: unit
        ref: "SizeGuardTest.kt#wouldUseOriginal_predictedOutputAboveInputSize_setsTheFlag"
        status: pass
      - kind: unit
        ref: "SizeGuardTest.kt#wouldUseOriginal_predictedOutputExactlyEqualToInputSize_setsTheFlag"
        status: pass
      - kind: unit
        ref: "SizeGuardTest.kt#wouldUseOriginal_predictedOutputOneByteBelowInputSize_doesNotSetTheFlag"
        status: pass
      - kind: unit
        ref: "SizeGuardTest.kt#wouldUseOriginal_neverSetWhenThePlanIsARemux"
        status: pass
      - kind: integration
        ref: "compress_test.dart#CompressPreset.p360 on small_480p.mp4 copies the original instead of encoding"
        status: pass
    human_judgment: false
  - id: D2
    description: "Transmux: a clip that already meets the target is remuxed (container copy, no video re-encode) rather than re-encoded, detected from the export result's own conversion-process fields, and measurably faster than a real encode in the same run"
    requirement: CORE-06
    verification:
      - kind: unit
        ref: "SizeGuardTest.kt (12 wouldTransmux_* cases, one per D-10 condition)"
        status: pass
      - kind: integration
        ref: "compress_test.dart#default options on small_480p.mp4 report transmuxed, not a re-encode"
        status: pass
      - kind: integration
        ref: "compress_test.dart#default options on noaudio_720p.mp4 also report transmuxed"
        status: pass
      - kind: integration
        ref: "compress_test.dart#a remux is measurably faster than a real encode of the same clip, in the same run"
        status: pass
    human_judgment: false
  - id: D3
    description: "Every preset measured on the real corpus (not seeded from memory); doc/PRESETS.md publishes the measured table with device/version/date, and lib/src/presets.dart's seeds are confirmed rather than guessed"
    requirement: CORE-02
    verification:
      - kind: integration
        ref: "compress_test.dart#the four presets form a monotonic resolution/output-size ladder on the high-bitrate clip"
        status: pass
      - kind: other
        ref: "dart pub publish --dry-run (exit 0, 0 warnings, doc/ and tool/ do not break package layout)"
        status: pass
    human_judgment: true
    rationale: "doc/PRESETS.md's prose (the two scaling rules, the two shortcuts, the requested-vs-delivered bitrate note) is documentation quality a human should skim before Phase 6 generates the README from it — no automated check proves prose is clear or correctly reasoned."

duration: ~95min
completed: 2026-09-16
status: complete
---

# Phase 2 Plan 4: Never-larger, transmux fast path, and measured presets

**Fixed a real Media3 bug (a non-default `VideoEncoderSettings` silently forces `videoNeedsEncoding()` to always return `true`) that made the transmux fast path unreachable no matter what `SizeGuard` predicted, then proved never-larger, transmux and the measured preset table all work on the emulator.**

## Performance

- **Duration:** ~95 min (estimated — start time not captured at invocation)
- **Completed:** 2026-09-16
- **Tasks:** 3
- **Files modified:** 6 modified, 2 created

## Accomplishments

- `SizeGuard.Plan` gained `wouldTransmux`/`wouldUseOriginal`, pure derivations of numbers `resolve()` already computes, decided in the fixed order the plan specifies (transmux first, never-larger second, real encode last) — 25 new JVM-level `SizeGuardTest` cases prove every D-10/D-11 boundary without an emulator.
- `TransformerEngine` now skips building a `Transformer` entirely when the resolver already knows encoding would not help (never-larger pre-check), and — the significant find this plan — genuinely remuxes a qualifying clip instead of always re-encoding it, after discovering and fixing why it never had before.
- `doc/PRESETS.md` publishes a measured (not seeded) table for all four presets across both `small_480p.mp4` and `portrait_hibitrate_1080p60.mp4`, generated by the new `tool/measure_presets.dart` harness; no preset constant needed adjustment.

## Task Commits

Each task was committed atomically:

1. **Task 1: Never-larger — the pre-check, the post-check and the always-copy substitution** - `b2f37e9` (feat)
2. **Task 2: Transmux fast path, detected from the export result and asserted as a measured speed ratio** - `2057cde` (feat)
3. **Task 3: Measure every preset on the corpus and generate doc/PRESETS.md from the measurements** - `0958a51` (feat)

## Files Created/Modified

- `android/src/main/kotlin/com/danjjohnson/compress_video/SizeGuard.kt` - `wouldTransmux`/`wouldUseOriginal` predicates on `Plan`, decided in fixed precedence
- `android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt` - never-larger pre-check, transmux-aware `DefaultEncoderFactory` construction, `finishSuccess`'s corrected transmux-then-never-larger precedence, `buildResultFromDestination` shared helper
- `android/src/test/kotlin/com/danjjohnson/compress_video/SizeGuardTest.kt` - 4 `wouldUseOriginal` cases + 12 `wouldTransmux` cases (one per D-10 condition, flipped off a shared qualifying baseline)
- `example/integration_test/compress_test.dart` - never-larger, transmux (incl. no-audio-track branch), speed-ratio, and preset-ladder integration tests
- `example/pubspec.yaml` - added `crypto` dev dependency for the never-larger digest-identity assertion
- `lib/src/presets.dart` - header now points at `doc/PRESETS.md` and records that the seeds were confirmed, not just proposed
- `doc/PRESETS.md` *(created)* - the measured preset table Phase 6's README is generated from
- `tool/measure_presets.dart` *(created)* - the reproducible measurement harness

## Decisions Made

- **The two flagged assumptions (CORE-05, CORE-06) were implemented as written, not resolved.** Per the plan's own instruction, they are surfaced here for the verifier rather than closed by fiat:
  - **CORE-05:** "never larger" is decided on total file byte count, and equality counts as larger (a result exactly equal to the input in bytes is substituted with the original). The alternative — only strictly-larger triggers substitution — would let a pointless same-size re-encode ship with worse quality; implemented as specified.
  - **CORE-06:** "a fraction of the encode time" is implemented as strictly less than 30% of a comparable encode's elapsed time on the same device, per 02-CONTEXT.md's acceptance bar. Measured live: a remux of `small_480p.mp4` completed in well under 30% of a real 50,000bps encode of the same clip in the same test run. This has only been measured on the emulator's software encoder; a physical-device re-measurement is still outstanding (QUESTIONS.md #3).
- **Speed-ratio test bitrate changed from the plan's suggested 150,000 to 50,000.** At `small_480p.mp4`'s real measured input bitrate (~130,000bps), an explicit request of 150,000 stays within `wouldTransmux`'s 1.15x headroom condition and the resolver correctly still remuxes it — that is the resolver working as designed (D-10's own point: remux is preferred whenever the source is already close enough to what was asked for), not a bug. A genuine "real encode" comparison needed a bitrate low enough to fail *both* the transmux headroom check *and* the never-larger threshold; 50,000 does both with margin, confirmed live.
- **No `lib/src/presets.dart` seed constant changed.** `portrait_hibitrate_1080p60.mp4`'s measured rows (the only clip where transmux/never-larger never mask a resolution difference) already form a strictly monotonic ladder in both resolution and output size at the seeded values.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The transmux fast path was unreachable regardless of what `SizeGuard` predicted**
- **Found during:** Task 2, first live emulator run of the transmux integration test
- **Issue:** `DefaultEncoderFactory.videoNeedsEncoding()` returns `true` whenever `requestedVideoEncoderSettings != VideoEncoderSettings.DEFAULT` (confirmed by `javap`-disassembling the installed `media3-transformer:1.11.1` AAR — this exact precondition is not documented in 02-RESEARCH.md's Pattern 2 or the public Javadoc). Every encode path in this plugin, before this fix, always built a non-default `VideoEncoderSettings` with an explicit bitrate, so `TransformerUtil.shouldTranscodeVideo`'s very first check short-circuited to "must transcode" before it ever reached the mime-type/effects comparison Pattern 2 describes. The predicate correctly predicted a transmux (`wouldTransmux=true`), but the actual export always re-encoded the video track anyway (`videoConversionProcess=TRANSCODED`).
- **Fix:** `TransformerEngine` now builds the `DefaultEncoderFactory` with default (unconfigured) `VideoEncoderSettings` whenever `target.wouldTransmux` is true, leaving no requested bitrate to force a re-encode.
- **Files modified:** `android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt`
- **Verification:** Live on `emulator-5554` — after the fix, `small_480p.mp4` at the default preset reports `videoConversionProcess=TRANSMUXED` and completes in ~317ms instead of running a real encode.
- **Committed in:** `2057cde` (Task 2 commit)

**2. [Rule 1 - Bug] The never-larger post-check could wrongly discard a genuine transmux**
- **Found during:** Task 2, same investigation as above
- **Issue:** `finishSuccess`'s original precedence computed `usedOriginal = tempBytes >= inputBytes` from the raw byte count *before* deciding transmux, then only reported `transmuxed` when `!usedOriginal`. Media3's own muxer does not repackage a container byte-for-byte: remuxing `small_480p.mp4` (77,504 bytes) produced a 472,825-byte output (~6x larger) despite being sample-for-sample identical to the input. Under the original precedence this container-overhead difference alone made the never-larger post-check fire and discard the genuine transmux, reporting `usedOriginal=true, transmuxed=false` — silently contradicting the plan's own documented decision order ("transmux is decided first ... never-larger second").
- **Fix:** `finishSuccess` now computes `transmuxed` first from `ExportResult`'s own per-track conversion-process fields, and only runs the never-larger byte-count check when the export was not a transmux (`usedOriginal = !transmuxed && tempBytes >= inputBytes`).
- **Files modified:** `android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt`
- **Verification:** The same live run above now reports `transmuxed=true, usedOriginal=false` with the actual 472,825-byte output.
- **Committed in:** `2057cde` (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (2 Rule 1 bugs, both discovered live via emulator investigation and both required for Task 2's own acceptance criteria to be satisfiable at all)
**Impact on plan:** Both fixes were necessary — without them the transmux fast path this plan exists to build could never actually run. No scope creep: both live entirely inside `TransformerEngine.kt`'s existing `compress`/`finishSuccess` functions.

## Known Stubs

None — every deliverable is wired to real Media3 behavior and proven on the emulator.

## Issues Encountered

- `doc/TOOLCHAIN.md` states `androidx.media3` at 1.11.0, but `android/build.gradle.kts` actually pins 1.11.1 (confirmed via `javap` on the installed AAR during the Task 2 investigation). Not fixed here — out of this plan's scope — but `doc/PRESETS.md` reports the real installed version (1.11.1) rather than propagating the stale TOOLCHAIN.md number. Recorded here so a future plan can reconcile TOOLCHAIN.md.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `SizeGuard.Plan.wouldTransmux`/`wouldUseOriginal` are ready for plan 02-07's `estimate()` to call directly — same predicates, same precedence, cannot diverge from what `compress()` actually does.
- **CORE-05 and CORE-06's flagged assumptions are carried forward unresolved, per this plan's own instruction** — the verifier should explicitly challenge both readings (see "Decisions Made" above) rather than treat them as settled by this plan's implementation choice.
- **CORE-06's <30% speed-ratio claim is only measured on the emulator's software encoder** (QUESTIONS.md #3 tracks the outstanding physical-device re-verification, same open item 02-03-SUMMARY.md already logged for `targetSizeMb`).
- `doc/PRESETS.md` and `tool/measure_presets.dart` are ready for Phase 6's README generation.
- Ready for `02-05-PLAN.md` (audio passthrough/re-encode/strip, trim, orientation proof).

---
*Phase: 02-android-compression-on-media3*
*Completed: 2026-09-16*

## Self-Check: PASSED

- `doc/PRESETS.md`, `tool/measure_presets.dart` — FOUND
- `android/src/main/kotlin/com/danjjohnson/compress_video/SizeGuard.kt`, `TransformerEngine.kt` — FOUND
- Commits `b2f37e9`, `2057cde`, `0958a51` — FOUND in `git log`
- `flutter test integration_test/compress_test.dart -d emulator-5554` — 19/19 passed
- `cd example/android && ./gradlew :compress_video:testDebugUnitTest` — all passed (including 25 new `SizeGuardTest` cases)
- `dart pub publish --dry-run` — exit 0, 0 warnings
