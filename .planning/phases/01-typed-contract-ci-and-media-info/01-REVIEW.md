---
phase: 01-typed-contract-ci-and-media-info
reviewed: 2026-09-21T00:00:00Z
depth: standard
files_reviewed: 46
files_reviewed_list:
  - analysis_options.yaml
  - android/build.gradle.kts
  - android/src/main/kotlin/com/danjjohnson/compress_video/Arguments.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/CompressVideoPlugin.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/MediaMath.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/Messages.g.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/Probe.kt
  - android/src/main/kotlin/com/danjjohnson/compress_video/Thumbnails.kt
  - android/src/test/kotlin/com/danjjohnson/compress_video/ArgumentsTest.kt
  - android/src/test/kotlin/com/danjjohnson/compress_video/CompressVideoPluginTest.kt
  - android/src/test/kotlin/com/danjjohnson/compress_video/MediaMathTest.kt
  - corpus/generate_corpus.sh
  - corpus/patch_rotation.py
  - corpus/sync_to_example.sh
  - corpus/verify_corpus.sh
  - darwin/compress_video/Package.swift
  - darwin/compress_video.podspec
  - darwin/compress_video/Sources/compress_video/Arguments.swift
  - darwin/compress_video/Sources/compress_video/CompressVideoPlugin.swift
  - darwin/compress_video/Sources/compress_video/MediaMath.swift
  - darwin/compress_video/Sources/compress_video/Messages.g.swift
  - darwin/compress_video/Sources/compress_video/Probe.swift
  - darwin/compress_video/Sources/compress_video/Thumbnails.swift
  - example/integration_test/media_info_test.dart
  - example/integration_test/thumbnail_test.dart
  - example/ios/RunnerTests/RunnerTests.swift
  - example/lib/main.dart
  - example/macos/RunnerTests/RunnerTests.swift
  - example/macos/Runner.xcodeproj/project.pbxproj
  - example/pubspec.yaml
  - example/test/widget_test.dart
  - .github/workflows/ci.yml
  - .gitignore
  - lib/compress_video.dart
  - lib/src/compress_video_exception.dart
  - lib/src/media_info.dart
  - lib/src/messages.g.dart
  - pigeons/messages.dart
  - .pubignore
  - pubspec.yaml
  - test/compress_video_exception_test.dart
  - test/media_info_mapping_test.dart
  - test/messages_contract_test.dart
  - test/thumbnail_api_test.dart
  - tool/check_parity.sh
  - tool/check_parity_test.sh
findings:
  critical: 1
  warning: 3
  info: 2
  total: 6
status: issues_found
---

# Phase 01: Code Review Report

**Reviewed:** 2026-09-21
**Depth:** standard
**Files Reviewed:** 46
**Status:** issues_found

## Summary

Reviewed the Pigeon typed contract, the Dart public API/mapping layer, the Android
(Probe.kt/Thumbnails.kt/Arguments.kt/MediaMath.kt) and Apple (Probe.swift/Thumbnails.swift/
Arguments.swift/MediaMath.swift) media-info and thumbnail implementations, the corpus
generation/verification tooling, `tool/check_parity.sh`/`check_parity_test.sh`, and
`.github/workflows/ci.yml`.

The Dart API surface is careful about null-safety, argument validation, and error mapping —
no raw `PlatformException` escapes, and every failure path is exercised by
`test/media_info_mapping_test.dart`. The Android and Apple native implementations mirror each
other closely (rotation math, scaling, clamping, atomic writes, resource cleanup on every path)
and are backed by a genuinely rigorous corpus/parity mechanism. No hardcoded secrets, no
injection vectors, no obvious null-pointer crashes were found in the reviewed native code.

The one BLOCKER is in the CI pipeline: the path filter that decides whether the expensive
`apple` job (and, transitively, the `parity` job that self-tests and runs `check_parity.sh`)
executes does not include `tool/`, so a change that breaks the parity gate itself can merge
with a fully green CI run that never exercised the gate. The WARNING findings cover a
platform behavior asymmetry in path standardization, a real (documented but under-flagged)
codec-detection blind spot on older Apple OS versions, and a robustness gap in
`check_parity.sh`'s handling of missing/malformed fields.

## Critical Issues

### CR-01: `tool/` is missing from the Apple-relevant CI path filter, so a broken parity gate can merge without ever running

**File:** `.github/workflows/ci.yml:71` (filter), `.github/workflows/ci.yml:448` (parity gating)

**Issue:** The `changes` job (lines 42-75) decides whether the `apple` job runs by grepping
the diff against:
```
^(darwin/|pigeons/|lib/|example/|pubspec\.yaml$|\.github/workflows/ci\.yml$)
```
`tool/` is not in this list. The `parity` job (line 441) requires
`needs.android.result == 'success' && needs.apple.result == 'success'` to run at all — and
when `apple` is skipped (not run, because no listed path changed), its result is `'skipped'`,
not `'success'`, so `parity`'s `if` evaluates false and the whole job — including
`tool/check_parity_test.sh`, the self-test that proves `check_parity.sh` itself still catches
an out-of-tolerance divergence — is skipped.

Concretely: a PR that only touches `tool/check_parity.sh` or `tool/check_parity_test.sh` (for
example, one that accidentally weakens the tolerance comparison, inverts a condition, or
introduces the "missing field → bash arithmetic error masks as pass" issue in WR-03 below)
will show a fully green CI run, because the one job that would have caught the regression
never executes. This is exactly the failure mode the parity mechanism exists to prevent
(silent cross-platform divergence), just moved one level up: the guard's own correctness is
unguarded on the PRs most likely to change it.

**Fix:** Add `tool/` (or at minimum `tool/check_parity` for a narrower match) to the filter
regex, and/or make the `parity` job's self-test step independent of the `apple` job (run
`tool/check_parity_test.sh` unconditionally, e.g., inside the `android` job or a new
lightweight job with no `needs`, so it always executes regardless of what changed):
```yaml
if git diff --name-only "$BASE" "$HEAD" | grep -Eq '^(darwin/|pigeons/|lib/|example/|tool/|pubspec\.yaml$|\.github/workflows/ci\.yml$)'; then
```

## Warnings

### WR-01: Apple's path standardization does not resolve symlinks, unlike Android's — undocumented cross-platform asymmetry

**File:** `darwin/compress_video/Sources/compress_video/Arguments.swift:160-165` vs
`android/src/main/kotlin/com/danjjohnson/compress_video/Arguments.kt:31-36`

**Issue:** `Arguments.kt`'s `requireReadableMediaFile`/`requireWritableOutputParent` resolve
`File(path).canonicalFile`, which fully resolves symlinks. `Arguments.swift`'s
`standardizedAbsolutePath` uses `URL(fileURLWithPath:).standardizedFileURL.path`, which the
code's own doc comment states explicitly does **not** resolve symlinks ("this is
standardisation, not canonicalisation"). Both files independently justify their own choice by
appeal to the OS sandbox already limiting what's reachable, but neither doc comment
acknowledges that the two platforms now canonicalize a caller-supplied path differently. A
caller that passes a path through a symlink whose target does not yet exist, or that changes
between validation and use (TOCTOU), is validated differently on Android vs. Apple, and this
divergence is never exercised or caught by the cross-platform parity gate (which only diffs
the *content* the two platforms report for the *same* fixed corpus paths, not path-resolution
policy for adversarial paths).

**Fix:** Either resolve symlinks on both platforms (Swift: use
`URL(fileURLWithPath:).resolvingSymlinksInPath()` in addition to standardization) or
explicitly document, in both files, that the two platforms deliberately differ here and why
that is safe (the sandbox argument), so a future reader doesn't have to rediscover the
asymmetry by diffing the two files.

### WR-02: Apple's video codec detection silently degrades to `unknown` for the entire iOS 13–15 / macOS 11–12 range

**File:** `darwin/compress_video/Sources/compress_video/Probe.swift:66-85`

**Issue:** On the legacy (`loadValuesAsynchronously`) path — which runs on every OS below the
`#available(iOS 16, macOS 13, *)` guard, i.e. the entire iOS 13–15 / macOS 11–12 range that the
project's own minimum-target constraint (iOS 13+, macOS 11+) commits to supporting —
`formatDescriptions` is hardcoded to `[]`. That flows into
`MediaMath.normalizeCodec(fourCharacterCode(from: formatDescriptions.first))`, which then
always returns `"unknown"` for `videoCodec` on those OS versions, regardless of the file's
actual codec. This is a real, silent capability gap (not a crash, but a materially less useful
result) for a a multi-year span of the plugin's committed OS support matrix, and it is not
exercised by the cross-platform parity gate (parity only runs on `macos-latest`'s current
simulator/OS, which is far newer than the affected range) or covered by any CI job pinned to
an older Apple OS.

**Fix:** At minimum, add a unit test (or an explicit note in TOOLCHAIN.md/README) that documents
this as a known, accepted platform-version limitation with its exact OS boundary, so it doesn't
get rediscovered as a field bug later. If avoiding the forced/conditional downcast the comment
describes is the only blocker, consider `unsafeBitCast`-free alternatives such as
`CMFormatDescriptionGetMediaSubType` reachable another way on the legacy path (e.g., via
`AVAssetTrack.formatDescriptions` boxed as `[CMFormatDescription]` through
`.compactMap { $0 as! CMFormatDescription? }` guarded by a count/type check before the cast, or
by using `withUnsafeBytes`-style type-checked extraction) rather than dropping the value
entirely.

### WR-03: `check_parity.sh` can produce a confusing bash arithmetic error instead of a clean MISMATCH when a field is missing

**File:** `tool/check_parity.sh:104-109`, `130-137`

**Issue:** `DUR_A`/`DUR_B` (line 104-105) and `C_A`/`C_B` (line 131-132) are read via
`jq -r ... '.[$clip].durationMs'` / `'.thumbnail.patchRgb[$i]'` with no fallback. If either
field is absent from a PARITY_JSON record (e.g., a future refactor renames a field, or a
platform's test crashes before recording it, leaving a partial/malformed line), `jq -r` returns
the literal string `"null"`, and the subsequent bash arithmetic
`$(( DUR_A > DUR_B ? DUR_A - DUR_B : DUR_B - DUR_A ))` fails with a bash syntax error
(`value too great for base` / `syntax error: operand expected`) rather than the script's
documented, clean `MISMATCH`/`FATAL` failure modes. Under `set -euo pipefail`, this still exits
non-zero (so the gate does still fail closed), but the failure message is an opaque bash
internal error instead of naming the missing field, undermining the debuggability the rest of
the script is deliberately designed around (see the `fail()` helper and its call sites).

**Fix:** Guard for `null`/missing before the arithmetic, e.g.:
```bash
if [ "$DUR_A" = "null" ] || [ "$DUR_B" = "null" ]; then
  fail "$clip.durationMs: A=$DUR_A B=$DUR_B (field missing on at least one platform)"
  continue
fi
```
and similarly for the `patchRgb` loop.

## Info

### IN-01: `Messages.g.*` regeneration is enforced by CI but not independently verified in this review

**File:** `lib/src/messages.g.dart`, `android/src/main/kotlin/com/danjjohnson/compress_video/Messages.g.kt`, `darwin/compress_video/Sources/compress_video/Messages.g.swift`

All three carry the `// Autogenerated from Pigeon (v29.0.2), do not edit directly.` header and
show no evidence of hand-editing (consistent field ordering/counts across the three
generated languages, matching `pigeons/messages.dart`). `.github/workflows/ci.yml:138-156`
already regenerates and diffs these on every CI run, which is the correct enforcement
mechanism — noted here only for completeness since `dart run pigeon` was not re-run during
this review.

### IN-02: `check_parity.sh`'s duration-tolerance lookup has the same unguarded-null issue as WR-03 for a missing sidecar field

**File:** `tool/check_parity.sh:94`

`TOLERANCE_MS=$(jq -r '.crossPlatform.durationToleranceMs' "$SIDECAR")` has no fallback if a
sidecar is missing that key; `[ "$DIFF" -gt "$TOLERANCE_MS" ]` would then emit a bash `-gt`
usage error rather than a clean message. Lower priority than WR-03 since every committed
sidecar currently carries this field and `corpus/verify_corpus.sh` enforces the sidecar shape,
but the same defensive fix (checking for `"null"` before the comparison) would make this
uniform with the rest of the script's error handling.

---

_Reviewed: 2026-09-21_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
