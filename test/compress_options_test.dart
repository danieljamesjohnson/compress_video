// Unit coverage of CompressOptions.validate() and CompressJob id generation.
//
// Every rejection case installs a mock handler on the CompressHostApi channel that fails the
// test if it is ever invoked, exactly like test/thumbnail_api_test.dart -- a validation bug
// that let a bad option combination reach the channel would show up as a test failure here,
// not as a native crash discovered later on-device.
import 'package:compress_video/compress_video.dart';
import 'package:compress_video/src/compress_job.dart' show generateJobId;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _startCompressChannelName =
    'dev.flutter.pigeon.compress_video.CompressHostApi.startCompress';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const CompressVideo compressVideo = CompressVideo();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(_startCompressChannelName, (
          ByteData? message,
        ) async {
          fail(
            'compress must not cross the platform channel for an invalid options combination',
          );
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(_startCompressChannelName, null);
  });

  Matcher throwsUnsupportedInput() => throwsA(
    isA<CompressVideoException>().having(
      (CompressVideoException e) => e.reason,
      'reason',
      CompressVideoErrorReason.unsupportedInput,
    ),
  );

  group('CompressOptions.validate', () {
    test('a non-positive maxFps is rejected', () {
      expect(
        () => const CompressOptions(maxFps: 0).validate(),
        throwsUnsupportedInput(),
      );
    });

    test('a maxLongSidePx below 16 is rejected', () {
      expect(
        () => const CompressOptions(maxLongSidePx: 15).validate(),
        throwsUnsupportedInput(),
      );
    });

    test('a non-positive maxLongSidePx is rejected', () {
      expect(
        () => const CompressOptions(maxLongSidePx: 0).validate(),
        throwsUnsupportedInput(),
      );
    });

    test('a non-positive videoBitrateBps is rejected', () {
      expect(
        () => const CompressOptions(videoBitrateBps: 0).validate(),
        throwsUnsupportedInput(),
      );
    });

    test('a non-positive targetSizeMb is rejected', () {
      expect(
        () => const CompressOptions(targetSizeMb: 0).validate(),
        throwsUnsupportedInput(),
      );
    });

    test('a non-finite targetSizeMb is rejected', () {
      expect(
        () => CompressOptions(targetSizeMb: double.nan).validate(),
        throwsUnsupportedInput(),
      );
      expect(
        () => CompressOptions(targetSizeMb: double.infinity).validate(),
        throwsUnsupportedInput(),
      );
    });

    test('a negative trimStartMs is rejected', () {
      expect(
        () => const CompressOptions(trimStartMs: -1).validate(),
        throwsUnsupportedInput(),
      );
    });

    test('a trimEndMs not strictly greater than trimStartMs is rejected', () {
      expect(
        () => const CompressOptions(
          trimStartMs: 1000,
          trimEndMs: 1000,
        ).validate(),
        throwsUnsupportedInput(),
      );
      expect(
        () =>
            const CompressOptions(trimStartMs: 1000, trimEndMs: 500).validate(),
        throwsUnsupportedInput(),
      );
    });

    test('a blank (non-null) outputPath is rejected', () {
      expect(
        () => const CompressOptions(outputPath: '   ').validate(),
        throwsUnsupportedInput(),
      );
    });

    test('a codec other than h264 is rejected', () {
      expect(
        () => const CompressOptions(codec: VideoCodec.hevc).validate(),
        throwsUnsupportedInput(),
      );
    });

    test('an hdr mode other than toneMapToSdr is rejected', () {
      expect(
        () => const CompressOptions(hdr: HdrMode.keepHdr).validate(),
        throwsUnsupportedInput(),
      );
    });

    test('an AudioReencode with a non-positive bitrateBps is rejected', () {
      expect(
        () => const CompressOptions(
          audio: AudioReencode(bitrateBps: 0, channels: 2),
        ).validate(),
        throwsUnsupportedInput(),
      );
    });

    test('an AudioReencode with channels outside 1 to 2 is rejected', () {
      expect(
        () => const CompressOptions(
          audio: AudioReencode(bitrateBps: 128000, channels: 0),
        ).validate(),
        throwsUnsupportedInput(),
      );
      expect(
        () => const CompressOptions(
          audio: AudioReencode(bitrateBps: 128000, channels: 3),
        ).validate(),
        throwsUnsupportedInput(),
      );
    });

    test(
      'combining targetSizeMb with videoBitrateBps is rejected as a contradictory target',
      () {
        expect(
          () => const CompressOptions(
            targetSizeMb: 10,
            videoBitrateBps: 2000000,
          ).validate(),
          throwsUnsupportedInput(),
        );
      },
    );

    test('the default options are valid', () {
      expect(() => const CompressOptions().validate(), returnsNormally);
    });

    test(
      'maxLongSidePx may combine with targetSizeMb without being rejected',
      () {
        expect(
          () => const CompressOptions(
            maxLongSidePx: 1280,
            targetSizeMb: 10,
          ).validate(),
          returnsNormally,
        );
      },
    );
  });

  group('CompressVideo.compress option validation', () {
    test(
      'an invalid options combination is rejected before crossing the channel',
      () {
        expect(
          () => compressVideo.compress(
            '/tmp/clip.mp4',
            options: const CompressOptions(maxFps: 0),
          ),
          throwsUnsupportedInput(),
        );
      },
    );

    test('a blank path is rejected before crossing the channel', () {
      expect(() => compressVideo.compress('   '), throwsUnsupportedInput());
    });
  });

  group('CompressJob id generation', () {
    test('two ids generated back to back differ', () {
      final String a = generateJobId();
      final String b = generateJobId();
      expect(a, isNot(b));
    });

    test('a generated id matches the documented pattern', () {
      final String id = generateJobId();
      expect(id, matches(RegExp(r'^[0-9]+-[0-9a-f]{16}$')));
    });
  });
}
