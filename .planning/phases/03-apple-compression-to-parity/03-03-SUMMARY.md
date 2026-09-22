---
phase: 03-apple-compression-to-parity
plan: 03
subsystem: ui
tags: [flutter, material3, image_picker, video_player, widget-test, flutter_test]

# Dependency graph
requires:
  - phase: 02-android-compression-on-media3
    provides: The public compress()/estimate()/CompressJob Dart API this screen consumes end-to-end on Android, the only platform with a working compression engine at this wave
provides:
  - "example/lib/src/main_screen.dart: the single-screen, seven-state BULD-04 demo (Idle, Picking, Estimating, Compressing, Cancelled, Failed, Done) driving pick -> options -> estimate -> compress -> progress/cancel -> result -> play, all on one shared Material 3 widget tree"
  - "example/lib/src/compression_runner.dart: the CompressionRunner seam (real CompressVideo-backed implementation + the abstract interface) that lets the screen be widget-tested with no platform channel"
  - "example/test/main_screen_test.dart: 19 widget tests covering all seven states, the 600/599 breakpoint pair, and both UI-SPEC backstops, runnable by `flutter test` on Linux with no device"
  - "A documented, reusable fix for a real Flutter widget-testing hazard: real dart:io work triggered by a tester.tap() issued outside WidgetTester.runAsync() never completes, regardless of how many plain pump() calls follow, because FakeAsync binds an async callback's continuations to whichever zone was active when it started"
affects: [03-09]

# Actuals (#2632)
actuals:
  tokens: 20300
  tasks: 3
  commits: 3

# Tech tracking
tech-stack:
  added: [image_picker@1.2.3, video_player@2.14.0]
  patterns:
    - "CompressionRunner abstraction: the screen never touches CompressJob directly, only a small CompressionHandle (progress stream + result future + cancel callback), which is what makes the screen widget-testable with a fake in place of the real platform channel"
    - "WidgetTester.runAsync() must wrap BOTH the action that starts real dart:io work AND the wait for it, in one block -- an async callback's continuations stay bound to whichever zone (fake-async test zone vs the real zone runAsync forks) was active when the callback started; splitting the tap and the wait across separate runAsync calls leaves the continuation permanently stuck in the fake zone"
    - "Widget tests that need 'a clip picked' use a fake ImagePickerPlatform (MockPlatformInterfaceMixin) resolving to a tiny 1-byte real file, not the 4.45MB bundled corpus asset, so the unavoidable real File.length() call stays fast regardless of machine load"

key-files:
  created:
    - example/lib/src/compression_runner.dart
    - example/lib/src/main_screen.dart
    - example/test/main_screen_test.dart
  modified:
    - example/lib/main.dart
    - example/pubspec.yaml
    - example/test/widget_test.dart
    - example/ios/Runner/Info.plist
    - example/macos/Runner/DebugProfile.entitlements
    - example/macos/Runner/Release.entitlements
    - example/macos/Flutter/GeneratedPluginRegistrant.swift

key-decisions:
  - "Executed as one continuous autonomous run (no interactive tracer-gate pause): re-ran the tracer's own <verify> end-to-end on the real Android emulator after task 1's commit (build, install, drive the full bundled-clip -> compress -> progress -> result -> play path, screenshots captured) before proceeding to tasks 2 and 3, matching the auto-mode tracer feedback gate."
  - "Added image_picker_platform_interface and plugin_platform_interface as dev_dependencies (never dependencies:) so main_screen_test.dart can fake ImagePickerPlatform.instance with MockPlatformInterfaceMixin -- both are already transitive dependencies of image_picker; this is test-only infrastructure, not a new production dependency, and does not violate the plan's 'no pub dependency beyond image_picker and video_player' prohibition (verified: the pubspec.yaml diff adds exactly two entries under dependencies:)."
  - "pumpMainScreen() sizes the test viewport generously (800x2400 logical px by default) instead of the flutter_test default 800x600, because the fully-populated screen (Options card + Estimate + Result + Player) is taller than 600px and left 'Compress video' positioned off-screen for tester.tap() in the default viewport -- confirmed via Flutter's own hit-test warning, not assumed."
  - "The Failed-state coverage (03-UI-SPEC backstop 'at least three distinct reasons') is three separate testWidgets blocks sharing one helper, not one test looping three times -- each iteration's real (runAsync-bound) pick work fully settles within its own isolated test rather than risking interleaving with the next iteration's fresh widget tree."

requirements-completed: [BULD-04]

coverage:
  - id: D1
    description: "One shared Dart widget tree drives pick -> options -> estimate -> compress -> progress/cancel -> result -> play through the real public API, proven end-to-end on the Android emulator (the only platform with a working engine this wave)"
    requirement: BULD-04
    verification:
      - kind: manual_procedural
        ref: "Live run on emulator-5554: bundled clip -> Compress -> 39% progress -> -82% smaller result card (4454349 -> 814822 bytes) -> inline playback toggled; screenshots committed under .planning/phases/03-apple-compression-to-parity/screenshots/"
        status: pass
    human_judgment: false
  - id: D2
    description: "All seven screen states (Idle, Picking, Estimating, Compressing, Cancelled, Failed, Done) implemented per 03-UI-SPEC.md and covered by widget tests with no device"
    requirement: BULD-04
    verification:
      - kind: automated_ui
        ref: "example/test/main_screen_test.dart (19 testWidgets cases)"
        status: pass
    human_judgment: false
  - id: D3
    description: "The options panel exposes exactly the public CompressOptions surface, pre-filled from CompressOptions()'s own defaults, disabled while compressing"
    requirement: BULD-04
    verification:
      - kind: automated_ui
        ref: "example/test/main_screen_test.dart#options-panel/empty, #Compressing"
        status: pass
    human_judgment: false
  - id: D4
    description: "Single 600px responsive breakpoint: desktop-constrained layout at >=600, full-bleed phone layout below it, no third breakpoint"
    requirement: BULD-04
    verification:
      - kind: automated_ui
        ref: "example/test/main_screen_test.dart#breakpoint: at exactly 600 / #breakpoint: at 599"
        status: pass
    human_judgment: false
  - id: D5
    description: "Both UI-SPEC backstops: targetSizeMb+videoBitrateBps together shows the validation SnackBar and never enters Compressing; a synthetic 200-character filename renders ellipsised on one line with no overflow at 360px"
    requirement: BULD-04
    verification:
      - kind: automated_ui
        ref: "example/test/main_screen_test.dart#backstop: targetSizeMb.../ #backstop: a 200-character filename..."
        status: pass
    human_judgment: false
  - id: D6
    description: "iOS NSPhotoLibraryUsageDescription and macOS files.user-selected.read-only entitlements (both Debug and Release) present for the picker"
    requirement: BULD-04
    verification:
      - kind: other
        ref: "grep -c NSPhotoLibraryUsageDescription example/ios/Runner/Info.plist; grep -c files.user-selected.read-only example/macos/Runner/{DebugProfile,Release}.entitlements"
        status: pass
    human_judgment: false
  - id: D7
    description: "The rewrite did not break the existing Phase 1/2 device integration suite"
    verification:
      - kind: integration
        ref: "example/integration_test/media_info_test.dart -d emulator-5554 (9 cases)"
        status: pass
    human_judgment: false
  - id: D8
    description: "iOS simulator / macOS desktop runs of the example app -- deferred, Mac offline this session"
    human_judgment: true
    rationale: "The MacBook Air is offline on the tailnet (QUESTIONS.md #8, carried from 03-01). No Apple compression engine exists yet either (that is this phase's later plans). Deferred to 03-09, which owns closing 02-UAT.md #6 with iOS-simulator and macOS screenshots once the Mac is reachable and the Apple engine lands."
    verification: []

# Metrics
duration: 92min
completed: 2026-09-22
status: complete
---

# Phase 3 Plan 3: Real Picker, Full Options Panel and Seven-State Screen Summary

**Rewrote the example app into BULD-04's real single-screen demo (pick → options → estimate → compress → progress/cancel → result → play) on Flutter's stock Material 3, covered all seven states plus both responsive breakpoints and both UI-SPEC backstops with 19 widget tests, and along the way root-caused and fixed a genuine `WidgetTester.runAsync()`/`FakeAsync` zone-binding hazard that was silently hanging or dropping picks in the new test suite.**

## Performance

- **Duration:** 92 min
- **Started:** 2026-09-22T14:46:22Z
- **Completed:** 2026-09-22T16:18:03Z
- **Tasks:** 3 of 3 completed
- **Files modified:** 10 (3 created, 7 modified)

## Accomplishments

- `example/lib/src/compression_runner.dart`: `CompressionRunner` abstraction (`CompressionHandle` = progress stream + result future + cancel callback) plus `RealCompressionRunner`, the seam that makes the screen widget-testable with no platform channel.
- `example/lib/src/main_screen.dart`: the full seven-state screen — Idle empty state, Picking (in-button spinner), Estimating (300ms-debounced live estimate), Compressing (disabled options, live progress, Cancel), Cancelled (SnackBar, no card), Failed (reason-mapped `errorContainer` card, Try again), Done (savings headline, stat rows, `Wrap` badge row, inline `video_player` playback with tap-to-toggle) — wired to the real `image_picker` picker and a bundled-clip fallback, with a single 600px responsive breakpoint.
- `example/lib/main.dart` reduced to a `MaterialApp` hosting `MainScreen` with Flutter's stock Material 3 light/dark themes and `themeMode: ThemeMode.system`.
- `example/test/main_screen_test.dart`: 19 widget tests — every state, both breakpoint sides, both backstops, section ordering, and the video-player loading/error states — all green on Linux with no device, in ~7 seconds.
- Verified the full tracer end-to-end on the real Android emulator (`emulator-5554`): built and installed the debug APK, drove bundled clip → Compress → live 39% progress → `-82% smaller` result card (4,454,349 → 814,822 bytes) → inline playback with a working tap-to-toggle; four screenshots committed under `.planning/phases/03-apple-compression-to-parity/screenshots/`.
- Confirmed the rewrite broke nothing already shipped: the existing `integration_test/media_info_test.dart` device suite (9 cases) still passes on `emulator-5554`.

## Task Commits

Each task was committed atomically:

1. **Task 1: End-to-end "bundled clip to played result"** — `9be3a86` (feat)
2. **Task 2: Implement the remaining six screen states, the picker, the options panel and the responsive layout** — `a1a476f` (feat)
3. **Task 3: Widget-test every state and both backstop considerations with a fake runner, on Linux** — `fd2e635` (test)

**Plan metadata:** committed together with this summary.

## Files Created/Modified

- `example/lib/src/compression_runner.dart` — `CompressionRunner`/`CompressionHandle` seam + `RealCompressionRunner`
- `example/lib/src/main_screen.dart` — the seven-state BULD-04 screen
- `example/test/main_screen_test.dart` — 19 widget tests, `FakeCompressionRunner`, `FakeImagePickerPlatform`, `pickClip`/`pumpMainScreen`/`waitForEstimateDebounce` test helpers
- `example/lib/main.dart` — reduced to `MaterialApp` hosting `MainScreen`
- `example/pubspec.yaml` — `image_picker`/`video_player` (production), `image_picker_platform_interface`/`plugin_platform_interface` (dev-only test infra)
- `example/test/widget_test.dart` — updated smoke test for the new screen
- `example/ios/Runner/Info.plist` — `NSPhotoLibraryUsageDescription`
- `example/macos/Runner/{DebugProfile,Release}.entitlements` — `com.apple.security.files.user-selected.read-only`
- `example/macos/Flutter/GeneratedPluginRegistrant.swift` — auto-regenerated by `flutter pub get` to register the new macOS plugin implementations

## Decisions Made

- Ran the tracer feedback gate autonomously: after committing task 1, re-verified its `<verify>` live on the real emulator before starting task 2's expansion work, rather than pausing for interactive confirmation — consistent with this being an unattended run per the orchestrator's instructions.
- `image_picker_platform_interface` and `plugin_platform_interface` added as `dev_dependencies` (never `dependencies:`) so the widget test can fake `ImagePickerPlatform.instance` — both were already transitive dependencies pulled in by `image_picker`; declaring them explicitly is required only because test code imports them directly. Verified this does not violate the plan's dependency prohibition: `git diff` on `example/pubspec.yaml` adds exactly two entries under `dependencies:` (`image_picker`, `video_player`).
- `pumpMainScreen()` sizes the test viewport to 800×2400 logical pixels by default (vs. `flutter_test`'s 800×600 default), because the fully-populated screen doesn't fit in 600px tall and left `Compress video` off-screen for `tester.tap()` — confirmed via Flutter's own "would not hit test" warning before fixing it, not assumed.
- The three-reason "Failed" state backstop is three separate `testWidgets` blocks sharing one helper function, not one test looping three times, to keep each iteration's real (`runAsync`-bound) work fully isolated.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `dart format` from the pinned stable SDK triggered Flutter's project migrator, rewriting `example/analysis_options.yaml` and `example/macos/Flutter/GeneratedPluginRegistrant.swift`**
- **Found during:** Task 1, first `flutter test` run with `PATH` pointed at `flutter-stable`
- **Issue:** Running any `flutter` (not just `dart format`) command with the stable SDK on `PATH` triggers Flutter's scaffold migrators — exactly the documented `.claude/CLAUDE.md` lane-note hazard. `analysis_options.yaml` picked up an unwanted `analyzer: exclude:` block; `GeneratedPluginRegistrant.swift` picked up legitimate new plugin registrations (`file_selector_macos`, `video_player_avfoundation`) mixed in with the unwanted change.
- **Fix:** Reverted the `analysis_options.yaml` exclude block (unwanted migrator side effect); kept the `GeneratedPluginRegistrant.swift` change (a correct, needed regeneration reflecting the new picker/player dependencies). From then on, invoked the stable SDK's `dart` binary directly (`$HOME/development/flutter-stable/bin/dart format`) rather than exporting it onto `PATH`, so only `dart format` — never a full `flutter` command — runs under the stable SDK.
- **Files modified:** `example/analysis_options.yaml` (reverted), `example/macos/Flutter/GeneratedPluginRegistrant.swift` (kept)
- **Verification:** `git diff` confirmed only the intended file changed after the revert; `flutter analyze` and `flutter build apk --debug` both clean afterward.
- **Committed in:** `9be3a86` (task 1 commit; the revert happened before staging)

**2. [Rule 3 - Blocking] `WidgetTester.runAsync()`/`FakeAsync` zone-binding hazard silently hung or dropped every widget test that picked a clip**
- **Found during:** Task 3, first full `flutter test test/main_screen_test.dart` run
- **Issue:** `AutomatedTestWidgetsFlutterBinding` runs the entire test body inside a `FakeAsync` zone. An async callback's continuations stay bound to whichever zone was active when the callback *started* — not to whichever zone is active when a *later* piece of test code awaits it. `tester.tap()` issued outside `runAsync()` starts the tapped `onPressed` callback's async chain (real `rootBundle.load`/`File.writeAsBytes`/`File.length()`) in the fake zone, where a genuine OS-backed `Future` never gets a real event-loop turn — no amount of `pump()` afterward, and no *separate*, later `runAsync()` call, unblocks it. One test (the 200-character-filename backstop) hung for the full default 10-minute per-test timeout before this was root-caused; several others failed fast with "widget not found" once a bounded wait was added, misleadingly looking like ordinary flakiness.
- **Fix:** `pickClip()` (and the 200-char-filename test's own pick) now perform the tap, the fake-picker completer resolution, and a bounded real wait *together inside one `runAsync()` block*. A parallel discovery — the estimate debounce `Timer` created as part of that same real-zone continuation is *itself* a real timer, so waiting for it to fire also needs its own `runAsync`-wrapped wait (`waitForEstimateDebounce`), not an ordinary fake-time `pump(duration)`. Also switched every pick in the test file from the 4.45MB bundled corpus asset to a tiny 1-byte real file (via a fake `ImagePickerPlatform`), since the unavoidable real `File.length()` call is then fast regardless of machine load.
- **Files modified:** `example/test/main_screen_test.dart`
- **Verification:** Full suite (19 cases) green twice in a row, ~7s each run; individually re-ran the previously-hanging 200-char-filename test in isolation to confirm it now completes in under a second.
- **Committed in:** `fd2e635` (task 3 commit)

**3. [Rule 3 - Blocking] `flutter test`'s default 800×600 surface left `Compress video` off-screen for `tester.tap()`**
- **Found during:** Task 3, same debugging session as deviation 2
- **Issue:** The fully-populated screen (picked-clip tile + Options card with 4 text fields, 2 segmented buttons and trim fields + Estimate line + Result card + Player) is taller than the default 600px-tall test viewport once a clip is picked. `tester.tap(find.text('Compress video'))` derived an offset outside the root render tree's bounds and silently missed, leaving several tests stuck in the pre-tap state.
- **Fix:** `pumpMainScreen()` sets `tester.view.physicalSize` to a generous 800×2400 by default (with `devicePixelRatio: 1.0` so logical == physical), used by every test except the three that deliberately manage their own narrower size (the two breakpoint tests and the 200-char-filename backstop, which now pass their own `viewSize` through the same helper).
- **Files modified:** `example/test/main_screen_test.dart`
- **Verification:** Same full-suite green run as deviation 2.
- **Committed in:** `fd2e635` (task 3 commit)

---

**Total deviations:** 3 auto-fixed (all Rule 3 — blocking issues preventing task completion, no scope creep).
**Impact on plan:** All three were necessary to reach a genuinely green, reliable `flutter test` — the plan's own explicit success criterion. None touched `main_screen.dart`'s production behavior; all three are either a reverted tooling side effect or test-infrastructure-only fixes.

## Issues Encountered

The `WidgetTester.runAsync()`/`FakeAsync` zone-binding hazard (deviation 2) is worth flagging beyond this plan: it is a general Flutter widget-testing pitfall, not specific to this screen. Any future widget test in this project that triggers real `dart:io` work from inside a `tester.tap()`/`tester.enterText()` callback needs the same "start and wait inside one `runAsync()` block" pattern — documented in `main_screen_test.dart`'s file header comment for the next person who hits it.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- BULD-04 is fully implemented and proven end-to-end on Android (the only platform with a working compression engine this wave) and covered by 19 fast, reliable widget tests with no device.
- **iOS simulator and macOS desktop runs of this screen remain outstanding** — deferred to 03-09, which owns closing 02-UAT.md #6 with those screenshots once the Mac is reachable (QUESTIONS.md #8, still open) and the Apple compression engine exists.
- `03-01`'s task 1 (Mac second-SDK bring-up, `tool/mac_sync.sh`/`tool/mac_run.sh`) is still outstanding and blocks every later Apple-side plan in this phase, unchanged by this plan.

## Self-Check: PASSED

- `[ -f example/lib/src/compression_runner.dart ]` → FOUND
- `[ -f example/lib/src/main_screen.dart ]` → FOUND
- `[ -f example/test/main_screen_test.dart ]` → FOUND
- `git log --oneline --all --grep="03-03"` → FOUND (9be3a86, a1a476f, fd2e635)
- Plan-level `<verification>` re-run post-commit: `flutter analyze --fatal-infos --fatal-warnings` clean; `dart format` (stable SDK) reports no changes under `example/lib`; `cd example && flutter test` — 20/20 passing (19 new + 1 existing); `cd example && flutter build apk --debug` clean; `integration_test/media_info_test.dart -d emulator-5554` — 9/9 passing

---
*Phase: 03-apple-compression-to-parity*
*Completed: 2026-09-22*
