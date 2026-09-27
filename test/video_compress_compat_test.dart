// Platform-free unit coverage of the video_compress compatibility library
// (lib/video_compress_compat.dart, 06-01-PLAN.md): every member of the incumbent's public
// surface, driven through the generated Pigeon host APIs' own channels and codec, exactly like
// test/compress_video_queue_test.dart and test/media_info_mapping_test.dart.
//
// No emulator and no real platform round trip. The shim is deprecated on purpose (it exists to
// be migrated away from), so this file ignores the deprecation lint for the whole file.
// ignore_for_file: deprecated_member_use_from_same_package
import 'package:compress_video/compress_video.dart'
    show
        CompressOptions,
        CompressPreset,
        CompressVideoErrorReason,
        CompressVideoException,
        kPresetSpecs;
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
}
