# video_compress (jonataslaw/VideoCompress) — issue & PR research brief

Data: 233 issues (176 open / 57 closed, 2020-04-06 → 2026-07-01), 97 PRs (32 open / 65 closed), top-40 issues + all their comments read in full, all 32 open PRs read in full, plugin source (`lib/`, `android/`, `ios/`, `macos/`, ~1,560 lines) read. Master is at `69c0e3f` (2025-02-13, README-only merge); the last code change is `4abdb48` (2024-10-31, v3.1.4, "Removes references to v1 Flutter Android embedding classes"). `android/build.gradle` still pins `com.otaliastudios:transcoder:0.10.5`, AGP 8.1.1, Kotlin 1.9.10, compileSdk 34, JVM target 1.8.

Issue volume by year: 2020 49 · 2021 52 · 2022 46 · 2023 33 · 2024 29 · 2025 18 · 2026 6 (to July). Open PRs by year: 2020 5 · 2021 5 · 2022 2 · 2023 3 · 2024 3 · 2025 9 · 2026 5 — contributor activity is *rising* while maintainer activity has stopped.

Caveat: comments were only fetched for the top-40 issues; for the other 193 issues only title/body were searched.

---

## A. Clusters

Reaction totals below are summed 👍 on the issues named (from `issues.json`), not on comments.

### A1. Android build/toolchain rot — **64 reactions** (largest cluster)
Issues: #142 (open, 24, 2021-10), #265 "New Release?" (closed, 17, 2024-07), #262 namespace/AGP 8 (open, 10, 2024-03), #255 JVM-target 1.8 vs 17 (open, 9, 2024-02), #176 (open, 4, 2022-05), plus lower-ranked #128 (closed, 4), #130, #284, #302 (2025-04, "javac (17) and compileDebugKotlin (21)"), #323 "Migrate Plugin to Built-in Kotlin" (open, 2026-05, AGP 9 drops KGP).

Root cause: the plugin's `android/build.gradle` is only ever bumped when a contributor sends a PR and the maintainer wakes up (kotlin 1.3.31 → PR #129 merged 2021-08; AGP 8 namespace → PR #246 opened 2023-08, merged **2024-05**, published to pub.dev **2024-08** after #265). Each Flutter/AGP release re-opens the same wound: #142 and #176 and #128 and #130 are the identical Kotlin-1.3.40 error; #255/#284/#302 are the identical JVM-target error (plugin hard-codes `jvmTarget = "1.8"` while apps moved to 17/21); #323 is the next one (AGP 9). Classification: **(a) pure plugin rot**. Any maintainer fixes this by bumping versions and cutting a release — the fix for #142 sat on master for ~10 months (#142: "The real problem is that pub.dev contains a previous version of this library (3.1.0)").

Telling quotes: "@jonataslaw Could you cut a new release so we can avoid referring to `master`?" (#142, 2021-12). "The last update on pub.dev is 20 months old. The master branch here only 2." (#265, 2024-07). "Legendary! Two days fighting with Gradle, absolutely no info on the net, and only this reply to the rescue." (#262, 2025-02, on a hand-edit-your-pub-cache workaround with +24).

### A2. Transcoder artifact vanished from Maven — **24 reactions**
Issues: #240 (closed, 8, 2023-06), #247 (open, 8, 2023-08), #260 (closed, 6, 2024-03), #207 (open, 2, **29 comments**, 2022-11).

Root cause: the plugin pinned `com.otaliastudios:transcoder:0.9.1`, which was only on JCenter/plugins.gradle.org; JCenter went read-only, then the artifact disappeared ("the oldest one is 0.10.0" on mvnrepository, #207). Master had moved to 0.10.4 (PR #170, 2022-05) but was **rolled back to 0.9.1** by PR #189 (merged 2022-11) to dodge the muxer crash (A3), and pub.dev 3.1.2 shipped 0.9.1. It took PR #263 (0.10.5, merged 2024-05) and the 3.1.3 release (2024-08) to end it — 20 months of every new build failing. Classification: **(a) rot**, with a twist: the maintainer chose the old version deliberately because the new one crashed, so it is entangled with (c).

Quotes: "I can no longer build the application due to this failure." (#240). "Better stay with v3.1.1 until the issue resolved." (#207, +2). "It suddenly worked and then failed again." (#240, 2024-08).

### A3. Android runtime: muxer failure / silent `null` return — **16 reactions**
Issues: #191 "Failed to stop the muxer" (open, 8, 2022-08), #192 (open, 5), #193 "returns null value" (open, 2, 18 comments, 2022-08 → still "same problem, june 2025"), #203 (closed, 1), #300 (open, 1, 2025-03: "Using 3.1.4, compressVideo return null when includeAudio = true"), #309 (open, 2025-04, LG V40/S9/Note 9 negative-PTS crash, "please bump Transcoder to ≥ 0.10.11"), #319 / #326 (2025-12 / 2026-06, pipeline stuck in `State.Wait`), #288 "Not working on Pixel phones with Android 15" (open, 4, compress never returns).

Root cause: two layers. (c) The underlying `natario1/deepmedia Transcoder` library had a muxer/audio bug in 0.9.x–0.10.5 fixed in 0.11.x (PR #301 cites deepmedia/Transcoder#159; #309 cites the PTS fix). (b) The plugin *hides* every failure: `onTranscodeFailed(exception) { result.success(null) }` (`VideoCompressPlugin.kt:170-172`), so users see a bare `null` and no error (#193, #300, #222, #326). Only `includeAudio:false` avoids it. Classification: **(c) library bug × (b) design gap** — bumping transcoder to 0.11.2 (three open PRs do this) fixes the crash; surfacing the error (PR #329) fixes the diagnosis.

Quotes: "After some testing I figured that this error only happens if I use the parameter `includeAudio: true` … as you might understand, a video without audio loses its purpose." (#203). "its always returns null from my android device but its working fine in iPhone. buggy plugin." (#193). "For me, the issue was not solved and I solved it by shifting to ffmpeg_kit_flutter" (#191).

### A4. Android runtime: unsupported inputs (extractor / 6-channel audio / odd files) — **15 reactions**
Issues: #113 MediaExtractor IOException (open, 7, 2021 → "me too, 2024-07-11"), #279 "Input channel count not supported: 6" (open, 4, 2024-10), #83 IllegalArgumentException after `video_trimmer` (open, 2), #198 `setDataSource failed: 0xFFFFFFEA` on .avi/.mjpg — a **hard process crash** from `Utility.getMediaInfoJson` (open, 2), #194 (Instagram-downloaded videos won't start), #220/#312 (4K/8K), #298 HDR washed out.

Root cause: (c) Transcoder/MediaCodec limits — no 5.1 audio remix (fixed by 0.11.2 pass-through per PR #287), no Dolby-Vision decoder on some Pixels (PR #329's `DolbyVisionCompatDataSource`), HDR→SDR tone-mapping absent. But (b) too: `getMediaInfoJson` does `Long.parseLong(durationStr)` on possibly-null metadata and is called *inside the transcoder completion callback* with no try/catch, so an unreadable file kills the app (#198, #181 `NumberFormatException: null`). Classification: **(c) with (b) hardening gap**.

### A5. `deleteAllCache` → `kotlin.Unit` codec crash — **8 reactions**
#131 (open, 8, 2021-08), #221 (2023-01), #327 (2026-06). Root cause: `Utility.deleteAllCache(context, result)` calls `result.success(...)` itself, then the plugin wraps it in `result.success(<Unit>)` — a double reply (`VideoCompressPlugin.kt:66`, `Utility.kt:130-133`). Classification: **(b) plain plugin bug**, 3-line fix; three open PRs fix it independently (#123 2021, #293 2025, #321 2026). Five years unmerged.

### A6. iOS crashes (`Fatal error: Unexpectedly found nil` / `Null check operator`) — **19 reactions**
Issues: #184 (open, 7, 2022-07), #136 (open, 6, 2021-09), #109 (open, 4, 2021-05 → "it's almost 2025 and it's still happening"), #75 (open, 2, 2020), #318 (2025-11, same line 203), #82, #80, #35 swift.h (closed, 15 comments, still being commented in 2026-04).

Root cause (from source): `SwiftVideoCompressPlugin.swift:203` force-unwraps `sourceVideoTrack!` — nil when AVFoundation cannot read a video track (iCloud-placeholder from `AssetEntity.file`, damaged MOV, file with no metadata). Then `compressVideo` never checks `exporter.status`; on failure it calls `getMediaInfoJson` on the non-existent output, which returns `[:]`, so Dart's `MediaInfo.fromJson` hits `File(path!)` at `media_info.dart:43` → "Null check operator used on a null value" (#184/#136). Commenters found `includeAudio:false` triggers it (#184, +6) because that path uses the hand-built `AVMutableComposition`. Classification: **(b) plugin design gap** — no error propagation on iOS at all (the swallowed-error pattern from A3, mirrored). #35 (`video_compress-Swift.h` not found) is (a) toolchain: an ObjC shim that PR #325 deletes.

Quotes: "This issue is solved by replacing `AssetEntity.file` with `AssetEntity.originFile`" (#109, +3). "All videos capture with my iphone 11 crashing" (#75).

### A7. Output size / no quality control — **25 reactions**
Issues: #77 "Can we introduce a High quality?" (open, 7, 2020-12), #200 "Compressed video on Android phones is too large" (open, 7, 2022-10), #294 "instead of quality preset can we give a target bit-rate?" (open, 6, 2025-01), #60 Default == Medium (open, 5, 2020-10), #324 "720p compression grows 5 MB → 14 MB" (2026-06), #210 (Instagram-like 720×720 @ 600 kbps), #183, #224, #137, #216, #252.

Root cause (from source): iOS maps `DefaultQuality` (index 0) to the `default:` branch = `AVAssetExportPresetMediumQuality`, identical to `MediumQuality` (index 2) — so #60 is literally true on iOS. Android `DefaultQuality` = `atMost(720)` with Transcoder's *estimated* bitrate, iOS Medium = 568 px preset — hence 5 MB vs 28 MB for the same clip (#200). No bitrate/CRF/file-size knob exists on either platform. PR #119 (2021-07) added `Res640x480…Res1920x1080` presets, which answers #77 but the issue was never closed. Classification: **(b) design gap** — Transcoder's `DefaultVideoStrategy.bitRate()` and AVFoundation's `fileLengthLimit` are both available; three open PRs (#217, #219, #329) each expose them differently.

Quotes: "The Medium/Default quality compresses a 100mb video to ~1mb … The next available quality is 'Highest' which will return a ~45mb video, which way too large." (#77). "on android emulator i tried to compress 52 MB video it took 15 minutes and i got compress video of 82 MB" (#200).

### A8. Thumbnails — **8 reactions in top-40; 29 issues mention "thumbnail" repo-wide (27 open)**
Issues: #105 null-safety cast error (open, 8, 2021 — fixed on master 2021-04 by PR #103, never closed), #23 MissingPluginException (open, 14 comments), #275 same frame at every position (3), #274 filenames collide (2), #272, #107 "Position is not seconds, it is microseconds :)", #124, #201, #311 (2025-07), #291 Chinese filenames, #248 (thumbnails in an isolate).

Root cause (from source): Dart docs say `position` is milliseconds; Android passes it straight to `getFrameAtTime(position)` which wants **microseconds**; iOS does `CMTimeMakeWithSeconds(position)` — **seconds**. So the same number means three different things (PR #289 fixes). `getFileThumbnail` writes to `<basePath>/<sourceName>.jpg`, so multiple frames overwrite (#274). Android `getBitmap` ignores rotation metadata (PR #331). Classification: **(b) plain bugs**.

### A9. Trimming (`startTime`/`duration`) — **6 reactions in top-40; 28 issues match trim/startTime/duration**
Issues: #93 (open, 6, 2021-03), #127, #167, #304 (2025-04: "i set 10 seconds for 12 secs video and than it returns 2 seconds video"), #292, #297 "Native trimming" (2025-02: "With the depreciation off fmpeg_kit_flutter…").

Root cause (from source): iOS only applies `exporter.timeRange` when `!isIncludeAudio` (`SwiftVideoCompressPlugin.swift:217-219`) — trimming silently does nothing with audio on (PR #305, one-line fix). Android builds `TrimDataSource(source, startUs, durationUs)` but Transcoder's constructor is `(source, trimStartUs, trimEndUs)` — the second argument is *how much to cut from the end*, which exactly explains #304 (12 s − 10 s = 2 s). Neither open trimming PR (#133, #306) fixes that semantic. Classification: **(b) design/implementation bug**.

### A10. Progress / cancel / concurrency — **11 reactions (both closed)**
#21 (closed, 7), #66 (closed, 4), #259 (iOS never reaches 100), #271 (cancel returns null), #227/#317 (batch progress), #307 PR. Root cause: single global `compressProgress$` and one `transcodeFuture`/`exporter` per plugin instance; progress handler is only registered when the singleton is constructed (#21 "You have to call `VideoCompress()` constructor at least once"). Classification: mostly fixed historically; batch/concurrent is **(b)**.

### A11. Isolates / background — **7 reactions; 9 issues match**
#242 (open, 7, 2023-07), #248 (4), #143, #238, #185. Root cause: `CompressMixin` does `const MethodChannel('video_compress')` with no injectable `BinaryMessenger`, so it cannot run in a background isolate (`BackgroundIsolateBinaryMessenger` exists since Flutter 3.7). Classification: **(b)** — small API addition.

### A12. Platforms: Web / Windows / Linux — **12 + 3 + 2 reactions**
#163 Flutter Web (open, 12, 2022-02), #253 Windows/Linux (3), #278 Windows (2), #78 desktop, #277 (Windows MissingPlugin), PR #314 Linux. Root cause: plugin is AVFoundation + Android MediaCodec; there is no browser/Win/Linux equivalent without ffmpeg.wasm/WebCodecs or shelling out to ffmpeg. Classification: **(c) platform limitation** — a whole new backend per platform. Quote: "due to browser security restrictions, there is no access to path. So, is there a plan to support video compression from available byte data (Uint8List) instead?" (#163).

### A13. iOS/macOS toolchain: Swift Package Manager — **21 reactions, all 2026**
#322 (open, 12, 2026-03, Flutter-team template), #328 (open, 9, 2026-07), #290 (1, 2024-12). Classification: **(a) rot**; PR #325 does it cleanly.

### A14. Orientation / portrait black bars — **~10 reactions**
#195 black left half (3), #315 (2025-10, iPhone Live Photo portrait → half black), #85 square output (3), #172/#125/#90/#22 wrong width/height. Root cause (from source): `Utility.isLandscapeImage(o) = o != 90 && o != 270`, then swaps W/H when it returns **true** — inverted (#172 spotted this in 2022; PR #330 fixes 2026). iOS: `AVMutableVideoComposition(propertiesOf:)` with a custom `frameDuration` loses the preferred transform → portrait video rendered into a landscape canvas (PR #308). Classification: **(b) bugs**.

### A15. Misc
- Licensing #134 (open, 4): "Is this package safe for commercial use? … the h264 codec is patented by MPEG LA". Never answered by maintainer. README's "we do not use FFMPEG … the GNU license is an obstacle for commercial applications" is the plugin's main selling point, so this matters to its audience.
- Watermark/stitch #30 (open, 6) — out of scope for both native backends without a compositing layer; **(c)**.
- Null-safety #86 (closed, 15) — historical rot, took 2 months in 2021.
- gif→mp4 #67/#104 (2), PR #74.
- Output path #24 (2), #186, #229, #149 — PR #187.
- Privacy manifest #254, external-storage permission #241 ("Issue in uploading on playstore").

---

## B. Workarounds people use

**Point pubspec at git instead of pub.dev** — the single most-repeated advice: `git: url: https://github.com/jonataslaw/VideoCompress.git ref: master` (#142 "So far this is the only working solution"; #176 +5; #86 `ref: "583e700"`; #105; #203 — the maintainer himself asks users to test `ref: master` instead of publishing).

**Hand-edit the plugin in `~/.pub-cache`**: set `ext.kotlin_version = '1.3.40'` (#142, #176 "暂时可以通过修改本地库kotlin版本为1.3.40"); add `namespace` to the plugin's `build.gradle` (#262, +24 — the most-upvoted comment in the dataset).

**App-side Gradle hacks**: add `jcenter()` and/or `maven { url "https://plugins.gradle.org/m2/" }` to `allprojects` (#207 +18, +5; #240; #247 — stopped working when the artifact was purged: "seems like transcoder/0.9.1 version has removed from the servers"); add `implementation 'com.otaliastudios:transcoder:0.10.5'` to the *app* to override (#240 +2); `afterEvaluate { … jvmTarget = "1.8" }` for every Kotlin subproject (#255 +15, "maybe it'll get you out of Java Jail"); bump `org.jetbrains.kotlin.android` to 1.9.24 (#255 +14); `subprojects { afterEvaluate { namespace = group } }` in `build.gradle.kts` (#262 +7); downgrade AGP to 7.4.2/Gradle 7.5 (#262 +4).

**Forks named**: `SpectoraSoftware/VideoCompress` (#240, +2, "fully working on android and iOS", newer transcoder); `kamaravichow/VideoCompressPlus` = **video_compress_plus** on pub.dev (#240, #207 "just use video_compress_plus and put 21 in the min version"); `awaik/VideoCompress` (#77, adds 640/960/1280 presets — later merged as PR #119); `hm-toan/VideoCompress` v3.1.5 (PR #321, "maintained for Flutter 3.41+ compatibility"); `yanivshaked` ref (#86).

**Switch package**: `ffmpeg_kit_flutter` (#191); **`v_video_compressor`** (#193 +2, and #313 which is the author advertising it: "Media3 for Android, AVFoundation for iOS", 5 quality levels, real-time progress); **`light_compressor`** (#280 title is just "light_compressor 👍👍👍"); `flutter_video_info` for metadata (#125); `ffmpeg.wasm` suggested for web (#163).

**Runtime dodges**: `includeAudio: false` to avoid the muxer crash / null (#191, #193, #184 +6); `AssetEntity.originFile` instead of `.file` from photo_manager (#109 +3, #75); compress *then* trim rather than trim then compress (#83 +2); instantiate `VideoCompress()` once so the progress stream works (#21); `use_frameworks!` or `use_frameworks! :linkage => :static` in Podfile (#35); "make sure … you stop and re-run the project and not just hot reload" (#23); upgrade to 3.1.3 (#207, 2024-08, +2).

---

## C. Open PRs (32)

One line each — what / mergeable? / closes. "Stale" = base moved under it; `mergeable=False` is GitHub's flag.

| PR | Date | What it does | Verdict | Closes |
|---|---|---|---|---|
| #40 | 2020-09 | V2 embedding + isolate registration | **Obsolete** — done by merged #44 (2020-10) | #33 |
| #51 | 2020-10 | README: instantiate `VideoCompress()` for progress | Obsolete (API changed) | #21 |
| #64 | 2020-10 | Copy example app from rurico/flutter_video_compress; commits generated files | Not mergeable (conflicts, checked-in `.flutter-plugins-dependencies`) | — |
| #74 | 2020-11 | gif→mp4 on Android via `com.otaliastudios.gif:compressor` | Feature; pre-null-safety, transcoder 0.9.1 era; needs rewrite | #67, #104 |
| #76 | 2020-11 | `num` start/duration; flips iOS `if !isIncludeAudio` → `if isIncludeAudio`; fixes cancel/timer | Right ideas, pre-null-safety code, conflicts | #93 (partly), #81 |
| #98 | 2021-04 | "Better example" + adds **`required String into`** to `compressVideo` + logs `exporter.status` | Not mergeable — breaking API smuggled in with example noise | — |
| #123 | 2021-07 | Fix `deleteAllCache` double-reply; *also* removes the W/H rotation swap; locale-safe filename | Core fix correct; rotation change conflicts with #330; stale | #131 |
| #133 | 2021-09 | Change trim multiplier `1000*1000` → `100*100` | **Wrong** (10⁴ µs ≠ seconds); reject | claims #127 |
| #139 | 2021-10 | `private fun init` → public | Obsolete since v1 embedding removed (3.1.4) | — |
| #145 | 2021-11 | Output filename `System.currentTimeMillis()` (no spaces) | Small, sensible; 3.1.2 worked around it in Dart instead | #237, #94 |
| #187 | 2022-08 | Adds **required** `destPath` param; deprecates `deleteAllCache` | Breaking (required); should be optional; touches example | #186, #24, #229, #149 |
| #188 | 2022-08 | `rotation:` param; Android `setVideoRotation`; iOS rewrites composition | Android half is 1 line and fine; iOS half is a large untested rewrite; conflicts with #308 | #162, #47 |
| #217 | 2023-01 | `AndroidOptions.bitrate`, `IosOptions.fileLengthLimit`, frameRate applied to all Android qualities, `canPerformMultiplePassesOverSourceMediaData` | Reasonable design; `mergeable=True`; conflicts with #219/#329 | #294, #77 |
| #219 | 2023-01 | `bitRate`/`outputWidth`/`outputHeight` + `VideoQuality.CustomQuality` (Android only); bumps transcoder 0.10.4 | Android-only, 153-line rewrite of the `when`; conflicts with #217/#329 | #294, #216, #62 |
| #228 | 2023-03 | README typo | Trivially mergeable | — |
| #285 | 2024-10 | **Downgrade** Dart SDK to `<3.0.0`, Kotlin to 1.7.10 | Reject | — |
| #287 | 2024-11 | "Release 3.1.5": transcoder **0.11.2**, AGP 8.2.2, Gradle 7.6.3, plus an R8 classpath hack in README/settings | Transcoder bump is right; R8 hack + `enableR8.fullMode=false` are noise; duplicates #301/#321 | #279, #191/#192/#300, #309 |
| #289 | 2024-11 | Thumbnail `position` → ms on Android (×1000) and iOS (/1000); also drops `library` directive, Dart 3 super-params | Correct, small, `mergeable=True` | #107, #275, #311, #124, #201 |
| #293 | 2025-01 | `deleteAllCache` double-reply fix (3 lines) | Correct, minimal | #131, #221, #327 |
| #301 | 2025-03 | transcoder 0.11.2 + example Gradle 8.3/AGP 8.1.0 | Correct, minimal (3 lines); the cleanest of the three bumps | #300, #191, #192, #193, #279, #309 |
| #303 | 2025-04 | `getFileThumbnail` returns `File?` | Breaking return type; masks rather than reports; also reformats unrelated code | #272 |
| #305 | 2025-04 | Remove `if !isIncludeAudio` around `exporter.timeRange` | Correct 1-line fix | #93 |
| #306 | 2025-04 | start/duration in **ms** instead of s (both platforms) | Silent semantic change of a public param; still passes duration as Transcoder's `trimEndUs` | #292 (no) |
| #307 | 2025-04 | Delete `isCompressing` guard for concurrent compress | Risky: one `transcodeFuture`/`exporter` and one progress stream per plugin, so cancel/progress break under concurrency | #317 (no) |
| #308 | 2025-04 | iOS: render portrait correctly when `frameRate` set (renderSize + layer transform) | Plausible and targeted; conflicts with #188 | #195, #315, #85 |
| #310 | 2025-07 | try/catch around `Uri.decodeFull` in thumbnail path | Tiny, defensive; fine | #291 |
| #314 | 2025-08 | **Linux** via `posix_spawn`'d `ffmpeg` binary; 1,212 lines (≈470 generated example/linux, 96 CMake, 562 C++) | Incomplete by its own TODO (no mediainfo, progress, thumbnails, log level); debug `printf("KEY:")`; a `va_arg` type-switch has `FL_VALUE_TYPE_INT` twice (string case unreachable); depends on user-installed ffmpeg — README claims "100% native code, no FFMPEG" | #253 (partial) |
| #321 | 2026-03 | AGP 8.7 (build.gradle) / 8.11.1 (example), Gradle 8.13, Kotlin 2.1.0, compileSdk 36, JVM 17, transcoder 0.11.2, manifest `package` removed, `deleteAllCache` fix, CI workflow | Substantively right, but rebrands README/homepage to the hm-toan fork — needs those hunks dropped; still `apply plugin: 'kotlin-android'` so does **not** address #323 | #255, #262, #302, #131, #279, #300 |
| #325 | 2026-06 | SPM for iOS+macOS; removes ObjC shim; renames `SwiftVideoCompressPlugin`→`VideoCompressPlugin`; min iOS 12 / Flutter 3.41 | Clean, follows Flutter guide, 6 👍; the Flutter floor bump is the only debate | #322, #328, #290, #35, #148 |
| #329 | 2026-07 | Dolby-Vision→HEVC mime remap; `bitRate` for `Res1280x720Quality`; iOS `fileLengthLimit`; **`onTranscodeFailed` → `result.error`** | Good; the error-surfacing alone is the most valuable 3 lines in the queue; bitrate only wired for one enum value | #193 (diagnosis), #294 (partly), #298-class HDR |
| #330 | 2026-07 | Invert the W/H swap condition | Correct 1-liner (matches #172's 2022 diagnosis) | #172, #125, #90, #22 |
| #331 | 2026-07 | Rotate thumbnail bitmap by `METADATA_KEY_VIDEO_ROTATION` | Correct; Korean comments | portrait thumbnails |

Note: PR #320 (closed, 2026-03) is the same author/title as #321 — a resubmit, not a separate change.

### What merging only the last-12-month PRs buys (since 2025-09-14: **#321, #325, #329, #330, #331**)
- Builds again on current Flutter/AGP/Kotlin and adds SPM (A1 + A13 — the two biggest clusters, ~85 reactions between them).
- Transcoder 0.11.2 → muxer / 6-channel / negative-PTS crashes (A3, A4).
- `deleteAllCache` fixed (A5).
- Android failures finally reported instead of `null` (A3 diagnosis).
- Width/height and thumbnail orientation on Android (A14).
- Partial bitrate/file-size control (A7, one enum value only).
- **Not** bought: thumbnail position units (#289), iOS trimming with audio (#305), iOS portrait black bars (#308), isolates, web. Also need to strip fork branding from #321 and it still doesn't do built-in-Kotlin for AGP 9 (#323).

### What the last ~24 months buys (adds #285 reject, #287, #289, #293, #301, #303, #305, #306, #307, #308, #310, #314)
Everything above plus thumbnail positions (#289), iOS trim (#305), iOS portrait rendering (#308), defensive thumbnail path (#310). #287/#293/#301 are duplicates of what #321 already contains. #303/#306/#307 should be declined or redone (breaking/risky). #314 needs finishing before it is a real Linux backend.

### Conflicts
- **Transcoder bump ×3**: #287, #301, #321 (and #219 to 0.10.4, stale). Pick #321 or #301.
- **`deleteAllCache` ×3**: #123, #293, #321.
- **Bitrate/quality ×3**: #217 (options objects, both platforms), #219 (flat params + `CustomQuality`, Android only), #329 (flat `bitRate`/`fileLengthLimit`, minimal). All touch the same `when(quality)` block and the Dart signature; mutually exclusive. #217's shape is the most complete; #329's is the least invasive.
- **Trimming ×4**: #76, #133 (wrong), #305, #306. #305 is the safe one; the Android `trimEndUs` semantic is fixed by none.
- **Rotation ×3**: #123 (remove swap), #330 (invert swap), #188 (add rotate param). #123 and #330 are mutually exclusive; #330 is right.
- **iOS composition ×2**: #188 vs #308 rewrite the same `videoComposition` block.
- **Thumbnail ×4**: #289 (units), #303 (nullable), #310 (decode), #331 (rotate) — #289/#303/#310 all edit `getFileThumbnail` in `video_compressor.dart`.
- **Example app ×3**: #64, #98, #187 each rewrite `example/lib/main.dart`.
- **SPM**: only #325 open; #321's ObjC-shim removal is not there, so no conflict.

---

## D. Wishes vs breakage

Rough regex split of all 233 titles: **31 build/toolchain**, **64 runtime crash/error/null/not-working**, **27 explicit feature requests**, 111 other (mostly further runtime/behaviour bugs like "returns null", "too slow", "wrong width"). By *reactions* the picture is starker: the top 10 issues by 👍 are 7 build/release (#142 24, #265 17, #86 15, #322 12, #262 10, #255 9, #328 9) + 1 dependency (#240/#247 8 each) + 1 platform wish (#163 12). **Breakage dominates demand; wishes dominate the long tail.**

Keyword counts over all 233 issues (title+body regex; open count in parentheses):

| Topic | Issues | Examples |
|---|---|---|
| thumbnail | 29 (27 open) | #105 (8), #275 (3), #274 (2), #311, #248 |
| progress | 28 (18) | #21 (7), #184, #259, #227, #317 |
| trim / startTime / duration | 28 (21) | #93 (6), #297 (2), #304, #292, #127 |
| audio | 26 (17) | #279 (4), #179 (2), #196, #319, #102, #225 |
| crash / fatal | 26 (20) | #109 (4), #82 (3), #198, #318, #309 |
| large / too big / file size | 16 (11) | #200 (7), #77 (7), #324, #224, #137 |
| frame rate / fps | 15 (10) | #77, #217-class |
| resolution / custom size / 1080 / 4K | 14 (10) | #77 (7), #60 (5), #85 (3), #42 (3), #216 (2), #220, #312 |
| cancel | 12 (9) | #82, #81, #271, #251 |
| rotation / orientation | 9 (7) | #172, #125, #162, #47, #315, #195 |
| isolate / background | 9 (7) | #242 (7), #248 (4), #143, #238, #185 |
| bitrate | 8 (5) | #294 (6), #210, #220 |
| web / browser / wasm | 6 (5) | #163 (12) |
| HDR / Dolby | 5 (3) | #298, #220, #329-PR |
| Swift PM / CocoaPods / Podfile | 5 (5) | #322 (12), #328 (9), #290 |
| gif | 2 (2) | #67 (2), #104 |
| HEVC / H.265 | 1 (0) | #313 only (a marketing post) — **nobody has asked for HEVC output** |
| watermark | 1 (1) | #30 (6) |
| gradle / build failed / kotlin | 35 (24) | #142, #255, #262, #247, #207 |
| otaliastudios / transcoder | 35 (25) | #265, #247, #240, #191, #113 |

**Top wishes by reactions**: Flutter Web #163 (12) · SPM #322/#328 (12+9, arguably breakage-in-waiting) · isolate #242 (7) · "High" quality #77 (7) · target bitrate #294 (6) · watermark/stitch #30 (6) · Windows/Linux #253/#278 (3+2) · custom width/height #216 (2) · output path #24 (2) · gif #67 (2) · native trimming #297 (2, "with the deprecation of ffmpeg_kit_flutter") · batch #317 · HDR #298 · background #238 · privacy manifest #254 · desktop #78 (1).

Reading the wishes together: people want **one knob for output size** (bitrate / file-size cap / "High" / custom resolution — #77, #294, #200, #216, #210, #137, #224 are the same wish), **control of where the file goes and what it is called** (#24, #186, #149, #229, #274), and **to run it off the main isolate** (#242, #248, #238, #185). Nobody asks for codecs (HEVC/AV1) or filters beyond #30.

---

## E. Who is reporting

Counts (title+body regex, all 233): **firebase 7** (#105, #143 Crashlytics dumps; #33 firebase_messaging conflict; #68 "when I upload the video on firebase"; #181 `FireStoreMethods()`; #4 firebase storage; #284) · **s3/aws 1** regex hit, and it is a log dump in #169 — effectively **0 genuine S3 mentions** · **upload 12** (#203, #279, #281, #151, #241, #150, #181, #68, #121 …) · **server/backend 17** regex hits, of which the genuine "we upload to our server" ones are #203, #288, #281, #151 · **chat/messaging 25** regex hits but almost all are `StandardMessageCodec`/`onMessage` stack frames; genuine chat apps: #150/#149/#151 (same author, `group_chat.dart`) · **union of firebase/s3/upload/server/backend/chat: 25 issues**.

Concrete evidence of what apps are built on this plugin:

- **Upload-to-server pipeline (the default use)**: "I have a mobile app in Flutter where I allow users to upload videos. I compress them using `video_compress: ^3.1.1` and then upload them to a server." (#203, 2022). "I'm also compressing videos with this package and then upload, one user can't upload anything, among like 2 TB uploads. I see from Intercom … his device is also Samsung S9 and Android 10." (#198 comment, 2022 — a production app with ~2 TB of uploads and Intercom support). "I could see it from logs sent to the server from the user phone that the compress method never returns" (#288, 2024). "// Upload the video to the server" in the body of #281. "callers with strict upload size limits" (PR #329, 2026).
- **Chat / social**: `nritya-user-app/lib/screens/group_chat.dart` in the stack of #150 (2021; same dev files #149, #151 — "I want to upload a video from local storage to server"). `com.example.socialnetworkapp` in #181 ("When I use Compression on voice"). `applicationId "com.kushalgupta.tiktok"` in #207 (a TikTok clone). "I want to compress it to an Instagram-like 720x720 video at around 600kbps" (#210). "Whatever videos i saved from instagram by external app are not compressing" (#194).
- **Share-sheet ingestion**: "My app is taking file from sharing intent (receive_sharing_intent) and compressing it" (#80).
- **Vertical/camera-first apps**: `package:apiir_bikefit/pages/record/video_page.dart` (#184 — a bike-fitting app recording the rider); "I use the «camera» package and my app has lock a portraitUp orientation, thats why all my videos has a wrong orientation" (PR #188); "a video extracted from an iPhone Live Photo" (#315); `package:happy_sing` on macOS with `.mkv` (#184 comment — a singing app).
- **Live video**: "Compression for Live Video Call" (#79).
- **IRC client on Android/iOS/Linux** — the Linux PR: "I would like to use your library in a IRC client i'm helping build. The client targets android, ios and linux, and we do most of the testing on linux" (PR #314).
- **Store-review pressure**: "please remove the write external storage permission in mainfest … Issue in uploading on playstore" (#241); "Plans for Implementing Privacy Manifest Support?" (#254).
- **Why they chose it**: speed and licence. "I have used the FFmpeg library and also Flutter_video_compress library to do the compression but they are very slow" (#23); "Is this package safe for commercial use? … the h264 codec is patented by MPEG LA" (#134); but also "it seems it is almost as slow as FFMpeg … To convert a 1 minute video, the time is around 40s" (#99).
- **Competitor authors in the tracker**: `hatemragab` commented in #35 (2020), recommended `v_video_compressor` in #193 (2025-07, +2) and posted its README as #313 — a five-year user who wrote a replacement.

Summary of the audience: consumer mobile apps that record or pick a clip and push it to their own backend (chat, social/TikTok-style, fitness, marketplace-ish "user uploads"), Firebase-heavy, mostly Android-first pain, small teams (one dev per issue, no company names except the SpectoraSoftware fork and the Inspectly reporter of #240). Nobody in the tracker mentions telehealth, S3, or enterprise.
