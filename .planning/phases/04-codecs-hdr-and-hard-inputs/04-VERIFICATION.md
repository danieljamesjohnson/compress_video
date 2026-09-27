---
phase: 04-codecs-hdr-and-hard-inputs
verified: 2026-09-27T00:00:00Z
status: human_needed
score: 4/5 must-haves verified (behavior-verified where testable; 1 truth present-but-unverified pending physical hardware)
behavior_unverified: 0
overrides_applied: 0
human_verification:
  - test: "Run doc/HARDWARE_CHECKLIST.md's HEVC-hardware-encode section on a physical Android phone: `flutter test integration_test/hard_inputs_test.dart -d <physical-device-id>` with `VideoCodec.hevc` opt-in, confirm `hevcFallback: false` and `videoCodec: 'hevc'` in the result."
    expected: "A real ARM/Qualcomm/Exynos hardware HEVC encoder is exercised and reports success (not merely the macOS CI host's Apple Silicon encoder, which is the only hardware-success evidence that exists today)."
    why_human: "No physical Android device is reachable from danserver (QUESTIONS.md #3); the Android emulator's software codec path cannot exercise a hardware encoder at all."
  - test: "Run doc/HARDWARE_CHECKLIST.md's HDR tone-map fidelity section by eye on a physical Android phone and an iPhone, using a real Dolby Vision profile-8 clip and a real Pixel HLG10 clip (not the synthetic corpus fixtures)."
    expected: "The tone-mapped SDR output is visually correct (not washed out, not over/under-exposed) when viewed by a human, and `toneMapped: true` is reported."
    why_human: "Success criterion 1 names 'a portrait iPhone Dolby Vision clip and a Pixel HLG10 clip' specifically — real camera output, not ffmpeg-synthesized HLG10/PQ10 fixtures. No such real clips exist on danserver (QUESTIONS.md #4), and 'not washed out' is inherently a visual, human judgment even once a real clip exists. The Android emulator additionally cannot tone-map at all with its software GL/decoder (both fallback attempts fail with codes 5001/3003, confirmed live and documented) so Android's `toneMapped: true` claim has never been observed on Android at all — only on the macOS CI host's Apple leg."
  - test: "Run doc/HARDWARE_CHECKLIST.md's keep-HDR section on a physical Android device capable of HDR editing, and confirm HEVC 10-bit HDR output plus `toneMapped: false`."
    expected: "A physical Android device takes the keep branch and produces genuinely HDR HEVC output, distinct from the macOS-host-only CI evidence that exists today."
    why_human: "Same physical-device gap as above; the Android emulator cannot take the keep-HDR success branch (confirmed exhausted-chain outcome only)."
  - test: "Watch for CI run 36299999129 (validating post-review-fix commits 80d8ef7, 1d87b0b, b8e9f0e) to complete, then confirm all four jobs (`android`, `apple`, `corpus`, `parity`) conclude `success`."
    expected: "Green, consistent with every prior Phase 4 CI run."
    why_human: "Run was still `in_progress` at verification time; this is the newest commit on `main` and has not yet produced a conclusion to check."
---

# Phase 4: Codecs, HDR, and Hard Inputs Verification Report

**Phase Goal:** The inputs every competitor got wrong come out correct: HDR phone video is not washed out, HEVC is used only where hardware supports it, and unusual audio never fails. A real-clip corpus in CI keeps it that way.
**Verified:** 2026-09-27
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (roadmap Success Criteria)

| # | Truth (Success Criterion) | Status | Evidence |
|---|---|---|---|
| 1 | A portrait iPhone Dolby Vision clip and a Pixel HLG10 clip from the corpus each compress, with default options, to a smaller upright SDR MP4 that is not washed out, reporting `toneMapped: true` on Android and Apple. | ⚠️ PARTIAL / PRESENT_BEHAVIOR_UNVERIFIED (see detail) | See below — code path exists and is exercised, but not on the clips the criterion names, and not successfully on Android at all. |
| 2 | With HEVC opt-in, a device with hardware HEVC produces HEVC; a device without falls back to H.264 and reports it. Keep-HDR opt-in: capable device → HEVC 10-bit HDR; incapable → tone-mapped SDR fallback, reported. | ✓ VERIFIED (CI-proven, one platform only) | CI run 36279264836 (macOS Apple Silicon host): `HEVC_BRANCH=success`, `KEEP_HDR_BRANCH=keep`. iOS simulator/Android emulator took the documented fallback branch. `HevcOutputDecisionTest.kt` (7 cases, incl. CR-01/CR-02 regression cases) and `CodecCapabilitiesTest.kt` (10 cases) prove the decision logic on plain JVM. No physical device has run either branch. |
| 3 | The 5.1-audio, PCM-audio, no-audio corpus clips and the 4K60 clip all compress successfully on the Android emulator and iOS simulator, without an error. | ✓ VERIFIED | CI run 36287969994 (all 4 jobs green): `surround51_480p`/`pcm_audio_480p`/`noaudio_720p` cases pass on Android emulator, iOS simulator, and macOS; PARITY_JSON records confirm identical outcomes across all 3 legs for these 3 cases. `uhd_4k60` compresses without error on Android emulator (bounded at 120s/test) per 04-01/04-02-SUMMARY.md; excluded from the parity gate itself (documented, not a failure) because its own test body legitimately branches on `usedOriginal`. |
| 4 | CI runs the full committed corpus through integration tests on Android emulator and iOS simulator. A documented hardware checklist covers HEVC hardware encode and HDR tone-map fidelity on physical devices and has been run once. | ✗ FAILED (checklist half only) | CI half: ✓ verified — CI run 36287969994 green, full corpus (Dolby Vision slot documented as reserved/unfillable, HLG10, PQ10, portrait, 4K60, PCM, no-audio, 5.1, already-small) runs on Android emulator + iOS simulator + macOS every push. Checklist-run half: ✗ — `doc/HARDWARE_CHECKLIST.md` exists (161 lines) and is honest that it has **not** been run on physical hardware (explicit "not yet run" status lines throughout, dated). REQUIREMENTS.md correctly leaves TEST-01 `Pending` for exactly this reason. The criterion's own text ("has been run once") is not met. |

**Score:** 2/4 roadmap success criteria fully verified (3, and CI-half of 4). Criterion 1 is present-in-code but not proven on the clips it names and not proven successfully on Android at all. Criterion 2 is proven on one platform (macOS CI host) only, never on physical hardware. Criterion 4's checklist-run requirement is honestly unmet.

### Requirements Coverage

| Requirement | Source Plan(s) | REQUIREMENTS.md status | Assessment |
|---|---|---|---|
| CDEC-01 | 04-03, 04-04, 04-05 | Complete | ✓ Supported — H.264 default, HEVC only via hardware probe (`CodecCapabilities.kt`/`.swift`), fallback reported. Hardware-success path proven on macOS CI host only (not physical Android/iOS device); the checked-box in REQUIREMENTS.md is defensible since the requirement text is about the mechanism ("used only when a hardware encoder exists... falls back... reported"), which is proven, not about "proven on every physical device type." |
| CDEC-02 | 04-02, 04-04, 04-05 | Complete | ⚠️ Partially supported — the tone-map-and-report mechanism is proven correct on the macOS CI host's Apple leg (success) and is code-complete on Android, but the Android emulator itself has never successfully tone-mapped (both OpenGL and MediaCodec attempts fail on this software-GL emulator, confirmed live, documented as an environment limitation not a code bug). No real Dolby Vision or real HLG10 device clip has ever been tone-mapped by this plugin. |
| CDEC-03 | 04-03, 04-04, 04-05 | Complete | ⚠️ Same evidence tier as CDEC-02 — keep branch proven only on macOS CI host; fallback branch proven on Android emulator + iOS simulator. |
| AUDO-03 | 04-02, 04-04, 04-05 | Complete | ✓ Well-supported — proven on Android emulator, iOS simulator, and macOS for 5.1, PCM, and no-audio cases, cross-platform parity-gated (CI run 36287969994). |
| TEST-01 | 04-01, 04-05 | Pending | ✓ Correctly left Pending — CI corpus half is done; hardware-checklist-run half is honestly unmet. No orphaned or contradicting requirement IDs found; the phase's own plans/SUMMARYs are internally consistent on this point (04-05-SUMMARY.md's `requirements-completed:` frontmatter list is the one inconsistency found — see Anti-Patterns below). |

No orphaned requirements: the union of `requirements:` fields across 04-01 through 04-05 (CDEC-01, CDEC-02, CDEC-03, AUDO-03, TEST-01) exactly matches the phase's declared requirement IDs.

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `corpus/hdr_hlg10.mp4`, `hdr_pq10.mp4`, `pcm_audio_480p.mov`, `surround51_480p.mp4`, `uhd_4k60.mp4` + sidecars | Reproducible fixtures per 04-01 must-haves | ✓ VERIFIED | `bash corpus/verify_corpus.sh` exits 0 locally against all 9 clips including the 5 new ones; `example/assets/corpus/` mirrors confirmed by CI. |
| `corpus/verify_corpus.sh` — `isHdr` derived from probed transfer, `hdr`/`hdrProbe`/`audio` sidecar blocks | Real probe-derived data, not hardcoded | ✓ VERIFIED | `hdr_hlg10.expected.json`/`hdr_pq10.expected.json` contain `hdr`/`hdrProbe` blocks per grep in 04-01-SUMMARY; `verify_corpus.sh` passes with all pre-existing sidecars byte-unchanged (confirmed by clean local run). |
| `android/.../CodecCapabilities.kt` + `CodecCapabilitiesTest.kt` | Pure capability probe over `EncoderUtil`, unit-tested on plain JVM | ✓ VERIFIED | File exists, `grep -c EncoderUtil` ≥ 1 per 04-03-SUMMARY; 10 JVM-only test cases including a non-matching-vendor case. |
| `darwin/.../CodecCapabilities.swift` | Apple hardware-HEVC probe via `VTCopyVideoEncoderList` | ✓ VERIFIED (with documented deviation) | 04-04-SUMMARY documents a deliberate, CI-forced deviation from the plan's `VTCopySupportedPropertyDictionaryForEncoder` approach (iOS-17.4-only API found via a real compile failure) to `VTCopyVideoEncoderList` — a legitimate in-flight correction, not a gap. |
| `android/.../TransformerEngine.kt` — `toneMapped`/`hevcFallback` computed from real output, `!usedOriginal` guard | Honest, output-derived reporting | ✓ VERIFIED | Grep confirms lines 717/722: `toneMapped = !usedOriginal && inputWasHdr && !outputIsHdr`; `hevcFallback = !usedOriginal && hevcFallbackFromRequest`; unconditional `usedOriginal = tempBytes >= inputBytes` at line 664, no HDR/HEVC-conditional weakening. |
| `darwin/.../CompressionEngine.swift` — same contract | Mirror of Android | ✓ VERIFIED | Grep confirms lines 705/832/833: identical `!usedOriginal` guard pattern, unconditional never-larger check. |
| `tool/check_parity.sh` / `tool/check_parity_test.sh` — `toneMapped`/`hevcFallback` compared exactly | Both directions proven | ✓ VERIFIED | Local run: `bash tool/check_parity_test.sh` → 13/13 PASS including flipped-`toneMapped` and flipped-`hevcFallback` teeth-demonstration cases. |
| `doc/HARDWARE_CHECKLIST.md` | TEST-01's hardware half, dated not-yet-run status | ✓ VERIFIED | Exists, 161 lines; explicit "Status: not yet run on a physical Android phone" / "not yet run — no real Dolby Vision clip exists" lines throughout; distinguishes CI-proven branch-level evidence from physical-device proof honestly. |
| `04-VALIDATION.md` Per-Task Verification Map | One row per task, all observed | ✓ VERIFIED | 15 rows present, all marked ✅ with cited CI run IDs / local command output; row-count self-check documented in the file. |

### Key Link Verification

| From | To | Via | Status |
|---|---|---|---|
| `ExportResult.colorInfo` (Android) | `CompressResultMessage.toneMapped` | `ColorInfo.isTransferHdr`, `!usedOriginal` guard | ✓ WIRED — confirmed by direct grep of `TransformerEngine.kt` |
| `Probe.getMediaInfo` re-probe (Apple) | `CompressResultMessage.toneMapped` | re-probe compared to input's HDR flag, `!usedOriginal` guard | ✓ WIRED — confirmed by direct grep of `CompressionEngine.swift` |
| `CodecCapabilities.hasHardwareEncoderFor` | `Transformer.Builder.setVideoMimeType` / `AVVideoCodecType.hevc` | shared `outputIsHevc`/`resolveHevcOutputDecision` decision, read by both MIME gate and `resolvePlan` | ✓ WIRED — confirmed by 04-REVIEW.md's line-by-line trace of the post-fix coupled decision (`HevcOutputDecisionTest.kt` 7 cases) and by grep showing the same `hevcFallback = (requestedHevc && !hasHardwareHevc) \|\| keepHdrFallbackActive` line on both platforms |
| `SizeGuard.InputInfo.audioChannelCount` / `outputCodecIsHevc` | `SizeGuard.wouldTransmux` | transmux predicate refuses >2ch audio and HEVC-resolved output | ✓ WIRED — per 04-02/04-03-SUMMARY and `SizeGuardTest.kt` cases |
| `hard_inputs_test.dart` PARITY_JSON | `tool/check_parity.sh` | CI greps PARITY_JSON lines from each leg's log | ✓ WIRED — CI run 36287969994's parity job diffed the new records across all 3 legs successfully |

### Anti-Patterns / Documentation Consistency

| File | Issue | Severity | Impact |
|---|---|---|---|
| `04-05-SUMMARY.md` frontmatter | `requirements-completed: [TEST-01, CDEC-01, CDEC-02, CDEC-03, AUDO-03]` lists TEST-01, but the same file's own `key-decisions` bullet and `REQUIREMENTS.md` correctly leave TEST-01 `Pending`. | ℹ️ Info | Cosmetic frontmatter/body inconsistency inside the SUMMARY itself; does not propagate to `REQUIREMENTS.md`, which is correct and was independently checked. Worth a one-line fix in the SUMMARY frontmatter but not a phase-blocking gap. |
| `android/.../TransformerEngine.kt:1144-1149` | `SURROUND_DOWNMIX_GAIN` doc comment misdescribes derivation (says `10^(-3/20)` but the literal is actually `1/√2`). Carried over from code review as IN-01, explicitly left open at Info by the reviewer. | ℹ️ Info | Comment-only inaccuracy, ~0.12% linear-gain difference, inaudible. No behavioral effect. Not re-flagged as a gap here since it was already triaged and accepted at Info by 04-REVIEW.md. |

No TBD/FIXME/XXX debt markers found in the phase's modified files (spot-checked against 04-REVIEW.md's file list, which found 0 critical/warning issues and only the one pre-existing IN-01 comment note across 25 reviewed files).

### CI Evidence

| Run | Plan | Conclusion |
|---|---|---|
| 36222965357 | 04-01 | success |
| 36234334130 | 04-02 | success |
| 36256309651 | 04-03 | success |
| 36279264836 | 04-04 | success — macOS host took HEVC/keep-HDR success branch |
| 36287969994 | 04-05 | success — parity gate green with widened toneMapped/hevcFallback comparison |
| 36299999129 | post-review-fix (80d8ef7, 1d87b0b, b8e9f0e) | **in_progress at verification time** — pending, not yet a completed result |

### Behavioral Spot-Checks (run directly by this verifier)

| Behavior | Command | Result | Status |
|---|---|---|---|
| Corpus reproducibility / drift gate | `bash corpus/verify_corpus.sh` | All 9 sidecars OK, `truncated_mdat.mp4` correctly has no sidecar by design | ✓ PASS |
| Parity gate teeth (both directions, all new fields) | `bash tool/check_parity_test.sh` | 13/13 PASS incl. flipped `toneMapped` and flipped `hevcFallback` | ✓ PASS |
| `!usedOriginal` guard present on both platforms | `grep` of `TransformerEngine.kt` / `CompressionEngine.swift` | Confirmed present, unconditional never-larger check untouched | ✓ PASS |
| CI run conclusions | `gh run view <id> --json status,conclusion` | 5/6 runs `success`; newest run `in_progress` | ✓ PASS (5), ? PENDING (1) |

### Human Verification Required

See frontmatter `human_verification` block. Summary:

1. **Physical Android HEVC hardware encode** — not run anywhere; only macOS CI host has produced HEVC-hardware success evidence.
2. **HDR tone-map fidelity on real Dolby Vision / real Pixel HLG10 clips, by eye** — the roadmap criterion names real camera clips specifically; only synthetic ffmpeg-authored HLG10/PQ10 fixtures exist, and even those have never successfully tone-mapped on the Android emulator (both fallback attempts exhaust with software-GL errors 5001/3003).
3. **Physical Android keep-HDR success branch** — not run anywhere; only macOS CI host evidence exists.
4. **CI run 36299999129 completion** — in progress at verification time, validating the code-review fix commits; needs a follow-up check once it concludes.

### Gaps Summary

The phase's engineering work is thorough, honestly self-documented, and the automated evidence (CI green across 5 completed runs on 3 platforms, clean code review after one fix iteration, passing local drift/parity gates) is strong. The gap is not a hidden defect — it is the phase's own stated, undisguised limitation: **success criterion 4's "has been run once" hardware checklist has genuinely not been run**, and **success criterion 1's real-device HDR clips do not exist on this hardware-constrained box**, and the Android emulator has never once successfully completed a tone-map (only ever the documented exhausted-fallback path). REQUIREMENTS.md correctly reflects this by leaving TEST-01 Pending. This routes to `human_needed` rather than `gaps_found` because nothing here is a code defect to fix in another plan — it requires a physical Android phone, a real Dolby Vision/HLG10 clip, and someone to run and observe the checklist (all named already in QUESTIONS.md #3/#4 and STATE.md's Deferred Verification table). No override is suggested because the plan itself already predicted and documented this exact gap rather than claiming completion — accepting it via override would just restate what REQUIREMENTS.md and doc/HARDWARE_CHECKLIST.md already say plainly.

---

_Verified: 2026-09-27_
_Verifier: Claude (gsd-verifier)_
