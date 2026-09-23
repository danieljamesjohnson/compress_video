---
quick_id: 260923-9lc
slug: fix-apple-ci-simulator-suite-watchdog-so
status: complete
date: 2026-09-23
commit: 42975c5
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
- Real proof is the next CI run on `github` after this push (hangs should appear as
  ~2-minute warnings and the step should finish well inside 60 minutes).

## Commit

- `42975c5` ci: phase-aware watchdog for the iOS simulator suites, hangs now cost ~2 min not ~12
