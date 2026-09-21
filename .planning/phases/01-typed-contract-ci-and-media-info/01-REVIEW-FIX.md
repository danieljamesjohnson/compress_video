---
phase: 01-typed-contract-ci-and-media-info
fixed_at: 2026-09-21T18:26:00Z
review_path: .planning/phases/01-typed-contract-ci-and-media-info/01-REVIEW.md
iteration: 1
findings_in_scope: 4
fixed: 4
skipped: 0
status: all_fixed
---

# Phase 01: Code Review Fix Report

**Fixed at:** 2026-09-21T18:26:00Z
**Source review:** .planning/phases/01-typed-contract-ci-and-media-info/01-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 4 (CR-01, WR-01, WR-02, WR-03; IN-02 folded into WR-03 as instructed — same
  unguarded-null pattern in the same file)
- Fixed: 4
- Skipped: 0

## Fixed Issues

### CR-01: `tool/` missing from Apple-relevant CI path filter, so a broken parity gate could merge unexercised

**Files modified:** `.github/workflows/ci.yml`
**Commit:** `f3d5dd6`
**Applied fix:** Added `tool/` and `corpus/` to the `changes` job's path-filter regex (the
review's suggested fix only named `tool/`; `corpus/` was added too per the fix-task
instructions, since parity sidecars live there and were an equally real blind spot). Also
made the `parity` job robust beyond the filter fix alone: it now runs whenever `android`
succeeded, regardless of `apple`'s result, and a new first step (`gate`) checks
`needs.apple.result` explicitly — a legitimate skip (confirmed independently against the
`changes` job's own `apple` output) becomes a clean, logged no-op; anything else (apple
failed, or apple was skipped while `changes` says Apple-relevant paths *did* change) fails
the job loudly instead of the whole job silently vanishing into GitHub's "skipped" status,
which branch protection can treat as passing rather than as a warning. Verified
`.github/workflows/ci.yml` parses with `python3 -c "import yaml; yaml.safe_load(...)"`.

### WR-01: Apple path validation did not resolve symlinks, unlike Android's `canonicalFile`

**Files modified:** `darwin/compress_video/Sources/compress_video/Arguments.swift`
**Commit:** `c55c0ef`
**Applied fix:** `standardizedAbsolutePath` now resolves symlinks via
`.resolvingSymlinksInPath()`, matching Android's `File.canonicalFile` semantics and the
cross-platform contract `lib/src/compress_options.dart`'s `outputPath` dartdoc already
promised ("the native side resolves `.`/`..` segments and symbolic links before writing") —
this was a genuine drift from an already-published Dart contract, not just a cosmetic
asymmetry. Because `resolvingSymlinksInPath()` can only fully resolve components that
already exist (a concern for `outputPath`, whose leaf is about to be created and so never
exists at validation time), the implementation walks up to the nearest existing ancestor,
resolves symlinks there, and reattaches the nonexistent suffix literally — the same
"canonicalise the existing prefix, append the rest" behaviour Java's `File.canonicalFile`
gives for a not-yet-existing path on the Kotlin side. Updated both call sites' dartdoc-style
comments to say "canonicalising" instead of "standardising" to mirror the Kotlin wording.

### WR-02: Apple codec detection silently degrades to `unknown` on iOS 13–15 / macOS 11–12

**Files modified:** `darwin/compress_video/Sources/compress_video/Probe.swift`,
`lib/src/media_info.dart`, `README.md`
**Commit:** `89fd89b`
**Applied fix:** The review's Fix section offered two paths: derive the codec on the legacy
path if avoidable-cast alternatives exist, or (if avoiding the forced/conditional downcast
is the blocker) make the limitation explicit in the `MediaInfo.videoCodec` dartdoc and the
README. I took the documented-limitation path: the existing `Probe.swift` comment already
explains the exact compiler-diagnostic conflict (forced cast banned by threat model vs.
conditional cast flagged "always succeeds" under this project's warnings-as-errors build)
in detail, and an `unsafeBitCast`-based workaround could not be verified to compile without
a Swift toolchain on this machine (CI is the authoritative Swift compiler per the task
instructions, reserved for one iteration at the end of all fixes). Added: an explicit
platform-version-limitation paragraph to `MediaInfo.videoCodec`'s dartdoc naming the exact
iOS 13–15/macOS 11–12 boundary and the reason; a "Known limitation" callout in the README's
`MediaInfo` fields table; and a cross-reference from the `Probe.swift` comment back to both.
Verified `dart analyze lib/src/media_info.dart` reports no issues.

### WR-03 / IN-02: `check_parity.sh` could crash with an opaque bash arithmetic error on a missing field

**Files modified:** `tool/check_parity.sh`, `tool/check_parity_test.sh`
**Commit:** `c9bca86`
**Applied fix:** Added explicit `"null"`/empty guards before every bash arithmetic use fed by
`jq -r`: `durationMs` (both platforms), the sidecar's own `durationToleranceMs` (IN-02 —
folded in here since it is literally the same unguarded-null pattern in the same file, as
the fix-task instructions anticipated), and each `thumbnail.patchRgb[i]` channel plus the
sidecar's `rgbTolerance`. Each guard produces a clean `MISMATCH ... (field missing ...)`
via the existing `fail()` helper and `continue`s to the next check, rather than crashing the
whole script with a bash `$(( ))` syntax error. Extended `tool/check_parity_test.sh` with two
new fixtures: Case 3 (missing `durationMs` on one platform) and Case 4 (missing
`thumbnail.patchRgb` entirely on one platform), each asserting the script fails cleanly and
names the missing field rather than erroring out. Ran `bash tool/check_parity_test.sh`
locally — all four cases (2 original + 2 new) pass.

## Skipped Issues

None — all four in-scope findings (CR-01, WR-01, WR-02, WR-03/IN-02) were fixed.

## Local verification performed

- `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"` — passes (CR-01)
- `dart analyze lib/src/media_info.dart` — no issues (WR-02)
- `bash -n tool/check_parity.sh` / `bash -n tool/check_parity_test.sh` — syntax OK (WR-03)
- `bash tool/check_parity_test.sh` — all 4 cases (2 original, 2 new) PASS (WR-03/IN-02)
- `flutter analyze --fatal-infos --fatal-warnings` at repo root and in `example/` — no issues
- `flutter test` — 84/84 tests pass
- `bash corpus/verify_corpus.sh` — all sidecars match their corpus clips
- `dart format .` at repo root and in `example/` (using the 3.47.5 SDK at
  `~/development/flutter-stable/bin`, per the toolchain-pin instruction) — 0 files changed
- **Swift files (`Arguments.swift`, `Probe.swift`) could not be type-checked locally** — no
  Swift toolchain is installed on danserver. Per the task instructions, CI (GitHub Actions
  `macos-latest`) is the authoritative Swift compiler for this phase. All four fixes were
  pushed to both `origin` (danserver bare repo) and `github`
  (`danieljamesjohnson/compress_video`) in a single push after all four commits landed, at
  commit `c9bca86`. CI was triggered (run `35638310380`) and polled to completion; result below.

### CI result (run 35638310380, commit c9bca86)

**Android job: PASS.** Formatting, `flutter analyze --fatal-infos --fatal-warnings`, the
Pigeon-contract regeneration diff, native unit tests, the full emulator integration suite,
corpus verification, `dart pub publish --dry-run`, and the APK/16KB-page-alignment checks all
passed unchanged.

**`Detect Apple-relevant changes` job: PASS**, and specifically confirms CR-01's filter fix
fired correctly for this push (which touched `.github/workflows/ci.yml`, Swift files under
`darwin/`, and `tool/`) — `apple=true` was correctly computed and the `apple` job ran.

**Apple job: FAILED**, but on a step unrelated to any of the four fixes. `Arguments.swift`'s
new symlink-resolution logic (WR-01) and `Probe.swift`'s doc-only comment change (WR-02) are
both exercised indirectly by `example/integration_test/media_info_test.dart`, which **passed
cleanly on both the initial run and the rerun**, emitting the correct
`PARITY_JSON` payload with `"videoCodec":"h264"` for all three clips both times — direct
evidence the Swift changes compile and behave correctly. The failure is in the *next* suite,
`example/integration_test/thumbnail_test.dart`, run via `flutter test ... -d <sim>`: it hung
with **zero test output** (not even the first test's name printed, unlike
`media_info_test.dart` which prints its first result within ~1s of the Xcode build finishing)
on both its first attempt and its automatic retry, on both the initial run and a full rerun of
the failed jobs (`gh run rerun 35638310380 --failed`). The hang happens before Flutter's test
harness even attaches to the launched app on the simulator, i.e. before any Dart test code
(and therefore before any native call into `Arguments.swift`/`Thumbnails.swift`) executes at
all. This exact failure mode — "`flutter test ... -d <sim>` occasionally hangs at app launch
with zero output on the hosted simulator" — is already documented in
`.github/workflows/ci.yml`'s own comment on the `Run corpus integration tests on the iOS
simulator` step, which explicitly cites **"seen 2026-09-15 and 2026-09-21"** (today) as prior
occurrences, and is why that step already retries once. Both the original run and the rerun
hit the retry too, and the retry also hung — this looks like a worse-than-usual instance of
the same known infra flake (possibly the runner image having a bad day today, since the
workflow's own comment cites today's date already), not a regression introduced by any of the
four fixes.

**`Cross-platform parity` job: FAILED, correctly and as designed** by CR-01's fix. Its new
`gate` step evaluated `needs.apple.result == 'failure'`, printed `FATAL: 'apple' job did not
succeed (result=failure); parity cannot run without its artifact.`, and exited 1 — this is
precisely the "fail loud instead of silently skip" behavior CR-01 was fixed to produce; it is
not a defect in the fix, it is confirmation the fix works (an `apple` failure now surfaces as
an explicit, named job failure rather than the old silent `if: needs.apple.result ==
'success'` skip).

**Residual (per "one CI fix iteration" budget):** the `thumbnail_test.dart` iOS-simulator hang
is recorded here as a pre-existing, already-documented CI flake, not fixed by this task. No
further code change was made for it, since (a) it is infra flakiness with zero diagnostic
output to act on, (b) the CI script already has one retry built in and both retries hung
identically, and (c) `media_info_test.dart`'s clean pass on the same simulator boot, in the
same job, both times, is strong evidence the four review fixes themselves are not the cause.
Recommend: re-run the `apple` job again (a third attempt, cost-free relative to a code
change) or investigate the hosted macOS runner image's simulator health separately from this
phase's fix scope.

## Findings requiring human verification

**WR-01: `fixed: requires human verification`.** The fix's "path exists" branch (full
`.resolvingSymlinksInPath()`) is now confirmed working by CI: `media_info_test.dart` calls
`requireReadableMediaFile` on every corpus clip and passed cleanly on both CI attempts.
However, the fix's *other* branch — the new ancestor-walking loop in
`standardizedAbsolutePath` that resolves symlinks in whatever prefix of a not-yet-existing
`outputPath` already exists, used by `requireWritableOutputParent` — was **not** exercised by
this CI run: it is only reached via `getThumbnailFile`'s custom-`outputPath` path in
`thumbnail_test.dart`, which is the exact suite that hung on the iOS simulator (see the CI
result section above) and never got to run any assertions. No existing corpus/integration
test constructs a *symlinked* output directory either way, so even a clean CI run would not
have exercised the symlink-resolution behavior specifically, only the "no symlinks present"
path through the same code. Recommend: re-run CI once `thumbnail_test.dart`'s hang is
resolved and confirm it passes, and separately consider adding a symlinked-output-directory
test case to `thumbnail_test.dart` or a Swift XCTest, since this is genuinely new logic this
phase's existing test suite does not target.

---

_Fixed: 2026-09-21T18:26:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
