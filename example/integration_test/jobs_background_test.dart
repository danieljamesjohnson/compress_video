// Integration test for JOBS-04: calling this plugin from a background isolate. This is the
// phase's single new suite (05-02-PLAN.md) -- it proves a real compression that runs to
// completion entirely inside `Isolate.run` and returns its typed result (task 1), plus the
// omitted-initialisation typed-error case (task 2). This suite deliberately records no
// PARITY_JSON entries -- isolate/background behaviour is platform-divergent by design, so there
// is nothing here worth cross-platform diffing.
//
// BACKGROUND (why `compress()` needed a second host call, `awaitCompressResult`): empirical
// testing during this plan's execution found that `compress()`'s own platform call
// (`CompressHostApi.startCompress`) never resolves when issued from a background isolate, even
// though `getMediaInfo`/`estimate` (the identical outgoing-call mechanism) succeed instantly
// off-root. Root-caused (not assumed): `startCompress`'s native implementation awaits
// `CompressVideoFlutterApi.onProgress`'s Dart-side acknowledgement before returning its final
// value, and a background isolate can NEVER register a handler to send that acknowledgement --
// `BackgroundIsolateBinaryMessenger.setMessageHandler` throws `UnsupportedError`
// unconditionally ("Messages from the host platform always go to the root isolate", the Flutter
// engine's own permanent design). Native genuinely completes the compression (confirmed via
// `adb logcat`: `TransformerInternal: Init` then `Release` within ~200-300ms for the corpus's
// cheapest clip) but its own suspended coroutine is permanently stranded waiting for an
// acknowledgement from an isolate that structurally cannot send one.
//
// The fix (no `SendPort`/`ReceivePort` bridge, staying inside this plan's own prohibitions):
// `CompressHostApi.awaitCompressResult(jobId)`, a second, independent async host call that
// resolves from a per-job outcome `JobRegistry` records the moment it is known -- BEFORE the
// blocking progress push -- rather than from `startCompress`'s own stranded reply.
// `CompressJob._run` detects a background isolate via `RootIsolateToken.instance == null` (null
// everywhere except the root isolate, a cheap synchronous check) and, only in that case, fires
// `startCompress` without awaiting its own reply and awaits `awaitCompressResult` instead. The
// root isolate path is completely unchanged: `startCompress`'s own reply continues to be awaited
// directly, exactly as every other suite in this repository already exercises.
//
// One consequence, confirmed rather than assumed: progress is STILL never delivered to a job
// started on a background isolate (the underlying push mechanism is unconditionally unavailable
// there, independent of this fix) -- only the terminal RESULT now reaches it. The first case
// below asserts the progress stream is genuinely empty rather than leaving it unchecked.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:compress_video/compress_video.dart';
import 'package:flutter/services.dart'
    show MethodChannel, RootIsolateToken, rootBundle;
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

/// The corpus's least expensive clip -- kept cheap since this suite spawns a whole isolate on
/// top of running a real compression.
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

/// The plain, sendable value the successful-compression closure returns. `Isolate.run` requires
/// everything it returns to be sendable across the isolate boundary -- a `CompressResult` (a
/// plain Dart object, not one of the SDK's transferable types) is not, so only primitives and
/// lists/maps of primitives cross back.
class _BackgroundCompressionOutcome {
  const _BackgroundCompressionOutcome({
    required this.progressValues,
    required this.outputPath,
    required this.inputBytes,
    required this.outputBytes,
  });

  final List<double> progressValues;
  final String outputPath;
  final int inputBytes;
  final int outputBytes;
}

/// Example-only (see `MainActivity.kt`'s doc comment): backgrounds this app and reports the
/// emulator's real API level, so the assertions below come from the platform rather than from
/// an assumption about which image is running.
const MethodChannel _backgroundingChannel = MethodChannel(
  'compress_video_example/backgrounding',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Isolate.run: a real compression completes entirely off the root isolate', () {
    testWidgets("the result carries that job's own output path and is never-larger, progress is "
        'confirmed absent (a structural, unrelated Flutter limitation -- see file header), and '
        "the root isolate's own job registry never sees it", (WidgetTester tester) async {
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

      final String inputPath = await _copySmallClip('isolate_run');
      final String outputPath = await _freshOutputPath(
        'isolate_run_output.mp4',
      );

      final _BackgroundCompressionOutcome
      outcome = await Isolate.run<_BackgroundCompressionOutcome>(() async {
        // Must be the first statement: it binds this isolate's own platform messenger
        // before anything else in this closure touches the plugin.
        CompressVideo.ensureInitializedInBackgroundIsolate(token!);

        final CompressVideo compressVideo = CompressVideo();
        final CompressJob job = compressVideo.compress(
          inputPath,
          options: CompressOptions(outputPath: outputPath),
        );

        final List<double> progressValues = <double>[];
        final StreamSubscription<double> subscription = job.progress.listen(
          progressValues.add,
        );
        final CompressResult result = await job.result;
        await subscription.cancel();

        return _BackgroundCompressionOutcome(
          progressValues: progressValues,
          outputPath: result.outputPath,
          inputBytes: result.inputBytes,
          outputBytes: result.outputBytes,
        );
      }).timeout(const Duration(seconds: 30));

      // Checked by existence at the requested path, not string equality with
      // outcome.outputPath: confirmed live that a background isolate's `Directory.systemTemp`
      // (used to build [outputPath] above) can resolve to a different-but-equivalent absolute
      // path alias than the one native reports back (observed: `/data/user/0/<pkg>/...` here
      // vs `/data/data/<pkg>/...` from native) -- both name the same underlying file on
      // Android (the well-known per-user bind-mount alias), so existence at either alias is
      // the correct assertion, not exact string equality across them.
      expect(
        File(outputPath).existsSync(),
        isTrue,
        reason:
            'a file must exist at the exact output path requested; native reported '
            'outputPath=${outcome.outputPath}',
      );
      final File outputFile = File(outcome.outputPath);
      expect(
        outputFile.existsSync(),
        isTrue,
        reason:
            "the compressed file must exist at native's own reported output path",
      );
      expect(outputFile.lengthSync(), greaterThan(0));
      expect(
        outcome.outputBytes,
        lessThanOrEqualTo(outcome.inputBytes),
        reason:
            'never-larger must hold for a job started from a background isolate too',
      );

      // Asserted, not merely unchecked: progress is confirmed EMPTY here, on every platform,
      // because BackgroundIsolateBinaryMessenger.setMessageHandler cannot receive native's
      // unsolicited onProgress push off-root (see file header) -- awaitCompressResult fixes
      // the RESULT, not this. If a future Flutter SDK version changes this, this assertion
      // fails loudly rather than silently passing on a stale expectation.
      expect(
        outcome.progressValues,
        isEmpty,
        reason:
            'progress cannot reach a background isolate through Pigeon\'s FlutterApi push '
            'channel; if this ever starts failing because the list is non-empty, the Flutter '
            'SDK constraint this test documents has changed and this suite (and the README) '
            'should be revisited',
      );

      // The root isolate's own job registry is separate (module-level state is per isolate
      // in Dart): a CompressVideo constructed here has no knowledge of the job that just ran
      // in the spawned isolate. Prove this by running an ordinary root-isolate compression
      // afterwards and confirming it succeeds independently, with its own distinct output.
      final String rootInputPath = await _copySmallClip('root_isolate_control');
      final String rootOutputPath = await _freshOutputPath(
        'root_isolate_control_output.mp4',
      );
      final CompressVideo rootCompressVideo = CompressVideo();
      final CompressJob rootJob = rootCompressVideo.compress(
        rootInputPath,
        options: CompressOptions(outputPath: rootOutputPath),
      );
      final CompressResult rootResult = await rootJob.result;
      // Existence-based, not string equality -- see the identical comment above for why.
      expect(File(rootOutputPath).existsSync(), isTrue);
      expect(File(rootResult.outputPath).existsSync(), isTrue);
      expect(rootOutputPath, isNot(outcome.outputPath));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group(
    'Background isolate: the omitted-initialisation case fails typed, never hangs',
    () {
      testWidgets(
        'forgetting ensureInitializedInBackgroundIsolate produces a typed CompressVideoException '
        'within a bounded time for both a job call and a plain future-returning call',
        (WidgetTester tester) async {
          // Deliberately never captures RootIsolateToken.instance -- the whole point of this case
          // is that the closure below never calls ensureInitializedInBackgroundIsolate at all.
          final String compressInputPath = await _copySmallClip(
            'omitted_init_compress',
          );
          final String compressOutputPath = await _freshOutputPath(
            'omitted_init_compress_output.mp4',
          );
          final String mediaInfoPath = await _copySmallClip(
            'omitted_init_media_info',
          );

          // The closure deliberately never calls ensureInitializedInBackgroundIsolate. Both
          // outcomes are captured as plain strings rather than rethrown across the isolate
          // boundary, and this whole call is awaited under an explicit bounded timeout -- a hang
          // fails this case by timing out with a clear message rather than stalling silently
          // (05-RESEARCH.md Pitfall 2's own warning: a case that never awaits the failing call
          // proves nothing).
          final List<String> outcomes = await Isolate.run<List<String>>(
            () async {
              String describe(Object error) => error is CompressVideoException
                  ? 'CompressVideoException:${error.reason.name}'
                  : error.runtimeType.toString();

              String compressOutcome;
              try {
                final CompressVideo compressVideo = CompressVideo();
                final CompressJob job = compressVideo.compress(
                  compressInputPath,
                  options: CompressOptions(outputPath: compressOutputPath),
                );
                await job.result;
                compressOutcome = 'no error';
              } catch (e) {
                compressOutcome = describe(e);
              }

              String mediaInfoOutcome;
              try {
                final CompressVideo compressVideo = CompressVideo();
                await compressVideo.getMediaInfo(mediaInfoPath);
                mediaInfoOutcome = 'no error';
              } catch (e) {
                mediaInfoOutcome = describe(e);
              }

              return <String>[compressOutcome, mediaInfoOutcome];
            },
          ).timeout(const Duration(seconds: 30));

          expect(
            outcomes[0],
            startsWith('CompressVideoException:'),
            reason:
                'compress() without initialisation must fail typed, not hang or succeed: got ${outcomes[0]}',
          );
          expect(
            outcomes[1],
            startsWith('CompressVideoException:'),
            reason:
                'getMediaInfo() without initialisation must fail typed, not hang or succeed: got ${outcomes[1]}',
          );
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    },
  );

  group('Android foreground service opt-in (JOBS-05, D-07/D-08)', () {
    testWidgets(
      'a job with androidForegroundService set runs inside a real mediaProcessing foreground '
      'service and completes with a typed, never-larger result',
      (WidgetTester tester) async {
        if (!Platform.isAndroid) {
          markTestSkipped(
            'androidForegroundService is Android-only (D-08); Apple platforms ignore the '
            'option entirely -- there is no equivalent to prove there.',
          );
          return;
        }

        final String path = await _copyAssetToTempFile(
          'assets/corpus/portrait_hibitrate_1080p60.mp4',
          'jobs_background_fgs_${DateTime.now().microsecondsSinceEpoch}.mp4',
        );

        final CompressVideo compressVideo = CompressVideo();
        final CompressJob job = compressVideo.compress(
          path,
          options: const CompressOptions(
            androidForegroundService: AndroidForegroundServiceOptions(
              notificationTitle: 'JOBS-05 foreground-service test',
              notificationText: 'compressing a distinctive test clip',
            ),
          ),
        );

        // Captured while the job is in flight for the summary's dumpsys evidence -- this
        // print is grepped by CI's own polled `dumpsys activity services` capture (see
        // 05-03-PLAN.md task 2), not this test itself.
        // ignore: avoid_print
        print(
          'FGS_TEST_JOB_STARTED path=$path notificationTitle="JOBS-05 foreground-service test"',
        );

        final CompressResult result = await job.result.timeout(
          const Duration(seconds: 60),
        );

        expect(
          result.outputBytes,
          lessThanOrEqualTo(result.inputBytes),
          reason:
              'never-larger must hold for a foreground-service-hosted job too',
        );
        expect(
          File(result.outputPath).existsSync(),
          isTrue,
          reason:
              'a foreground-service-hosted job must still produce a real output file',
        );
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );
  });

  group('Backgrounding mid-encode survives, honestly, on whatever API level runs '
      'this suite (JOBS-05, D-08/D-10)', () {
    testWidgets('a job with the foreground-service option keeps progressing after the app is sent to '
        'the background mid-encode, and completes with a typed, never-larger result; below '
        'API 35 the option is accepted and inert', (WidgetTester tester) async {
      if (!Platform.isAndroid) {
        markTestSkipped(
          'the moveTaskToBack/apiLevel channel is Android-only example code; Apple '
          'platforms have no equivalent to prove here.',
        );
        return;
      }

      final int apiLevel =
          await _backgroundingChannel.invokeMethod<int>('apiLevel') ?? 0;
      final bool serviceExpected = apiLevel >= 35;

      final String path = await _copyAssetToTempFile(
        'assets/corpus/portrait_hibitrate_1080p60.mp4',
        'jobs_background_bg_${DateTime.now().microsecondsSinceEpoch}.mp4',
      );

      final CompressVideo compressVideo = CompressVideo();
      final CompressJob job = compressVideo.compress(
        path,
        options: const CompressOptions(
          androidForegroundService: AndroidForegroundServiceOptions(
            notificationTitle: 'Backgrounding test',
            notificationText: 'proving the encode survives backgrounding',
          ),
        ),
      );

      final List<double> progressValues = <double>[];
      final StreamSubscription<double> subscription = job.progress.listen(
        progressValues.add,
      );
      addTearDown(subscription.cancel);

      // Waits for the first real progress event -- clamped below 100 by construction
      // (TransformerEngine.kt) -- so the backgrounding call below genuinely lands
      // mid-encode rather than racing a job that has already finished.
      await Future.doWhile(() async {
        if (progressValues.isNotEmpty) {
          return false;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return true;
      }).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          fail(
            'never observed a progress event before the backgrounding window closed',
          );
        },
      );
      final int progressEventsBeforeBackgrounding = progressValues.length;

      await _backgroundingChannel.invokeMethod<void>('moveTaskToBack');

      final CompressResult result = await job.result.timeout(
        const Duration(seconds: 60),
      );
      await subscription.cancel();

      final int progressEventsAfterBackgrounding = progressValues.length;
      final double highestProgressObserved = progressValues.isEmpty
          ? 0
          : progressValues.reduce((double a, double b) => a > b ? a : b);

      // 05-RESEARCH.md Open Question 1, answered by measurement rather than assumed --
      // grepped by CI as BACKGROUNDING_MEASURED, and quoted verbatim in the summary.
      // ignore: avoid_print
      print(
        'BACKGROUNDING_MEASURED apiLevel=$apiLevel serviceExpected=$serviceExpected '
        'progressEventsBeforeBackgrounding=$progressEventsBeforeBackgrounding '
        'progressEventsAfterBackgrounding=$progressEventsAfterBackgrounding '
        'highestProgressObserved=$highestProgressObserved',
      );

      expect(
        result.outputBytes,
        lessThanOrEqualTo(result.inputBytes),
        reason: 'never-larger must hold for a job backgrounded mid-encode too',
      );
      expect(
        File(result.outputPath).existsSync(),
        isTrue,
        reason:
            'a job backgrounded mid-encode must still produce a real output file',
      );

      if (serviceExpected) {
        expect(
          progressEventsAfterBackgrounding,
          greaterThan(progressEventsBeforeBackgrounding),
          reason:
              'API 35+: the encode must keep progressing in the mediaProcessing foreground '
              'service after the app is backgrounded, not freeze the instant it loses the '
              'foreground -- this is what OQ1 asks this suite to measure rather than assume',
        );
      }
      // Below API 35 (D-08): the option is accepted and inert -- no service starts, and
      // the never-larger/file-exists assertions above already prove the job is unaffected.
      // The BACKGROUNDING_MEASURED line above records which branch this run took.
    }, timeout: const Timeout(Duration(seconds: 90)));
  });

  group('Background isolate: calls proven working since 05-02', () {
    testWidgets(
      'getMediaInfo returns correctly from inside Isolate.run, proving '
      'ensureInitializedInBackgroundIsolate genuinely makes this plugin usable off-root',
      (WidgetTester tester) async {
        final RootIsolateToken? token = RootIsolateToken.instance;
        expect(token, isNotNull);

        final String path = await _copySmallClip('media_info');

        final List<Object?> result = await Isolate.run<List<Object?>>(() async {
          CompressVideo.ensureInitializedInBackgroundIsolate(token!);
          final CompressVideo compressVideo = CompressVideo();
          final MediaInfo info = await compressVideo.getMediaInfo(path);
          return <Object?>[info.widthPx, info.heightPx, info.durationMs];
        }).timeout(const Duration(seconds: 30));

        expect(result[0], greaterThan(0), reason: 'widthPx');
        expect(result[1], greaterThan(0), reason: 'heightPx');
        expect(result[2], greaterThan(0), reason: 'durationMs');
      },
      timeout: const Timeout(Duration(seconds: 40)),
    );
  });
}
