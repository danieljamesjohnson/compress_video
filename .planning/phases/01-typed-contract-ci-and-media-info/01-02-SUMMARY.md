---
phase: 01-typed-contract-ci-and-media-info
plan: 02
subsystem: testing
tags: [ffmpeg, ffprobe, mp4, corpus, fixtures, media-info]

# Dependency graph
requires: []
provides:
  - Three ffmpeg-generated corpus clips (portrait_rot90.mp4, small_480p.mp4, noaudio_720p.mp4) mirroring real phone video structurally, committed directly (no LFS)
  - A stdlib-only tkhd display-matrix patcher (corpus/patch_rotation.py) since ffmpeg's `-metadata:s:v:0 rotate=` is a verified no-op on the installed ffmpeg 6.1.1
  - A deterministic, byte-reproducible corpus generator (corpus/generate_corpus.sh) that self-asserts every structural property before declaring success
  - Ground-truth `*.expected.json` sidecars in platform-facing units (unsigned-clockwise rotation, displayed dimensions, normalised codec tokens, crossPlatform/tolerant field split) plus a thumbnail probe-patch contract, all produced only by corpus/verify_corpus.sh (drift-gated)
  - corpus/sync_to_example.sh, ready to mirror clips+sidecars into example/assets/corpus/ once the plugin scaffold exists
  - corpus/README.md documenting every convention the later integration tests rely on
affects: [01-03, 01-04, 01-05, 01-06, 01-07]

# Actuals (#2632)
actuals:
  tokens: 7000
  tasks: 2
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Direct ISO/IEC 14496-12 tkhd-matrix byte patch (Python, stdlib struct only) in place of ffmpeg's broken rotate= metadata shortcut"
    - "verify_corpus.sh as single producer of sidecar ground truth, drift-gated against the committed clips — sidecars are never hand-edited"
    - "-threads 1 -x264-params threads=1:sliced_threads=0 on every libx264 encode, required for byte-reproducible corpus generation (libx264's default multi-threaded rate control is not deterministic)"

key-files:
  created:
    - corpus/patch_rotation.py
    - corpus/generate_corpus.sh
    - corpus/verify_corpus.sh
    - corpus/sync_to_example.sh
    - corpus/README.md
    - corpus/portrait_rot90.mp4
    - corpus/small_480p.mp4
    - corpus/noaudio_720p.mp4
    - corpus/portrait_rot90.expected.json
    - corpus/small_480p.expected.json
    - corpus/noaudio_720p.expected.json
  modified: []

key-decisions:
  - "Derived the thumbnail probe-patch's displayed coordinates (920,1700) analytically from the tkhd matrix's rotation transform (x'=codedHeight-y, y'=x for 90deg CW), then confirmed empirically by sampling the actual decoded pixel at both 1000ms and 1500ms — matches the plan's 'derive empirically' instruction for the RGB values while still needing the coordinate transform math to know where to sample."
  - "Added -threads 1 -x264-params threads=1:sliced_threads=0 to every libx264 invocation in generate_corpus.sh after discovering re-runs produced non-identical bytes for the bitrate-targeted clip — required to satisfy the plan's must-have 'generate_corpus.sh is reproducible' truth."

patterns-established:
  - "corpus/verify_corpus.sh --write is the only way to (re)generate a sidecar; default mode is a pure drift gate. Never hand-edit *.expected.json."

requirements-completed: [INFO-01, INFO-02]

coverage:
  - id: D1
    description: "Three corpus clips generated with correct structural properties (portrait clip has a genuine 90deg CW tkhd display matrix at coded 1920x1080; small clip has H.264+AAC and no matrix; no-audio clip has zero audio streams), each under the 1.5MB cap, and the generator is byte-reproducible on re-run"
    requirement: "INFO-01"
    verification:
      - kind: other
        ref: "bash corpus/generate_corpus.sh (self-asserts rotation, coded dims, stream counts, codecs, size cap; exits non-zero naming the clip on any failure)"
        status: pass
      - kind: other
        ref: "two consecutive generate_corpus.sh runs produce sha256-identical corpus/*.mp4"
        status: pass
      - kind: other
        ref: "python3 corpus/patch_rotation.py <path-with-no-tkhd> <h> <deg> exits 1 with 'tkhd box not found'"
        status: pass
    human_judgment: false
  - id: D2
    description: "Ground-truth sidecars in platform-facing units (unsigned clockwise rotationDegrees, displayed widthPx/heightPx, normalised videoCodec, crossPlatform vs tolerant split, thumbnail probe-patch geometry+colour), produced only by a drift-gated verifier"
    requirement: "INFO-02"
    verification:
      - kind: other
        ref: "bash corpus/verify_corpus.sh exits 0 against committed clips+sidecars; jq assertions confirm rotationDegrees=90, widthPx=1080, heightPx=1920, hasAudio/videoCodec/isHdr values, thumbnailProbe.expectedRgb length 3 and positionMs=1500, tolerant block present"
        status: pass
      - kind: other
        ref: "hand-tampering a committed sidecar value (widthPx and separately rotationDegrees) makes verify_corpus.sh exit 1 with a diff naming the field; restoring makes it exit 0 again"
        status: pass
    human_judgment: false
  - id: D3
    description: "sync_to_example.sh fails loudly (non-zero exit, message naming the missing directory) while example/ does not exist, and mirrors sidecars alongside clips once it does"
    verification:
      - kind: other
        ref: "bash corpus/sync_to_example.sh (example/ absent) -> exit 1, stderr 'example/ not found — run this after the plugin scaffold exists'"
        status: pass
      - kind: other
        ref: "grep -c 'expected.json' corpus/sync_to_example.sh -> 1"
        status: pass
    human_judgment: false

# Metrics
duration: 25min
completed: 2026-09-15
status: complete
---

# Phase 1 Plan 02: Corpus Clips, Ground-Truth Sidecars and Drift Verifier Summary

**Three ffmpeg-generated, byte-reproducible corpus clips (portrait rotation via a direct tkhd-matrix patch, small low-bitrate, no-audio) plus drift-gated `*.expected.json` sidecars encoding unsigned-clockwise rotation, displayed dimensions and a thumbnail colour-patch probe.**

## Performance

- **Duration:** 25 min
- **Started:** 2026-09-15T14:45:00Z (approx.)
- **Completed:** 2026-09-15T14:52:02Z
- **Tasks:** 2 completed
- **Files modified:** 11 created (3 scripts, 1 README, 3 .mp4 clips, 3 .expected.json sidecars, 1 patcher)

## Accomplishments
- Wrote `corpus/patch_rotation.py`, a stdlib-only direct `tkhd` display-matrix patcher (ffmpeg's `-metadata:s:v:0 rotate=` is a verified no-op on the installed ffmpeg 6.1.1); raises on a missing `tkhd` box rather than exiting 0, verified live
- Wrote `corpus/generate_corpus.sh`, which builds all three clips with ffmpeg lavfi sources, self-asserts every structural property (display matrix, coded dimensions, stream counts, codecs, 1.5MB size cap) before declaring success, and is now byte-reproducible run-to-run after adding single-threaded libx264 encoding
- Generated and committed `portrait_rot90.mp4` (1920x1080 coded, 90° CW `tkhd` matrix, H.264+AAC, burnt-in ms timecode, 8-bucket colour-patch schedule), `small_480p.mp4` (854x480, bitrate-capped, no matrix) and `noaudio_720p.mp4` (1280x720, no audio), all well under the 1.5MB cap
- Wrote `corpus/verify_corpus.sh`, the single producer of the sidecars: derives ground truth from ffprobe (unsigned-clockwise `rotationDegrees`, displayed not coded `widthPx`/`heightPx`, normalised `videoCodec`, `crossPlatform`/`tolerant` field split, `durationToleranceMs`/`videoBitrateTolerancePct`/`frameRateToleranceFps`) plus the thumbnail probe-patch RGB (sampled from the actual displayed frame, with an assertion that adjacent 500ms buckets are distinguishable); `--write` mode writes sidecars, default mode diffs and fails on drift — verified against a deliberate tamper-and-restore
- Wrote `corpus/sync_to_example.sh`, which mirrors clips and sidecars into `example/assets/corpus/` with sha256 verification and fails loudly naming the missing directory while `example/` doesn't exist yet
- Wrote `corpus/README.md` documenting the rotation sign convention, the displayed-vs-coded dimension rule, the `crossPlatform`/`tolerant` split and the thumbnail probe-patch contract

## Task Commits

1. **Task 1: Generate the three corpus clips with a real display matrix** - `4c55b35` (feat)
2. **Task 2: Derive the ground-truth sidecars, the drift verifier and the mirror script** - `9d50987` (feat)

**Deviation fix (Rule 1, found during Task 2):** `21238e7` (fix) — see Deviations below.

**Plan metadata:** (this commit, docs)

## Files Created/Modified
- `corpus/patch_rotation.py` - Direct `tkhd` display-matrix patcher (stdlib `struct` only)
- `corpus/generate_corpus.sh` - Reproducible generator for all three clips, self-asserting
- `corpus/verify_corpus.sh` - Single producer of sidecars; drift gate in default mode
- `corpus/sync_to_example.sh` - Mirrors clips+sidecars into `example/assets/corpus/`, sha256-verified
- `corpus/README.md` - Conventions doc (rotation sign, displayed dims, field split, probe contract)
- `corpus/portrait_rot90.mp4`, `corpus/small_480p.mp4`, `corpus/noaudio_720p.mp4` - The three clips
- `corpus/portrait_rot90.expected.json`, `corpus/small_480p.expected.json`, `corpus/noaudio_720p.expected.json` - Ground-truth sidecars

## Decisions Made
- Thumbnail probe displayed-coordinate transform derived analytically from the `tkhd` matrix (a coded point `(px,py)` in a `WxH` coded frame displays at `(H-py, px)` for a 90° clockwise matrix), giving patch centre `(920, 1700)` in the 1080x1920 displayed frame; the RGB value itself was then sampled empirically per the plan's instruction, and cross-checked against a second sample at 1000ms to confirm the two adjacent colour buckets are distinguishable (yellow vs blue, both far outside the 24-unit tolerance).
- Added `-threads 1 -x264-params threads=1:sliced_threads=0` to every libx264 encode in `generate_corpus.sh` (see Deviations) — required for the plan's reproducibility must-have.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] libx264's default multi-threaded rate control made `generate_corpus.sh` non-reproducible**
- **Found during:** Task 2, while validating the plan's must-have truth "`bash corpus/generate_corpus.sh` is reproducible: re-running it on danserver produces clips whose ffprobe-reported stream properties are identical to the committed ones."
- **Issue:** Re-running `generate_corpus.sh` produced `small_480p.mp4` (bitrate-targeted ABR encode) with a different file size and video bitrate on each run (and `noaudio_720p.mp4` marginally so), because libx264's default multi-threaded encoding introduces non-determinism into rate control.
- **Fix:** Added `-threads 1 -x264-params threads=1:sliced_threads=0` to all three `ffmpeg`/libx264 invocations in `generate_corpus.sh`. Verified two consecutive runs now produce sha256-identical output for all three clips. Regenerated and recommitted the clips with this fix, then re-derived all three sidecars from the new (now-reproducible) clips.
- **Files modified:** `corpus/generate_corpus.sh`, `corpus/portrait_rot90.mp4`, `corpus/small_480p.mp4`, `corpus/noaudio_720p.mp4`
- **Verification:** `sha256sum corpus/*.mp4` identical across two consecutive `generate_corpus.sh` runs; `bash corpus/verify_corpus.sh` still exits 0 against the re-derived sidecars
- **Committed in:** `21238e7`

---

**Total deviations:** 1 auto-fixed (1 bug).
**Impact on plan:** No scope creep — this was necessary to satisfy the plan's own must-have reproducibility truth. The portrait clip's bytes also changed slightly (identity `preset`/`crf` path was already close to deterministic but the video-stream `bit_rate` value ffprobe reports depends on rate-control internals too), so all three sidecars were re-derived and re-verified after the fix, not just the one clip that first exposed the bug.

## Issues Encountered
None beyond the deviation above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- The corpus is complete, self-verifying, and ready for `example/assets/corpus/` once the plugin scaffold lands (a later plan in this phase) — `sync_to_example.sh` will succeed as soon as `example/` exists; today it correctly refuses to run.
- The sidecar contract (`crossPlatform`/`tolerant`/`thumbnailProbe`, unsigned-clockwise rotation, displayed dimensions) is now the fixed ground truth every later `MediaInfo`/thumbnail integration test in this phase must assert against.
- Ready for the remaining Wave 1+ plans in Phase 1 (Pigeon contract, Kotlin/Swift native implementations, CI wiring, example app).

---
*Phase: 01-typed-contract-ci-and-media-info*
*Completed: 2026-09-15*
