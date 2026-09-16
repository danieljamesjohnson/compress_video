---
status: testing
phase: 02-android-compression-on-media3
source: [02-VERIFICATION.md]
started: 2026-09-16T03:51:30Z
updated: 2026-09-16T03:51:30Z
---

## Current Test

number: 1
name: targetSizeMb / estimate() accuracy on a physical phone's hardware encoder
expected: |
  On a real Android phone, re-run the targetSizeMb and estimate() accuracy cases. Either the hardware encoder holds the designed ±15% and the emulator tolerances (±55% / ±75%) get tightened, or the deviation is intrinsic to Media3 CBR rate control and the dartdoc caveat stays permanent.
awaiting: user response

## Tests

### 1. targetSizeMb / estimate() accuracy on a physical phone's hardware encoder
expected: Hardware encoder result decides whether the ±15% design tolerance is restorable or the caveat is permanent (QUESTIONS.md #3).
result: [pending]

### 2. clearCache() never follows a symlink out of <cacheDir>/compress_video/
expected: A symlink planted inside the cache subdir pointing outside it is skipped by PluginFiles.sweep; the external target survives. (Can be closed by an agent with a symlink integration test.)
result: [pending]

### 3. Non-AAC audio source falls back to an AAC re-encode
expected: Compressing a clip with MP3/Vorbis audio under default AudioOptions yields audioReencoded: true, no crash. (Can be closed by an agent with a new corpus fixture.)
result: [pending]

### 4. Decoder-failure error codes map as documented
expected: A genuine ERROR_CODE_DECODER_INIT_FAILED / DECODING_FORMAT_UNSUPPORTED maps to decoderUnavailable vs unsupportedInput per ErrorMapping.kt. (Needs a fixture with an unsupported codec.)
result: [pending]

### 5. Out-of-space is rejected before encoding and mapped mid-encode
expected: With the destination filesystem near full, the pre-flight StatFs check throws outOfSpace before a Transformer is built; a mid-encode ENOSPC maps to outOfSpace. (Not safe to automate on the shared danserver emulator.)
result: [pending]

### 6. Example app compress screen on a real display
expected: Progress bar advances, result line shows bytes/dimensions/elapsed, cancel returns the button to idle. (Optional; headless emulator run was inconclusive — native splash persisted.)
result: [pending]

## Summary

total: 6
passed: 0
issues: 0
pending: 6
skipped: 0
blocked: 0

## Gaps
