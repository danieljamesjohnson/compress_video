# QUESTIONS — things only Dan can do

## 1. Authorize danserver's SSH key on the MacBook Air — RESOLVED 2026-09-21 (Dan added the key; Mac user is `danjohnson`; `ssh dans-macbook-air` works from danserver)

`ssh dans-macbook-air` from danserver is refused: `Permission denied (publickey,password,keyboard-interactive)`.
Agents need it to compile and test the iOS/macOS side (decision 2026-09-15: "SSH to dans-macbook-air").

On the Mac:
1. System Settings → General → Sharing → **Remote Login: on**, allow user `dan` (or whatever your Mac user is; the failed attempt used `dan`).
2. Append danserver's public key to `~/.ssh/authorized_keys` on the Mac. Print it on danserver with:
   ```
   cat ~/.ssh/id_ed25519.pub 2>/dev/null || cat ~/.ssh/id_rsa.pub
   ```
3. Confirm Xcode (with iOS simulators), CocoaPods and Flutter are installed on the Mac, and tell agents the Mac username if it is not `dan`.

Until this is done, Apple-side phases will build Swift code without verification and the roadmap orders Android phases first.

## 2. pub.dev publisher — RESOLVED 2026-09-29 (Dan: publish under the Google account; `dart pub publish` run from danserver with Dan completing the Google sign-in; pub.dev accepted compress_video 1.0.0; tag v1.0.0 pushed to both remotes; GitHub release created)

No verified publisher exists for your account yet. Before the release phase, either create one (needs a domain you control, e.g. `danjjohnson.com`) or decide to publish under your Google account. Not blocking until the last phase.

**Update 2026-09-27 (06-04): this now blocks the release.** The package is ready to publish as
1.0.0: `dart pub publish --dry-run` reports `Package has 0 warnings.` (572 KB archive), dartdoc
reports 0 warnings, and both are CI gates. The only thing between the package and pub.dev is your
publisher choice, then the one command in `doc/RELEASE.md`. Both options are written out there
(item 4 of the pre-publish checklist). This blocks ROADMAP criterion 1 ("live on pub.dev at
160/160"). No agent will publish, tag or create the release.

**One more decision, also 2026-09-27: may agents install `pana`?** `pana` is the tool pub.dev
uses to compute pub points. The release plan allowed installing it only if pub.dev listed its
publisher as `dart.dev`. pub.dev lists it as `tools.dart.dev`
(`curl -s https://pub.dev/api/packages/pana/publisher` gives `{"publisherId":"tools.dart.dev"}`).
That publisher's own page says "Tooling packages published by the Dart Team", and `dartdoc` is
under the same publisher. It was still not what the plan required, so pana was **not installed,
not run, and has no CI step**. The pana score of this package is therefore unknown. If you are
satisfied that `tools.dart.dev` is the Dart team, say so and an agent will install pana, run it,
fix what it names, and add the CI gate at threshold 0. If you would rather not, the first check
after publishing (`https://pub.dev/packages/compress_video/score`) is where the score is seen.

**RESOLVED 2026-09-27 (the pana question only):** approved. `tools.dart.dev` is the Dart team's
tooling publisher, and the plan's `dart.dev` was a mistake in the plan, not a rule about which
publisher is trusted. pana 0.23.19 was installed and run: the package scores **160 of 160**. CI
now has the step `pana: 160/160 pub points (RELS-01)`. The publisher choice above is still open
and still blocks the release.

**Update 2026-09-28 (phase close):** Phase 6 is complete on the agent side. Final CI run of record
36366408783 is green on all four jobs (pana 160/160 and dartdoc 0 warnings on the hosted runner,
compat suite on Android emulator, iOS simulator and macOS host, parity). Verification
(06-VERIFICATION.md) is `human_needed` on exactly two items, both yours: (a) choose the publisher
and run the publish per `doc/RELEASE.md` (`dart pub publish`, tag `v1.0.0`, GitHub release), and
(b) re-run `doc/HARDWARE_CHECKLIST.md` on a physical Android phone and the MacBook Air first
(#3, #4, #8). One notification was sent for this on 2026-09-28. Nothing else is waiting on an
agent.

## 3. Physical Android phone for hardware checks

The emulator covers builds and most logic. HEVC hardware encoding and HDR tone-map fidelity need a real phone (a Pixel with HLG10 capture is ideal). When one is available, either plug it into danserver over USB or expose `adb` over the tailnet. Not blocking until the codec/HDR phase.

**Added 2026-09-15 (02-03):** the emulator's software H.264 encoder (`c2.android.avc.encoder`)
does not reliably keep `CompressOptions.targetSizeMb`'s documented plus-or-minus 15 percent
tolerance on this project's 4-second high-bitrate corpus clip once it's been resized/frame-rate-
capped down — measured live: a 1.0MB target produced +19.1%, a 2.0MB target produced -29.9%
(both directions, not just under- or over-shoot). `SizeGuard`'s formula itself is exact and
unit-tested (`SizeGuardTest.kt`); this is real software-encoder rate-control behavior, not an
arithmetic bug. The emulator integration test (`compress_test.dart`) uses a documented, wider
±35% tolerance for this reason. When a physical phone is available, re-run the same
`targetSizeMb` cases against its hardware encoder and tighten the emulator test's tolerance
comment (or confirm ±15% only holds on hardware, and adjust `CompressOptions.targetSizeMb`'s
dartdoc accordingly) — see `02-03-SUMMARY.md` Deviations for the full writeup. Not blocking;
grouped with this phone's other hardware-encoder verification work.

**Added 2026-09-15 (02-07):** the same software-encoder CBR characteristic affects
`CompressEstimate.outputBytes`'s pre-flight accuracy, not just `targetSizeMb`. Measured live
against all four presets on the high-bitrate corpus clip: the real encode diverged from the
formula's designed plus-or-minus 15 percent tolerance by 7.9 to 67.0 percent (p360 7.9%, p480
34.2%, p720 67.0%, p1080 43.0% — not monotonic with resolution). `SizeGuardTest.kt` proves the
underlying arithmetic is exact; this is real rate-control behavior, the same class of finding as
the `targetSizeMb` note above. `example/integration_test/compress_output_test.dart` uses a
documented ±75% emulator tolerance for this reason, and `CompressEstimate.outputBytes`'s dartdoc
carries the same caveat. When a physical phone is available, re-run the estimate-accuracy cases
against its hardware encoder and tighten (or confirm) the tolerance — see `02-07-SUMMARY.md`
Deviations. Not blocking; grouped with this phone's other hardware-encoder verification work.

**Update 2026-09-27 (06-04):** the release now waits on this. Item 1 of the pre-publish
checklist in `doc/RELEASE.md` is a re-run of `doc/HARDWARE_CHECKLIST.md` against a release
build, and it needs this.

## 4. Real phone clips for the test corpus

Phase 1 ships an ffmpeg-generated corpus that mirrors phone structure (rotation display matrix, AAC, no-audio, already-small). Real clips are still needed for the rotation/HDR checks that every competitor got wrong. When convenient, get these onto danserver (the feedback drop at http://danserver/drop, or `scp` into `~/CodeProjects/compress-video/corpus/incoming/`):

- an iPhone portrait clip recorded with HDR on (Dolby Vision profile 8), 5-10 s
- a Pixel (or any Android) portrait clip with HDR/HLG10 on, 5-10 s
- any short clip with 5.1 audio if you have one (optional)

Not blocking until Phase 4 (Codecs, HDR and Hard Inputs).

**Update 2026-09-27 (06-04):** the release now waits on this. Item 1 of the pre-publish
checklist in `doc/RELEASE.md` is a re-run of `doc/HARDWARE_CHECKLIST.md` against a release
build, and it needs this.

## 5. GitHub repository visibility — RESOLVED 2026-09-21 (Dan: "make it public"; repo is now public, Actions minutes uncapped)

Phase 1 creates `github.com/danieljamesjohnson/compress_video` as **private** and wires GitHub Actions to it (Linux + macOS runners). Your account is on the free plan: private repos get 2,000 Actions minutes/month and macOS is billed at 10×, so the macOS job is path-filtered to Apple-relevant changes. Making the repo public (Settings → General → Change visibility) lifts the cap entirely and is the intended MIT end state. Your call on when.

## 6. GitHub Actions billing block — RESOLVED 2026-09-21 (repo made public per #5; Actions jobs start again, macOS included)

While driving 01-06 (Apple Probe/Thumbnails) to a green CI run, the `apple` job stopped starting
entirely. `gh run view <id> --attempt 3` shows:

> The job was not started because recent account payments have failed or your spending limit
> needs to be increased. Please check the 'Billing & plans' section in your settings.

This happened after several real Apple CI runs in one session (each macOS run is billed at 10x
Actions minutes per QUESTIONS.md #5) — likely either a lapsed payment method or the account's
Actions spending limit was reached mid-session.

**To unblock:** GitHub → Settings → Billing and plans → check for a failed payment / update the
payment method, and/or raise the Actions spending limit (Settings → Billing and plans → Plans
and usage → Spending limits — the default on a fresh account is often $0, which blocks any
overage past the included free minutes).

Until this is fixed, no `apple` job on this workflow can run at all (not "red", literally never
started — `Detect Apple-relevant changes` and `Android` still ran fine on the free Linux
minutes). 01-06's Apple Swift changes are code-complete and were validated as far as CI would run
(see 01-06-SUMMARY.md), but the final fully-green confirmation of the last fix is blocked here.
Re-run the `CI` workflow's latest `main` push (`gh run rerun <id> --failed` or a new push) once
billing is resolved.

## 7. CocoaPods (and Homebrew) are not installed on the MacBook Air

Xcode 26.2, an iOS 26.2 simulator runtime and Flutter are present, but `pod` is not, and there is no
Homebrew. Flutter's CocoaPods integration path (and any `flutter build ios` for an app that still
uses CocoaPods) needs it. Agents cannot install it: `sudo gem install cocoapods` needs your password.
Either run `sudo gem install cocoapods` on the Mac, or install Homebrew and `brew install cocoapods`.
Until then, Phase 3 builds on the Mac use the Swift Package Manager path and CI covers CocoaPods.

**Update 2026-09-22:** an agent tried the no-password route — `gem install --user-install cocoapods` into
`~/.gem` — three times with progressively pinned versions (ffi 1.16.3 installs; then `securerandom`,
then `zeitwerk` each demand Ruby ≥ 3.1/3.2). macOS 26's system Ruby is 2.6.10, so **no CocoaPods
release resolvable today installs on the system Ruby, with or without sudo** — `sudo gem install
cocoapods` would hit the same wall. What actually works: install Homebrew, then `brew install cocoapods`
(Homebrew's formula bundles its own modern Ruby). Both steps need your admin password once. Why it
matters: the example app's `ios/` and `macos/` projects carry committed Podfiles (that is how CI proves
the CocoaPods install path), and Flutter runs `pod install` for them even with SPM enabled, so
**`flutter build ios`/`flutter build macos` of the example cannot run on the Mac at all until `pod`
exists** — which is why Phase 3's Apple verification is currently routed through the GitHub Actions
macOS runner (30-40 min per attempt) instead of your Mac (minutes). The second Flutter SDK
(`~/development/flutter-stable`, 3.47.5) is installed and ready; `~/flutter` is untouched.
Leftover from the attempts, harmless and removable: `~/.gem/ruby/2.6.0/` (partial gems) and
`~/development/cocoapods-install*.log`.

**RESOLVED 2026-09-25:** found `/opt/homebrew/bin/pod` (CocoaPods 1.17.0) and Homebrew 5.1.15 on the Mac
-- Dan installed them. Note for agents: non-interactive SSH does not put `/opt/homebrew/bin` on PATH, so
`which pod` over plain `ssh` says "not found"; `tool/mac_run.sh` exports it. `flutter build ios` on the
Mac now gets past `pod install` (455 ms).


## 8. MacBook Air is offline on the tailnet (blocks 03-01 task 1)

2026-09-22, executing 03-01-PLAN.md task 1 (Mac second-SDK bring-up + `tool/mac_sync.sh`/`mac_run.sh`):
`ssh dans-macbook-air true` and a fresh `ssh -o ConnectTimeout=8 -o BatchMode=yes dans-macbook-air`
both time out ("Connection timed out" on port 22, tried twice, ~15 min apart). `tailscale status`
confirms: `dans-macbook-air ... macOS active; relay "dfw"; offline, last seen 5m ago`. This is not
the QUESTIONS.md #1 permission issue (that was resolved 2026-09-21 and SSH has worked since) — the
machine itself is unreachable on the tailnet right now, most likely asleep (lid closed / idle) with
no wake-on-LAN for Remote Login.

**To unblock:** wake the MacBook Air (open the lid, or otherwise bring it out of sleep) so it
rejoins the tailnet. No password or credential is needed once it's awake — SSH itself has worked
reliably since #1 was resolved.

Not urgent enough to interrupt you for — it doesn't block the rest of Phase 3 planning/execution,
only the Mac-dependent parts of 03-01 task 1 (SDK install, `tool/mac_sync.sh`/`mac_run.sh` proof)
and everything downstream that needs a live Mac. Tasks 2 and 3 of 03-01 completed and committed
regardless; task 1 is carried forward as blocked until the Mac is reachable again — see
03-01-SUMMARY.md.

**Update 2026-09-22 09:38-09:50 CDT:** the Mac came back on the tailnet at 09:38 (SSH answered, Xcode
26.2 responded, a `caffeinate -i -s -t 10800` was started to hold it awake and the second Flutter SDK
clone was kicked off in the background at `~/development/flutter-stable`), then it dropped off again
about 10 minutes later — `caffeinate -s` only prevents system sleep on AC power, so it is almost
certainly on battery with the lid closed. **What unblocks Phase 3 for real: leave the MacBook Air open
(or plug it into power with the lid closed and "Prevent automatic sleeping on power adapter" on) for
the next couple of hours.** The SDK clone may be partial; the 03-01 continuation re-validates it and
re-clones if needed. Until then the run continues with plans that need no Mac (03-03 done; 03-02 is
using the GitHub Actions macOS runner as its XCTest verifier).

**Update 2026-09-25 ~09:15-09:40 CDT:** reachable again for about 25 minutes (on battery, 91%,
`pmset` showed sleep held off by Music/sharingd), long enough to execute 03-01 task 1's scripts and
find a real Swift type-check failure (fixed, `fac7f69`), then it slept again in the middle of
`flutter build macos`. Still the same ask: **leave the MacBook Air open or on power with sleep-on-adapter
off** for a couple of hours so `bash tool/mac_sync.sh && bash tool/mac_run.sh build-ios && bash
tool/mac_run.sh build-macos` can close 03-01 task 1's last acceptance criterion. Not blocking: the
autonomous run continues on the GitHub Actions macOS runner (Dan's instruction, 2026-09-25).

**Update 2026-09-25 (executing 03-08-PLAN.md task 1):** `timeout 15 ssh -o ConnectTimeout=8
-o BatchMode=yes dans-macbook-air true` timed out again; `tailscale status` shows
`dans-macbook-air ... offline, last seen 5h ago`. This blocks 03-08 task 1 specifically:
`tool/verify_fresh_app.sh`'s own `<precondition>` requires `bash tool/mac_sync.sh && bash
tool/mac_run.sh build-macos` to exit 0 before the script is even written, precisely because 03-01
task 1's own Mac-side `build-macos` proof (above) never completed either. Per the executor's
precondition protocol this is never auto-approved or worked around — task 1 did not run at all
(no file written, no commit). Tasks 2 and 3 of 03-08 do not depend on the Mac and proceeded
normally via GitHub Actions. Same ask as above: leave the MacBook Air open or on power with
sleep-on-adapter off. When it next answers, resume with `bash tool/mac_sync.sh && bash
tool/mac_run.sh build-ios && bash tool/mac_run.sh build-macos` (closing 03-01 task 1), then
`03-08-PLAN.md` task 1 exactly as written.

**Update 2026-09-25 (executing 03-09-PLAN.md task 1):** `timeout 15 ssh -o ConnectTimeout=8
-o BatchMode=yes dans-macbook-air true` timed out again ("Connection timed out" on port 22),
probed once at the start of this plan per its own Mac-dependent-task instructions. This blocks
03-09 task 1 specifically: the example app driven by hand on the iOS simulator and the macOS
host, with screenshots closing 02-UAT.md item 6 and closing BULD-04's Apple half. Per the
executor's precondition protocol and this run's explicit standing instruction to defer rather
than loop, task 1 did not run at all — no screenshots, no 02-UAT.md change, no commit. Tasks 2
and 3 of 03-09 do not need the Mac (CI run 36202392709 stands as the observed evidence for the
plugin engine's behaviour on iOS/macOS; only the example app's own UI needs a live Mac) and
proceeded normally. Same ask as the rows above: leave the MacBook Air open or on power with
sleep-on-adapter off. When it next answers, resume with `bash tool/mac_sync.sh && bash
tool/mac_run.sh ios integration_test/compress_test.dart` (03-09 task 1's own precondition),
then execute `03-09-PLAN.md` task 1 exactly as written.

**Update 2026-09-27 (06-04):** the release now waits on this. Item 1 of the pre-publish
checklist in `doc/RELEASE.md` is a re-run of `doc/HARDWARE_CHECKLIST.md` against a release
build, and the Apple half of it needs the MacBook Air awake.

## 9. JOBS-04 scope decision: `compress()` from a background isolate hangs — engine limitation, not fixable in-package

Executing `05-02-PLAN.md` (Phase 5, background isolates) found that `compress()` issued from
inside `Isolate.run` never resolves, even AFTER calling the new
`CompressVideo.ensureInitializedInBackgroundIsolate(RootIsolateToken)` correctly as the plan
specifies. This is worse than 05-RESEARCH.md's own Pitfall 2 assumed ("MEDIUM confidence,
untested") — the hang reproduces on the plain, correctly-initialised happy path, not only
when initialisation is skipped.

**What was confirmed empirically (not assumed), reading Flutter's own SDK source
(`_background_isolate_binary_messenger_io.dart`) and `adb logcat` during execution:**

1. Progress can never reach a background isolate at all — `BackgroundIsolateBinaryMessenger
   .setMessageHandler` throws `UnsupportedError` unconditionally ("Messages from the host
   platform always go to the root isolate"). This is permanent, documented Flutter engine
   design, not a bug. Fixed in-package: `_ensureFlutterApiRegistered` now catches this and
   continues instead of crashing `compress()` synchronously (committed, `87d1a28`).

2. Separately, and this is the actual blocker: `compress()`'s own platform call
   (`CompressHostApi.startCompress`) never resolves off-root. Native's Media3 `Transformer`
   genuinely runs and completes (logcat shows `Init` then `Release` within ~200-300ms for the
   corpus's cheapest clip), but the Dart-side `await` hangs forever — reproduced 3 times with
   debug instrumentation that isolated the hang to that one call (`getMediaInfo` and
   `estimate`, which use the IDENTICAL outgoing-call mechanism, both succeed instantly
   off-root under the same harness). This matches the shape of the upstream issue
   `flutter/flutter#144342` cited in 05-RESEARCH.md (a null-check exception during a platform
   message response callback, silently reported rather than surfaced — i.e. the pending
   completer is lost and never resolves).

**Why I didn't route around it:** the only mechanism that could relay progress or a result
across the isolate boundary in this situation is a hand-rolled `SendPort`/`ReceivePort`
bridge — exactly what this plan's own threat model and 05-RESEARCH.md's "Don't Hand-Roll"
table prohibit, and for good reason (it's the exact anti-pattern
`BackgroundIsolateBinaryMessenger` exists to replace).

**What shipped anyway (committed, real, tested):** the initialiser, the resilience fix, and
an integration suite (`example/integration_test/jobs_background_test.dart`) proving what DOES
work off-root once initialised — `getMediaInfo`, and by the same code path
`getThumbnail`/`estimate`/`clearCache` — with a `skip: true` case documenting the `compress()`
hang rather than hiding it. Task 2 (CI wiring) and Task 3 (README claims) were NOT executed
since both are premised on `compress()` working from a background isolate.

**Decision needed — how should JOBS-04 be scoped given this?**
- (a) Ship JOBS-04 as "every call except `compress()` itself works from a background isolate"
  — document the limitation plainly and close the incumbent's issue #242 partially.
- (b) File the upstream Flutter engine bug report and wait/track it before closing JOBS-04 at
  all (unknown timeline).
- (c) Investigate further for a narrower in-package explanation I haven't found (I could be
  wrong about (2) being a genuine engine bug — happy to dig further if you want, just flag it).

Not blocking the rest of Phase 5's plans in the sense of needing YOUR action right now to
unstick other work, but `05-03`/`05-04`/`05-05` (foreground service, iOS suspension, phase
sign-off) may reference or build on JOBS-04's shape, so I'm pausing 05-02 as `status: halted`
rather than guessing which of (a)/(b)/(c) you want. See `05-02-SUMMARY.md` for full detail.

**Update 2026-09-27 (resolved by orchestrator-directed fix-and-retry):** the scope question above
is superseded — `compress()` from a background isolate now works. Root cause was narrower than
this entry's original diagnosis: Android's `startCompress` blocked on `CompressVideoFlutterApi
.onProgress`'s acknowledgement before returning, and a background isolate can never send one, but
that block was NOT structurally required — the result can be (and now is) recorded independently
of it. Fixed with a new Pigeon `CompressHostApi.awaitCompressResult(jobId)` async method, backed
by a per-job outcome in `JobRegistry` completed the instant it is known, on both platforms, with
no `SendPort`/`ReceivePort` bridge. Verified on Android with multiple stable emulator runs and
zero regressions to the existing progress/result ordering guarantees. Apple's mirror
implementation is written but not locally compiled (Mac still unreachable) — the pushed CI run's
`apple` job is the pending confirmation before `REQUIREMENTS.md`'s JOBS-04 is marked `Complete`.
See `05-02-SUMMARY.md` for the full diagnosis and two further real bugs found and fixed along the
way. No further action needed from Dan on this item unless CI surfaces something new.
