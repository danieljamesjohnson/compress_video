// Unit coverage of generated-message-to-public-model mapping, and of the unknown sentinels.
//
// Installs a mock handler directly on the generated ProbeHostApi channel, using the exact
// generated channel name and codec, so this test exercises the same encode/decode path a real
// platform reply travels through -- without needing an emulator or simulator.
import 'package:compress_video/compress_video.dart';
import 'package:compress_video/src/messages.g.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _channelName =
    'dev.flutter.pigeon.compress_video.ProbeHostApi.getMediaInfo';
const MessageCodec<Object?> _codec = ProbeHostApi.pigeonChannelCodec;

void _setHandler(Future<ByteData?> Function(ByteData? message) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(_channelName, handler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const CompressVideo compressVideo = CompressVideo();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(_channelName, null);
  });

  test('a full message maps field for field', () async {
    _setHandler((ByteData? message) async {
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

    final MediaInfo info = await compressVideo.getMediaInfo('/tmp/full.mp4');

    expect(info.durationMs, 4000);
    expect(info.widthPx, 1080);
    expect(info.heightPx, 1920);
    expect(info.rotationDegrees, 90);
    expect(info.sizeBytes, 150610);
    expect(info.videoCodec, 'h264');
    expect(info.videoBitrateBps, 192768);
    expect(info.frameRateFps, 30.0);
    expect(info.hasAudio, true);
    expect(info.isHdr, false);
  });

  test('nullable fields map to null, never 0 or an empty string', () async {
    _setHandler((ByteData? message) async {
      final MediaInfoMessage response = MediaInfoMessage(
        durationMs: 3000,
        widthPx: 1280,
        heightPx: 720,
        rotationDegrees: 0,
        sizeBytes: 30618,
        hasAudio: false,
        isHdr: false,
      );
      return _codec.encodeMessage(<Object?>[response]);
    });

    final MediaInfo info = await compressVideo.getMediaInfo('/tmp/nulls.mp4');

    expect(info.videoCodec, isNull);
    expect(info.videoBitrateBps, isNull);
    expect(info.frameRateFps, isNull);
  });

  for (final String reasonName in CompressVideoErrorReason.values.map(
    (CompressVideoErrorReason r) => r.name,
  )) {
    test('a simulated platform error with code "$reasonName" surfaces as '
        'CompressVideoException with reason $reasonName', () async {
      _setHandler((ByteData? message) async {
        return _codec.encodeMessage(<Object?>[
          reasonName,
          'simulated platform error',
          null,
        ]);
      });

      await expectLater(
        () => compressVideo.getMediaInfo('/tmp/error.mp4'),
        throwsA(
          isA<CompressVideoException>().having(
            (CompressVideoException e) => e.reason,
            'reason',
            CompressVideoErrorReason.values.firstWhere(
              (CompressVideoErrorReason r) => r.name == reasonName,
            ),
          ),
        ),
      );
    });
  }

  test(
    'an unrecognised platform error code falls back to unknown, preserving the '
    'original code',
    () async {
      _setHandler((ByteData? message) async {
        return _codec.encodeMessage(<Object?>[
          'someFutureReasonThisVersionDoesNotKnow',
          'simulated future platform error',
          null,
        ]);
      });

      await expectLater(
        () => compressVideo.getMediaInfo('/tmp/future-error.mp4'),
        throwsA(
          isA<CompressVideoException>()
              .having(
                (CompressVideoException e) => e.reason,
                'reason',
                CompressVideoErrorReason.unknown,
              )
              .having(
                (CompressVideoException e) => e.platformDetail,
                'platformDetail',
                'someFutureReasonThisVersionDoesNotKnow',
              ),
        ),
      );
    },
  );
}
