# Corpus

Eleven ffmpeg-generated clips that mirror real phone video structurally (ten healthy, one
deliberately damaged), plus a machine-derived `*.expected.json` sidecar per healthy clip. The
same sidecar is asserted against by one integration test file run on both the Android emulator
and the iOS simulator, so "media info is correct" is a single cross-platform assertion instead
of an opinion re-derived twice.

Real phone clips (iPhone Dolby Vision, Pixel HLG) are requested from Dan in `QUESTIONS.md` #4 and
join this corpus once he provides them — these synthetic clips cover Phase 1's rotation/unit/null
bug classes and Phase 4's codec/HDR/hard-input bug classes in the meantime, and the generation
script stays committed so they are always reproducible. See "Reserved slots" below.

## Files

| File | What it is |
|---|---|
| `patch_rotation.py` | Direct `tkhd` display-matrix patcher. Stdlib-only (`struct`). |
| `generate_corpus.sh` | Reproducible ffmpeg generation of all ten healthy clips; self-asserts every structural property before declaring success. |
| `verify_corpus.sh` | The single producer of `*.expected.json`. `--write` regenerates the sidecars; default mode diffs derived content against the committed sidecars and fails on any drift. |
| `sync_to_example.sh` | Mirrors clips + sidecars into `example/assets/corpus/`, verified by `sha256sum`. Fails loudly if `example/` doesn't exist yet. |
| `portrait_rot90.mp4` | 1920x1080 coded, H.264 + AAC stereo, ~4s, 90° clockwise `tkhd` display matrix (phone-portrait structure), burnt-in ms timecode, 8-bucket colour-patch schedule for the thumbnail probe. |
| `small_480p.mp4` | 854x480, H.264 + AAC, low bitrate, no display matrix. |
| `noaudio_720p.mp4` | 1280x720, H.264, no audio stream, no display matrix. |
| `portrait_hibitrate_1080p60.mp4` | 1920x1080 coded, 60fps, high-entropy (`mandelbrot` source) H.264 at ~8.7Mbps + AAC stereo, ~4s, 90° clockwise `tkhd` display matrix, same colour-patch schedule as `portrait_rot90.mp4` plus a 24px pure-white border. Proves genuine compression, the 30fps frame-rate cap, upright output and no letterboxing all in one fixture (Phase 2). |
| `truncated_mdat.mp4` | 854x480, H.264 + AAC, faststart-encoded then truncated to 60% of its byte length. `moov` (and duration) survive; the media data does not — drives a real platform-codec decode failure (Phase 2). |
| `trim_source_10s.mp4` | 1280x720 coded, 30fps, H.264 + AAC stereo (128kbps/48kHz), no display matrix, ~1Mbps, 10s, burnt-in ms timecode, explicit 30-frame GOP. The only clip long enough to express a 2000ms→7000ms trim (Phase 3, D-13) — see "Why `trim_source_10s.mp4` exists" below. |
| `hdr_hlg10.mp4` | 1280x720, 2s, HEVC Main10 (`yuv420p10le`), HLG (`arib-std-b67`) transfer, BT.2020 primaries, no audio, four 160x160 red/green/blue/white colour patches at y=40/x=40,240,440,640. Synthetic stand-in for a real HLG10 phone clip until Dan drops one (Phase 4, D-01). |
| `hdr_pq10.mp4` | Same geometry and colour patches as `hdr_hlg10.mp4`, but PQ/SMPTE-2084 (`smpte2084`) transfer with mastering-display and max-CLL side data (Phase 4, D-01). |
| `pcm_audio_480p.mov` | 854x480, H.264 + LPCM (`pcm_s16le`) stereo audio, muxed as `.mov` (not `.mp4`) — ffmpeg's ISO-MP4 PCM sample entry (`ipcm` fourcc) isn't recognized by Android's `MediaExtractor` as an audio track at all (confirmed live, 04-RESEARCH.md Pitfall 5); `.mov` gets the classic QuickTime `sowt` fourcc instead, same codec (Phase 4, D-10). |
| `surround51_480p.mp4` | 854x480, H.264 + 6-channel (5.1) AAC audio at 384kbps, built with ffmpeg's `pan=5.1` filter graph (Phase 4, D-09). |
| `uhd_4k60.mp4` | 3840x2160 at 60fps, 2s, no audio, high-entropy (`mandelbrot` source) H.264 capped to a few MB (Phase 4, D-12). |
| `*.expected.json` | Ground-truth sidecar per healthy clip, in platform-facing units (see below). `truncated_mdat.mp4` has none — see below. `trim_source_10s.expected.json` additionally carries a `trim` block; `hdr_hlg10.expected.json`/`hdr_pq10.expected.json` additionally carry `hdr`/`hdrProbe` blocks; `pcm_audio_480p.expected.json`/`surround51_480p.expected.json` additionally carry an `audio` block (see "New Phase 4 sidecar blocks" below). |

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
platform's `getMediaInfo`/`getThumbnail` implementation.

### `small_480p`'s duration delta, resolved (D-17, 03-07-PLAN.md task 3)

The 01-07 finding above (Android `3026`, Apple `2992`, both against an `ffprobe`-reported
`durationMs: 3000`) is re-examined here with the Apple compression engine landed, by reading the
clip's own container boxes directly rather than trusting any one tool's summary.

**Direct box inspection on danserver (2026-09-25), `corpus/small_480p.mp4`:**

- `moov/mvhd` (the movie header — the container's own single, authoritative statement of the
  presented duration): `timescale=1000`, `duration=3000` → **exactly 3.000s**.
- Both tracks carry an `edts/elst` (edit list) with `entry_count=1`, `segment_duration=3000` (in
  the `mvhd`'s 1000-unit movie timescale, i.e. 3.000s) and `media_time=1024` (a media-timescale
  offset — 1024 samples of AAC encoder priming on the audio track, and the same raw `1024` value,
  differently scaled by that track's own `15360` timescale, on the video track). An edit list
  this precise is deliberate authoring, not accidental: whatever encoder produced this fixture
  wrote an explicit instruction that the PRESENTED duration is 3000ms, distinct from either
  track's raw, un-edited media duration.
- `ffprobe -show_format` (which is edit-list-aware in the ffmpeg version installed on danserver)
  reports `duration=3.000000` for the container and for both streams individually — agreeing
  exactly with the `mvhd`/`elst` reading above, not coincidentally: `ffprobe` applies the same
  edit list this inspection read by hand.

**Conclusion: the container's actual, intended duration is 3000ms**, established two independent
ways (raw `mvhd`/`elst` box values, and an edit-list-aware `ffprobe` read) that agree exactly.
Neither platform's compression-engine-reported `durationMs` (Android `3026`, Apple `2992`) matches
this exactly, but both are close: Android is 26ms off, Apple is 8ms off, and BOTH sit inside this
clip's own `durationToleranceMs` (34ms, one frame at 30fps) — this is not a case of one platform
"demonstrably misreading" the file (which would justify a code fix) so much as each platform's
own duration-computation path (Android's `MediaMetadataRetriever`, Apple's re-probe via `Probe`
reading `AVAsset.duration`) landing at a slightly different rounding of the same edit-list-trimmed
timeline — Apple's path evidently honours the edit list more precisely than Android's, consistent
with the original 01-07 observation that Apple was already closer to ffprobe's ground truth.

**Action taken: none to either platform's reading.** Per this plan's own instruction, a platform
is only "fixed" to match the other when one is demonstrably wrong; here neither is wrong by more
than a fraction of a frame, and the sidecar's existing `durationToleranceMs` contract already
absorbs the full observed spread. `small_480p`'s duration delta is treated as fully resolved: the
ground-truth value is documented above, both platforms' deviations from it are within contract,
and no cross-platform parity gate change follows from it.

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

## Why `trim_source_10s.mp4` exists

Every other clip in this corpus is 3-4 seconds long (`portrait_rot90.mp4`/`portrait_hibitrate_1080p60.mp4`
~4s, `small_480p.mp4`/`noaudio_720p.mp4`/`truncated_mdat.mp4` 2-3s). Phase 3 (Apple compression
parity) needs to prove an exact 2000ms→7000ms trim on all three platforms, and a 5-second output
range cannot be carved out of a clip that is itself only 3-4 seconds long. `trim_source_10s.mp4`
is a dedicated 10-second, 30fps, 1280x720 H.264 + AAC clip with a 30-frame (exactly one second)
GOP — stated explicitly here, and in the generator, rather than left as an ffmpeg default, because
it is the keyframe structure a trim's `AVAssetReader.timeRange` / Media3 `ClippingConfiguration`
has to seek within. It carries the same burnt-in millisecond timecode style as the portrait clips
so a trimmed output's first frame is checkable by eye, but no colour-patch schedule and no
rotation matrix — this fixture proves duration exactness, not orientation or thumbnails, which
the existing clips already cover.

## The `trim` sidecar block

`trim_source_10s.expected.json` alone carries a fourth top-level block, `trim`, on top of the
standard `crossPlatform`/`tolerant` blocks every healthy clip gets: `startMs` (2000), `endMs`
(7000), `expectedDurationMs` (`endMs - startMs`, derived rather than a second literal), and
`toleranceMs` (one frame at the clip's own measured frame rate, rounded UP to the next whole
millisecond — `34` at this clip's 30fps, matching the fixed 34ms `durationToleranceMs` convention
every other 30fps clip in this corpus already carries). Every trim assertion in Phase 3 reads
these four values from the sidecar; none of them is ever hardcoded in a test. `verify_corpus.sh`
also refuses to derive this block if `endMs` is not strictly greater than `startMs`, or if `endMs`
lands within 500ms of the clip's own measured duration — a trim range that runs off (or nearly
off) the end of the source would make the duration assertion prove nothing.

## The parity gate widens to compression results (03-08, D-16)

`media_info_test.dart`/`thumbnail_test.dart` are not the only suites `tool/check_parity.sh`
diffs. `compress_test.dart`, `compress_audio_test.dart`, `compress_jobs_test.dart` and
`compress_output_test.dart` each accumulate their own `_compressionParity` records and print one
`PARITY_JSON {"compression": {...}}` line in their own `tearDownAll`. Because a compression CASE
is not the same thing as a corpus CLIP, these records do not look their tolerance up from a
`$clip.expected.json` sidecar by name; each record instead carries its own `durationToleranceMs`
directly (the test itself already reads that value from whichever sidecar the case's underlying
clip has, exactly as every other duration assertion in this repo does). `tool/check_parity.sh`
merges every suite's own `compression` object into one combined case-name → record map (`jq`'s
`*` operator does this as a deep merge, not `+`'s shallow one), requires the same case names on
every platform (a case present on only one is a FATAL, never a silent skip — T-03-35), and then
applies:

- **Exact fields:** `widthPx`, `heightPx`, `videoCodec`, `audioCodec`, `transmuxed`,
  `usedOriginal`, `audioReencoded`, `channels`, `reason`, `durationToleranceMs`, `wouldTransmux`,
  `wouldUseOriginal` — every one of these is either a discrete flag/enum/string or itself a
  shared, identically-derived constant, so no platform difference is legitimate here.
- **`durationMs`:** tolerance-based, against the record's own embedded `durationToleranceMs`
  (not a corpus lookup).
- **`outputBytes`:** intentionally NOT exact. The two engines legitimately produce different byte
  counts by design (different encoders, different rate control) — this field is compared with a
  documented **±50% envelope** (the smaller value must be at least half the larger): a tenfold
  regression still fails, a legitimate encoder difference does not.
- **`elapsedMs`:** recorded for the log only. Never compared at all — wall-clock time depends
  entirely on hardware (a software simulator encoder versus a real Video Toolbox chip versus an
  emulator's software codec), which is not a parity question this gate can meaningfully answer.

`tool/check_parity_test.sh` proves this in both directions with hand-written fixtures for every
new field kind, including one deliberately flipped `transmuxed` flag demonstrating the gate
actually catches a real divergence (T-03-36), before any of it is trusted against a real CI
artifact.

### `videoBitrateBps` is deliberately NOT a gated field

`doc/PRESETS.md`'s Apple section measured a real, expected cross-platform divergence in the
*opposite direction* from Android's own measured divergence: Android's emulator software encoder
undershoots a preset's nominal bitrate target (down to ~71% at `p1080`), while both Apple devices
(iOS Simulator and the macOS host) *overshoot* it (103–110%). Both are legitimate, measured
encoder-delivery characteristics, not a `SizeGuard` formula bug (`SizeGuardTest.kt`'s Swift twin
proves the formula itself is exact and platform-independent on both sides). This plan does not
add a `videoBitrateBps` field to the compression `PARITY_JSON` schema at all: a tolerance wide
enough to span roughly a 30-40 percentage-point spread in both directions would be too loose to
catch a real regression in either direction, and the measured numbers already live in
`doc/PRESETS.md`, which is the right place for a MEASURED comparison table, not a pass/fail gate.
If a future phase adds this field, it must span both directions (Android's undershoot AND
Apple's overshoot), per `doc/PRESETS.md`'s own flagged note.

### The `truncated_mdat.mp4` error-reason divergence is deliberately NOT gated (arbitration)

03-06 recorded a real, measured cross-platform difference for the one damaged-file fixture in
this corpus: compressing `truncated_mdat.mp4` fails with reason `io` (platform code 2000, "Asset
loader error") on the Android emulator, and with reason `unsupportedInput` (platform code
-11880, "Invalid sample cursor") on Apple (03-06-SUMMARY.md), and asked this plan to arbitrate
whether the parity contract should force one bucket or document the difference.

**Decision: document the difference; do not force agreement.** Both mappings are independently
correct, deliberate readings of a genuinely different native diagnostic for the same damaged
file — Android's Media3 surfaces a generic asset-loader I/O failure, while AVFoundation's more
specific "invalid sample cursor" is the correctly-verified mapping `ErrorMapping.swift` uses
(matched by raw `AVError.Code` value, not a guessed case name — 03-06-SUMMARY.md). Neither
platform is "wrong": forcing them to agree would mean either re-mapping Android's `io` result to
`unsupportedInput` on a fixture that genuinely IS a low-level I/O read failure there, or
re-mapping Apple's more specific diagnostic down to a vaguer `io` bucket — both would trade a
real, verified per-platform mapping for a false cross-platform agreement. `compress_jobs_test.dart`
therefore intentionally never emits a `PARITY_JSON` record for the `truncated_mdat.mp4` case at
all (see that file's own header comment); only the two error-reason cases this project's own
tests ALREADY assert are identical on every platform (`fileNotFound` for a missing path,
`unsupportedInput` for a zero-byte file) are recorded and gated. This mirrors `small_480p`'s
duration-delta resolution above: a platform is only "fixed" to match the other when one is
demonstrably wrong, and here neither is.

## New Phase 4 sidecar blocks

`verify_corpus.sh`'s `derive_sidecar` scopes each of these to a named clip list
(`HDR_CLIPS`/`AUDIO_PROBE_CLIPS`), so the seven pre-existing sidecars stay byte-identical.

### `hdr` and `hdrProbe` (HDR_CLIPS: `hdr_hlg10.mp4`, `hdr_pq10.mp4`)

`hdr` carries `colorTransfer`, `colorPrimaries` and `bitDepth`, read directly from ffprobe — the
same facts `crossPlatform.isHdr` is derived from, kept alongside it for a later plan's
diagnostics.

`hdrProbe` carries `patches` (an array of `{xPx, yPx, dominantChannel}` in DISPLAYED coordinates
— neither HDR clip carries a rotation matrix, so displayed coordinates equal coded coordinates),
plus `minSaturation`, `minWhiteLuma` and `dominanceMargin`. These are documented threshold
constants, **not** an expected RGB triple: ffmpeg cannot author a reference tone-map (a naive
ffmpeg decode of an HLG/PQ stream produces exactly the washed-out values this phase exists to
prevent), so recording an ffmpeg-sampled colour as "the answer" would encode the bug as the
contract. A later plan samples the REAL tone-mapped output from a real platform compression and
checks it against these thresholds instead.

**What the floors mean (04-02):** `minSaturation` is `(max channel - min channel) / max channel`,
expressed on a 0-255 scale (not 0-1 and not a percentage) — a correctly-saturated primary-colour
patch should read comfortably above this floor; a washed-out passthrough reads near 0.
`dominanceMargin` is the minimum raw channel-value gap (0-255) the patch's own painted dominant
channel must hold over each of the other two channels — this is what actually distinguishes "a
red patch" from "a grey patch with a faint red tint." `minWhiteLuma` is the minimum value the
white patch's darkest channel may read — proving the patch is bright rather than merely
"not-colourful."

**Not yet exercised against a real successful tone-map.** `example/integration_test/
hard_inputs_test.dart`'s `_expectHdrFidelity` helper (04-02 task 2) implements exactly this
assertion and is wired into both HDR clips' test cases, but on the `compress_video_api35`
emulator the tone-map pipeline itself fails on BOTH the OpenGL and MediaCodec paths (see
`doc/HARDWARE_CHECKLIST.md`'s HDR section) — a confirmed environment limitation, not a code bug.
The fidelity assertion has therefore never run against a real tone-mapped file; these three
constants (`40`, `120`, `20`, unchanged from 04-01) remain unvalidated starting points. **To
re-derive them once real tone-mapped output exists** (a physical Android phone, or a future
emulator/OS update that makes the tone-map pipeline work here): compress `hdr_hlg10.mp4` with
default options, sample the four patch coordinates from the produced file's own thumbnail, and
set each floor comfortably below the measured value (not equal to it — these are floors meant to
catch a regression, not pin an exact measurement).

### `audio` (AUDIO_PROBE_CLIPS: `pcm_audio_480p.mov`, `surround51_480p.mp4`)

Carries `codec` (ffprobe's raw `codec_name`, unnormalized — there is no audio entry in
`normalize_codec`, and this block is about what the source really is) and `channels`. Scoped to
these two clips because they are the ones whose whole point is an unusual audio codec/channel
count; every other clip's audio is already covered by `crossPlatform.hasAudio`.

## Reserved slots

`hdr_dolbyvision_p8.mp4` (Dolby Vision profile 8) is a **reserved name, not a generated file**.
ffmpeg cannot author Dolby Vision RPU metadata, so this fixture can only come from a real Dolby
Vision-encoding device (an iPhone). It is requested from Dan in `QUESTIONS.md` #4 and, until it
exists, lives as a real-device-only case in `doc/HARDWARE_CHECKLIST.md`. Do not attempt to
synthesize it with ffmpeg — a fixture claiming to be Dolby Vision without a genuine RPU would
make the DV-specific test pass for the wrong reason.
