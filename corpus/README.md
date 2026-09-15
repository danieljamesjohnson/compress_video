# Corpus

Three ffmpeg-generated clips that mirror real phone video structurally, plus a machine-derived
`*.expected.json` sidecar per clip. The same sidecar is asserted against by one integration test
file run on both the Android emulator and the iOS simulator, so "media info is correct" is a
single cross-platform assertion instead of an opinion re-derived twice.

Real phone clips (iPhone Dolby Vision, Pixel HLG) are requested from Dan in `QUESTIONS.md` #4 and
join this corpus in Phase 4 — these synthetic clips cover Phase 1's rotation/unit/null bug classes
in the meantime, and the generation script stays committed so they are always reproducible.

## Files

| File | What it is |
|---|---|
| `patch_rotation.py` | Direct `tkhd` display-matrix patcher. Stdlib-only (`struct`). |
| `generate_corpus.sh` | Reproducible ffmpeg generation of the three clips; self-asserts every structural property before declaring success. |
| `verify_corpus.sh` | The single producer of `*.expected.json`. `--write` regenerates the sidecars; default mode diffs derived content against the committed sidecars and fails on any drift. |
| `sync_to_example.sh` | Mirrors clips + sidecars into `example/assets/corpus/`, verified by `sha256sum`. Fails loudly if `example/` doesn't exist yet. |
| `portrait_rot90.mp4` | 1920x1080 coded, H.264 + AAC stereo, ~4s, 90° clockwise `tkhd` display matrix (phone-portrait structure), burnt-in ms timecode, 8-bucket colour-patch schedule for the thumbnail probe. |
| `small_480p.mp4` | 854x480, H.264 + AAC, low bitrate, no display matrix. |
| `noaudio_720p.mp4` | 1280x720, H.264, no audio stream, no display matrix. |
| `*.expected.json` | Ground-truth sidecar per clip, in platform-facing units (see below). |

## Regenerating

Never hand-edit a `.mp4` or a `.expected.json`. To change the corpus:

```bash
bash corpus/generate_corpus.sh      # regenerate the clips
bash corpus/verify_corpus.sh --write  # re-derive the sidecars from the new clips
bash corpus/verify_corpus.sh          # confirm no drift
bash corpus/sync_to_example.sh        # mirror into example/ (once it exists)
```

## Why ffmpeg's `rotate=` metadata trick isn't used

`ffmpeg -metadata:s:v:0 rotate=90` is a verified no-op on the installed ffmpeg 6.1.1-3ubuntu5: it
prints a deprecation notice but leaves the `tkhd` matrix at identity. `patch_rotation.py` writes
the matrix directly (ISO/IEC 14496-12 box format), verified round-trip against `ffprobe`'s
`side_data_list`. See `.planning/phases/01-typed-contract-ci-and-media-info/01-RESEARCH.md` →
"Common Pitfalls" #1/#2 for the full reproduction.

## Rotation sign convention: unsigned clockwise, not ffprobe's signed CCW

`ffprobe` reports the display matrix rotation as **signed, counter-clockwise** — a 90-degree
clockwise phone-portrait rotation shows up as `"rotation": -90` in `side_data_list`. Android's
`METADATA_KEY_ROTATION` and Apple's `preferredTransform`-derived angle are both **unsigned
clockwise degrees**. The sidecar's `crossPlatform.rotationDegrees` records the **platform-facing**
value — `90` for `portrait_rot90.mp4`, not ffprobe's raw `-90` — because that is what every
integration test on every platform must actually assert against. Getting this backwards would
make the whole rotation test trivially green for the wrong reason.

## Displayed dimensions, not coded dimensions

`ffprobe`'s `.streams[].width`/`.height` report the **coded** (pre-rotation) frame size —
`1920x1080` for `portrait_rot90.mp4`, even though every real player shows it upright at
`1080x1920`. `crossPlatform.widthPx`/`heightPx` in the sidecar are the **displayed** dimensions
(coded width/height swapped when `rotationDegrees` is 90 or 270). This is exactly the bug class
`PITFALLS.md` #9 documents the incumbent (`video_compress`) shipping backwards — swapping
width/height for rotation 0/180 instead of 90/270.

## `crossPlatform` vs `tolerant` fields

- **`crossPlatform`** — every platform must report these identically (within
  `durationToleranceMs` for duration, which absorbs one frame of rounding at 30fps): `durationMs`,
  `widthPx`, `heightPx`, `rotationDegrees`, `sizeBytes`, `hasAudio`, `isHdr`, `videoCodec`.
  `videoCodec` is a normalised token (`h264`, `hevc`, `av1`, `vp9`, `unknown` — Android's
  `video/avc` and Apple's `avc1` both normalise to `h264`).
- **`tolerant`** — platforms are allowed to disagree on these, within the documented tolerance:
  `videoBitrateBps` (± `videoBitrateTolerancePct`, 25%) and `frameRateFps` (±
  `frameRateToleranceFps`, 0.5fps). A platform that cannot report a tolerant field at all must
  report `null`, never `0` — `0` would silently look like a real (wrong) measurement.

## Thumbnail probe-patch contract

`portrait_rot90.mp4` carries a flat 200x200 colour patch that changes to a new fully-saturated
colour every 500ms (red, green, blue, yellow, magenta, cyan, white, black, in order). This makes a
thumbnail's moment and orientation both checkable by sampling one pixel region — no OCR, no fuzzy
image comparison.

`thumbnailProbe.positionMs` (1500) is the time to request a thumbnail at. `patchXPx`/`patchYPx`
are the centre of the patch in **displayed** coordinates (the coordinates a rotation-correct
thumbnail generator actually produces — `Bitmap.getScaledFrameAtTime` on Android,
`AVAssetImageGenerator` with `appliesPreferredTrackTransform = true` on Apple). `expectedRgb` is
the colour sampled at that moment; `rgbTolerance` (24) absorbs JPEG encoding loss. A test that
samples the *coded*-frame coordinates instead of the displayed ones will read the wrong patch
entirely — this is the same orientation bug class as the width/height swap above, just for
thumbnails instead of dimensions.

`verify_corpus.sh` asserts the probe actually distinguishes 1000ms from 1500ms (an adjacent
colour bucket) by more than `rgbTolerance` in at least one channel — a probe that can't tell two
buckets apart would pass every implementation, including a broken one.
