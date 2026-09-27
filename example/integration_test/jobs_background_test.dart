// Integration test for JOBS-04: calling this plugin from a background isolate.
//
// STATUS (05-02 execution, 2026-09-27): this suite is INCOMPLETE relative to 05-02-PLAN.md's
// original scope. Task 1's own acceptance criteria demanded a real compression that both
// completes AND delivers progress to the spawned isolate; empirical testing during this plan's
// execution found that is not achievable for THIS half (the compression call itself), for a
// reason unrelated to progress delivery -- see the skipped case below and QUESTIONS.md for the
// full write-up. This file therefore proves the part of JOBS-04 that IS verified working
// (`getMediaInfo`, and by the same code path `getThumbnail`/`estimate`/`clearCache`, all callable
// from a background isolate once `ensureInitializedInBackgroundIsolate` is called) and documents,
// rather than hides, the part that currently is not (`compress`). This suite deliberately records
// no PARITY_JSON entries -- isolate/background behaviour is platform-divergent by design, so
// there is nothing here worth cross-platform diffing.
//
// Two things were confirmed empirically against the Flutter SDK source
// (`_background_isolate_binary_messenger_io.dart`) and this plugin's own native logs during this
// plan's execution, not assumed from 05-RESEARCH.md's original (lower-confidence) text:
//
// 1. Progress can NEVER be delivered to a job started on a background isolate, on any platform.
//    Pigeon's `onProgress` push from native lands on a Dart `BasicMessageChannel.setMessageHandler`,
//    and `BackgroundIsolateBinaryMessenger.setMessageHandler` throws `UnsupportedError`
//    unconditionally -- "Messages from the host platform always go to the root isolate" is the
//    Flutter engine's own, permanent design, not a bug in this plugin or something Pigeon codegen
//    could avoid. Working around it would mean hand-rolling a `SendPort`/`ReceivePort` relay from
//    the root isolate back into the spawned isolate, which 05-RESEARCH.md's own "Don't Hand-Roll"
//    table and this plan's own prohibitions explicitly rule out. `lib/src/compress_job.dart`'s
//    `_ensureFlutterApiRegistered` now catches this and continues rather than letting it crash
//    `compress()` synchronously (05-02, Rule 1/3 deviation) -- but registration failing is a
//    SEPARATE finding from what follows.
//
// 2. Separately, and more severely: `compress()`'s own platform call (`CompressHostApi
//    .startCompress`, an ordinary outgoing `send()`-based request/reply -- the SAME mechanism
//    `getMediaInfo`/`estimate` use, and those DO complete correctly off-root) never resolves when
//    issued from a background isolate. Native's `Media3` `Transformer` genuinely runs and
//    completes (confirmed via `adb logcat`: `TransformerInternal: Init` followed by `Release`
//    within ~200-300ms for the corpus's cheapest clip), but the Dart-side `await` on the reply
//    hangs forever -- not a typed exception, an actual hang, reproduced three times with debug
//    instrumentation isolating the call to `_api.startCompress(...)` specifically (confirmed via
//    `getMediaInfo`/`estimate` succeeding instantly under the identical harness). This matches the
//    shape of the upstream issue 05-RESEARCH.md's own Pitfall 2 cited (flutter/flutter#144342: a
//    null-check exception during a platform message response callback, silently reported rather
//    than surfaced) -- but is WORSE than that citation's "MEDIUM confidence, untested" framing
//    assumed: the hang reproduces on the plain, correctly-initialised happy path, not only when
//    initialisation is skipped. This is an external Flutter engine limitation, not something
//    fixable inside this package without the same prohibited bridge. See QUESTIONS.md for the
//    decision this raises for JOBS-04's scope.
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:compress_video/compress_video.dart';
import 'package:flutter/services.dart' show RootIsolateToken, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Copies a bundled corpus asset out of [rootBundle] into a fresh temporary file and returns
/// its filesystem path -- this file's own copy of compress_jobs_test.dart's private helper of
/// the same shape (each suite in this directory carries its own rather than exporting one).
Future<String> _copyAssetToTempFile(String assetPath, String fileName) async {
  final ByteData data = await rootBundle.load(assetPath);
  final Directory tempDir = await Directory.systemTemp.createTemp(
    'compress_video_jobs_background_test_',
  );
  final File file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    flush: true,
  );
  return file.path;
}

/// The corpus's least expensive clip -- kept cheap since this suite spawns a whole isolate.
Future<String> _copySmallClip(String suffix) => _copyAssetToTempFile(
  'assets/corpus/small_480p.mp4',
  'jobs_background_${suffix}_${DateTime.now().microsecondsSinceEpoch}.mp4',
);

/// Returns a path inside a fresh temporary directory that no file has ever been written to.
Future<String> _freshOutputPath(String fileName) async {
  final Directory tempDir = await Directory.systemTemp.createTemp(
    'compress_video_jobs_background_test_output_',
  );
  return '${tempDir.path}/$fileName';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Background isolate: calls that are confirmed working', () {
    testWidgets(
      'getMediaInfo returns correctly from inside Isolate.run, proving '
      'ensureInitializedInBackgroundIsolate genuinely makes this plugin usable off-root '
      "for every call that does not depend on native's unsolicited progress push",
      (WidgetTester tester) async {
        // Captured on the root isolate: `RootIsolateToken.instance` is null anywhere else, so
        // it must be obtained here and passed into the closure rather than looked up inside it.
        final RootIsolateToken? token = RootIsolateToken.instance;
        expect(
          token,
          isNotNull,
          reason:
              'RootIsolateToken.instance must be non-null on the root isolate '
              '(if this fails, the test itself is running off the root isolate)',
        );

        final String path = await _copySmallClip('media_info');

        final List<Object?> result = await Isolate.run<List<Object?>>(() async {
          // Must be the first statement: it binds this isolate's own platform messenger
          // before anything else in this closure touches the plugin.
          CompressVideo.ensureInitializedInBackgroundIsolate(token!);

          final CompressVideo compressVideo = CompressVideo();
          final MediaInfo info = await compressVideo.getMediaInfo(path);
          // Isolate.run requires everything it returns to be sendable -- a plain list of
          // primitives, not a MediaInfo instance.
          return <Object?>[info.widthPx, info.heightPx, info.durationMs];
        });

        expect(result[0], greaterThan(0), reason: 'widthPx');
        expect(result[1], greaterThan(0), reason: 'heightPx');
        expect(result[2], greaterThan(0), reason: 'durationMs');
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });

  group('Background isolate: compress() -- confirmed NOT working, documented not hidden', () {
    testWidgets(
      'compress() issued from inside Isolate.run never resolves -- native completes the '
      'transform (confirmed via logcat) but the Dart-side await hangs; skipped rather than '
      'left to time out the whole suite, per QUESTIONS.md',
      (WidgetTester tester) async {
        final RootIsolateToken token = RootIsolateToken.instance!;
        final String inputPath = await _copySmallClip('compress_hang_repro');
        final String outputPath = await _freshOutputPath(
          'compress_hang_repro_output.mp4',
        );

        // Bounded so a CI run that hits this (if ever un-skipped) fails fast with a clear
        // TimeoutException rather than consuming the whole step's budget.
        await Isolate.run<void>(() async {
          CompressVideo.ensureInitializedInBackgroundIsolate(token);
          final CompressVideo compressVideo = CompressVideo();
          final CompressJob job = compressVideo.compress(
            inputPath,
            options: CompressOptions(outputPath: outputPath),
          );
          await job.result;
        }).timeout(const Duration(seconds: 30));
      },
      // Confirmed hang, not a flake: compress() from a background isolate never resolves
      // (native Transformer completes per logcat; the Dart await does not). External Flutter
      // engine limitation, not fixable here without a prohibited SendPort/ReceivePort bridge --
      // see QUESTIONS.md and this file's header. Un-skip once either the upstream engine
      // behaviour changes or a sanctioned fix is agreed.
      skip: true,
    );
  });
}
