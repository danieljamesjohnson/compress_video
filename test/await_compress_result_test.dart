// CR-02 (05-REVIEW.md): `awaitCompressResult` must fail with a typed error -- never hang --
// for a jobId nothing ever started, or one whose result was already consumed by a previous
// call. This proves the Dart-side generated `CompressHostApi.awaitCompressResult` proxy
// correctly decodes the typed `unknown`-reason failure both native engines now throw for those
// two cases, by installing a fake host API on the generated channel (same technique
// test/thumbnail_api_test.dart and test/compress_job_test.dart use for their own platform
// channels) rather than requiring a real Android/Apple host. `CompressJob`'s own wrapper
// behaviour is deliberately untouched by this fix and is not exercised here.
import 'package:compress_video/compress_video.dart';
import 'package:compress_video/src/messages.g.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _awaitCompressResultChannelName =
    'dev.flutter.pigeon.compress_video.CompressHostApi.awaitCompressResult';
const MessageCodec<Object?> _codec = CompressHostApi.pigeonChannelCodec;

/// Installs a fake host API on the generated `awaitCompressResult` channel that replies with a
/// platform error carrying [reasonName] and [message] -- the shape both `Compression.kt`'s and
/// `Compression.swift`'s new CR-02 guards throw for an unknown or already-consumed jobId.
void _installFailingAwaitCompressResultHandler({
  required String reasonName,
  required String message,
}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(_awaitCompressResultChannelName, (
        ByteData? envelope,
      ) async {
        return _codec.encodeMessage(<Object?>[reasonName, message, null]);
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(_awaitCompressResultChannelName, null);
  });

  Matcher throwsPlatformExceptionWithCode(String code) =>
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', code));

  test('a jobId nothing ever started fails typed with reason "unknown" instead of hanging '
      '(CR-02)', () async {
    _installFailingAwaitCompressResultHandler(
      reasonName: 'unknown',
      message:
          'awaitCompressResult called for unknown jobId: startCompress was never called '
          'for it',
    );
    final CompressHostApi api = CompressHostApi();

    await expectLater(
      () => api.awaitCompressResult('0-1111111111111111'),
      throwsPlatformExceptionWithCode('unknown'),
    );
    // The reason name both engines throw for this case maps to the documented,
    // non-hanging Dart-facing reason (test/compress_video_exception_test.dart covers the
    // full mapping table generically; asserted again here to pin CR-02's exact contract).
    expect(reasonFromPlatformCode('unknown'), CompressVideoErrorReason.unknown);
  });

  test(
    'a jobId whose result was already consumed by an earlier call fails typed with reason '
    '"unknown" instead of hanging on a second call (CR-02)',
    () async {
      _installFailingAwaitCompressResultHandler(
        reasonName: 'unknown',
        message:
            'awaitCompressResult called again for jobId, whose result was already consumed '
            'by an earlier awaitCompressResult call',
      );
      final CompressHostApi api = CompressHostApi();

      await expectLater(
        () => api.awaitCompressResult('0-2222222222222222'),
        throwsPlatformExceptionWithCode('unknown'),
      );
    },
  );
}
