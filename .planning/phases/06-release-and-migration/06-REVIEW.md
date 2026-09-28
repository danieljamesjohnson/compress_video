---
phase: 06-release-and-migration
reviewed: 2026-09-28T00:47:28Z
depth: standard
files_reviewed: 20
files_reviewed_list:
  - lib/video_compress_compat.dart
  - test/video_compress_compat_test.dart
  - test/video_compress_compat_snippets_test.dart
  - test/migration_doc_test.dart
  - test/preset_table_test.dart
  - tool/preset_table.dart
  - tool/generate_preset_table.dart
  - tool/run_ios_integration_suites.sh
  - example/integration_test/video_compress_compat_test.dart
  - darwin/compress_video/Sources/compress_video/Compression.swift
  - android/src/main/kotlin/com/danjjohnson/compress_video/Compression.kt
  - example/ios/RunnerTests/RunnerTests.swift
  - example/macos/RunnerTests/RunnerTests.swift
  - .github/workflows/ci.yml
  - MIGRATION.md
  - README.md
  - CHANGELOG.md
  - doc/RELEASE.md
  - pubspec.yaml
  - .pubignore
findings:
  critical: 0
  warning: 9
  info: 6
  total: 15
status: issues_found
---

# Phase 6: Code Review Report

**Reviewed:** 2026-09-28T00:47:28Z
**Depth:** standard
**Files Reviewed:** 20
**Status:** issues_found

## Summary

Reviewed the compat shim, its unit/snippet/integration tests, the preset-table generator, the
two native `awaitCompressResult` changes, the new CI gates and the release documents, against
the incumbent's real source in `.planning/research/sources/video_compress_3.1.4/`.

Method: every file was read in full. Nothing was executed — no test, build or CI step was run by
this review, because `flutter test`/`flutter analyze` rewrite `analysis_options.yaml` and the
review is read-only. Every finding below is from reading code; where a finding depends on
runtime behaviour I could not observe, it says so.

No BLOCKER was found. The items the orchestrator asked about specifically:

| Asked about | Verdict |
|---|---|
| Signatures vs the incumbent | Match: eight `VideoQuality` values in the incumbent's order, the same parameter names, types and defaults on every verb. Return types are non-nullable where the incumbent's were nullable, as documented. |
| Single in-flight job | Holds within one instance (check and set are in one synchronous run, no `await` between). **Breaks across `dispose()`** — WR-01. |
| `compressProgress$` subscription lifecycle | No leak. The forwarding subscription is cancelled in `finally` on success, failure and cancel. |
| `deleteOrigin` safety | Sound. String compare, then resolved-path compare, then `FileSystemEntity.identical`; any `FileSystemException` keeps the input. Hard links and case-insensitive names fall to `identical`. No path found that deletes the only copy. |
| Cancel resolves to `isCancel: true` | Yes, and only for reason `cancelled`; `interrupted` and every other reason is rethrown. |
| Never returns null | Holds for every verb. |
| Preset-table parser vs doc/PRESETS.md | Parses the three real tables correctly and fails loudly on every malformed input tried by reading. The defect is in what the rendered text **claims** — WR-05. |
| CI shell correctness | Gates are fail-closed. Two robustness defects — WR-06. `jq` is on `ubuntu-latest`. One wrong statement in 06-04-SUMMARY about pipefail — IN-01. |
| Swift `@MainActor` change | No data race introduced: every `JobRegistry` result-bookkeeping member is `@MainActor` and is now called from a `@MainActor` method with no hop. The **ordering guarantee the doc comment claims is stronger than what Swift promises** — WR-03. |
| Doc claims the code does not deliver | Four found — WR-04, WR-05, WR-07, IN-02. |

## Warnings

### WR-01: `dispose()` orphans the in-flight job — it can no longer be cancelled, and single-in-flight is lost

**Classification:** WARNING
**File:** `lib/video_compress_compat.dart:541-545` (with `:468-470`, `:278`, `:288`)
**Issue:** `dispose()` sets `_instance = null`. The next read of `VideoCompress` builds a new
`IVideoCompress` with its own `CompressVideo` engine, its own `_currentJob` (null) and its own
`_isCompressing` (false). If a compression is in flight at that moment:

1. `VideoCompress.cancelCompression()` reaches the new instance, finds `_currentJob == null` and
   does nothing. Nothing holds a reference to the old job, so **it cannot be cancelled at all**.
2. `VideoCompress.isCompressing` reads `false` while an encode is running.
3. A second `compressVideo` is accepted and runs **concurrently** on the second engine's own
   queue — the single-in-flight contract D-03 (06-01) says is kept.

The dartdoc says "As with the incumbent, this does not cancel a compression that is still in
flight". That is true of `dispose()` itself but not of what follows it: the incumbent's
`cancelCompression` was `channel.invokeMethod('cancelCompression')`, a process-wide native call
that cancelled the running job whichever Dart instance sent it
(`video_compressor.dart:168-170`). So `dispose()` then `cancelCompression()` worked in the
incumbent and silently does nothing here. Calling `VideoCompress.dispose()` from a widget's
`dispose()` and cancelling on the way out is an ordinary pattern.

No test covers it: every unit test calls `dispose()` only in `tearDown`, after the job settled.

**Fix:** keep the engine and the in-flight state at library level, so they survive the
instance:

```dart
final CompressVideo _sharedEngine = CompressVideo(maxConcurrentJobs: 1);
CompressJob? _currentJob;          // library-level, not per instance
bool _isCompressing = false;       // library-level, not per instance
```

`dispose()` then still replaces the instance (and its `compressProgress$`), while
`cancelCompression`, `isCompressing` and the `StateError` guard keep describing the one job that
is really running. Add a unit test: start a job, `dispose()`, assert `isCompressing` is still
`true`, `cancelCompression()` sends one cancel, and a second `compressVideo` throws `StateError`.

### WR-02: Android was not given the Swift validation-order fix — the two platforms now fail differently

**Classification:** WARNING
**File:** `android/src/main/kotlin/com/danjjohnson/compress_video/Compression.kt:29-38`
**Issue:** Quick task 260927-r4k moved `Arguments.requireValidCompressRequest(request)` on Apple
to **after** `registerJob` and inside the `do`/`catch`, with the stated reason "so a request
that fails validation is still a known job whose typed failure completeResult records, rather
than an 'unknown jobId'" (`Compression.swift:112-114`). The Kotlin file received only the grace
loop. It still validates on line 31, **before** `JobRegistry.resultDeferredFor(jobId)` on line
38 and outside the `try`.

For a caller on a background isolate (which reads its outcome from `awaitCompressResult`, not
from `startCompress`'s reply) a request native validation rejects therefore gives:

| Platform | Result |
|---|---|
| Apple | the real typed failure (`unsupportedInput`), at once |
| Android | reason `unknown`, "awaitCompressResult called for unknown jobId", after the full 2 s grace |

The summary and the Kotlin comment both say the two platforms "resolve ... identically". They do
not. Reachable whenever native validation is stricter than `CompressOptions.validate()`, or the
two drift.

**Fix:**

```kotlin
requireMainLooper("startCompress")
requireValidJobId(jobId)
JobRegistry.resultDeferredFor(jobId)          // register first
return try {
    Arguments.requireValidCompressRequest(request)   // now inside the try
    val inputFile = Arguments.requireReadableMediaFile(path)
    ...
```

### WR-03: The Swift doc comment promises an ordering that unstructured `Task`s do not guarantee

**Classification:** WARNING
**File:** `darwin/compress_video/Sources/compress_video/Compression.swift:76-86`, `:103-110`
**Issue:** The class comment states that staying on the `MainActor` "makes registration complete
before the next channel message's handler can run at all". The fix removes the suspension
points **inside** `startCompress`, which is correct and is a real improvement. But the two calls
still arrive as two separate `Task { @MainActor in ... }` created by Pigeon
(`Messages.g.swift:928` and the matching `awaitCompressResult` handler). Swift gives no ordering
guarantee between two unstructured tasks; on older Swift runtimes a task whose closure is
actor-isolated starts on the global executor and then hops to the actor, which is exactly the
reordering this fix is meant to remove. The package declares `swift-tools-version: 5.9` and
`s.swift_version = '5.0'` and supports iOS 13 / macOS 11, so it is built and run on toolchains
and OS runtimes other than CI's.

So the primary fix is "very likely ordered on current toolchains", and the **2 s grace loop is
the only mechanism that actually guarantees the outcome**. The summary already admits the race
is not reproduced by any test. I could not observe this at runtime; the claim here is about
what the language guarantees, not about a failure I saw.

**Fix:** correct the comment to say the ordering is expected, not guaranteed, and that the grace
loop is the guarantee. Treat the grace constants as load-bearing (not "belt and braces") — a
comment on `knownJobIdGracePolls` should say so, so nobody shortens or deletes them.

### WR-04: README statements that the code shipped in this phase now contradicts

**Classification:** WARNING
**File:** `README.md:62-63`, `README.md:176-177`, `README.md:308-310`
**Issue:** Three statements in the published README are false as of 1.0.0:

1. `:62-63` — "There is no ambiguous bare `duration` or `position` anywhere in the public API."
   `lib/video_compress_compat.dart` is a public library and declares `duration` (seconds, on
   `compressVideo`), `duration` (milliseconds, on `MediaInfo`), `position` and `startTime`.
2. `:176-177` — "there is no global progress stream and no 'is compressing' flag anywhere in
   this package". The compat library ships `compressProgress$` and `isCompressing`. The same
   sentence is in `lib/compress_video.dart:177` and `lib/src/compress_job.dart:127`.
3. `:308-310` — `encoderUnavailable` and `outOfSpace` are described as "(compression, later
   versions)" and `interrupted` as "(Apple engine, later versions)". CHANGELOG.md:20-23 says all
   three "are now real outcomes", and `interrupted` is raised on Android as well.

**Fix:** scope 1 and 2 to the main library ("... in `package:compress_video/compress_video.dart`;
the deprecated compat import keeps the old names on purpose"). In 3, delete the three
parentheticals and describe `interrupted` as raised on both Android and Apple.

### WR-05: The generated table calls a synthetic clip a recorded phone clip, and labels simulator numbers "iOS"

**Classification:** WARNING
**File:** `tool/preset_table.dart:228-231`, `:266-269`; `README.md:130-131`, `:134`
**Issue:** The generator writes the column headers "From a 1080p60 phone clip: Android / iOS /
macOS", and the README sentence above the table says the table shows what each preset "really
produced from a portrait 1080p phone clip recorded at 60 frames per second". The clip is
`portrait_hibitrate_1080p60.mp4`, which `corpus/generate_corpus.sh:206-217` generates with
ffmpeg from a mandelbrot source. It was never recorded on a phone. The project's own rule is
"The corpus is generated, not recorded", and its verification constraint is "real clips, not
synthetic" — so this is the one distinction the README must not blur. A high-entropy fractal
also compresses differently from camera footage, so the numbers are not what a reader's phone
video will produce.

Second, the footnote warns that the **Android** numbers come from an emulator's software
encoder, but says nothing about the "iOS" column, which is parsed from the heading
`### Measured table — iOS Simulator (software encoder)`. A reader takes the iOS column for
iPhone results.

`test/preset_table_test.dart:249-256` asserts the header text, so the test pins the wrong
wording in place.

**Fix:** in `renderPresetTable`, change the three headers to e.g. "From the 1080p60 test clip:
Android emulator / iOS Simulator / macOS", and extend the footnote: "The clip is a generated
test pattern, not camera footage. The Android and iOS numbers come from software encoders on an
emulator and a simulator; a phone's hardware encoder will give different numbers." Change the
README sentence at `:130-131` to match, update the test, regenerate.

### WR-06: The pana gate floats on an unpinned tool and hides its own diagnostics

**Classification:** WARNING
**File:** `.github/workflows/ci.yml:303-308`
**Issue:** Two defects in one step.

1. `dart pub global activate pana` installs whatever is latest. The gate requires
   `grantedPoints == maxPoints` with threshold 0. pana also scores things outside the
   repository: a dependency publishing a new major version, or a new pana release adding or
   re-weighting a check, turns **every** push red with no change in this repository. This is
   the same floating-toolchain risk the project treats as its largest complaint cluster.
2. pana's stderr is redirected to `${out%.json}.log` and that file is never printed or
   uploaded. When pana crashes or writes invalid JSON, the unguarded `jq -r '.scores | ...'`
   on line 307 exits non-zero under `bash -e` and the step dies there, before the `FATAL`
   message and with the real reason sitting in a file nobody can read.

**Fix:**

```yaml
run: |
  dart pub global activate pana 0.23.19
  out="${RUNNER_TEMP:-/tmp}/pana-report.json"
  log="${out%.json}.log"
  code=0
  dart pub global run pana ... --json . > "$out" 2> "$log" || code=$?
  if ! jq -e '.scores' "$out" > /dev/null 2>&1; then
    echo "FATAL: pana produced no score (exit code $code). Its stderr:" >&2
    cat "$log" >&2
    exit 1
  fi
  ...
```

Record the pin in `doc/TOOLCHAIN.md` with the other version pins.

### WR-07: A Markdown-only push runs no CI, so the two document drift gates do not guard the documents

**Classification:** WARNING
**File:** `.github/workflows/ci.yml:6-16`, `:265-275`; `CHANGELOG.md:50-54`
**Issue:** `paths-ignore` lists `**/*.md`. A push that changes only `README.md` (a hand edit
between the markers), only `doc/PRESETS.md` (new measurements) or only `MIGRATION.md` starts no
workflow run. The README drift gate and `test/migration_doc_test.dart` therefore never run for
the changes most likely to break them. CHANGELOG.md:51 says "A test keeps the guide in agreement
with the code" and `:54` says "A CI gate fails when the table is out of date" with no
qualification. 06-03 and 06-04 both noticed this and chose to leave it; it is recorded here
because the published CHANGELOG states the guarantee without the exception.

**Fix:** GitHub evaluates `paths-ignore` patterns in order and honours `!` negation, so:

```yaml
paths-ignore:
  - '.planning/**'
  - '**/*.md'
  - '!README.md'
  - '!MIGRATION.md'
  - '!doc/PRESETS.md'
```

If that is judged too risky to change before release, soften the two CHANGELOG sentences
instead ("... on the next push that changes code").

### WR-08: The integration cancel case races the encode it is cancelling

**Classification:** WARNING
**File:** `example/integration_test/video_compress_compat_test.dart:237-259`
**Issue:** The case waits for the first progress value below 100, then calls
`cancelCompression()`, then requires `isCancel == true`. Between the progress event and the
cancel reaching native there are two channel hops. On a fast host — the macOS runner measured
1.4 s for this exact clip at p1080 (`doc/PRESETS.md:187`) — the job can finish first, the call
resolves with `isCancel: false`, and the case fails with nothing wrong in the code. 06-02's own
summary names this as the likely failure. The runner script treats a failure with real test
output as genuine and does not retry it (`run_ios_integration_suites.sh:242-245`), so one lost
race fails the Apple job.

**Fix:** cancel without waiting for progress, which the shim supports because `_currentJob` is
set synchronously inside `compressVideo`:

```dart
final Future<MediaInfo> pending = VideoCompress.compressVideo(path, ...);
await VideoCompress.cancelCompression();
final MediaInfo info = await pending;
expect(info.isCancel, isTrue);
```

If the mid-flight cancel must be kept, use the longest corpus clip and accept either outcome
only when the output file's existence agrees with `isCancel`.

### WR-09: A personal email address and private host names ship inside the package

**Classification:** WARNING
**File:** `doc/RELEASE.md:28`; `.pubignore:30-37`
**Issue:** `doc/RELEASE.md` names the maintainer's personal Google address as the publishing
account. `doc/` is not excluded by `.pubignore`, so the file is part of the published archive
and of the public repository, where it is permanently harvestable. (The same address in
`darwin/compress_video.podspec` is the conventional author field and is a separate choice.)
`.pubignore` also lets through `tool/mac_run.sh`, `tool/mac_sync.sh` and `doc/TOOLCHAIN.md`,
which carry the private host names `dans-macbook-air` and `danserver`, plus the maintainer-only
release procedure itself. None of these is a credential; they are private details a package
user has no use for, and a published version can never be deleted.

**Fix:** write "your Google account" in `doc/RELEASE.md:28`, and add to `.pubignore`:

```
doc/RELEASE.md
doc/TOOLCHAIN.md
tool/mac_run.sh
tool/mac_sync.sh
```

Re-run `dart pub publish --dry-run` and pana afterwards; `tool/preset_table.dart` and
`tool/generate_preset_table.dart` must stay, because `test/preset_table_test.dart` imports one.

## Info

### IN-01: 06-04-SUMMARY states the wrong default shell; the gates are still fail-closed

**Classification:** WARNING-adjacent note, no defect in the code
**File:** `.github/workflows/ci.yml:319-321`
**Issue:** The summary says `bash -eo pipefail` "is how GitHub Actions runs a `run:` block".
That is the shell only when `shell: bash` is written explicitly; with no `shell:` key the
default on Linux is `bash -e {0}`, **without** pipefail. So in
`dart doc --dry-run 2>&1 | tee dartdoc.log` a crash of `dart doc` is masked by `tee`. The gate
still fails, because the following `grep -q "Found 0 warnings and 0 errors."` finds nothing.
**Fix:** add `shell: bash` to both new steps, so the local proof and the runner match.

### IN-02: CHANGELOG says the compat import has "the whole public surface"

**File:** `CHANGELOG.md:46-48`
**Issue:** MIGRATION.md lists nine incumbent names as "Not provided" (`Compress`, `channel`,
`initProcessCallback`, `setProcessingStatus`, `MediaMetadataRetriever`, `Enum`,
`MediaInfo.fromJson`, ...). **Fix:** "has the documented surface of `video_compress` 3.1.4;
MIGRATION.md lists the few names that are not provided".

### IN-03: `compressVideo` copies `CompressOptions` field by field

**File:** `lib/video_compress_compat.dart:381-398`
**Issue:** A field added to `CompressOptions` later is silently dropped here, with no compile
error. **Fix:** add `CompressOptions.copyWith`, or build the options directly from
`quality` with a `switch` so there is nothing to copy.

### IN-04: `compressProgress$` drops values sent while nobody is subscribed

**File:** `lib/video_compress_compat.dart:242-251`
**Issue:** The incumbent used a single-subscription controller, which buffers until the first
listener. The broadcast controller here drops. Code that subscribes after starting a
compression loses the early values. The dartdoc calls both differences "supersets"; this one is
not. **Fix:** document it next to the other two differences, in the class dartdoc and in
MIGRATION.md's `compressProgress$` row.

### IN-05: MIGRATION.md says a compression's output "is upright"

**File:** `MIGRATION.md:134` (against `:65` and 06-01 decision 2)
**Issue:** 06-01 left `orientation` null because "a transmuxed or copied output may still carry
rotation metadata". When never-larger returns a copy of a rotated input, the output is not
upright. **Fix:** "Not provided. Read `rotationDegrees` from `getMediaInfo(result.outputPath)`."

### IN-06: The last integration case depends on an earlier one having passed

**File:** `example/integration_test/video_compress_compat_test.dart:91-92`, `:292-308`
**Issue:** `deleteAllCache` reads `lowQualityOutputPath`, set by the LowQuality case. One
failure is reported as two. **Fix:** have the case produce its own output with `small_480p.mp4`.

---

_Reviewed: 2026-09-28T00:47:28Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
