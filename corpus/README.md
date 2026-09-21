# Corpus

Five ffmpeg-generated clips that mirror real phone video structurally (four healthy, one
deliberately damaged), plus a machine-derived `*.expected.json` sidecar per healthy clip. The
same sidecar is asserted against by one integration test file run on both the Android emulator
and the iOS simulator, so "media info is correct" is a single cross-platform assertion instead
of an opinion re-derived twice.

Real phone clips (iPhone Dolby Vision, Pixel HLG) are requested from Dan in `QUESTIONS.md` #4 and
join this corpus in Phase 4 — these synthetic clips cover Phase 1's rotation/unit/null bug classes
in the meantime, and the generation script stays committed so they are always reproducible.

## Files

| File | What it is |
|---|---|
| `patch_rotation.py` | Direct `tkhd` display-matrix patcher. Stdlib-only (`struct`). |
| `generate_corpus.sh` | Reproducible ffmpeg generation of all five clips; self-asserts every structural property before declaring success. |
| `verify_corpus.sh` | The single producer of `*.expected.json`. `--write` regenerates the sidecars; default mode diffs derived content against the committed sidecars and fails on any drift. |
| `sync_to_example.sh` | Mirrors clips + sidecars into `example/assets/corpus/`, verified by `sha256sum`. Fails loudly if `example/` doesn't exist yet. |
| `portrait_rot90.mp4` | 1920x1080 coded, H.264 + AAC stereo, ~4s, 90° clockwise `tkhd` display matrix (phone-portrait structure), burnt-in ms timecode, 8-bucket colour-patch schedule for the thumbnail probe. |
| `small_480p.mp4` | 854x480, H.264 + AAC, low bitrate, no display matrix. |
| `noaudio_720p.mp4` | 1280x720, H.264, no audio stream, no display matrix. |
| `portrait_hibitrate_1080p60.mp4` | 1920x1080 coded, 60fps, high-entropy (`mandelbrot` source) H.264 at ~8.7Mbps + AAC stereo, ~4s, 90° clockwise `tkhd` display matrix, same colour-patch schedule as `portrait_rot90.mp4` plus a 24px pure-white border. Proves genuine compression, the 30fps frame-rate cap, upright output and no letterboxing all in one fixture (Phase 2). |
| `truncated_mdat.mp4` | 854x480, H.264 + AAC, faststart-encoded then truncated to 60% of its byte length. `moov` (and duration) survive; the media data does not — drives a real platform-codec decode failure (Phase 2). |
| `*.expected.json` | Ground-truth sidecar per healthy clip, in platform-facing units (see below). `truncated_mdat.mp4` has none — see below. |

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

## CI's cross-platform parity gate reuses these same tolerances (01-07)

`tool/check_parity.sh` diffs the ACTUAL `crossPlatform` values the Android emulator and the iOS
simulator each observed for every clip (not just "both ran the same test file"). It applies
exactly the tolerances documented above — every `crossPlatform` field except `durationMs` must be
byte-identical between platforms; `durationMs` may differ by up to that clip's own sidecar
`durationToleranceMs`; the thumbnail's sampled patch RGB may differ per channel by up to
`thumbnailProbe.rgbTolerance` — read live from the sidecar files, never hardcoded in the script.

**Observed real deltas (2026-09-21, CI run 35624754433, commit 06ec7b6):** `small_480p`'s
`durationMs` came back `3026` on the Android emulator and `2992` on the iOS simulator — a 34ms
difference, exactly one `durationToleranceMs` bucket at 30fps, i.e. the two platforms disagree by
about one frame on this clip's rounded duration. Against this clip's own ffprobe-derived ground
truth (`durationMs: 3000`), Apple's `2992` is 8ms off and Android's `3026` is 26ms off — Apple is
closer to ground truth here, though both are within the clip's own `durationToleranceMs` (34ms)
and neither fails its OWN platform's `_expectCrossPlatformMatches` assertion. The `portrait_rot90`
thumbnail's sampled patch came back `[255, 255, 0]` (pure yellow) on Android and `[255, 242, 0]`
on iOS — a 13-point green delta from JPEG re-encoding, well inside `rgbTolerance` (24). Both are
legitimate platform differences the tolerances above exist to absorb, not bugs in either
platform's `getMediaInfo`/`getThumbnail` implementation. `small_480p`'s duration delta (Android
further from ffprobe truth than Apple) is flagged for Phase 3 (which owns CORE-07 exact
cross-platform parity) to re-examine once the Apple compression engine lands, rather than fixed
here.

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

`thumbnailProbe` fields: `positionMs` (time to request the thumbnail at), `patchXPx`/`patchYPx`
(displayed-coordinate centre of the colour patch), `expectedRgb` (the sampled colour at that
moment), `rgbTolerance` (JPEG-loss allowance). Present only on the two clips carrying the colour
patch, `portrait_rot90.mp4` and `portrait_hibitrate_1080p60.mp4`.

## Edge probe contract (`edgeProbe`)

`portrait_hibitrate_1080p60.mp4` alone also carries `edgeProbe`, a small self-checking block that
makes "no letterboxing" checkable the same way `thumbnailProbe` makes "correct orientation"
checkable: `borderPx` (24, the painted border's coded thickness), `insetPx` (4, how far in from
each displayed edge the sample points sit — always inside the border regardless of rotation),
`expectedRgb` (the sampled near-white colour), `rgbTolerance` (48, wider than the thumbnail
probe's because border sampling averages a coarser area near a hard edge). `verify_corpus.sh`
samples all four edge midpoints (top, bottom, left, right, in displayed coordinates) and fails
naming the clip if any of the four disagree with each other beyond `rgbTolerance`, or if the
sampled colour cannot be told apart from pure black by more than `rgbTolerance` in any channel —
a probe that cannot distinguish the border from letterbox padding would pass a broken
implementation just as easily as a correct one.

## Why `portrait_hibitrate_1080p60.mp4` exists

Every Phase 1 corpus clip was measured live and found far below every preset bitrate Phase 2
defines: `portrait_rot90.mp4` is ~193 kbps for a 1080x1920 displayed frame, `small_480p.mp4` is a
hardcoded 300 kbps, `noaudio_720p.mp4` is ~76 kbps — and the lowest Phase 2 preset (p360) starts
at 800 kbps. Run a "preset shrinks the file" test against those clips alone and it can only ever
hit the never-larger (`usedOriginal: true`) path, never the real encode path — the opposite of
what the test claims to prove. They are also all 30fps, so a frame-rate cap would be silently
untested.

`portrait_hibitrate_1080p60.mp4` fixes both at once: a high-entropy `mandelbrot` lavfi source
(the encoder can't cheat the bitrate on a static or low-detail image) encoded at 60fps and a
target ~8 Mbps — its measured source bitrate lands around 8.7 Mbps, strictly above every preset
bitrate this phase defines, so a preset encode of it can only get smaller by genuinely
re-encoding. It carries the same 90° clockwise `tkhd` matrix and colour-patch schedule as
`portrait_rot90.mp4`, so the existing rotation/thumbnail-probe contract applies to it unchanged.

## White-border edge probe (no-letterbox check)

`portrait_hibitrate_1080p60.mp4` is painted with a solid pure-white 24px border around the whole
coded frame, drawn after the colour patch so nothing overwrites it. `verify_corpus.sh` derives an
`edgeProbe` sidecar block by sampling four points, each inset 4px from the midpoint of one
displayed edge, and asserts all four agree with each other and are distinguishable from black by
more than `rgbTolerance`. A rotation-correct, non-letterboxed output should sample that same
near-white colour at all four edge midpoints after a compress pass. A broken implementation that
pads the output with black bars (e.g. mismatched aspect ratio handling, or a "safe area" crop
that misses the true frame edges) would instead sample black or a mix of black and border colour
at one or more of those points — which is exactly what `edgeProbe.rgbTolerance` is tight enough
to catch.

## `truncated_mdat.mp4` has no sidecar, on purpose

`truncated_mdat.mp4` is deliberately structurally damaged (faststart-encoded, then truncated to
60% of its byte length) so that its `moov` atom survives — ffprobe still reports a video stream
and a duration for it — but its media data does not, so a decode of it reaches the platform codec
and fails there. It is never fed to a "does the output match ground truth" sidecar assertion;
`verify_corpus.sh` only asserts it still probes as a video file with a readable duration. Do not
add a `.expected.json` for it — a sidecar implies "this clip's ground truth is derivable",
which is exactly the property this fixture does not have.
