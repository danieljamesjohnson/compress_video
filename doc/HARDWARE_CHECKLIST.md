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

## HEVC hardware encode and keep-HDR output (deferred to 04-03)

Neither the Android emulator nor the iOS Simulator has any hardware HEVC encoder
(04-RESEARCH.md Summary — confirmed live by pulling this project's own AVD's
`media_codecs.xml`). CDEC-01/CDEC-03's hardware-success paths need either a physical Android
phone or the macOS CI host's Apple Silicon Media Engine (already exercised by CI once 04-03/04-04
land the HEVC opt-in). This section will be filled in by the plan that implements CDEC-01/03.

## `targetSizeMb` / `estimate()` tolerances on a hardware encoder (QUESTIONS.md #3)

Carried forward from Phase 2 (02-03-SUMMARY.md, 02-07-SUMMARY.md): the emulator's software H.264
encoder's rate control diverges from the documented ±15% design tolerance by a wide margin
(measured 7.9-67.0% across presets). Whether a physical device's hardware encoder holds closer to
the designed tolerance is unproven. Re-run `compress_test.dart`'s `targetSizeMb` cases and
`compress_output_test.dart`'s `estimate()`-accuracy cases on a physical phone once available.

## Dolby Vision profile 8 (QUESTIONS.md #4)

`hdr_dolbyvision_p8.mp4` is a reserved corpus slot (`corpus/README.md`), not a generated file —
ffmpeg cannot author Dolby Vision RPU metadata. This case is real-iPhone-clip-only until Dan
drops one.
