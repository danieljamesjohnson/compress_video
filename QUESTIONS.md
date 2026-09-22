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

## 2. pub.dev publisher

No verified publisher exists for your account yet. Before the release phase, either create one (needs a domain you control, e.g. `danjjohnson.com`) or decide to publish under your Google account. Not blocking until the last phase.

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

## 4. Real phone clips for the test corpus

Phase 1 ships an ffmpeg-generated corpus that mirrors phone structure (rotation display matrix, AAC, no-audio, already-small). Real clips are still needed for the rotation/HDR checks that every competitor got wrong. When convenient, get these onto danserver (the feedback drop at http://danserver/drop, or `scp` into `~/CodeProjects/compress-video/corpus/incoming/`):

- an iPhone portrait clip recorded with HDR on (Dolby Vision profile 8), 5-10 s
- a Pixel (or any Android) portrait clip with HDR/HLG10 on, 5-10 s
- any short clip with 5.1 audio if you have one (optional)

Not blocking until Phase 4 (Codecs, HDR and Hard Inputs).

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
