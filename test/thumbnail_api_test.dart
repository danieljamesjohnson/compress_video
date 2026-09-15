// Unit coverage of CompressVideo.getThumbnail/getThumbnailFile's Dart-side argument
// validation. Installs a mock handler on both generated ThumbnailHostApi channels that fails
// the test if it is ever invoked, so every case here proves the rejection happened locally --
// a validation bug that let a bad argument reach the channel would show up as a test failure
// here, not as a native crash discovered later on-device.
import 'package:compress_video/compress_video.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _getThumbnailChannelName =
    'dev.flutter.pigeon.compress_video.ThumbnailHostApi.getThumbnail';
const String _getThumbnailFileChannelName =
    'dev.flutter.pigeon.compress_video.ThumbnailHostApi.getThumbnailFile';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const CompressVideo compressVideo = CompressVideo();

  setUp(() {
    // Any invocation is itself the test failure: a validation bug let a bad argument reach
    // the channel.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(_getThumbnailChannelName, (
          ByteData? message,
        ) async {
          fail(
            'getThumbnail must not cross the platform channel for an invalid argument',
          );
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(_getThumbnailFileChannelName, (
          ByteData? message,
        ) async {
          fail(
            'getThumbnailFile must not cross the platform channel for an invalid argument',
          );
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(_getThumbnailChannelName, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(_getThumbnailFileChannelName, null);
  });

  Matcher throwsUnsupportedInput() => throwsA(
    isA<CompressVideoException>().having(
      (CompressVideoException e) => e.reason,
      'reason',
      CompressVideoErrorReason.unsupportedInput,
    ),
  );

  group('getThumbnail', () {
    test(
      'a negative positionMs is rejected without crossing the channel',
      () async {
        await expectLater(
          () => compressVideo.getThumbnail('/tmp/clip.mp4', positionMs: -1),
          throwsUnsupportedInput(),
        );
      },
    );

    test('a quality of 0 is rejected without crossing the channel', () async {
      await expectLater(
        () => compressVideo.getThumbnail('/tmp/clip.mp4', quality: 0),
        throwsUnsupportedInput(),
      );
    });

    test('a quality of 101 is rejected without crossing the channel', () async {
      await expectLater(
        () => compressVideo.getThumbnail('/tmp/clip.mp4', quality: 101),
        throwsUnsupportedInput(),
      );
    });

    test(
      'a maxDimensionPx of 0 is rejected without crossing the channel',
      () async {
        await expectLater(
          () => compressVideo.getThumbnail('/tmp/clip.mp4', maxDimensionPx: 0),
          throwsUnsupportedInput(),
        );
      },
    );

    test('a blank path is rejected without crossing the channel', () async {
      await expectLater(
        () => compressVideo.getThumbnail('   '),
        throwsUnsupportedInput(),
      );
    });
  });

  group('getThumbnailFile', () {
    test(
      'a negative positionMs is rejected without crossing the channel',
      () async {
        await expectLater(
          () => compressVideo.getThumbnailFile('/tmp/clip.mp4', positionMs: -1),
          throwsUnsupportedInput(),
        );
      },
    );

    test('a quality of 0 is rejected without crossing the channel', () async {
      await expectLater(
        () => compressVideo.getThumbnailFile('/tmp/clip.mp4', quality: 0),
        throwsUnsupportedInput(),
      );
    });

    test('a quality of 101 is rejected without crossing the channel', () async {
      await expectLater(
        () => compressVideo.getThumbnailFile('/tmp/clip.mp4', quality: 101),
        throwsUnsupportedInput(),
      );
    });

    test(
      'a maxDimensionPx of 0 is rejected without crossing the channel',
      () async {
        await expectLater(
          () => compressVideo.getThumbnailFile(
            '/tmp/clip.mp4',
            maxDimensionPx: 0,
          ),
          throwsUnsupportedInput(),
        );
      },
    );

    test('a blank path is rejected without crossing the channel', () async {
      await expectLater(
        () => compressVideo.getThumbnailFile('   '),
        throwsUnsupportedInput(),
      );
    });

    test(
      'a blank (non-null) outputPath is rejected without crossing the channel',
      () async {
        await expectLater(
          () => compressVideo.getThumbnailFile(
            '/tmp/clip.mp4',
            outputPath: '   ',
          ),
          throwsUnsupportedInput(),
        );
      },
    );
  });
}
