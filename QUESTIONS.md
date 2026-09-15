# QUESTIONS — things only Dan can do

## 1. Authorize danserver's SSH key on the MacBook Air (blocks all Apple builds)

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
