## 0.1.0

Initial unreleased development version. Not yet published to pub.dev.

* Plugin scaffold for Android, iOS and macOS with a shared `darwin/` Apple source tree.
* Typed error taxonomy (`CompressVideoException`, `CompressVideoErrorReason`).
* Typed Pigeon contract for every Dart-native call; no hand-written channel map anywhere in the
  package, enforced by a dedicated CI check.
* `CompressVideo.getMediaInfo(path)` — duration, displayed (rotation-corrected) dimensions,
  rotation, size, codec, bitrate, frame rate, audio presence and HDR-ness, on Android
  (`MediaMetadataRetriever`) and Apple (`AVFoundation`).
* `CompressVideo.getThumbnail` / `getThumbnailFile` — a rotation-correct poster frame as JPEG
  bytes or written to a file, at any millisecond, with quality and max-dimension controls that
  never upscale.
* CI on a Linux runner (Android) and a macOS runner (iOS + macOS), path-gated.
* A cross-platform parity gate (`tool/check_parity.sh`): a dedicated CI job diffs the
  `crossPlatform` media-info and thumbnail values the Android emulator and the iOS simulator
  each actually observed, so "the two platforms agree" is a diff, not an inference from running
  the same test file on both.
* CI is green on both runners plus the parity gate (run 35631865999).
