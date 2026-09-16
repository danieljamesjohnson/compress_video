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
  tokens: 16565
  tasks: 3
  commits: 4

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Decision order at the SizeGuard.resolve() level (pre-flight PREDICTION only): transmux recommended first, never-larger pre-check second, real encode last — this decides which Media3 operation TransformerEngine attempts, not what the caller ultimately receives"
    - "TransformerEngine.finishSuccess applies the never-larger POST-check unconditionally (usedOriginal = tempBytes >= inputBytes, no exception for an attempted remux) BEFORE deciding transmuxed from ExportResult's own per-track conversion-process fields — CORE-05 describes the file the caller receives, not the operation that was attempted, so a remux that came out larger than the input is discarded exactly like a real encode would be"
    - "DefaultEncoderFactory is built with default (non-custom) VideoEncoderSettings whenever wouldTransmux is true — the discovered precondition for Media3 to ever transmux at all"
    - "Transformer.Builder's own default muxer (DefaultMuxer.Factory -> InAppMp4Muxer) reserves a large speculative free-space box for progressive-download (moov-before-mdat) layout; an explicit InAppMp4Muxer.Factory().setAttemptStreamableOutputEnabled(false) removes that reservation for every export, encode or remux"
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
    - lib/src/compress_result.dart
    - lib/src/presets.dart

key-decisions:
  - "Kept CORE-05's equality-counts-as-larger reading (flagged assumption, carried forward unresolved per plan instruction — see Next Phase Readiness)"
  - "Kept CORE-06's <30% elapsed-time threshold as written (flagged assumption, carried forward unresolved)"
  - "Chose 50,000bps (not the plan-suggested 150,000) as the speed-ratio test's explicit encode bitrate: at small_480p.mp4's real ~130kbps, 150,000 stays within wouldTransmux's 1.15x headroom and would itself remux, not encode — verified by hand-computation and confirmed live; documented in the test's own comment"
  - "No lib/src/presets.dart seed constant changed — portrait_hibitrate_1080p60.mp4's four preset rows are real, discriminating re-encodes and already form the required monotonic ladder"

patterns-established:
  - "CORE-05's never-larger guarantee is UNCONDITIONAL: it applies to every file the plugin returns, remux or encode alike, with no exemption for how the file was produced — documented explicitly in SizeGuard.Plan's wouldUseOriginal/wouldTransmux dartdoc, CompressResult.transmuxed's dartdoc, and TransformerEngine.finishSuccess (orchestrator-corrected after an initial implementation wrongly exempted remuxes)"

requirements-completed: [CORE-02, CORE-05, CORE-06]

coverage:
  - id: D1
    description: "Never-larger: an encode predicted to grow the file is skipped before it runs (pre-check), and any produced file (encode OR attempted remux) that is not smaller than the input is discarded after it runs (post-check, UNCONDITIONAL); both substitute a plugin-owned copy of the original and report usedOriginal"
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
        ref: "SizeGuardTest.kt#wouldUseOriginal_neverSetWhenThePlanIsARemux (pre-flight PREDICTION only -- see Deviations #3)"
        status: pass
      - kind: integration
        ref: "compress_test.dart#CompressPreset.p360 on small_480p.mp4 copies the original instead of encoding"
        status: pass
      - kind: integration
        ref: "compress_test.dart#default options on noaudio_720p.mp4 never returns a file larger than the input, even though the no-audio-track branch qualifies it for transmux"
        status: pass
    human_judgment: false
  - id: D2
    description: "Transmux: a clip that already meets the target is remuxed (container copy, no video re-encode) rather than re-encoded, detected from the export result's own conversion-process fields, only reported when the remuxed file also passed the same never-larger check a real encode would, and measurably faster than a real encode in the same run"
    requirement: CORE-06
    verification:
      - kind: unit
        ref: "SizeGuardTest.kt (12 wouldTransmux_* cases, one per D-10 condition)"
        status: pass
      - kind: integration
        ref: "compress_test.dart#default options on small_480p.mp4 report transmuxed, not a re-encode (now also asserts outputBytes <= inputBytes)"
        status: pass
      - kind: integration
        ref: "compress_test.dart#a remux is measurably faster than a real encode of the same clip, in the same run"
        status: pass
    human_judgment: true
    rationale: "No corpus clip on this emulator demonstrates an observable transmuxed:true result specifically via the no-audio-track (CONVERSION_PROCESS_NA) branch -- noaudio_720p.mp4's attempted remux lands at exactly the input's own byte count and is correctly substituted per CORE-05's equality-counts-as-larger reading. The predicate-level D-10 condition is unit-proven (wouldTransmux_noAudioInputWithEverythingElseQualifying_qualifies), but the end-to-end no-audio transmux path itself is an open coverage gap for the verifier, not a passing automated proof."
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

duration: ~130min
completed: 2026-09-16
status: complete
---

# Phase 2 Plan 4: Never-larger, transmux fast path, and measured presets

**Fixed two real Media3 bugs found live on the emulator — a non-default `VideoEncoderSettings` that silently forces `videoNeedsEncoding()` to always return `true`, and a default muxer configuration that reserves a multi-hundred-KB `free` box on every export — then proved CORE-05's never-larger guarantee holds unconditionally (remux or encode) and the measured preset table reflects the fix.**

## Performance

- **Duration:** ~130 min (estimated — start time not captured at invocation; includes an orchestrator-requested rework after initial review)
- **Completed:** 2026-09-16
- **Tasks:** 3
- **Files modified:** 7 modified, 2 created

## Accomplishments

- `SizeGuard.Plan` gained `wouldTransmux`/`wouldUseOriginal`, pure derivations of numbers `resolve()` already computes, decided in the fixed order the plan specifies for which operation to ATTEMPT (transmux first, never-larger pre-check second, real encode last) — 25 new JVM-level `SizeGuardTest` cases prove every D-10/D-11 boundary without an emulator.
- `TransformerEngine` now skips building a `Transformer` entirely when the resolver already knows encoding would not help (never-larger pre-check), and genuinely remuxes a qualifying clip instead of always re-encoding it — after finding and fixing two real Media3 bugs (see Deviations) that first made the transmux path unreachable, then let it silently violate CORE-05.
- The never-larger POST-check now applies **unconditionally** to whatever file a job actually produces, encode or attempted remux alike — a remuxed file that is not smaller than the input is discarded exactly like a bad encode would be.
- `doc/PRESETS.md` publishes a measured (not seeded) table for all four presets across both `small_480p.mp4` and `portrait_hibitrate_1080p60.mp4`, re-generated after the muxer fix; no preset constant needed adjustment.

## Task Commits

Each task was committed atomically, plus one orchestrator-requested rework commit:

1. **Task 1: Never-larger — the pre-check, the post-check and the always-copy substitution** - `b2f37e9` (feat)
2. **Task 2: Transmux fast path, detected from the export result and asserted as a measured speed ratio** - `2057cde` (feat)
3. **Task 3: Measure every preset on the corpus and generate doc/PRESETS.md from the measurements** - `0958a51` (feat)
4. **Rework: CORE-05 applies unconditionally to remuxed files, not just encodes** - `64f01b0` (fix, orchestrator-flagged Rule 1 deviation)

## Files Created/Modified

- `android/src/main/kotlin/com/danjjohnson/compress_video/SizeGuard.kt` - `wouldTransmux`/`wouldUseOriginal` predicates on `Plan`; dartdoc corrected to describe a pre-flight recommendation, not a guarantee about the returned file
- `android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt` - never-larger pre-check, transmux-aware `DefaultEncoderFactory` construction, `finishSuccess`'s UNCONDITIONAL never-larger post-check (transmux detected only for a file that survives it), explicit `InAppMp4Muxer.Factory().setAttemptStreamableOutputEnabled(false)`, `buildResultFromDestination` shared helper
- `android/src/test/kotlin/com/danjjohnson/compress_video/SizeGuardTest.kt` - 4 `wouldUseOriginal` cases + 12 `wouldTransmux` cases (one per D-10 condition, flipped off a shared qualifying baseline)
- `example/integration_test/compress_test.dart` - never-larger, transmux, no-audio-track (rewritten to assert the corrected invariant), speed-ratio, and preset-ladder integration tests; `targetSizeMb` tolerance widened
- `example/pubspec.yaml` - added `crypto` dev dependency for the never-larger digest-identity assertion
- `lib/src/compress_result.dart` - `transmuxed`/`usedOriginal` dartdoc corrected to state the unconditional invariant
- `lib/src/presets.dart` - header now points at `doc/PRESETS.md` and records that the seeds were confirmed, not just proposed
- `doc/PRESETS.md` *(created)* - the measured preset table Phase 6's README is generated from; re-measured after the muxer fix
- `tool/measure_presets.dart` *(created)* - the reproducible measurement harness

## Decisions Made

- **CORE-05's never-larger guarantee is unconditional — it applies to the file the caller receives, with no exception for a remux.** The orchestrator caught this after the Task 2 commit: an earlier version of `finishSuccess` decided `transmuxed` before running the never-larger post-check, which let a genuinely-attempted remux report `transmuxed:true` even at 6x the input's size. "Transmux is decided first, never-larger second" (the plan's own decision order) governs which Media3 operation is *attempted*, not whether the byte guarantee applies to what is *returned*. See Deviations #3 for the full fix.
- **The two flagged assumptions (CORE-05, CORE-06) were implemented as written, not resolved.** Per the plan's own instruction, they are surfaced here for the verifier rather than closed by fiat:
  - **CORE-05:** "never larger" is decided on total file byte count, and equality counts as larger (a result exactly equal to the input in bytes is substituted with the original). The alternative — only strictly-larger triggers substitution — would let a pointless same-size re-encode ship with worse quality; implemented as specified. This reading is now enforced unconditionally (see above), which is what makes `noaudio_720p.mp4`'s attempted remux (landing at exactly the input's own byte count) correctly return the original rather than the remux.
  - **CORE-06:** "a fraction of the encode time" is implemented as strictly less than 30% of a comparable encode's elapsed time on the same device, per 02-CONTEXT.md's acceptance bar. Measured live: a remux of `small_480p.mp4` completed in well under 30% of a real 50,000bps encode of the same clip in the same test run. This has only been measured on the emulator's software encoder; a physical-device re-measurement is still outstanding (QUESTIONS.md #3).
- **Speed-ratio test bitrate changed from the plan's suggested 150,000 to 50,000.** At `small_480p.mp4`'s real measured input bitrate (~130,000bps), an explicit request of 150,000 stays within `wouldTransmux`'s 1.15x headroom condition and the resolver correctly still remuxes it — that is the resolver working as designed (D-10's own point: remux is preferred whenever the source is already close enough to what was asked for), not a bug. A genuine "real encode" comparison needed a bitrate low enough to fail *both* the transmux headroom check *and* the never-larger threshold; 50,000 does both with margin, confirmed live.
- **No `lib/src/presets.dart` seed constant changed.** `portrait_hibitrate_1080p60.mp4`'s measured rows (the only clip where transmux/never-larger never mask a resolution difference) already form a strictly monotonic ladder in both resolution and output size at the seeded values — re-confirmed after the muxer fix changed every row's absolute byte count.
- **`targetSizeMb`'s documented emulator tolerance widened from ±35% to ±55%, live.** The muxer fix removed a `free`-box reservation that had been padding every export's byte count, including real encodes at an explicit `targetSizeMb` — that padding had been partially offsetting the software CBR encoder's own real undershoot (documented in 02-03). Removing it exposed a larger true deviation (measured -49.6% at a 2.0MB target, vs -29.9% before). This is the same encoder/short-clip characteristic 02-03 already flagged, now measured more accurately rather than masked by an unrelated container-padding artifact.
- **The `noaudio_720p.mp4` transmux test was rewritten, not merely tolerance-widened.** With the muxer fix, that clip's attempted remux lands at exactly the input's own byte count (30,618 == 30,618), so the unconditional never-larger post-check correctly substitutes the original. The test now asserts `usedOriginal:true`/`transmuxed:false`/`outputBytes == inputBytes` and documents this as an open CORE-06 coverage gap: no corpus clip on this emulator demonstrates an *observable* `transmuxed:true` result specifically via the no-audio-track branch (the D-10 predicate itself is still unit-proven at the `SizeGuardTest.kt` level).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The transmux fast path was unreachable regardless of what `SizeGuard` predicted**
- **Found during:** Task 2, first live emulator run of the transmux integration test
- **Issue:** `DefaultEncoderFactory.videoNeedsEncoding()` returns `true` whenever `requestedVideoEncoderSettings != VideoEncoderSettings.DEFAULT` (confirmed by `javap`-disassembling the installed `media3-transformer:1.11.1` AAR — this exact precondition is not documented in 02-RESEARCH.md's Pattern 2 or the public Javadoc). Every encode path in this plugin, before this fix, always built a non-default `VideoEncoderSettings` with an explicit bitrate, so `TransformerUtil.shouldTranscodeVideo`'s very first check short-circuited to "must transcode" before it ever reached the mime-type/effects comparison Pattern 2 describes. The predicate correctly predicted a transmux (`wouldTransmux=true`), but the actual export always re-encoded the video track anyway (`videoConversionProcess=TRANSCODED`).
- **Fix:** `TransformerEngine` now builds the `DefaultEncoderFactory` with default (unconfigured) `VideoEncoderSettings` whenever `target.wouldTransmux` is true, leaving no requested bitrate to force a re-encode.
- **Files modified:** `android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt`
- **Verification:** Live on `emulator-5554` — after the fix, `small_480p.mp4` at the default preset reports `videoConversionProcess=TRANSMUXED` and completes in ~317ms instead of running a real encode.
- **Committed in:** `2057cde` (Task 2 commit)

**2. [Rule 1 - Bug, SUPERSEDED by #3 below] The never-larger post-check could wrongly discard a genuine transmux**
- **Found during:** Task 2, same investigation as above
- **Issue:** `finishSuccess`'s original precedence computed `usedOriginal = tempBytes >= inputBytes` from the raw byte count *before* deciding transmux, then only reported `transmuxed` when `!usedOriginal`. Media3's own muxer does not repackage a container byte-for-byte: remuxing `small_480p.mp4` (77,504 bytes) produced a 472,825-byte output (~6x larger) despite being sample-for-sample identical to the input. Under the original precedence this container-overhead difference alone made the never-larger post-check fire and discard the genuine transmux, reporting `usedOriginal=true, transmuxed=false`.
- **Initial fix (Task 2 commit `2057cde`):** Made `finishSuccess` compute `transmuxed` first from `ExportResult`'s own per-track conversion-process fields, and only run the never-larger byte-count check when the export was not a transmux. **This was wrong** — it exempted a remux from CORE-05 entirely rather than fixing the real cause (see #3).
- **Committed in:** `2057cde` (Task 2 commit) — superseded by `64f01b0`

**3. [Rule 1 - Bug, orchestrator-flagged] Fix #2 above exempted remuxed files from CORE-05 instead of fixing the actual cause**
- **Found during:** Post-Task-3 orchestrator review of this plan
- **Issue:** The coordinator correctly identified that #2's fix let a 472,825-byte remuxed file of a 77,504-byte input report `transmuxed:true` — a direct CORE-05 violation ("never makes the file bigger") that the plan's decision-order language does not license. "Transmux is decided first, never-larger second" governs which operation `compress()` *attempts*, not whether the byte guarantee applies to the file it *returns*.
- **Root cause investigation:** A raw MP4 box walk of the remuxed output (written as a temporary throwaway integration test, not committed) found a single 395,344-byte `free` box between `moov` and `mdat` — the entire cause of the 6x bloat, not "muxer overhead" in any ordinary sense. `javap` on the installed `media3-transformer:1.11.1` AAR traced this to `Transformer.Builder`'s own default muxer (`DefaultMuxer.Factory`, which always delegates to `InAppMp4Muxer`) leaving `attemptStreamableOutputEnabled` at InAppMp4Muxer's own default of `true`: to write `moov` before `mdat` (so playback can start before the file finishes downloading), the muxer reserves speculative space for `moov` to grow into as samples arrive, then pads whatever is unused as a real `free` box. For a few-second, few-sample clip that reservation dwarfs the actual content.
- **Fix:** Two changes, both necessary: (a) `finishSuccess`'s never-larger post-check is now unconditional (`usedOriginal = tempBytes >= inputBytes`, full stop) and transmux is detected only for a file that survives it; (b) `TransformerEngine` now builds an explicit `InAppMp4Muxer.Factory().setAttemptStreamableOutputEnabled(false)` for every export (encode or remux), removing the reservation at its source rather than merely tolerating it. With (b) alone, the same `small_480p.mp4` remux measures 77,481 bytes — 23 bytes *smaller* than the input — so it now also passes (a) honestly rather than needing an exemption.
- **Side effects found and fixed:** The muxer change reduces the byte count of every export, not just remuxes, which broke two passing integration tests that depended on the old (larger) numbers: `noaudio_720p.mp4`'s attempted remux now lands at exactly the input's own byte count (correctly triggers `usedOriginal`, rewritten to assert that); `targetSizeMb`'s software-encoder tolerance widened from ±35% to ±55% because the removed padding had been partially offsetting the encoder's own real CBR undershoot (measured -49.6% at a 2.0MB target, vs -29.9% before the muxer fix).
- **Files modified:** `android/src/main/kotlin/com/danjjohnson/compress_video/TransformerEngine.kt`, `SizeGuard.kt` (dartdoc only), `lib/src/compress_result.dart` (dartdoc only), `example/integration_test/compress_test.dart`, `doc/PRESETS.md` (re-measured)
- **Verification:** Full `compress_test.dart` suite (19 tests) green on `emulator-5554`; `SizeGuardTest.kt` (25 new cases) green; root `flutter test` (68 tests) green; `dart pub publish --dry-run` exit 0, 0 warnings.
- **Committed in:** `64f01b0`

---

**Total deviations:** 3 auto-fixed (3 Rule 1 bugs; #2 was itself superseded by #3 after orchestrator review — the net fix is #1 + #3)
**Impact on plan:** All three fixes were necessary — without #1 the transmux fast path could never run at all; without #3 it would have run but silently violated the project's core value ("never makes the file bigger") for any remux whose container padding exceeded the input size. No scope creep: all three live inside `TransformerEngine.kt`'s existing `compress`/`finishSuccess` functions plus the dartdoc/test/doc updates needed to keep the codebase's own description of the invariant honest.

## Known Stubs

None — every deliverable is wired to real Media3 behavior and proven on the emulator.

## Issues Encountered

- `doc/TOOLCHAIN.md` states `androidx.media3` at 1.11.0, but `android/build.gradle.kts` actually pins 1.11.1 (confirmed via `javap` on the installed AAR during the Task 2 investigation). Not fixed here — out of this plan's scope — but `doc/PRESETS.md` reports the real installed version (1.11.1) rather than propagating the stale TOOLCHAIN.md number. Recorded here so a future plan can reconcile TOOLCHAIN.md.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `SizeGuard.Plan.wouldTransmux`/`wouldUseOriginal` are ready for plan 02-07's `estimate()` to call directly — same predicates, same precedence, cannot diverge from what `compress()` actually ATTEMPTS. `estimate()` must not assume `wouldTransmux == true` implies the caller will receive a remuxed file; it can only predict what will be attempted, not the post-check outcome of a real byte count it has not produced.
- **CORE-05 and CORE-06's flagged assumptions are carried forward unresolved, per this plan's own instruction** — the verifier should explicitly challenge both readings (see "Decisions Made" above) rather than treat them as settled by this plan's implementation choice.
- **CORE-06's <30% speed-ratio claim is only measured on the emulator's software encoder** (QUESTIONS.md #3 tracks the outstanding physical-device re-verification, same open item 02-03-SUMMARY.md already logged for `targetSizeMb`).
- **Open coverage gap for the verifier:** no corpus clip on this emulator demonstrates an *observable* `transmuxed:true` result via the no-audio-track (`CONVERSION_PROCESS_NA`) branch specifically — `small_480p.mp4`'s transmux proof has audio; `noaudio_720p.mp4`'s attempted remux lands at exactly the input's own byte count and is correctly substituted. The D-10 predicate condition itself is unit-proven at the `SizeGuardTest.kt` level, but an end-to-end proof of a no-audio remux surviving the never-larger post-check does not exist in this phase's corpus.
- **`InAppMp4Muxer.Factory().setAttemptStreamableOutputEnabled(false)` trades progressive-download-friendly (moov-first) layout for correct file sizes.** This plugin writes finished local files rather than serving them progressively while still being written, so the trade was made without hesitation here — but if a future requirement needs streamable/fast-start output specifically, this decision should be revisited rather than silently reversed.
- `doc/PRESETS.md` and `tool/measure_presets.dart` are ready for Phase 6's README generation, re-measured after the muxer fix.
- Ready for `02-05-PLAN.md` (audio passthrough/re-encode/strip, trim, orientation proof).

---
*Phase: 02-android-compression-on-media3*
*Completed: 2026-09-16*

## Self-Check: PASSED

- `doc/PRESETS.md`, `tool/measure_presets.dart` — FOUND
- `android/src/main/kotlin/com/danjjohnson/compress_video/SizeGuard.kt`, `TransformerEngine.kt` — FOUND
- Commits `b2f37e9`, `2057cde`, `0958a51`, `64f01b0` — FOUND in `git log`
- `flutter test integration_test/compress_test.dart -d emulator-5554` — 19/19 passed (post-rework)
- `cd example/android && ./gradlew :compress_video:testDebugUnitTest` — all passed (including 25 new `SizeGuardTest` cases)
- `flutter test` (root) — 68/68 passed
- `dart pub publish --dry-run` — exit 0, 0 warnings (post-rework)
