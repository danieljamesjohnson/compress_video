// Platform-free unit coverage of the video_compress compatibility library
// (lib/video_compress_compat.dart, 06-01-PLAN.md): every member of the incumbent's public
// surface, driven through the generated Pigeon host APIs' own channels and codec, exactly like
// test/compress_video_queue_test.dart and test/media_info_mapping_test.dart.
//
// No emulator and no real platform round trip. The shim is deprecated on purpose (it exists to
// be migrated away from), so this file ignores the deprecation lint for the whole file.
// ignore_for_file: deprecated_member_use_from_same_package
import 'dart:async';
import 'dart:io';

import 'package:compress_video/compress_video.dart'
    show
        CompressOptions,
        CompressPreset,
        CompressVideoErrorReason,
        CompressVideoException,
        kPresetSpecs;
import 'package:compress_video/src/compress_job.dart'
    show CompressVideoFlutterApiImpl;
import 'package:compress_video/src/messages.g.dart';
import 'package:compress_video/video_compress_compat.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _getMediaInfoChannelName =
    'dev.flutter.pigeon.compress_video.ProbeHostApi.getMediaInfo';
const MessageCodec<Object?> _codec = ProbeHostApi.pigeonChannelCodec;

void _setHandler(
  String channelName,
  Future<ByteData?> Function(ByteData? message)? handler,
) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(channelName, handler);
}

const String _startCompressChannelName =
    'dev.flutter.pigeon.compress_video.CompressHostApi.startCompress';
const String _cancelChannelName =
    'dev.flutter.pigeon.compress_video.CompressHostApi.cancel';
const String _clearCacheChannelName =
    'dev.flutter.pigeon.compress_video.CompressHostApi.clearCache';
const String _getThumbnailChannelName =
    'dev.flutter.pigeon.compress_video.ThumbnailHostApi.getThumbnail';
const String _getThumbnailFileChannelName =
    'dev.flutter.pigeon.compress_video.ThumbnailHostApi.getThumbnailFile';

/// Fakes the native side of every host call the shim's compression, thumbnail and cache verbs
/// reach. `startCompress` is held open on a per-job [Completer] the test resolves by hand, so
/// "in flight" is a state a test controls, never a wall-clock sleep.
class _FakeHost {
  final List<String> startedJobIds = <String>[];
  final List<String> startedPaths = <String>[];
  final List<CompressRequestMessage> requests = <CompressRequestMessage>[];
  final List<String> cancelledJobIds = <String>[];
  final List<List<Object?>> thumbnailCalls = <List<Object?>>[];
  final List<List<Object?>> thumbnailFileCalls = <List<Object?>>[];
  int clearCacheCalls = 0;

  /// When set, `clearCache` replies with a platform error carrying this reason name.
  String? clearCacheFailure;

  /// What `getThumbnailFile` replies with.
  String thumbnailFilePath = '/tmp/fake-thumbnail.jpg';

  final Map<String, Completer<ByteData?>> _pendingReplies =
      <String, Completer<ByteData?>>{};

  void install() {
    _setHandler(_startCompressChannelName, (ByteData? message) async {
      final List<Object?> args =
          _codec.decodeMessage(message)! as List<Object?>;
      final String jobId = args[1]! as String;
      startedPaths.add(args[0]! as String);
      startedJobIds.add(jobId);
      requests.add(args[2]! as CompressRequestMessage);
      final Completer<ByteData?> completer = Completer<ByteData?>();
      _pendingReplies[jobId] = completer;
      return completer.future;
    });
    _setHandler(_cancelChannelName, (ByteData? message) async {
      final List<Object?> args =
          _codec.decodeMessage(message)! as List<Object?>;
      cancelledJobIds.add(args[0]! as String);
      return _codec.encodeMessage(<Object?>[null]);
    });
    _setHandler(_clearCacheChannelName, (ByteData? message) async {
      clearCacheCalls++;
      final String? failure = clearCacheFailure;
      if (failure != null) {
        return _codec.encodeMessage(<Object?>[
          failure,
          'simulated platform error',
          null,
        ]);
      }
      return _codec.encodeMessage(<Object?>[null]);
    });
    _setHandler(_getThumbnailChannelName, (ByteData? message) async {
      thumbnailCalls.add(_codec.decodeMessage(message)! as List<Object?>);
      return _codec.encodeMessage(<Object?>[
        Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF]),
      ]);
    });
    _setHandler(_getThumbnailFileChannelName, (ByteData? message) async {
      thumbnailFileCalls.add(_codec.decodeMessage(message)! as List<Object?>);
      return _codec.encodeMessage(<Object?>[thumbnailFilePath]);
    });
  }

  void uninstall() {
    _setHandler(_startCompressChannelName, null);
    _setHandler(_cancelChannelName, null);
    _setHandler(_clearCacheChannelName, null);
    _setHandler(_getThumbnailChannelName, null);
    _setHandler(_getThumbnailFileChannelName, null);
  }

  /// Resolves [jobId]'s in-flight `startCompress` call with a successful result.
  void completeSuccess(
    String jobId, {
    String outputPath = '/tmp/fake-output.mp4',
  }) {
    _pendingReplies
        .remove(jobId)!
        .complete(
          _codec.encodeMessage(<Object?>[
            CompressResultMessage(
              outputPath: outputPath,
              inputBytes: 1000,
              outputBytes: 500,
              widthPx: 640,
              heightPx: 360,
              durationMs: 4000,
              videoCodec: 'h264',
              audioCodec: 'aac',
              transmuxed: false,
              usedOriginal: false,
              toneMapped: false,
              hevcFallback: false,
              audioReencoded: false,
              elapsedMs: 100,
            ),
          ]),
        );
  }

  /// Resolves [jobId]'s in-flight `startCompress` call with a typed failure.
  void completeFailure(String jobId, String reasonName) {
    _pendingReplies
        .remove(jobId)!
        .complete(
          _codec.encodeMessage(<Object?>[
            reasonName,
            'simulated platform error',
            null,
          ]),
        );
  }
}

Matcher _throwsCompressVideoException(CompressVideoErrorReason reason) =>
    throwsA(
      isA<CompressVideoException>().having(
        (CompressVideoException e) => e.reason,
        'reason',
        reason,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    VideoCompress.dispose();
    _setHandler(_getMediaInfoChannelName, null);
  });

  group('VideoQuality', () {
    test("has the incumbent's eight values in the incumbent's order", () {
      expect(VideoQuality.values.length, 8);
      expect(
        VideoQuality.values.map((VideoQuality q) => q.name).toList(),
        <String>[
          'DefaultQuality',
          'LowQuality',
          'MediumQuality',
          'HighestQuality',
          'Res640x480Quality',
          'Res960x540Quality',
          'Res1280x720Quality',
          'Res1920x1080Quality',
        ],
      );
    });

    test('every value maps to exactly the documented CompressOptions', () {
      const Map<VideoQuality, CompressOptions> expected =
          <VideoQuality, CompressOptions>{
            VideoQuality.DefaultQuality: CompressOptions(
              preset: CompressPreset.p720,
            ),
            VideoQuality.LowQuality: CompressOptions(
              preset: CompressPreset.p360,
            ),
            VideoQuality.MediumQuality: CompressOptions(
              preset: CompressPreset.p480,
            ),
            VideoQuality.HighestQuality: CompressOptions(
              preset: CompressPreset.p1080,
            ),
            VideoQuality.Res640x480Quality: CompressOptions(
              preset: CompressPreset.p360,
            ),
            VideoQuality.Res960x540Quality: CompressOptions(
              preset: CompressPreset.p720,
              maxLongSidePx: 960,
            ),
            VideoQuality.Res1280x720Quality: CompressOptions(
              preset: CompressPreset.p720,
            ),
            VideoQuality.Res1920x1080Quality: CompressOptions(
              preset: CompressPreset.p1080,
            ),
          };
      // Guards the table above against a ninth value being added without a mapping.
      expect(expected.keys.toSet(), VideoQuality.values.toSet());

      for (final VideoQuality quality in VideoQuality.values) {
        final CompressOptions options = quality.compressOptions;
        expect(options, expected[quality], reason: quality.name);
        expect(options.validate, returnsNormally, reason: quality.name);
      }
    });

    test('the Res* names resolve to the long side their name states', () {
      int longSide(VideoQuality quality) {
        final CompressOptions options = quality.compressOptions;
        return options.maxLongSidePx ??
            kPresetSpecs[options.preset]!.maxLongSidePx;
      }

      expect(longSide(VideoQuality.Res640x480Quality), 640);
      expect(longSide(VideoQuality.Res960x540Quality), 960);
      expect(longSide(VideoQuality.Res1280x720Quality), 1280);
      expect(longSide(VideoQuality.Res1920x1080Quality), 1920);
    });
  });

  group('VideoCompress singleton', () {
    test('is one instance until dispose() is called, and a new one after', () {
      final IVideoCompress first = VideoCompress;
      expect(identical(first, VideoCompress), isTrue);

      first.dispose();

      expect(identical(first, VideoCompress), isFalse);
    });

    test('isCompressing is false by default', () {
      expect(VideoCompress.isCompressing, isFalse);
    });

    test('setLogLevel completes without touching the platform', () async {
      await expectLater(VideoCompress.setLogLevel(0), completes);
    });
  });

  group('getMediaInfo', () {
    test('maps the typed engine fields onto the compat MediaInfo', () async {
      _setHandler(_getMediaInfoChannelName, (ByteData? message) async {
        final MediaInfoMessage response = MediaInfoMessage(
          durationMs: 4000,
          widthPx: 1080,
          heightPx: 1920,
          rotationDegrees: 90,
          sizeBytes: 150610,
          videoCodec: 'h264',
          videoBitrateBps: 192768,
          frameRateFps: 30.0,
          hasAudio: true,
          isHdr: false,
        );
        return _codec.encodeMessage(<Object?>[response]);
      });

      final MediaInfo info = await VideoCompress.getMediaInfo('/tmp/full.mp4');

      expect(info.path, '/tmp/full.mp4');
      expect(info.width, 1080);
      expect(info.height, 1920);
      expect(info.orientation, 90);
      expect(info.filesize, 150610);
      expect(info.duration, 4000.0);
      expect(info.file, isNotNull);
      expect(info.file!.path, '/tmp/full.mp4');
      expect(info.title, isNull);
      expect(info.author, isNull);
      expect(info.isCancel, isNull);
    });

    test(
      'a platform fileNotFound surfaces as a typed exception, never null',
      () async {
        _setHandler(_getMediaInfoChannelName, (ByteData? message) async {
          return _codec.encodeMessage(<Object?>[
            'fileNotFound',
            'simulated platform error',
            null,
          ]);
        });

        await expectLater(
          () => VideoCompress.getMediaInfo('/tmp/missing.mp4'),
          _throwsCompressVideoException(CompressVideoErrorReason.fileNotFound),
        );
      },
    );
  });

  group('MediaInfo.toJson', () {
    test("writes the incumbent's key set", () {
      final MediaInfo info = MediaInfo(
        path: '/tmp/a.mp4',
        width: 640,
        height: 360,
        orientation: 0,
        filesize: 500,
        duration: 4000.0,
        isCancel: false,
      );

      final Map<String, dynamic> json = info.toJson();

      expect(json.keys.toSet(), <String>{
        'path',
        'title',
        'author',
        'width',
        'height',
        'orientation',
        'filesize',
        'duration',
        'isCancel',
        'file',
      });
      expect(json['path'], '/tmp/a.mp4');
      expect(json['filesize'], 500);
      expect(json['duration'], 4000.0);
    });

    test('omits orientation and isCancel when they are null, and survives a '
        'null path', () {
      final Map<String, dynamic> json = MediaInfo(path: null).toJson();

      expect(json.containsKey('orientation'), isFalse);
      expect(json.containsKey('isCancel'), isFalse);
      expect(json['path'], isNull);
      expect(json['file'], isNull);
    });
  });

  group('ObservableBuilder', () {
    test('notSubscribed flips on the first subscribe', () {
      final ObservableBuilder<double> builder = ObservableBuilder<double>();
      expect(builder.notSubscribed, isTrue);

      final Subscription subscription = builder.subscribe((double _) {});

      expect(builder.notSubscribed, isFalse);
      subscription.unsubscribe();
    });
  });

  group('compressVideo', () {
    late _FakeHost fake;

    setUp(() {
      fake = _FakeHost()..install();
    });

    tearDown(() {
      fake.uninstall();
    });

    test('maps quality, trim in seconds, includeAudio and frameRate onto the '
        'request, and the result onto MediaInfo', () async {
      expect(VideoCompress.isCompressing, isFalse);

      final Future<MediaInfo> pending = VideoCompress.compressVideo(
        '/x.mp4',
        quality: VideoQuality.LowQuality,
        startTime: 2,
        duration: 3,
        includeAudio: false,
        frameRate: 24,
      );

      expect(VideoCompress.isCompressing, isTrue);
      expect(fake.startedPaths, <String>['/x.mp4']);
      final CompressRequestMessage request = fake.requests.single;
      expect(request.presetMaxLongSidePx, 640);
      expect(request.maxLongSidePx, isNull);
      expect(request.trimStartMs, 2000);
      expect(request.trimEndMs, 5000);
      expect(request.audioMode, AudioModeMessage.strip);
      expect(request.maxFps, 24);
      expect(request.outputPath, isNull);

      fake.completeSuccess(fake.startedJobIds.single);
      final MediaInfo info = await pending;

      expect(info.path, '/tmp/fake-output.mp4');
      expect(info.file!.path, '/tmp/fake-output.mp4');
      expect(info.width, 640);
      expect(info.height, 360);
      expect(info.filesize, 500);
      expect(info.duration, 4000.0);
      expect(info.isCancel, isFalse);
      expect(VideoCompress.isCompressing, isFalse);
    });

    test('defaults: DefaultQuality is p720, audio passes through, 30 fps, no '
        'trim', () async {
      final Future<MediaInfo> pending = VideoCompress.compressVideo('/x.mp4');

      final CompressRequestMessage request = fake.requests.single;
      expect(request.presetMaxLongSidePx, 1280);
      expect(request.maxLongSidePx, isNull);
      expect(request.trimStartMs, isNull);
      expect(request.trimEndMs, isNull);
      expect(request.audioMode, AudioModeMessage.passthrough);
      expect(request.maxFps, 30);

      fake.completeSuccess(fake.startedJobIds.single);
      await pending;
    });

    test(
      'duration without startTime trims from the start of the clip',
      () async {
        final Future<MediaInfo> pending = VideoCompress.compressVideo(
          '/x.mp4',
          duration: 3,
        );

        final CompressRequestMessage request = fake.requests.single;
        expect(request.trimStartMs, isNull);
        expect(request.trimEndMs, 3000);

        fake.completeSuccess(fake.startedJobIds.single);
        await pending;
      },
    );

    test('Res960x540Quality sends an explicit 960 long side over the p720 '
        'preset', () async {
      final Future<MediaInfo> pending = VideoCompress.compressVideo(
        '/x.mp4',
        quality: VideoQuality.Res960x540Quality,
      );

      final CompressRequestMessage request = fake.requests.single;
      expect(request.maxLongSidePx, 960);
      expect(request.presetMaxLongSidePx, 1280);

      fake.completeSuccess(fake.startedJobIds.single);
      await pending;
    });

    test('a second compressVideo while one is in flight throws StateError '
        'before any channel call', () async {
      final Future<MediaInfo> first = VideoCompress.compressVideo('/a.mp4');
      expect(VideoCompress.isCompressing, isTrue);

      await expectLater(
        () => VideoCompress.compressVideo('/b.mp4'),
        throwsA(isA<StateError>()),
      );

      expect(fake.startedJobIds, hasLength(1));
      expect(fake.startedPaths, <String>['/a.mp4']);
      expect(VideoCompress.isCompressing, isTrue);

      fake.completeSuccess(fake.startedJobIds.single);
      await first;
      expect(VideoCompress.isCompressing, isFalse);

      // The slot is free again: a later call starts normally.
      final Future<MediaInfo> third = VideoCompress.compressVideo('/c.mp4');
      expect(fake.startedPaths, <String>['/a.mp4', '/c.mp4']);
      fake.completeSuccess(fake.startedJobIds.last);
      await third;
    });

    test('progress reaches two subscribers of compressProgress\$, and after '
        'one unsubscribes only the other still receives', () async {
      final List<double> seenByA = <double>[];
      final List<double> seenByB = <double>[];
      final Subscription subscriptionA = VideoCompress.compressProgress$
          .subscribe(seenByA.add);
      final Subscription subscriptionB = VideoCompress.compressProgress$
          .subscribe(seenByB.add);

      final Future<MediaInfo> pending = VideoCompress.compressVideo('/x.mp4');
      final String jobId = fake.startedJobIds.single;

      CompressVideoFlutterApiImpl().onProgress(jobId, 42.0);
      await pumpEventQueue();
      expect(seenByA, <double>[42.0]);
      expect(seenByB, <double>[42.0]);

      subscriptionA.unsubscribe();
      CompressVideoFlutterApiImpl().onProgress(jobId, 77.0);
      await pumpEventQueue();
      expect(seenByA, <double>[42.0]);
      expect(seenByB, <double>[42.0, 77.0]);

      fake.completeSuccess(jobId);
      await pending;
      subscriptionB.unsubscribe();
    });

    test('cancelCompression cancels the job in flight, and compressVideo '
        'resolves to MediaInfo(isCancel: true) with a null path', () async {
      final Future<MediaInfo> pending = VideoCompress.compressVideo('/x.mp4');
      final String jobId = fake.startedJobIds.single;

      await VideoCompress.cancelCompression();
      expect(fake.cancelledJobIds, <String>[jobId]);

      // Mirrors how native resolves the in-flight call once its own cancel completes.
      fake.completeFailure(jobId, 'cancelled');
      final MediaInfo info = await pending;

      expect(info.isCancel, isTrue);
      expect(info.path, isNull);
      expect(info.file, isNull);
      expect(VideoCompress.isCompressing, isFalse);
    });

    test('after dispose() the compression in flight is still visible, still '
        'cancellable, and still blocks a second compressVideo', () async {
      final IVideoCompress first = VideoCompress;
      final Future<MediaInfo> pending = first.compressVideo('/a.mp4');
      final String jobId = fake.startedJobIds.single;

      first.dispose();
      expect(identical(first, VideoCompress), isFalse);

      expect(VideoCompress.isCompressing, isTrue);
      await expectLater(
        () => VideoCompress.compressVideo('/b.mp4'),
        throwsA(isA<StateError>()),
      );
      expect(fake.startedPaths, <String>['/a.mp4']);

      await VideoCompress.cancelCompression();
      expect(fake.cancelledJobIds, <String>[jobId]);

      fake.completeFailure(jobId, 'cancelled');
      final MediaInfo info = await pending;
      expect(info.isCancel, isTrue);
      expect(VideoCompress.isCompressing, isFalse);

      // The slot is free again on the new instance.
      final Future<MediaInfo> next = VideoCompress.compressVideo('/c.mp4');
      expect(fake.startedPaths, <String>['/a.mp4', '/c.mp4']);
      fake.completeSuccess(fake.startedJobIds.last);
      await next;
    });

    test('cancelCompression with nothing in flight completes and sends no '
        'cancel', () async {
      await expectLater(VideoCompress.cancelCompression(), completes);

      expect(fake.cancelledJobIds, isEmpty);
    });

    test('a platform outOfSpace failure throws a typed exception, and '
        'isCompressing is false afterwards', () async {
      final Future<MediaInfo> pending = VideoCompress.compressVideo('/x.mp4');
      // Observed before the failure is delivered, so it is never an unhandled async error.
      final Future<void> expectation = expectLater(
        pending,
        _throwsCompressVideoException(CompressVideoErrorReason.outOfSpace),
      );

      fake.completeFailure(fake.startedJobIds.single, 'outOfSpace');
      await expectation;

      expect(VideoCompress.isCompressing, isFalse);
    });

    test('an invalid argument throws a typed exception without starting a '
        'job, and leaves isCompressing false', () async {
      await expectLater(
        () => VideoCompress.compressVideo('/x.mp4', frameRate: 0),
        _throwsCompressVideoException(
          CompressVideoErrorReason.unsupportedInput,
        ),
      );

      expect(fake.startedJobIds, isEmpty);
      expect(VideoCompress.isCompressing, isFalse);
    });

    group('deleteOrigin', () {
      late Directory tempDir;
      late File input;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('compat_delete_origin_');
        input = File('${tempDir.path}/input.mp4')
          ..writeAsBytesSync(<int>[1, 2, 3, 4]);
      });

      tearDown(() {
        tempDir.deleteSync(recursive: true);
      });

      test('deleteOrigin: true deletes the input once the output is a '
          'different file', () async {
        final File output = File('${tempDir.path}/output.mp4')
          ..writeAsBytesSync(<int>[1, 2]);

        final Future<MediaInfo> pending = VideoCompress.compressVideo(
          input.path,
          deleteOrigin: true,
        );
        fake.completeSuccess(
          fake.startedJobIds.single,
          outputPath: output.path,
        );
        final MediaInfo info = await pending;

        expect(info.path, output.path);
        expect(input.existsSync(), isFalse);
        expect(output.existsSync(), isTrue);
      });

      test('deleteOrigin: true leaves the input when the output path is the '
          'input path', () async {
        final Future<MediaInfo> pending = VideoCompress.compressVideo(
          input.path,
          deleteOrigin: true,
        );
        fake.completeSuccess(fake.startedJobIds.single, outputPath: input.path);
        await pending;

        expect(input.existsSync(), isTrue);
      });

      test('deleteOrigin: true leaves the input when the output path is '
          'another name for the same file', () async {
        final Link alias = Link('${tempDir.path}/alias.mp4')
          ..createSync(input.path);

        final Future<MediaInfo> pending = VideoCompress.compressVideo(
          input.path,
          deleteOrigin: true,
        );
        fake.completeSuccess(fake.startedJobIds.single, outputPath: alias.path);
        await pending;

        expect(input.existsSync(), isTrue);
      });

      test('deleteOrigin: true leaves the input when the job fails', () async {
        final Future<MediaInfo> pending = VideoCompress.compressVideo(
          input.path,
          deleteOrigin: true,
        );
        final Future<void> expectation = expectLater(
          pending,
          _throwsCompressVideoException(CompressVideoErrorReason.io),
        );
        fake.completeFailure(fake.startedJobIds.single, 'io');
        await expectation;

        expect(input.existsSync(), isTrue);
      });

      test('deleteOrigin: true leaves the input when the job is '
          'cancelled', () async {
        final Future<MediaInfo> pending = VideoCompress.compressVideo(
          input.path,
          deleteOrigin: true,
        );
        await VideoCompress.cancelCompression();
        fake.completeFailure(fake.startedJobIds.single, 'cancelled');
        final MediaInfo info = await pending;

        expect(info.isCancel, isTrue);
        expect(input.existsSync(), isTrue);
      });

      test('deleteOrigin defaults to false and leaves the input', () async {
        final File output = File('${tempDir.path}/output.mp4')
          ..writeAsBytesSync(<int>[1, 2]);

        final Future<MediaInfo> pending = VideoCompress.compressVideo(
          input.path,
        );
        fake.completeSuccess(
          fake.startedJobIds.single,
          outputPath: output.path,
        );
        await pending;

        expect(input.existsSync(), isTrue);
      });
    });
  });

  group('thumbnails', () {
    late _FakeHost fake;

    setUp(() {
      fake = _FakeHost()..install();
    });

    tearDown(() {
      fake.uninstall();
    });

    test("getByteThumbnail with the incumbent's defaults sends position 0 and "
        'quality 100', () async {
      final Uint8List bytes = await VideoCompress.getByteThumbnail('/x.mp4');

      expect(bytes, <int>[0xFF, 0xD8, 0xFF]);
      expect(fake.thumbnailCalls.single, <Object?>['/x.mp4', 0, 100, null]);
    });

    test('getByteThumbnail passes an explicit quality and position '
        'through', () async {
      await VideoCompress.getByteThumbnail(
        '/x.mp4',
        quality: 50,
        position: 1500,
      );

      expect(fake.thumbnailCalls.single, <Object?>['/x.mp4', 1500, 50, null]);
    });

    test('getByteThumbnail with an out-of-range quality throws a typed '
        'exception', () async {
      await expectLater(
        () => VideoCompress.getByteThumbnail('/x.mp4', quality: 0),
        _throwsCompressVideoException(
          CompressVideoErrorReason.unsupportedInput,
        ),
      );

      expect(fake.thumbnailCalls, isEmpty);
    });

    test('getFileThumbnail returns the File the engine wrote', () async {
      fake.thumbnailFilePath = '/cache/thumb-1.jpg';

      final File file = await VideoCompress.getFileThumbnail(
        '/x.mp4',
        quality: 50,
        position: -1,
      );

      expect(file.path, '/cache/thumb-1.jpg');
      expect(fake.thumbnailFileCalls.single, <Object?>[
        '/x.mp4',
        0,
        50,
        null,
        null,
      ]);
    });
  });

  group('deleteAllCache', () {
    late _FakeHost fake;

    setUp(() {
      fake = _FakeHost()..install();
    });

    tearDown(() {
      fake.uninstall();
    });

    test("deleteAllCache calls the engine's clearCache and returns "
        'true', () async {
      final bool deleted = await VideoCompress.deleteAllCache();

      expect(deleted, isTrue);
      expect(fake.clearCacheCalls, 1);
    });

    test('deleteAllCache throws a typed exception when the platform '
        'fails', () async {
      fake.clearCacheFailure = 'io';

      await expectLater(
        VideoCompress.deleteAllCache,
        _throwsCompressVideoException(CompressVideoErrorReason.io),
      );
    });
  });
}
