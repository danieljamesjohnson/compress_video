---
quick_id: 260923-9lc
slug: fix-apple-ci-simulator-suite-watchdog-so
status: complete
date: 2026-09-23
commit: 42975c5, befad90, 702f1f0
---

# Summary: Fix Apple CI simulator suite watchdog so launch hangs fail fast

## What was done

- Diagnosed the recurring CI failure emails: the Apple job's simulator suite step timed out
  at 60 minutes on every push since 03-04. Run 35826458554's log shows four launch hangs at
  ~12 minutes each. Root cause is an upstream Flutter flake (flutter/flutter#116248, #77992):
  the `xcrun simctl spawn <udid> log stream` process Flutter uses for VM-service discovery
  dies on ~50% of hosted-simulator launches; the tool prints "No tests ran." and
  "Error waiting for a debug connection: The log reader failed unexpectedly" and never
  exits. The step's inline watchdog judged "launched" by `wc -l > 1`, which Flutter's own
  build preamble satisfies instantly, so every hang got the 600 s post-launch budget.
- Added `tool/run_ios_integration_suites.sh` (the suite loop, extracted from ci.yml) with a
  phase-aware watchdog: build (900 s) -> launch (150 s, proven only by a real `MM:SS +N:`
  test-progress line) -> run (600 s); immediate kill on the log-reader error; launch
  failures retried up to 8 times from a fresh simulator boot; a suite with real test output
  that fails still fails fast with no retry.
- Added `tool/run_ios_integration_suites_test.sh`: replays clean pass, log-reader death then
  pass, silent hang on every attempt, build never finishing, genuine failure (proves no
  retry), and two suites with a hang in the middle (proves PARITY_JSON capture) against a
  fake `flutter`. All six pass locally in ~23 s.
- ci.yml's step now calls the script; step comment rewritten with the upstream issue and the
  measured timeline. `timeout-minutes: 60` unchanged.
- Updated the stale lane note in `.claude/CLAUDE.md` that described the old watchdog.

## Verification

- `bash -n` on both scripts; workflow YAML re-parsed with PyYAML.
- `bash tool/run_ios_integration_suites_test.sh` -> "all checks passed".
- CI run 35857609478 (first run with the script): fully green, parity included -- the first
  green run since 35787878946. The simulator step absorbed 5 launch hangs across 10 attempts
  (media_info x2, thumbnail x1, compress_audio x2) in 47 minutes; compress_audio_test.dart
  ran and passed 7/7 for the first time on CI (so the 03-05 AAC re-encode fix in 8a44a04 is
  now proven on the simulator).
- But each hang still cost 3-4.5 min after its build, and the "watchdog:" reason lines were
  missing from the log: the Flutter tool overwrote them in the attempt log it still held
  open, and kill_tree waited unbounded on a tool that takes minutes to exit on SIGTERM.
  Follow-up `befad90`: SIGKILL after 10 s, reason + phase timings reported in the ::warning
  line on stdout; self-test gains a SIGTERM-ignoring fake.
- CI run 35865459091 (befad90): zero launch hangs across three attempts, so the SIGKILL path
  went unexercised, but compress_test.dart failed for a different reason: the `flutter test`
  20 s default per-test timeout hit "p720 scales the long side down to 1280" (~10 s on the
  green run) on a runner whose Xcode build also took 188 s instead of the usual 50-110 s; the
  second failure was the timed-out test's SemanticsHandle assertion leaking into the next
  case. Follow-up `702f1f0`: `--timeout 120s` on both the Apple script's and the Android
  emulator's `flutter test` invocations. Verifying in run 35869222604.

## Commits

- `42975c5` ci: phase-aware watchdog for the iOS simulator suites, hangs now cost ~2 min not ~12
- `befad90` ci: bound the watchdog kill with SIGKILL, report why and how long on stdout
- `702f1f0` ci: raise the integration suites' default per-test timeout to 120 s
