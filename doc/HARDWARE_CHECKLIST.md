# Hardware Checklist

Checks that can only be proven on real hardware — a physical Android phone, a real iPhone (for
Dolby Vision), and (for the parts CI's simulator/emulator can already prove) an Apple Silicon
device. Every item names the exact command to run and the exact result that counts as a pass.
Nothing here is "done" until it has actually been run once on the named hardware and the result
recorded below with a date — this file documents what to check and why, not that it has been
checked, until it has.

## Why this file exists

Two environments this project verifies against every push — the `compress_video_api35` Android
emulator (`google_apis`, x86_64, `swiftshader_indirect` software GL) and the iOS Simulator — have
no hardware video encoder at all, and (confirmed live, Phase 4) the emulator's software HEVC
decoder cannot complete Media3's HDR tone-map pipeline for a genuinely HDR source. CI proves
everything these environments CAN prove; this file is for the rest.

## HDR tone-mapping: goldfish decoder cannot tone-map Main10 on the Android emulator (04-02)

**Status: confirmed limitation, not yet re-tested on physical hardware.**

Confirmed live on `compress_video_api35` (API 35, `swiftshader_indirect` software GL),
2026-09-26, compressing `corpus/hdr_hlg10.mp4` and `corpus/hdr_pq10.mp4` with default options:

- `HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL` (the first attempt) fails with
  `ExportException.errorCode` 5001 (`ERROR_CODE_VIDEO_FRAME_PROCESSING_FAILED`). Logcat traces
  the root cause to `androidx.media3.transformer.DefaultDecoderFactory` throwing
  `IllegalArgumentException: The surface has been released` while configuring the
  `c2.goldfish.hevc.decoder` video decoder — the GL effects pipeline's input `Surface` is
  released before the decoder can write to it, consistent with 04-RESEARCH.md Pitfall 3 (no
  synchronous capability check exists for this path; OpenGL tone-mapping support depends on
  runtime GL extension availability like `GL_EXT_YUV_target`, which a software GL renderer may
  not implement).
- The `HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_MEDIACODEC` retry (API 31+, available on this API-35
  emulator) then fails with code 3003 (`ERROR_CODE_DECODING_FORMAT_UNSUPPORTED`) — the decoder
  rejects the requested tone-mapped output colour-transfer configuration
  (`color-transfer-request=3` in the codec's own `CodecInfo`) outright.
- Both failures are correctly surfaced as a single typed `unsupportedInput` `CompressVideoError`
  naming the exhausted chain and the last numeric code, per CDEC-02's contract ("if neither path
  is available, fail with a typed `unsupportedInput` error rather than emit washed-out video").
  `example/integration_test/hard_inputs_test.dart`'s HDR cases assert exactly this outcome (see
  that file's own extensive comment for the reasoning) and pass on this emulator today.

**What this means:** on this specific software-rendered emulator, HDR tone-mapping is a
*documented environment limitation*, not a code bug — the fallback chain (04-02-PLAN.md task 2)
runs exactly as designed and reports honestly. Whether a physical Android device's hardware HEVC
decoder can complete either tone-map path (most real devices ship a hardware decoder with
`GL_EXT_YUV_target` support, and/or a MediaCodec that actually implements
`color-transfer-request`) is unproven and is this checklist item.

**To verify on a physical Android phone (QUESTIONS.md #3):**

```bash
adb install -r example/build/app/outputs/flutter-apk/app-debug.apk
adb push corpus/hdr_hlg10.mp4 corpus/hdr_pq10.mp4 /sdcard/Download/
# Run the example app's compress flow against each pushed file, OR run the integration suite
# directly against the connected device:
cd example && flutter test integration_test/hard_inputs_test.dart -d <device-id>
```

**Expected result on capable hardware:** the HDR test group's `try` branch executes (not the
`catch` branch) — `result.toneMapped` is `true`, `result.usedOriginal` and `result.transmuxed`
are both `false`, `result.videoCodec` is `h264`, a re-probe of the output reports `isHdr: false`,
and the `_expectHdrFidelity` assertion (saturation, dominance, white-luma) passes for every patch.
If the OpenGL attempt still fails but the device is API 31+, confirm the MediaCodec retry is what
actually succeeds (each attempt is independently observable via the standard Android
`TransformerInternal` log tag).

**When run:** not yet run. Record the device model, Android version, and result here once tested.

## HEVC hardware encode and keep-HDR output

**Status: CI-proven on the macOS host's real Apple Silicon Media Engine (04-04); the physical
Android phone half is still not yet run.**

Neither the Android emulator nor the iOS Simulator has any hardware HEVC encoder
(04-RESEARCH.md Summary — confirmed live by pulling this project's own AVD's
`media_codecs.xml`), so both CI targets always exercise the fallback branch
(`hevcFallback: true`). The macOS CI host (`macos-latest`, Apple Silicon, confirmed `arm64` via
CI's own `uname -m` step) DOES have a genuine hardware HEVC encoder, and CI run 36279264836
(04-04-SUMMARY.md) confirmed it takes the real success branch for both cases in
`hard_inputs_test.dart`: `HEVC_BRANCH=success` for the HEVC opt-in request on
`portrait_hibitrate_1080p60.mp4` (re-probed `videoCodec: hevc`, `hevcFallback: false`), and
`KEEP_HDR_BRANCH=keep` for both HLG and PQ keep-HDR requests (re-probed `isHdr: true`,
`toneMapped: false`, `hevcFallback: false`, HEVC Main10 output with the source's own transfer
function and BT.2020 primaries). **This closes the "has a hardware-capable success path ever
executed" half of CDEC-01/CDEC-03 on a CI runner Dan does not control** — it is real hardware
evidence, not a simulator/emulator fallback, but it is still not a physical phone, and it does not
measure a bitrate or byte count (see `doc/PRESETS.md`'s "HEVC and HDR" section, which stays
explicitly unmeasured for exactly this reason).

**What remains unproven and needs a physical Android phone (QUESTIONS.md #3):**

```bash
adb install -r example/build/app/outputs/flutter-apk/app-debug.apk
adb push corpus/portrait_hibitrate_1080p60.mp4 corpus/hdr_hlg10.mp4 corpus/hdr_pq10.mp4 /sdcard/Download/
cd example && flutter test integration_test/hard_inputs_test.dart -d <device-id>
```

**Expected result on a phone with a hardware HEVC encoder:** the `HEVC opt-in` group's
`HEVC_BRANCH=success` print line appears (not `fallback`), `result.hevcFallback` is `false`, and a
re-probe of the output reports `videoCodec: hevc`. For the keep-HDR group: `KEEP_HDR_BRANCH=keep`
for both HLG and PQ, `result.toneMapped` and `result.hevcFallback` both `false`, and a re-probe
reports `isHdr: true`.

**When run:** not yet run on a physical Android phone. Record the device model, Android version,
and result here once tested.

## `targetSizeMb` / `estimate()` tolerances on a hardware encoder (QUESTIONS.md #3)

**Status: not yet run on a physical Android phone.**

Carried forward from Phase 2 (02-03-SUMMARY.md, 02-07-SUMMARY.md): the emulator's software H.264
encoder's rate control diverges from the documented ±15% design tolerance by a wide margin
(measured 7.9-67.0% across presets, `compress_test.dart`'s own comment documents the emulator's
widened ±35%/±75% tolerances used in place of the ±15% design target). Whether a physical device's
hardware encoder holds closer to the designed tolerance is unproven.

```bash
adb install -r example/build/app/outputs/flutter-apk/app-debug.apk
cd example && flutter test integration_test/compress_test.dart -d <device-id>
flutter test integration_test/compress_output_test.dart -d <device-id>
```

**Expected result on capable hardware:** re-run the `targetSizeMb` 1.0/2.0 MB cases in
`compress_test.dart` and the `estimate()`-accuracy cases in `compress_output_test.dart`; compare
the printed relative-error percentages against this emulator's own documented 7.9-67.0% spread
(`doc/PRESETS.md`'s "Requested vs. delivered bitrate" section) and the iOS Simulator's 2.2-5.8%
spread (`doc/PRESETS.md`'s Apple section) — if hardware holds within the original ±15%/±75%
design tolerance, tighten `CompressOptions.targetSizeMb`'s dartdoc and the test's own tolerance
comment accordingly; if it does not, document the new measured number the same way the emulator
and simulator measurements already are.

**When run:** not yet run on a physical Android phone. Record the device model, Android version,
and the measured relative-error percentages here once tested.

## Dolby Vision profile 8 (QUESTIONS.md #4)

**Status: not yet run — no real Dolby Vision clip exists on danserver.**

`hdr_dolbyvision_p8.mp4` is a reserved corpus slot (`corpus/README.md`), not a generated file —
ffmpeg cannot author Dolby Vision RPU metadata. This case is real-iPhone-clip-only until Dan
drops one. Do not attempt to synthesize it with ffmpeg (`corpus/README.md`'s "Reserved slots").

**Once the real clip exists, drop it in as `corpus/hdr_dolbyvision_p8.mp4`, regenerate the
sidecar, and run:**

```bash
bash corpus/verify_corpus.sh --write && bash corpus/sync_to_example.sh
cd example && flutter test integration_test/hard_inputs_test.dart -d <device-id>
```

**Expected result:** `getMediaInfo` reports `isHdr: true`; a default-options compress reports
`toneMapped: true` and a re-probe of the output shows `isHdr: false`; a `HdrMode.keepHdr` request
either keeps genuine Dolby Vision/HDR10 HEVC on a capable device or falls back to tone-mapped SDR
H.264 reporting both `toneMapped: true` and `hevcFallback: true` — the same dual-outcome contract
`hard_inputs_test.dart`'s synthetic HLG/PQ cases already assert, extended to a real profile-8 file
once one exists. A new test case for this clip belongs in `hard_inputs_test.dart` at that point;
none exists yet because there is nothing to run it against.

**When run:** not yet run — no real Dolby Vision clip exists on danserver yet (QUESTIONS.md #4).
