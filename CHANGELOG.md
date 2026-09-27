## Unreleased

* **Codecs, HDR and hard inputs (Phase 4)** — HEVC is now an opt-in (`VideoCodec.hevc`), used
  only when the device has a hardware HEVC encoder and falling back to H.264 with
  `hevcFallback: true` reported otherwise, on both Android (`CodecCapabilities`/`EncoderUtil`)
  and Apple (`CodecCapabilities`/`VTCopyVideoEncoderList`). HDR input (Dolby Vision profile 8,
  HLG, HDR10) is tone-mapped to SDR by default (`toneMapped: true`), with an `HdrMode.keepHdr`
  opt-in that outputs HEVC Main10 HDR (HLG or PQ transfer, BT.2020 primaries) on a capable device
  and falls back to tone-mapped SDR, reported via both flags, on one that isn't. Sources with 5.1
  audio, PCM/uncompressed audio, or no audio track at all compress successfully by downmixing or
  re-encoding to 2-channel AAC (`audioReencoded: true`) rather than failing. A committed corpus of
  HDR, unusual-audio and 4K60 clips runs through `example/integration_test/hard_inputs_test.dart`
  on the Android emulator, the iOS simulator and the macOS host in CI, with cross-platform
  compression parity records for every case proven identical across all three; the macOS CI
  runner's real Apple Silicon Media Engine is the first place this project's own CI has proven the
  HEVC-success and keep-HDR-success paths. `doc/HARDWARE_CHECKLIST.md` documents what only a
  physical Android phone and a real Dolby Vision clip can still prove.
* **Apple compression engine** — `AVAssetReader`/`AVAssetWriter` on iOS (13+) and macOS (11+),
  sharing one Swift core with the media-info/thumbnail code from the initial release:
  presets and explicit targets (max long side, bitrate, target file size), never-larger,
  transmux fast path, frame-rate cap, audio passthrough/re-encode/strip, per-job progress and
  cancel, typed errors, and the pre-flight `estimate()` — the same observable behaviour Android
  already had, proven by the same integration-test suites running unmodified on the iOS
  simulator and the macOS host in CI.
* **Trim on all three platforms** — `trimStartMs`/`trimEndMs`, honoured within one output frame
  on Android, iOS and macOS alike.
* **Both install paths on Apple** — the package installs through CocoaPods and through Swift
  Package Manager on iOS and macOS from the same shared `darwin/` source tree, both proven by CI
  builds of the example app.
* **A real example app** — pick a video, choose options, compress with live progress and cancel,
  see a result card (bytes saved, dimensions, codec, transmux/never-larger/re-encode badges,
  elapsed time), and play the output back — on Android, iOS and macOS.
* **Cross-platform parity gate widened to compression** — the same `PARITY_JSON` mechanism that
  already compared media-info and thumbnail values now diffs compression results (dimensions,
  codecs, the three shortcut flags, duration) between Android, iOS and macOS in CI, with output
  bytes and elapsed time deliberately excluded as platform-dependent by design (see the README's
  "What 'the same on every platform' means" section and `doc/PRESETS.md`'s measured tables).

## 0.1.0

Initial unreleased development version. Not yet published to pub.dev.

* Plugin scaffold for Android, iOS and macOS with a shared `darwin/` Apple source tree.
* Typed error taxonomy (`CompressVideoException`, `CompressVideoErrorReason`).
* Typed Pigeon contract for every Dart-native call; no hand-written channel map anywhere in the
  package, enforced by a dedicated CI check.
* `CompressVideo.getMediaInfo(path)` — duration, displayed (rotation-corrected) dimensions,
  rotation, size, codec, bitrate, frame rate, audio presence and HDR-ness, on Android
  (`MediaMetadataRetriever`) and Apple (`AVFoundation`).
* `CompressVideo.getThumbnail` / `getThumbnailFile` — a rotation-correct poster frame as JPEG
  bytes or written to a file, at any millisecond, with quality and max-dimension controls that
  never upscale.
* CI on a Linux runner (Android) and a macOS runner (iOS + macOS), path-gated.
* A cross-platform parity gate (`tool/check_parity.sh`): a dedicated CI job diffs the
  `crossPlatform` media-info and thumbnail values the Android emulator and the iOS simulator
  each actually observed, so "the two platforms agree" is a diff, not an inference from running
  the same test file on both.
* CI is green on both runners plus the parity gate (run 35631865999).
