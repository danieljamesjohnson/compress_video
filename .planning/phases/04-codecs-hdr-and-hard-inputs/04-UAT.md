---
status: testing
phase: 04-codecs-hdr-and-hard-inputs
source: [04-VERIFICATION.md]
started: 2026-09-27T06:31:44Z
updated: 2026-09-27T06:31:44Z
---

## Current Test
number: 1
name: Run doc/HARDWARE_CHECKLIST.md's HEVC-hardware-encode section on a physical Android phone: `flutter test integration_test/hard_inputs_test.dart -d <physical-device-id>` with `VideoCodec.hevc` opt-in, confirm `hevcFallback: false` and `videoCodec: 'hevc'` in the result.
expected: |
  A real ARM/Qualcomm/Exynos hardware HEVC encoder is exercised and reports success (not merely the macOS CI host's Apple Silicon encoder, which is the only hardware-success evidence that exists today).
awaiting: user response

## Tests

### 1. Run doc/HARDWARE_CHECKLIST.md's HEVC-hardware-encode section on a physical Android phone: `flutter test integration_test/hard_inputs_test.dart -d <physical-device-id>` with `VideoCodec.hevc` opt-in, confirm `hevcFallback: false` and `videoCodec: 'hevc'` in the result.
expected: A real ARM/Qualcomm/Exynos hardware HEVC encoder is exercised and reports success (not merely the macOS CI host's Apple Silicon encoder, which is the only hardware-success evidence that exists today).
why_human: No physical Android device is reachable from danserver (QUESTIONS.md #3); the Android emulator's software codec path cannot exercise a hardware encoder at all.
result: [pending]

### 2. Run doc/HARDWARE_CHECKLIST.md's HDR tone-map fidelity section by eye on a physical Android phone and an iPhone, using a real Dolby Vision profile-8 clip and a real Pixel HLG10 clip (not the synthetic corpus fixtures).
expected: The tone-mapped SDR output is visually correct (not washed out, not over/under-exposed) when viewed by a human, and `toneMapped: true` is reported.
why_human: Success criterion 1 names 'a portrait iPhone Dolby Vision clip and a Pixel HLG10 clip' specifically — real camera output, not ffmpeg-synthesized HLG10/PQ10 fixtures. No such real clips exist on danserver (QUESTIONS.md #4), and 'not washed out' is inherently a visual, human judgment even once a real clip exists. The Android emulator additionally cannot tone-map at all with its software GL/decoder (both fallback attempts fail with codes 5001/3003, confirmed live and documented) so Android's `toneMapped: true` claim has never been observed on Android at all — only on the macOS CI host's Apple leg.
result: [pending]

### 3. Run doc/HARDWARE_CHECKLIST.md's keep-HDR section on a physical Android device capable of HDR editing, and confirm HEVC 10-bit HDR output plus `toneMapped: false`.
expected: A physical Android device takes the keep branch and produces genuinely HDR HEVC output, distinct from the macOS-host-only CI evidence that exists today.
why_human: Same physical-device gap as above; the Android emulator cannot take the keep-HDR success branch (confirmed exhausted-chain outcome only).
result: [pending]

## Summary
total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
