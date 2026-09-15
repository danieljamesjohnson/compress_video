# video_compress — what it is, who needs it, and whether to rebuild it

Research brief, 2026-09-14. Follows [FINDINGS.md](../../../../pubdev-stale-scan/FINDINGS.md) (2026-09-11), which picked
`video_compress` as the best abandoned-but-used pub.dev package. Nothing was built. Every number
is from the pub.dev API, the GitHub API, the repo source, or a linked page; headline counts are
reused from FINDINGS.md rather than re-derived. The long-form working notes are committed next
to this file: [issues and PRs](sources/issues-and-prs.md) (every cluster and all 32
PRs, one line each), [who uses it](sources/who-uses-it.md) (dependents, SDKs,
StackOverflow), [competitors and native APIs](sources/competitors-and-native-apis.md).

## 0. The short version

**What it is.** A Flutter plugin with one job: take a video the user just recorded or picked,
make it much smaller, hand back the new file. Also: grab a poster-frame thumbnail and read
duration/size/dimensions. On Android it wraps a third-party MediaCodec library
([deepmedia/Transcoder](https://github.com/deepmedia/Transcoder)); on iOS/macOS it wraps Apple's
built-in `AVAssetExportSession`. About 1,600 lines of code in total, roughly a third each Dart, Kotlin and Swift (the macOS plugin is a copy of the iOS one).

**Who needs it.** Any app where a phone video leaves the phone: chat clients, TikTok-style
feeds, KYC selfie videos, inspection and incident reporting, marketplace listings. iOS's picker
shrinks videos for free; Android's does not, so Android uploads are roughly 3× bigger until the
app compresses them ([SO 53290269](https://stackoverflow.com/questions/53290269/how-to-compress-a-video-in-flutter)).
What they get: shorter progress bars, fewer failed uploads on cellular, and a smaller Firebase
egress bill, which is charged per viewer ([Firebase pricing](https://firebase.google.com/pricing):
$0.12/GB downloaded).

**What is wrong with it.** The maintainer is the GetX author and has effectively stopped:
last code change 2024-10-31, 0 PRs merged in 12 months, 32 open PRs, 176 open issues. The
complaints are dominated by *rot* (builds break on each new Android toolchain) and by a design
choice to swallow every native error and return `null`. The wishes collapse to one missing knob:
control over output size (target bitrate or file size).

**Verdict (details in §6).** It is a real, current, beatable gap. The work is about one third
plumbing (build tooling, Swift Package Manager, method channels) and two thirds genuinely
interesting media engineering (bitrate strategy, rotation, HDR, passthrough, cancel semantics).
It is a good portfolio story if the v1 is *the one-call compressor that never makes a file
bigger, never returns null, and builds on today's Flutter*. It is a poor one if it becomes
"the sixth fork with a version bump".

## 1. What it actually is

### The API (from `lib/src/video_compress/video_compressor.dart`)

| Call | What it does |
|---|---|
| `VideoCompress.compressVideo(path, quality:, deleteOrigin:, startTime:, duration:, includeAudio:, frameRate:)` | Transcodes to a new MP4 in the app's temp/cache dir and returns `MediaInfo` (path, width, height, duration, filesize). Throws if a compression is already running. |
| `VideoQuality` enum | `DefaultQuality, LowQuality, MediumQuality, HighestQuality, Res640x480Quality, Res960x540Quality, Res1280x720Quality, Res1920x1080Quality` |
| `compressProgress$.subscribe(...)` | 0–100 progress stream (one global stream for the whole app). |
| `cancelCompression()` | Cancels the single in-flight job. |
| `getMediaInfo(path)` | Duration, dimensions, orientation, file size, title/author. |
| `getByteThumbnail` / `getFileThumbnail(path, quality:, position:)` | JPEG poster frame, in memory or on disk. |
| `deleteAllCache()`, `setLogLevel()` | Housekeeping. |

Every native error is caught in `_invoke` and printed with `debugPrint`, so callers see `null`,
not an exception ([video_compressor.dart:35-46](https://github.com/jonataslaw/VideoCompress/blob/master/lib/src/video_compress/video_compressor.dart)).
That one decision is behind the largest runtime cluster in the tracker (§3).

### Android: what each preset really does

`android/src/main/kotlin/.../VideoCompressPlugin.kt` maps the enum to a Transcoder
`DefaultVideoStrategy`. Transcoder (pinned at `com.otaliastudios:transcoder:0.10.5`, released
2023-02-20) uses hardware `MediaCodec` encoders, always outputs H.264 + AAC in MP4, physically
rotates frames so the output carries no rotation metadata, and when no bitrate is given estimates
one as `0.07 × 2 × width × height × fps`
([BitRates.java](https://github.com/deepmedia/Transcoder/blob/main/lib/src/main/java/com/otaliastudios/transcoder/internal/utils/BitRates.java)).
Frame rate is capped at 30 fps (`min(input, 30)`). Audio is re-encoded to AAC at the input's
bitrate, never passed through.

| Preset | Android rule (`DefaultVideoStrategy`) | Result for a 1920×1080 input | Estimated bitrate |
|---|---|---|---|
| `DefaultQuality` | short side ≤ 720 | 1280×720 | ≈ 3.9 Mbps |
| `LowQuality` | short side ≤ 360 | 640×360 | ≈ 0.97 Mbps |
| `MediumQuality` | short side ≤ 640 | 1136×640 | ≈ 3.1 Mbps |
| `HighestQuality` | no resize, fixed 3,686,400 bps, keyframe every 3 s | 1920×1080 (or 4K stays 4K) | 3.7 Mbps fixed |
| `Res640x480Quality` | ≤ 480 × 640 | 640×360 | ≈ 0.97 Mbps |
| `Res960x540Quality` | ≤ 540 × 960 | 960×540 | ≈ 2.2 Mbps |
| `Res1280x720Quality` | ≤ 720 × 1280 | 1280×720 | ≈ 3.9 Mbps |
| `Res1920x1080Quality` | ≤ 1080 × 1920 | 1920×1080 | ≈ 8.7 Mbps |

Bitrates are the Transcoder formula at 30 fps; the plugin never sets one except for
`HighestQuality`. Two consequences users hit: `HighestQuality` on a 4K clip re-encodes 4K at
3.7 Mbps (blocky), and a 720p source at `DefaultQuality` gets ~3.9 Mbps, which can be *larger*
than a well-encoded original (issue [#200](https://github.com/jonataslaw/VideoCompress/issues/200):
"52 MB video … 15 minutes … 82 MB"). Transcoder also passes the video track through untouched if
the input is already within size, fps and keyframe limits, so "compression" sometimes changes
nothing.

Trimming is wrong on Android: the code calls `TrimDataSource(source, startUs, durationUs)` but
the library's second argument is *how much to cut from the end*
([TrimDataSource.java:28](https://github.com/deepmedia/Transcoder/blob/main/lib/src/main/java/com/otaliastudios/transcoder/source/TrimDataSource.java)),
which is exactly what [#304](https://github.com/jonataslaw/VideoCompress/issues/304) reports
("10 seconds for 12 secs video … returns 2 seconds video"). No open PR fixes this.

### iOS/macOS: presets are Apple's presets

`ios/Classes/SwiftVideoCompressPlugin.swift` builds an `AVAssetExportSession` with
`shouldOptimizeForNetworkUse = true` and maps the enum to Apple presets: Low → `AVAssetExportPresetLowQuality`,
Medium → `MediumQuality`, Highest → `HighestQuality`, the four `Res…` values → the matching
`640x480 / 960x540 / 1280x720 / 1920x1080` presets. `DefaultQuality` falls into the `default:`
branch, which is `MediumQuality`, so Default and Medium are identical on iOS
([#60](https://github.com/jonataslaw/VideoCompress/issues/60)). There is no bitrate control at
all because `AVAssetExportSession` presets do not expose one (only `fileLengthLimit`, unused).
Output is always H.264 MP4; the HEVC presets exist but are not used. Progress is a 0.1 s timer
polling `exporter.progress`; cancel calls `cancelExport()`. The export status is never checked,
so a failed export falls through to reading metadata of a file that does not exist, which is the
"Null check operator used on a null value" crash ([#184](https://github.com/jonataslaw/VideoCompress/issues/184),
[#136](https://github.com/jonataslaw/VideoCompress/issues/136)). Trimming only applies when
`includeAudio` is false (a one-line bug, PR [#305](https://github.com/jonataslaw/VideoCompress/pull/305)).
The macOS plugin is a copy of the iOS file with `UIImage` swapped for `NSBitmapImageRep`.

### Other things the source tells you

- Thumbnail `position` is documented as milliseconds, passed to Android as microseconds and to
  iOS as seconds (three meanings for one number; PR [#289](https://github.com/jonataslaw/VideoCompress/pull/289)).
- Android `getMediaInfo` swaps width/height for rotation 0/180 instead of 90/270 (inverted
  condition; PR [#330](https://github.com/jonataslaw/VideoCompress/pull/330)). FluffyChat carried
  a workaround for this for a year (§2).
- `deleteAllCache` replies to the method channel twice and crashes with "Unsupported value
  kotlin.Unit" ([#131](https://github.com/jonataslaw/VideoCompress/issues/131), open since
  2021, three separate PRs fix it).
- The plugin cannot run in a background isolate (hard-coded `MethodChannel`, no injectable
  messenger; [#242](https://github.com/jonataslaw/VideoCompress/issues/242)).
- Build config: AGP 8.1.1, Kotlin 1.9.10, compileSdk 34, `jvmTarget = "1.8"`, minSdk 21, iOS
  deployment target 8.0, CocoaPods only (no Swift Package Manager). Transcoder itself has moved
  to `io.deepmedia.community:transcoder-android:0.11.2` (2024-11-05).

### History

Created 2020-03-29 by jonataslaw (publisher `getx.site`), MIT licence, 262 stars, 344 forks,
40 contributors. Commits by year: 74 / 28 / 28 / 3 / 12 / 2 (2020→2025). Releases: 0.1.0
(2020-03) … 3.1.2 (2022-11), 3.1.3 (2024-08), 3.1.4 (2025-02-13). The 3.1.3 release came
21 months after 3.1.2 and only after issue [#265 "New Release?"](https://github.com/jonataslaw/VideoCompress/issues/265)
(17 reactions). Sources: [pub.dev API](https://pub.dev/api/packages/video_compress), `git log`.

## 2. Who uses it and for what

**Scale.** 170,009 downloads/30d and 747 likes (../../../../pubdev-stale-scan/FINDINGS.md). GitHub's dependency graph lists
"3,094 repositories, 51 packages" ([dependents page](https://github.com/jonataslaw/VideoCompress/network/dependents));
code search for `video_compress:` in `pubspec.yaml` returns 1,224 files versus 23 for
`light_compressor:` and 428 for `ffmpeg_kit_flutter_new:`. 40 published pub.dev packages depend
on it ([pub.dev search](https://pub.dev/api/search?q=dependency%3Avideo_compress)). Of 418
unique dependent repos sampled, 164 (39%) were pushed in 2026, so the base is live.

**Kinds of apps** (hand-classified top 70 dependents by stars): social / short-video feed 22
(mostly TikTok clones descended from
[RivaanRanawat/tiktok-flutter-clone](https://github.com/RivaanRanawat/tiktok-flutter-clone),
400★), chat / messaging 16, templates and libraries 9, then one or two each of education,
medical, fitness, dating, marketplace, field reporting. The long tail adds delivery-driver apps,
inspection and incident reporting, and KYC.

**Named users.**
- Chat: [OpenIM demo](https://github.com/openimsdk/openim-flutter-demo) (442★),
  [Mixin Messenger desktop](https://github.com/MixinNetwork/flutter-app) (329★),
  [Twake on Matrix](https://github.com/linagora/twake-on-matrix) (166★, Linagora),
  [Extera](https://github.com/ExteraApp/Extera), [Keychat](https://github.com/keychat-io/keychat-app),
  [imboy](https://github.com/imboy-pub/imboy-flutter), [nebuchadnezzar](https://github.com/ubuntu-flutter-community/nebuchadnezzar),
  Easemob's [chat UIKit](https://github.com/easemob/easemob-uikit-flutter) (`em_chat_uikit`).
- Feeds: [DTubeGo](https://github.com/dtube/DTubeGo), [flutter-instagram-offline-first-clone](https://github.com/itsezlife/flutter-instagram-offline-first-clone) (264★), LikeMinds feed SDK.
- Package-level dependents are mostly **KYC/liveness SDKs** that shrink a selfie video before
  POSTing it: `trustchex_flutter_sdk` (927 dl/30d, the largest), `myaza_kyc_sdk_flutter`,
  `biometry`, `intp_flutter_liveness_sdk`; plus MyCover.ai's insurance/vehicle-inspection SDKs,
  Zebra's and Take Blip's design systems, and a dozen media pickers.
- The mainstream chat SDKs (`stream_chat_flutter`, Flyer, `chatview`, Sendbird, Zego, Tencent)
  bundle **no** video compressor and leave it to the app, which is why the app-level dependents
  are dominated by chat clients.

**The key signal: a flagship user just left.** FluffyChat, the most popular Flutter Matrix
client, used the package from 2021, carried a workaround for the reversed width/height bug from
2025-06, and on 2026-08-17 merged
[PR #3405 "replace video compress package with light compressor"](https://github.com/krille-chan/fluffychat/pull/3405)
(now `light_compressor_v2`). Twake guards against the plugin making files *bigger* with an
explicit `compressedSize < videoInfo.fileSize` check in its send path.

**What they are trying to accomplish** (issue and StackOverflow text, verbatim):
- Upload pipeline: "I allow users to upload videos. I compress them using video_compress and
  then upload them to a server" ([#203](https://github.com/jonataslaw/VideoCompress/issues/203));
  "one user can't upload anything, among like 2 TB uploads" ([#198](https://github.com/jonataslaw/VideoCompress/issues/198), a production app).
- Target size, not presets: "20MB ----> I want to compress this video to be 2MB maximum … I
  cannot give a limit" ([SO 59246836](https://stackoverflow.com/questions/59246836/compress-videos-in-flutter));
  "Instagram-like 720x720 video at around 600kbps" ([#210](https://github.com/jonataslaw/VideoCompress/issues/210)).
- Speed: ">1 minute to compress a 100 MB file … What I want is something closer to Telegram's
  behavior: passthrough/remux if the video is already H.264/AAC ≤ 720p/30fps"
  ([SO 79757413](https://stackoverflow.com/questions/79757413/), 2025-09).
- Maintenance as a purchasing criterion: "none work well once a video gets around 300MB … PR's
  not being pulled in and issues not being resolved" ([SO 71027684](https://stackoverflow.com/questions/71027684/)).
- Why they chose it: "I have used the FFmpeg library … but they are very slow" ([#23](https://github.com/jonataslaw/VideoCompress/issues/23));
  the README's "100% native code, we do not use FFMPEG … the GNU license is an obstacle for
  commercial applications"; and licensing worry "the h264 codec is patented by MPEG LA"
  ([#134](https://github.com/jonataslaw/VideoCompress/issues/134), never answered).

**What a good compressor unlocks.** Phone video is big: roughly 65 MB per minute at iPhone
1080p/30 ([MacRumors quoting Apple's settings screen](https://www.macrumors.com/how-to/save-storage-space-recording-video-iphone-ipad/));
a FlutterFlow thread reports "30-second videos often exceed 100MB" and "a feed of 10 videos can
cause a 2GB download spike from Firebase"
([thread](https://community.flutterflow.io/ask-the-community/post/huge-video-file-sizes-please-go-away-on-device-video-compression-for-bJGE6qMcoBbAibN)).
Egress is billed per viewer, so a feed app pays size × views. The compressor is the difference
between a send that feels like Telegram and one that fails on the train.

## 3. What is broken and what people wish for

Read in full: the top 40 issues by reactions+comments with all their comments, and all 32 open
PRs with diffs. Counts below are over all 233 issues (title+body regex) unless stated.

### Clusters, largest first (reactions are summed 👍 on the issues named)

| Cluster | Reactions | Representative issues | Rot / gap / library? |
|---|---|---|---|
| Android build/toolchain rot (Kotlin version, AGP 8 namespace, JVM target, AGP 9 built-in Kotlin) | 64 | [#142](https://github.com/jonataslaw/VideoCompress/issues/142) (24), [#265](https://github.com/jonataslaw/VideoCompress/issues/265) (17), [#262](https://github.com/jonataslaw/VideoCompress/issues/262) (10), [#255](https://github.com/jonataslaw/VideoCompress/issues/255) (9), [#323](https://github.com/jonataslaw/VideoCompress/issues/323) (2026-05, next one) | **Rot.** Fixes sat on master 10–20 months before a release. |
| Output size / no quality control | 25 | [#77](https://github.com/jonataslaw/VideoCompress/issues/77) (7), [#200](https://github.com/jonataslaw/VideoCompress/issues/200) (7), [#294](https://github.com/jonataslaw/VideoCompress/issues/294) (6), [#60](https://github.com/jonataslaw/VideoCompress/issues/60) (5), [#324](https://github.com/jonataslaw/VideoCompress/issues/324) | **Design gap.** Both native APIs offer the knob; plugin never exposed it. |
| Transcoder artifact vanished from JCenter (`0.9.1`) | 24 | [#240](https://github.com/jonataslaw/VideoCompress/issues/240), [#247](https://github.com/jonataslaw/VideoCompress/issues/247), [#207](https://github.com/jonataslaw/VideoCompress/issues/207) (29 comments) | **Rot**, self-inflicted: master had 0.10.4, maintainer rolled back to dodge a crash. |
| Swift Package Manager (iOS/macOS) | 21 | [#322](https://github.com/jonataslaw/VideoCompress/issues/322) (12), [#328](https://github.com/jonataslaw/VideoCompress/issues/328) (9), all 2026 | **Rot.** PR [#325](https://github.com/jonataslaw/VideoCompress/pull/325) does it cleanly. |
| iOS crashes: force-unwrapped nil track, export status never checked | 19 | [#184](https://github.com/jonataslaw/VideoCompress/issues/184), [#136](https://github.com/jonataslaw/VideoCompress/issues/136), [#109](https://github.com/jonataslaw/VideoCompress/issues/109), [#318](https://github.com/jonataslaw/VideoCompress/issues/318) (2025-11) | **Design gap.** No error propagation on iOS. |
| Android muxer crash / silent `null` | 16 | [#191](https://github.com/jonataslaw/VideoCompress/issues/191), [#193](https://github.com/jonataslaw/VideoCompress/issues/193) (18 comments, still "same problem, june 2025"), [#300](https://github.com/jonataslaw/VideoCompress/issues/300), [#309](https://github.com/jonataslaw/VideoCompress/issues/309), [#288](https://github.com/jonataslaw/VideoCompress/issues/288) (Pixel/Android 15) | **Library bug × design gap.** Transcoder ≤0.10.5 muxer bug (fixed 0.11.x) *plus* `onTranscodeFailed → result.success(null)`. |
| Unsupported inputs (6-channel audio, Dolby Vision, .avi, HDR washed out) | 15 | [#113](https://github.com/jonataslaw/VideoCompress/issues/113), [#279](https://github.com/jonataslaw/VideoCompress/issues/279), [#198](https://github.com/jonataslaw/VideoCompress/issues/198), [#298](https://github.com/jonataslaw/VideoCompress/issues/298) | **Library limits** plus a hardening gap (`Long.parseLong(null)` inside the completion callback kills the process). |
| Web / Windows / Linux | 12 / 3 / 2 | [#163](https://github.com/jonataslaw/VideoCompress/issues/163) (12) | **Platform limitation.** Whole new backend per platform. |
| Orientation / portrait black bars | ~10 | [#195](https://github.com/jonataslaw/VideoCompress/issues/195), [#315](https://github.com/jonataslaw/VideoCompress/issues/315), [#172](https://github.com/jonataslaw/VideoCompress/issues/172) | **Bugs.** Inverted swap; iOS `videoComposition` loses the transform. |
| Thumbnails (29 issues, 27 open) | 8 | [#105](https://github.com/jonataslaw/VideoCompress/issues/105), [#275](https://github.com/jonataslaw/VideoCompress/issues/275), [#274](https://github.com/jonataslaw/VideoCompress/issues/274) | **Bugs.** Unit confusion; filenames collide; no rotation. |
| `deleteAllCache` double reply | 8 | [#131](https://github.com/jonataslaw/VideoCompress/issues/131) (2021), [#327](https://github.com/jonataslaw/VideoCompress/issues/327) (2026) | **Bug**, 3-line fix, unmerged for five years. |
| Isolates / background | 7 | [#242](https://github.com/jonataslaw/VideoCompress/issues/242), [#248](https://github.com/jonataslaw/VideoCompress/issues/248) | **Design gap.** Small API addition. |
| Trimming (28 issues) | 6 | [#93](https://github.com/jonataslaw/VideoCompress/issues/93), [#304](https://github.com/jonataslaw/VideoCompress/issues/304), [#297](https://github.com/jonataslaw/VideoCompress/issues/297) | **Bugs** on both platforms (§1). |

By reactions, the top ten issues are seven build/release-rot items, two "artifact vanished"
items and one wish (Web). **Breakage dominates demand; wishes dominate the long tail.** Issue
volume by year: 49 / 52 / 46 / 33 / 29 / 18 / 6 (2020→2026 to July); the still-open PRs by year
of opening end 9 in 2025 and 5 in 2026, so *contributors* are more active than ever while the
maintainer is absent.

**Wishes, by reactions:** Web ([#163](https://github.com/jonataslaw/VideoCompress/issues/163), 12), run in an isolate (7), a "High" quality (7), target
bitrate (6), watermark/stitch ([#30](https://github.com/jonataslaw/VideoCompress/issues/30), 6), Windows/Linux (3+2), custom width/height (2),
choose the output path (2), gif→mp4 (2), native trimming "with the deprecation of
ffmpeg_kit_flutter" (2), batch/concurrent, HDR, privacy manifest. Read together they are three
asks: **one knob for output size**, **control of where the file goes**, and **run it off the main
isolate**. Keyword counts: bitrate 8 issues, rotation 9, isolate 9, HDR/Dolby 5, web 6,
**HEVC/H.265 1** (a marketing post by a competitor). Nobody asks for codecs or filters.

### Workarounds in the wild

Point `pubspec.yaml` at `git: … ref: master` (the maintainer himself recommends it instead of
releasing, [#203](https://github.com/jonataslaw/VideoCompress/issues/203)); hand-edit
`build.gradle` inside `~/.pub-cache` (the +24 comment on
[#262](https://github.com/jonataslaw/VideoCompress/issues/262) is the most-upvoted comment in the
tracker); add `jcenter()` back (+18); force `jvmTarget` for every subproject (+15); use
`includeAudio: false` to dodge the muxer crash (+6, "a video without audio loses its purpose");
switch to `ffmpeg_kit_flutter`, `v_video_compressor` (whose author is a five-year user of this
tracker and posted its README as [#313](https://github.com/jonataslaw/VideoCompress/issues/313)),
or `light_compressor`; forks `SpectoraSoftware/VideoCompress`, `video_compress_plus` (32 dl/30d),
`hm-toan/VideoCompress` (PR [#321](https://github.com/jonataslaw/VideoCompress/pull/321)).

### The 32 open PRs

PR-by-PR verdicts are in [the notes](sources/issues-and-prs.md#c-open-prs-32); the shape:

- **Merging only the five opened in the last 12 months** ([#321](https://github.com/jonataslaw/VideoCompress/pull/321)
  toolchain + Transcoder 0.11.2 + `deleteAllCache`; [#325](https://github.com/jonataslaw/VideoCompress/pull/325)
  SPM; [#329](https://github.com/jonataslaw/VideoCompress/pull/329) surface `onTranscodeFailed` as
  an error, `bitRate`, `fileLengthLimit`, Dolby Vision remap; [#330](https://github.com/jonataslaw/VideoCompress/pull/330)
  width/height; [#331](https://github.com/jonataslaw/VideoCompress/pull/331) thumbnail rotation)
  would close the two biggest clusters (build rot and SPM, ~85 reactions), fix the muxer /
  6-channel / negative-PTS crashes, and finally report Android failures instead of `null`.
  #321 carries the hm-toan fork's branding in README/homepage that must be stripped, and still
  uses the external Kotlin plugin, so AGP 9 ([#323](https://github.com/jonataslaw/VideoCompress/issues/323)) is not covered.
- **The 24-month window adds** three real fixes ([#289](https://github.com/jonataslaw/VideoCompress/pull/289)
  thumbnail units, [#305](https://github.com/jonataslaw/VideoCompress/pull/305) iOS trim,
  [#308](https://github.com/jonataslaw/VideoCompress/pull/308) iOS portrait rendering), three
  duplicates of the Transcoder bump, three to decline ([#303](https://github.com/jonataslaw/VideoCompress/pull/303)
  breaking return type, [#306](https://github.com/jonataslaw/VideoCompress/pull/306) silent
  seconds→ms change, [#307](https://github.com/jonataslaw/VideoCompress/pull/307) removes the
  concurrency guard without fixing the single shared future/stream), and
  [#314](https://github.com/jonataslaw/VideoCompress/pull/314) Linux: 1,212 lines that
  `posix_spawn` a user-installed `ffmpeg`, incomplete by its own TODO, with a `va_arg` type bug.
- **Conflicts:** three bitrate/quality designs ([#217](https://github.com/jonataslaw/VideoCompress/pull/217)
  options objects, [#219](https://github.com/jonataslaw/VideoCompress/pull/219) Android-only
  `CustomQuality`, [#329](https://github.com/jonataslaw/VideoCompress/pull/329) flat params) all
  rewrite the same `when(quality)` block; three Transcoder bumps; three `deleteAllCache` fixes;
  four trimming PRs of which one ([#133](https://github.com/jonataslaw/VideoCompress/pull/133))
  is wrong and none fixes the Android `trimEndUs` semantic; two rewrites of the iOS
  `videoComposition` block.

**Plugin rot vs real design gaps.** Rot: toolchain versions, JCenter, SPM, the ObjC shim (about
110 reactions, all fixable by merging what is already in the queue). Real gaps: no output-size
control, errors swallowed on both platforms, one global job/progress stream, no isolate
support, three different units for the same parameter, wrong trim semantics, no HDR/rotation
care. Library limits: 5.1 audio, Dolby Vision, HDR tone-mapping, exotic containers.

## 4. How the field does it now

### The three challengers (downloads from FINDINGS.md; the rest from cloned source, 2026-09-14)

**`light_compressor_v2`** (15.7k downloads/30d, 4★, one individual with 140 of 141 commits).
Android: raw `MediaCodec` + OpenGL surfaces + `MediaMuxer`, a vendored fork of the archived
LightCompressor library, 4,089 lines of Kotlin. iOS: `AVAssetReader`/`AVAssetWriter` with a real
bitrate key, 3,464 lines of Swift. The best API design in the field: target bitrate or target
size with a two-pass retry, a pre-flight size estimate, hardware-only HEVC with automatic H.264
fallback and a `usedFormat` in the result, audio passthrough by default, batch jobs, an Android
foreground service, and an honest "iOS background: not supported". Gaps: no HDR tone-mapping (it
stamps the source's HDR transfer flag onto 8-bit output), rotation by metadata only, and thin
device testing (1.9.0 fixed a 100%-reproducible crash on real iPhones for any `.mov` with audio;
1.9.1 fixed "a compression could end with no result at all").

**`v_video_compressor`** (11.4k, 14★, an org name with one real contributor; releases come from
`codex/release-*` branches). Android: **Media3 Transformer 1.8.0**, 3,683 lines of Kotlin. iOS:
`AVAssetExportSession` presets plus a `fileLengthLimit` "budget", 2,784 lines of Swift. The option
surface is FFmpeg vocabulary (`crf`, x264 speed presets, `bFrames`, `mp3`) that neither engine
can honour; the README admits iOS `videoBitrate` is "approximated"; and there is **no
`VideoEncoderSettings` anywhere in the Android source**, so the per-quality bitrate constants
seemingly never reach the encoder. No HDR code, no background support. On iOS with HEVC
available, every quality level maps to a 1080p HEVC preset.

**`ffmpeg_kit_flutter_new`** (51k, 179★, one individual; a fork of Arthenica's retired FFmpegKit).
FFmpeg 8.1.2 on five platforms. It can do anything, including HDR tone-mapping and exact CRF,
but it is a CLI-string toolkit, not a `compressVideo()`; software x264/x265 is slow and hot on
phones; the full-GPL Android AAR is **108.9 MB** on Maven Central, iOS pulls 22–29 MB frameworks
at `pod install`, and the full variant is effectively GPL v3.

Sources: [light_compressor_v2](https://github.com/Farid023/light_compressor_v2) (`CompressorUtils.kt`, `Compressor.kt`, `LightCompressor.swift`, `CHANGELOG.md`, `background_config.dart`), [v_video_compressor](https://github.com/v-chat-sdk/v_video_compressor) (`VVideoCompressionEngine.kt/.swift`, `README.md` lines 645-646), [ffmpeg_kit_flutter_new](https://github.com/sk3llo/ffmpeg_kit_flutter) (`README.md`, `scripts/setup_ios.sh`, Maven Central content-length for `ffmpeg-kit-full-gpl-2.2.1.aar`).

Also seen: `flutter_compress` 2.0.0 (2026-08-30, 3★) is the only one with a **web** target
(WebCodecs + mp4box/mp4-muxer, ~0.2 MB of JS) and the only Media3 user that actually sets
`VideoEncoderSettings.setBitrate`; `xue_hua_media_compression` covers five platforms but outputs
video with **no audio**; `video_compress_kit`'s repo is a 404; `flutter_video_compressor` is a
stub that hard-codes the iOS Medium preset. The original `light_compressor` is archived
(2024-04). In short: the two credible native challengers are both one-person projects with
real gaps, and the incumbent still out-downloads their sum roughly 6:1.

### The modern native APIs a rebuild would sit on

**Android: Media3 Transformer** (stable 1.11.0, 2026-08-05; minSdk 23 since 1.9.0;
[release notes](https://developer.android.com/jetpack/androidx/releases/media3)). It is Google's
own replacement for exactly what Transcoder does, and it is pure Kotlin/Java (about 4 MB of AARs
before R8, no `.so`, so no 16 KB page-size exposure). Out of the box it gives:
`setVideoMimeType` H.264 or H.265, `VideoEncoderSettings.setBitrate` (and Google's CodecDB
bitrate recommendation), `Presentation` resize, `ClippingConfiguration` trim, automatic
**transmux** when the input already matches (the "Telegram passthrough" users ask for), automatic
landscape-plus-rotation-metadata handling, `setHdrMode` tone-mapping (OpenGL path on API 29+,
keep-HDR on 31+/33+, including Dolby Vision profile 8), `getProgress` and `cancel()`
([getting started](https://developer.android.com/media/media3/transformer/getting-started),
[transformations](https://developer.android.com/media/media3/transformer/transformations),
[supported formats](https://developer.android.com/media/media3/transformer/supported-formats)).
Constraints: one thread per instance, no concurrent exports on one instance, MediaCodec limits
the output formats. Compared with Transcoder (864★, H.264-only, last commit 2024-11-05, open
issue #191 "HDR Tone Mapping") it is the obvious base; compared with raw MediaCodec it saves
roughly 4,000 lines of surface/colour/muxer plumbing that `light_compressor_v2` had to vendor.

**iOS/macOS: `AVAssetReader` + `AVAssetWriter`** for the real work, with `AVAssetExportSession`
kept for presets and passthrough. The export session cannot set a bitrate: its only size lever
is `fileLengthLimit` ([docs](https://developer.apple.com/documentation/avfoundation/avassetexportsession)),
its quality presets are documented only as "compresses video in H.264 … audio in AAC" with no
resolution or bitrate ([export presets](https://developer.apple.com/documentation/avfoundation/export-presets)),
and its `progress` property is deprecated in iOS 27 in favour of `states(updateInterval:)`.
The writer path gives `AVVideoAverageBitRateKey`, `AVVideoCodecType.hevc`, HDR via
`AVVideoColorPropertiesKey`, rotation via `input.transform = track.preferredTransform` (set
before writing starts), and audio passthrough with `outputSettings: nil` plus a
`sourceFormatHint` ([AVAssetWriterInput](https://developer.apple.com/documentation/avfoundation/avassetwriterinput)).
Apple's guidance on HDR: HEVC presets preserve HDR, H.264 presets tone-map to SDR and
"maximize backwards compatibility" ([WWDC20 10010](https://developer.apple.com/videos/play/wwdc2020/10010/)).

**Web** is possible only via WebCodecs plus a JS muxer (Chrome/Edge 94+, Firefox 130+, Safari
full support only from 26, video-only in 16.4–18 per
[caniuse](https://github.com/Fyrd/caniuse/blob/main/features-json/webcodecs.json)); ffmpeg.wasm
is a 31 MB GPL core that needs cross-origin isolation headers. Web demand in the tracker is one
issue with 12 reactions; it is a v2 question.

## 5. The hard parts

- **Codec choice.** HEVC halves file size but needs hardware encoders (many low-end Androids
  expose only the software `c2.android.hevc.encoder`; Apple needs A10+) and recipients on
  Windows/Chrome need hardware decode ([caniuse hevc](https://github.com/Fyrd/caniuse/blob/main/features-json/hevc.json)).
  Default H.264, opt-in HEVC with automatic fallback and a `usedCodec` in the result. Nobody in
  the tracker has asked for HEVC; they ask for smaller files, which is what it buys.
- **HDR.** iPhones shoot Dolby Vision 8.4 (HLG-based) by default and Android requires HLG10
  capture support, so HDR input is routine. Push it through an 8-bit pipeline and you get the
  "washed out" video of [#298](https://github.com/jonataslaw/VideoCompress/issues/298);
  `light_compressor_v2` mislabels SDR pixels as HDR, `v_video_compressor` has no HDR code,
  Transcoder has an open issue. Media3's tone-map modes and Apple's H.264 presets solve it;
  policy: tone-mapped SDR H.264 by default, HDR-preserving HEVC opt-in.
- **Rotation.** Portrait video is landscape frames plus a flag. Drop the flag: sideways. Keep it
  and also rotate: doubly rotated. Swap width/height without rotating: black bars. Every
  package here has shipped one of these. Media3 does it right by default; `AVAssetWriter`
  needs the transform set before writing.
- **Audio.** Passthrough is free and lossless (Media3 transmux; writer input with nil settings
  and a format hint), re-encode is needed for odd sources, 5.1 layouts and downmix. The
  incumbent re-encodes always and offers only `includeAudio`; audio is the subject of 26 of its issues.
- **Progress and cancel.** Media3 progress is unavailable during transmux phases; the writer
  path has no progress API (derive from sample timestamps); cancel must resolve to a distinct
  `Cancelled` result and delete the partial file, never a generic error or `null`.
- **Background.** iOS gives five seconds plus a finite `beginBackgroundTask`; an Apple engineer
  calls the `-11847 Operation Interrupted` export failure "expected behavior … there is no way
  to reliably pick up where you left off" ([forum thread](https://developer.apple.com/forums/thread/672056)).
  Android needs a foreground service, type `mediaProcessing`, capped at 6 hours per 24
  ([service types](https://developer.android.com/develop/background-work/services/fgs/service-types)).
  The honest v1 story is: document it, auto-restart on foreground, offer the Android service.
- **Big files.** 4K60 needs a Level 5.1+ encoder (query `MediaCodecInfo.VideoCapabilities`);
  set `AVVideoExpectedSourceFrameRateKey` for >30 fps sources or frames get dropped; outputs
  near 4 GB may truncate; software paths run slower than real time on phones.
- **Web.** Only the WebCodecs path is realistic; Safari support is recent; skip for v1.
- **16 KB pages.** Only native `.so` code is affected; a Media3/AVFoundation plugin has zero
  exposure, the FFmpeg route needed a re-uploaded 100 MB AAR
  ([Android guide](https://developer.android.com/guide/practices/page-sizes)).

**How much native code a v1 needs.** The incumbent is ~380 lines of Kotlin and ~370 of Swift on
top of two engines that hide most of the work. A Media3 + AVAssetWriter v1 that handles bitrate,
resize, trim, rotation, tone-mapping, audio passthrough, progress and cancel properly is more:
`flutter_compress` does it in ~1,750 Kotlin + ~1,300 Swift, `v_video_compressor` in ~3,700 +
~2,800 with a lot of option noise. A realistic budget is **1,500–2,500 lines of Kotlin and
1,500–2,500 lines of Swift**, plus a Dart layer of ~1,000 lines and a test-clip corpus. Roughly
one third of the effort is plumbing (SPM + CocoaPods, Gradle/AGP 9 built-in Kotlin, method
channels or Pigeon, isolate support, CI on real devices); two thirds is media engineering.

**A sensible v1 in one paragraph.** One call, `compress(path, {preset | targetBitrate |
targetSizeMB, maxLongSide, maxFps, codec: h264 (default) | hevc, audio: passthrough (default) |
aac | none, trim, hdr: toneMapToSdr (default) | keep})`, returning a typed result (`output path,
size before/after, dimensions, duration, usedCodec, wasTransmuxed, toneMapped, cancelled`) or a
typed error, never `null`, and never a file larger than the input (fall back to the original and
say so). Progress as a per-job stream, cancel per job, safe to call from an isolate. Android on
Media3 Transformer with `VideoEncoderSettings`, `Presentation`, `ClippingConfiguration`,
`setHdrMode`, and an optional `mediaProcessing` foreground service; iOS/macOS on
`AVAssetReader`/`AVAssetWriter` with `AVAssetExportSession` for passthrough. Thumbnails and
`getMediaInfo` kept, with one unit (milliseconds) everywhere. minSdk 23, iOS 13+, SPM and
CocoaPods both, a real-device test corpus (Dolby Vision iPhone clip, HLG Pixel clip, portrait,
PCM audio, no audio, 4K60), and a migration guide from `video_compress`'s enum. No web, no
desktop beyond macOS, no watermark, no filters.

## 6. Is this a Dan project?

**For.**
- The gap is real and current: 170k downloads/30d, 176 open issues, contributors *more* active
  in 2025–26 than ever, the maintainer absent, and a flagship user (FluffyChat) that migrated
  away four weeks ago. That is the device_calendar shape before the funded fork appeared, and
  here no funded fork has appeared: the challengers are one-person projects with documented
  gaps (§4).
- The domain is interesting in a way calendar recurrence is not: codecs, HDR, colour, rotation,
  muxing, encoder capability negotiation, two real platform media stacks. It is the kind of
  thing that produces good blog posts ("why your compressed iPhone video is washed out").
- The scope is naturally small. One verb. The API is a single function plus two helpers, and
  the users' three asks (an output-size knob, control of the output file, off-main-isolate)
  are all v1 features, not a roadmap.
- The story writes itself for a portfolio or interview: *"the most-downloaded Flutter video
  compressor was abandoned with 176 open issues; I read every one, found that the real demand
  was 'never make my file bigger, never return null, and build on today's toolchain', and
  rebuilt it on Google's and Apple's current media APIs with a test corpus that covers the cases
  every competitor shipped broken."* It is product thinking plus native engineering, which is
  the combination Dan is trying to show.
- Measurable success: pub.dev downloads, likes, "used by" repos, and named migrations are all
  public. "Shipped and people use it" in six months looks like: on pub.dev with 160/160
  points, 5–15k downloads/30d (where the two challengers sit after 15–19 months), a handful
  of named apps migrated (a Matrix client, a KYC SDK, a TikTok-clone template), and issues
  answered within days.

**Against.**
- It is native-heavy. The interesting parts are in Kotlin and Swift, not Dart, and they need
  real devices to test: an iPhone that shoots Dolby Vision, a Pixel, a low-end Android with a
  software-only HEVC encoder. Without a device lab the HDR/rotation promises are untested.
- Maintenance is a treadmill by construction. The biggest complaint cluster is toolchain rot,
  and it will hit the rebuild too: AGP 9's built-in Kotlin, each Flutter release's SPM/Gradle
  template change, Media3 minSdk bumps, iOS API deprecations (`progress` in iOS 27). The
  pitch "it builds on today's Flutter" has to stay true every quarter.
- Winning the base is slow. `light_compressor_v2` and `v_video_compressor` have 15–19 months
  and 11–16k downloads each; the incumbent still has 170k despite 19 months of silence. Discovery
  on pub.dev favours the incumbent's name and likes. A rebuild competes for the same 20–30k
  who have already decided to move, unless it gets the "drop-in replacement with a migration
  guide" story exactly right.
- Roughly a third of the work is plumbing nobody will admire.
- Passion check: is Dan interested in *video*, or in *rescuing a popular package*? If the
  latter, `device_calendar` is the same shape with less native depth; if the former, this is
  the better project, and the web target is a natural later chapter.

**Verdict.** Go, on one condition: the v1 is the *drop-in* replacement described in §5 (same
verbs, enum migration table, never-larger, never-null, typed results), released within weeks
with the five current PRs' worth of fixes already inside it, and then grows the output-size
knob and HDR handling as the differentiators. Do not start by forking `jonataslaw/VideoCompress`
and merging PRs; the Transcoder dependency is the thing to leave behind. The competition is
beatable because both challengers are single people with visible correctness gaps and the
incumbent's audience is large, active and already looking.
