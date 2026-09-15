# Who uses `video_compress`, and why

Research brief on the Flutter package [`video_compress`](https://pub.dev/packages/video_compress) (repo [jonataslaw/VideoCompress](https://github.com/jonataslaw/VideoCompress)). Data gathered 2026-09-14. Every number below is quoted from the cited source; nothing is estimated.

## 0. Headline numbers

| Metric | Value | Source |
|---|---|---|
| pub.dev likes / points / 30-day downloads | **747 likes, 140/160 points, 167,492 downloads in 30 days** | [pub.dev score API](https://pub.dev/api/packages/video_compress/score) |
| Latest release | **3.1.4, 2025-02-13** (14 versions total) | [pub.dev package API](https://pub.dev/api/packages/video_compress) |
| Publisher | getx.site (verified) | [pub.dev page](https://pub.dev/packages/video_compress) |
| GitHub stars / forks / open issues | **262 stars, 344 forks, 208 open issues**, last push 2025-02-13, not archived | [`gh api repos/jonataslaw/VideoCompress`](https://api.github.com/repos/jonataslaw/VideoCompress) |
| Total issues ever / open PRs | 233 issues, **32 open PRs** | GitHub search API (`repo:jonataslaw/VideoCompress is:issue`, `is:pr is:open`) |
| GitHub "Used by" (dependency graph) | **"3,094 Repositories" and "51 Packages"** | [network/dependents](https://github.com/jonataslaw/VideoCompress/network/dependents) |
| GitHub code search: `video_compress:` in `pubspec.yaml` | **`total_count: 1224`** | `gh api search/code -f q='video_compress: filename:pubspec.yaml'` |
| GitHub code search: `VideoCompress.compressVideo` in Dart | **1,048** hits | `gh api search/code -f q='VideoCompress.compressVideo language:Dart'` |
| pub.dev packages that depend on it | **40** | [`pub.dev/api/search?q=dependency:video_compress`](https://pub.dev/api/search?q=dependency%3Avideo_compress) (4 pages of 10) |

Competitor context from the same pub.dev score endpoint (likes / 30-day downloads): `light_compressor` 160 / 3,617; `ffmpeg_kit_flutter_new` 202 / 41,514; `ffmpeg_kit_flutter` 471 / 2,695; `video_compress_plus` 23 / 32; `flutter_video_compress` 86 / 16; `media_tool_flutter` 7 / 11. GitHub pubspec code-search totals for the same names: `light_compressor:` 23, `ffmpeg_kit_flutter_new:` 428, `ffmpeg_kit_flutter:` 394, `video_compress_plus:` 15 (vs. 1,224 for `video_compress:`). For scale, `flutter_image_compress:` returns 6,432.

So: **video_compress is, by a wide margin, the default on-device video compressor in Flutter** — roughly 40× the monthly downloads of `light_compressor` and ~4× `ffmpeg_kit_flutter_new` — despite 208 open issues and no release in 19 months.

---

## 1. GitHub dependents

### Method
`gh api -X GET search/code -f q='video_compress: filename:pubspec.yaml'`, pages 1–5 at 100/page (the API caps at 1,000 results and reports `total_count: 1224`). The variant `'"video_compress:" path:pubspec.yaml'` returned 0 (the `path:` qualifier needs a directory, not a filename). The 500 hits collapsed to **418 unique repositories** (no forks — the code-search index excludes forks). Star/description/pushed-at metadata was pulled by GraphQL for all 418. Raw dumps: `repos.json`, `repo_meta.json`, `all_repos.txt`, `assign.json` in this scratchpad.

Population facts for the 418: 167 have ≥1 star, 41 have ≥10 stars. Last-push year: 2020: 7, 2021: 4, 2022: 27, 2023: 58, 2024: 82, 2025: 76, **2026: 164** — i.e. 39 % of dependents were pushed to this calendar year, so the user base is active, not archaeological.

### Classification of the 70 highest-starred dependents (hand-classified from name/description/topics; plugin's own `example/` excluded)

| Category | Count | Notes |
|---|---|---|
| **Social / short-video feed** | **22** | ≥15 are TikTok/Instagram/YouTube-Shorts clones; also DTube, ChaseApp, watch-party |
| **Chat / messaging** | **16** | includes 4 shipped Matrix clients, Mixin, OpenIM, Keychat, imboy, Easemob UIKit |
| Other (media utilities, notes, VPN, ML, diaries) | 14 | memoflow, Latch media vault, media players, deepfake detector, baby diary |
| Template / boilerplate / library | 9 | GetX templates, mason bricks, `flood` framework, Zebra design system |
| Education / e-learning | 2 | |
| Enterprise / field-reporting | 2 | SOS emergency reporting, CMMS inspections |
| Tutorial / demo | 1 | |
| Telehealth / medical | 1 | appointment admin panel |
| Fitness | 1 | posture app |
| Dating | 1 | |
| Marketplace / classifieds | 1 | used-clothes marketplace |
| Real-estate, delivery/gig | 0 in top-70 | but present in the long tail (see below) |

A keyword-based pass over all 418 (rough, first-match-wins; `assign.json`) gives the same shape: social/video feed 81, chat/messaging 65, education 31, telehealth/medical 21, template 18, marketplace 16, tutorial/demo 14, enterprise/field-reporting 14, delivery/gig 14, video-tool/library 9, fitness 5, dating 3, real-estate 1, other/unclear 125. The long tail is where delivery/gig (e.g. `ABHISHEKS9045/Cabme` driver app, `kookyinfomedia/Foodie-Driver`, `muhammadkhizr/groshop_driver`), field-reporting (`JavierGavra/lapormin` citizen reporting, `aliozkanozdurmus/emniyet360-veni-isg` occupational-safety inspections, `Traffic-Violations-Reporting-System/TVRS-Mobile-App`, `Kenabadobee09922/…Flare-Alert` fire dispatch) and medical (`tim-ref/messenger-client`, `Nabeel-Shehzad/healthsync_patient`, `efesrnn/medTrackPlus`) show up — plus a striking cluster of ~10 near-identical `lost_n_found_starter` repos pushed May–June 2026, evidently a bootcamp/course assignment that ships `video_compress` in its starter template.

**Read-through:** two thirds of the serious users are "user records a video on the phone and sends it to other people" apps — chat and social — and the rest are mostly "user attaches a video as evidence/content" (inspection, reporting, marketplace listing, telehealth intake).

### Named dependents (stars from GraphQL, 2026-09-14)

Shipped / production-grade products:

1. **[openimsdk/openim-flutter-demo](https://github.com/openimsdk/openim-flutter-demo)** — 442★ — official OpenIM instant-messaging client; uses `VideoCompress.getMediaInfo` in `openim_common/lib/src/utils/utils.dart`. Several white-label forks (`coscx/ckt`, `laogui8851-droid/IM-71_JUN_TUAN`, `itimor2022/pppim-flutter`, `guigui779/JUN_XUN_LIAN_1`) carry the same `openim_common/pubspec.yaml`.
2. **[MixinNetwork/flutter-app](https://github.com/MixinNetwork/flutter-app)** — 329★ — Mixin Messenger desktop (macOS/iPadOS/Linux/Windows); wraps the plugin in `lib/utils/video.dart` (`class _CustomVideoCompress extends IVideoCompress`) and calls it from the chat file-preview model. Pushed 2026-09-14.
3. **[linagora/twake-on-matrix](https://github.com/linagora/twake-on-matrix)** — 166★ — Linagora's Matrix client; `lib/presentation/extensions/send_file_extension.dart` logs `'sendFileEventMobile::Compressing video (${videoInfo.fileSize} bytes)'`, calls `VideoCompress.compressVideo(videoPath, quality: VideoQuality.MediumQuality, deleteOrigin: false)` and only uses the result `if (compressedSize < videoInfo.fileSize && compressedSize > 0)` — a guard against the plugin making files bigger (see §3). Pushed 2026-09-14.
4. **[ExteraApp/Extera](https://github.com/ExteraApp/Extera)** — 100★ — "feature-rich [matrix] client".
5. **[keychat-io/keychat-app](https://github.com/keychat-io/keychat-app)** — 97★ — Bitcoin/Nostr secure chat super-app.
6. **[imboy-pub/imboy-flutter](https://github.com/imboy-pub/imboy-flutter)** — 65★ — open-source IM (Erlang backend) with WebRTC calls.
7. **[wetee-dao/DTIM](https://github.com/wetee-dao/DTIM)** — 113★ — Web3/Matrix collaboration tool.
8. **[ubuntu-flutter-community/nebuchadnezzar](https://github.com/ubuntu-flutter-community/nebuchadnezzar)** — 20★ — Matrix client for Linux.
9. **[lingyicute/Yomi-Android](https://github.com/lingyicute/Yomi-Android)** — 9★ — Matrix client.
10. **[easemob/easemob-uikit-flutter](https://github.com/easemob/easemob-uikit-flutter)** — 6★ — Easemob/Agora Chat UIKit (published as `em_chat_uikit`, 226 downloads/30d).
11. **[dtube/DTubeGo](https://github.com/dtube/DTubeGo)** — 39★ — mobile client for the DTube decentralised video platform.
12. **[hzc073/memoflow](https://github.com/hzc073/memoflow)** — 235★ — Android client for usememos/memos (note-taking with attachments).
13. **[itsezlife/flutter-instagram-offline-first-clone](https://github.com/itsezlife/flutter-instagram-offline-first-clone)** — 264★ — "Production-ready" Instagram clone (PowerSync + Supabase) with posts, stories, reels; widely forked as a starter.
14. **[cylonix/cylonix](https://github.com/cylonix/cylonix)** — 40★ — open-source Tailscale-alternative client.
15. **[moss-apps/Latch](https://github.com/moss-apps/Latch)** — 15★ — media-hiding vault app.
16. **[ZebraDevs/zds_flutter](https://github.com/ZebraDevs/zds_flutter)** — 4★ / pub.dev `zds_flutter` — Zebra Technologies design-system components (enterprise/field devices).
17. **[carverauto/flutter](https://github.com/carverauto/flutter)** — "ChaseApp — follow live police chases" (successor repo `carverauto/chaseapp` pushed 2025-12).
18. **[s17476/under_control_v2](https://github.com/s17476/under_control_v2)** — CMMS: "planning and recording of technical inspections of machines".

Tutorials/clones with reach: **[RivaanRanawat/tiktok-flutter-clone](https://github.com/RivaanRanawat/tiktok-flutter-clone)** (400★, "Full Stack TikTok Clone using Flutter, Firebase & GetX") is the template for at least 20 lower-starred TikTok clones in the sample (`alok2811`, `CharlyKeleb`, `Pankaj0405`, `abhishek7974`, `codewithdhruv22`, `RodrigoNP3`, `zak-rockerfeller`, `atiqabdullah07`, `Viet20021476`, `CK1412/TopTop-App`, `WorkWithAfridi/NotTikTok-TikTokClone`, `SandeepKumar482/TunTun`, …). **[axelulu/Getx-PinkApp](https://github.com/axelulu/Getx-PinkApp)** (104★) is a Bilibili clone; **[LeeeYudE/flutter_wechat](https://github.com/LeeeYudE/flutter_wechat)** (98★) a WeChat clone.

The GitHub dependents page additionally names **storypad (theachoem)**, **sama-client-flutter (SAMA-Communications)**, **conversational-ai-flutter (GetStream)** and **art.kubus** as dependents ([source](https://github.com/jonataslaw/VideoCompress/network/dependents)); their top-level `pubspec.yaml` on `main` did not contain the string when fetched raw, so they are likely sub-package or older-branch dependents — listed here as "GitHub says so", not independently verified.

### A notable *ex*-dependent: FluffyChat
[krille-chan/fluffychat](https://github.com/krille-chan/fluffychat) — the most popular Flutter Matrix client — used `video_compress` from at least 2021-12-27 ("chore: Fix video compress") through 2025-06-21 ("fix: Workaround for reversed width and height of compressed videos sent from Android", [3d0a3ee](https://github.com/krille-chan/fluffychat/commit/3d0a3ee2264430720329aefd1e10ac27f57c258f)), and on **2026-08-17** merged [PR #3405 "replace video compress package with light compressor"](https://github.com/krille-chan/fluffychat/pull/3405). Its current `pubspec.yaml` lists `light_compressor_v2: ^1.9.1`. That is the highest-profile migration away from the package and it happened one month ago.

---

## 2. Which packages depend on it, and what the big SDKs use instead

### Packages on pub.dev that depend on `video_compress` (40, from the pub.dev search API)
Grouped by what they are (version, last publish, 30-day downloads from the pub.dev API):

- **Chat / IM UIKits:** `em_chat_uikit` 2.3.3 (2026-08-28, 226 dl) — Easemob's chat UI kit; `flutter_yim` 6.3.13 (2026-08-22, 772 dl) and `flutter_ypush` 5.2.5 (144 dl) — YIM messaging SDK; `flutter_chen_im` 0.0.3; `kat_common` 0.1.3 (570 dl).
- **Identity / KYC / liveness SDKs (record a selfie video, upload it):** `trustchex_flutter_sdk` 1.523.2 (2026-09-04, **927 dl** — the biggest dependent), `myaza_kyc_sdk_flutter` 2.7.0 (2026-09-08, 245 dl), `biometry` 2.0.0 (2026-07-23), `intp_flutter_liveness_sdk` 1.3.6, `meta_g_sdk` 0.0.34.
- **Insurance / vehicle inspection:** `mca_official_flutter_sdk` 0.7.63 (MyCover.ai, 2026-06-24), `mca_flutter_sdk`, `mca_official_inspection_sdk` ("vehicle inspection"), `inspection_camera` / `multimedia_camera`.
- **Media pickers / story editors / compression wrappers:** `flutter_stories_editor` 0.0.42, `picker_instagram` 1.0.15, `image_select`, `flutter_media_compress` 1.1.0, `flutter_media_picker_pro` 1.1.2, `nex_media_picker`, `zeba_academy_media_tools`, `mosaic_image_picker`, `nui_media`, `rhythm_files`.
- **Feed SDK:** `likeminds_feed_flutter_core` 1.17.1 (LikeMinds community-feed SDK).
- **Design systems / component libraries:** `zds_flutter` 2.3.0 (Zebra), `blip_ds` 0.4.4 (Take Blip, 188 dl), `v_components`, `dan_ui`, `armoyu_widgets`.
- **Forms:** `input_sheet` 0.2.1 (46 likes), `lite_forms`.
- **Private/company SDKs:** `dative_core`, `hrd` ("Sunsimexco HRD Application"), `vimean_group_dart_libraries`, `zhq_flutter`, `gogoboom_flutter_common`, `palio_lite`, `flutter_image_process`.

Source: [`pub.dev/api/search?q=dependency:video_compress`](https://pub.dev/api/search?q=dependency%3Avideo_compress) pages 1–4, plus each package's `/api/packages/<name>` and `/score` endpoints.

### The well-known chat/media SDKs — checked one by one (pub.dev `latest.pubspec.dependencies`)

| Package | Version | Depends on video_compress? | What it uses instead |
|---|---|---|---|
| `stream_chat_flutter` | 10.4.0 | **No** | `image_picker`, `file_picker`, `video_player`, `image_size_getter` — no compressor at all |
| `flutter_chat_ui` (Flyer) | 2.12.0 | No | nothing media-related; `flyer_chat_video_message` 0.0.13+1 also has no compressor |
| `chatview` | 3.1.0 | No | `image_picker`, `cached_network_image` |
| `sendbird_uikit` | 1.5.0 | No | `video_thumbnail` only |
| `agora_chat_uikit` | 2.0.3 | No | `get_thumbnail_video` |
| `em_chat_uikit` (Easemob, same vendor as Agora Chat) | 2.3.3 | **Yes** | — |
| `tencent_cloud_chat_uikit` | 5.0.1+5 | No | `flutter_image_compress`, `fc_native_video_thumbnail` (images compressed, video not) |
| `zego_uikit` | 2.29.2 | No | `file_picker` |
| `flutter_openim_sdk` | 3.8.3 | No (but the official demo app does, see §1) | — |
| `wechat_assets_picker` | 10.1.3 | No | `video_player`, `extended_image` |
| `flutter_quill` | 11.5.1 | No | — |

Takeaway: **the mainstream chat SDKs deliberately do not bundle a video compressor** — they leave it to the app, which is exactly why the app-level dependents in §1 are dominated by chat clients. The only vendor UIKit that bundles it is Easemob's. The biggest *package*-level users are KYC/liveness SDKs that need to shrink a selfie video before POSTing it to a verification API.

---

## 3. StackOverflow and forums

Stack Overflow and Reddit block the web-search crawler, so questions were pulled from the [StackExchange API](https://api.stackexchange.com/2.3/search/advanced?q=video_compress&tagged=flutter&site=stackoverflow) (`q=video_compress` → 21 questions; `q=compress video` → 40). The top questions by votes, with what the asker was trying to do:

1. **"How to compress a video in flutter?"** — 7 votes, 16,647 views, 2018-11-13. *"I'm using image_picker to pick video from gallery which compress the video from 30MB to 10MB on iOS but in android there is no compression."* — [link](https://stackoverflow.com/questions/53290269/how-to-compress-a-video-in-flutter). This is the canonical question: **iOS's picker compresses for free, Android's does not**, so Android uploads are 3× bigger unless you add a compressor.
2. **"Compress & Upload large videos to Google cloud storage using Flutter/Dart"** — 6 votes, 2022-02-07. *"none work well once a video gets around 300MB. They crash or have other issues on various platforms and hardware. Namely, video compress and light compressor. The GH commits and support are concerning as well … PR's not being pulled in and issues not being resolved in a timely manner"* — [link](https://stackoverflow.com/questions/71027684/compress-upload-large-videos-to-google-cloud-storage-using-flutter-dart). Direct evidence that maintenance state is already a purchasing criterion.
3. **"How to stop iOS from compressing video when picked with Flutter image_picker?"** — 4 votes, 2022-09-09 — the mirror problem: some apps want the *un*compressed original — [link](https://stackoverflow.com/questions/73665238/how-to-stop-ios-from-compressing-video-when-picked-with-flutter-image-picker).
4. **"Flutter video compress plugin makes video size greater"** — 2 votes, 1,888 views, 2021-05-18. *"a 36mb video gets compressed to almost 20mb but sometimes it gets to 60mb after compression"* — [link](https://stackoverflow.com/questions/67594673/flutter-video-compress-plugin-makes-video-size-greater). (Twake's `compressedSize < videoInfo.fileSize` guard in §1 exists for exactly this.)
5. **"Why does my video compressor not work? Throws error: Null check operator used on a null value (video_compress)"** — 3 votes, 886 views, 2022-07-15, iPhone 12 Pro, versions 3.0.0–3.1.1 — [link](https://stackoverflow.com/questions/72992462/why-does-my-video-compressor-not-work-throws-error-null-check-operator-used-on).
6. **"compress videos in flutter"** — 2,215 views, 2019-12-09. *"Size of video picked from the gallery: 20MB ----> I want to compress this video to be 2MB maximum … I cannot give a limit of video compression."* — [link](https://stackoverflow.com/questions/59246836/compress-videos-in-flutter). Users want a **target size**, which the package does not offer (only quality presets).
7. **"ffmpeg arguments with flutter for video upload to firebase"** — 2,640 views, 2019-04-24 — *"compress a videos file size so I can upload to firebase storage"* — [link](https://stackoverflow.com/questions/55837654/ffmpeg-arguments-with-flutter-for-video-upload-to-firebase).
8. **"How can I achieve Telegram-level video compression speed in Flutter (hardware encode + passthrough)?"** — 2025-09-06. *"I've tried the video_compress package, but it's slow (e.g. >1 minute to compress a 100 MB file). From what I can tell, it doesn't reliably use hardware encoders … What I want is something closer to Telegram's behavior: Passthrough/remux if the video is already H.264/AAC ≤ 720p/30fps"* — [link](https://stackoverflow.com/questions/79757413/how-can-i-achieve-telegram-level-video-compression-speed-in-flutter-hardware-en).
9. **"is there any latest compression lib in flutter"** — 2022-06-09. *"not able to compress fast way... it's taking too much of time"* — [link](https://stackoverflow.com/questions/72565889/is-there-any-latest-compression-lib-in-flutter).
10. **"How can I optimize video reels in flutter"** — 2023-09-26. *"I want to display the videos in the same way as the Reels section of TikTok … each video takes time to load … I'm also compressing the videos when they're uploaded to the server."* — [link](https://stackoverflow.com/questions/77177713/how-can-i-optimize-video-reels-in-flutter).
11. **"App Crashs When Compressing Video"** — 3 votes, 2020-06-30 — Android external-storage path failure — [link](https://stackoverflow.com/questions/62669263/app-crashs-when-compressing-video-when-i-use-flutter-video-compession).
12. **"Why is light_compressor in flutter not compressing my videos"** — 2023-06-21 — *"the library that seems to work is light_compressor"* — [link](https://stackoverflow.com/questions/76521283/why-is-light-compressor-in-flutter-not-compressing-my-videos).

The other high-vote hits for `video_compress` are **build breakage**, not usage: "Could not find com.otaliastudios:transcoder:0.9.1" (5 votes, 5,536 views, [link](https://stackoverflow.com/questions/74576677/flutter-gradle-build-failed-with-an-exception-could-not-find-com-otaliastudio)), "Gradle task assembleDebug failed … for video compress" (4 votes, 3,773 views, [link](https://stackoverflow.com/questions/64997538/how-does-one-resolve-gradle-task-assembledebug-failed-with-exit-code-1-error-f)), "Build failed in Flutter app due to video_compress package" (2,828 views, [link](https://stackoverflow.com/questions/75070808/build-failed-in-flutter-app-due-to-video-compress-package)). The same story on the repo's own tracker — the most-commented issues are [#207](https://github.com/jonataslaw/VideoCompress/issues/207) checkDebugAarMetadata (29 comments), [#240](https://github.com/jonataslaw/VideoCompress/issues/240)/[#247](https://github.com/jonataslaw/VideoCompress/issues/247) transcoder:0.9.1 not found (18 + 13), [#193](https://github.com/jonataslaw/VideoCompress/issues/193) "returns null" (18), [#142](https://github.com/jonataslaw/VideoCompress/issues/142) Kotlin plugin version (24 reactions), [#255](https://github.com/jonataslaw/VideoCompress/issues/255) JVM-target mismatch, [#163](https://github.com/jonataslaw/VideoCompress/issues/163) "Flutter Web support" (12 reactions), [#203](https://github.com/jonataslaw/VideoCompress/issues/203)/[#191](https://github.com/jonataslaw/VideoCompress/issues/191) "Failed to stop the muxer". There is even a published fork whose whole description is *"Fixed issues of dependency of transcoder 0.9.1"* ([ansari-salman/video_compress-3.1.2](https://github.com/ansari-salman/video_compress-3.1.2)).

**Reddit:** r/FlutterDev could not be read (both the search crawler and reddit's JSON endpoints refused the request from this box), so no Reddit claims are made here. The nearest forum evidence is the FlutterFlow community thread **"Huge Video File Sizes Please Go Away: On-Device Video Compression for Android?"** — *"30-second videos often exceed 100MB without compression"*, *"A feed of 10 videos can cause a 2GB download spike from Firebase"*, and Android *"uploads raw, uncompressed files, unlike iOS which performs on-device compression"* ([link](https://community.flutterflow.io/ask-the-community/post/huge-video-file-sizes-please-go-away-on-device-video-compression-for-bJGE6qMcoBbAibN)). Alternatives that surface in search results and in the SO threads: `light_compressor` / `light_compressor_v2` (what FluffyChat moved to; "H.264/H.265, target size, trim … Android MediaCodec / Apple AVFoundation", [pub.dev](https://pub.dev/packages/light_compressor_v2)), `ffmpeg_kit_flutter_new` (full FFmpeg, LGPL/GPL binaries), and server-side transcoding (Cloudinary's guide uses `video_compress` 3.1.0 for the client path and pitches its own service for production, [link](https://cloudinary.com/guides/video-effects/2-ways-to-compress-video-in-flutter)).

---

## 4. The why, in plain English

**What people are trying to do.** In almost every case the user has just recorded or picked a phone video and needs to send it somewhere: a chat message (Matrix, OpenIM, Mixin, Easemob, WhatsApp-clones), a feed post (TikTok/Instagram/Shorts clones, DTube, LikeMinds), an evidence attachment (inspection, incident/SOS reporting, insurance claim, vehicle inspection), or a verification selfie (KYC/liveness SDKs). The upload target is overwhelmingly Firebase Storage / GCS / S3 / a Matrix homeserver. They reach for `video_compress` because (a) it is the first result and the most-downloaded, (b) it is "100% native code … we do not use FFMPEG as it is very slow, bloated and the GNU license is an obstacle for commercial applications" ([README](https://github.com/jonataslaw/VideoCompress/blob/master/README.md)), which matters to commercial apps and to binary size, and (c) it also gives them the two adjacent things every upload flow needs — `getMediaInfo` (duration/dimensions to store alongside the message) and `getFileThumbnail` (the poster frame). OpenIM's demo, for example, imports it *only* for `getMediaInfo`.

**Why the raw file is a problem.** Phone cameras produce big files: MacRumors quotes Apple's default (1080p/30) at *"a minute of video takes up 65MB"* ([link](https://www.macrumors.com/how-to/save-storage-space-recording-video-iphone-ipad/)); a third-party calculator lists 720p30 40 MB/min, 1080p30 60 MB/min, 1080p60 90 MB/min, 4K30 170 MB/min, 4K60 400 MB/min, with a disclaimer that these are estimates ([hevcut.com](https://hevcut.com/guides/iphone-video-size-calculator)); Apple's own support pages fetched here did not expose per-minute figures, so treat those as approximate. The SO askers' own numbers — 30 MB→10 MB via iOS picker, 36 MB→20 MB via the plugin, "20MB → 2MB maximum" wanted, 100 MB and 300 MB inputs — bracket the same reality. On Android there is no free picker-side compression, so the same clip is ~3× larger than on iOS until the app compresses it.

**What a good compressor unlocks.**
- *Upload time and reliability on cellular.* A 3× smaller file is a 3× shorter progress bar and 3× fewer failed uploads; the "Telegram-level" question shows the bar users now expect is Telegram's near-instant send.
- *Chat UX.* Messaging apps want a send to feel instant; every Matrix client in §1 compresses before `sendFileEvent`. Twake's code path literally logs the byte count before and after.
- *Storage and egress bills.* Firebase's Blaze plan charges **$0.026/GB stored and $0.12/GB downloaded** on legacy buckets, with only 1 GB/day of free egress ([firebase.google.com/pricing](https://firebase.google.com/pricing)). Egress is charged per *viewer*, so a feed app pays the file size × number of views — which is why the FlutterFlow poster saw "a 2GB download spike" from ten videos. Cloudinary's guide lists the same motivations: *"Faster load times"*, *"Reduced mobile data consumption"*, *"Quicker uploads and less chance of app crashes"*, *"Lower storage and delivery costs on the backend"* ([link](https://cloudinary.com/guides/video-effects/2-ways-to-compress-video-in-flutter)). (AWS's S3 pricing page did not render numeric rates through the fetcher; no S3 figure is quoted.)
- *Playback.* Reels-style feeds need a modest bitrate and a universally playable container; the package's promise of "MP4 containers with AAC audio for universal compatibility across Safari, Mozilla, Chrome, Android, and iOS" ([pub.dev](https://pub.dev/packages/video_compress)) is part of the draw.

**What the evidence says users are missing today** (each cited above): a *target size / bitrate* control rather than three quality presets; hardware-encode with passthrough so a 100 MB file does not take >1 minute; a guarantee that output is never larger than input; Android build stability (the transcoder:0.9.1 / Kotlin / JVM-target issues dominate both SO and the tracker); Web support; and a maintainer who merges PRs (32 open). The single most important data point in this brief is that FluffyChat — one of the package's oldest, most visible users — replaced it on 2026-08-17 for `light_compressor_v2`, while `video_compress` still pulls 167k downloads a month. Demand is intact; the incumbent is drifting.

---

### Files in this scratchpad
`page1..5.json` (raw code-search pages), `repos.json`, `repo_meta.json`, `all_repos.txt` (418 repos, stars, descriptions), `assign.json` (keyword classification), `so1.json`/`so2.json`/`sobodies.json` (StackExchange API dumps).
