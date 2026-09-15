// Compile-time contract test for the generated Pigeon message class.
//
// This test constructs a `MediaInfoMessage` using every field as a named argument with its
// exact unit-suffixed name. Renaming or retyping any field in `pigeons/messages.dart` breaks
// compilation of this file — that is the point: it pins the wire contract's field names and
// types so a drive-by rename in the generator input is caught here, not three languages away.
import 'package:compress_video/src/messages.g.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MediaInfoMessage round-trips every unit-suffixed field', () {
    final MediaInfoMessage full = MediaInfoMessage(
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

    expect(full.durationMs, 4000);
    expect(full.widthPx, 1080);
    expect(full.heightPx, 1920);
    expect(full.rotationDegrees, 90);
    expect(full.sizeBytes, 150610);
    expect(full.videoCodec, 'h264');
    expect(full.videoBitrateBps, 192768);
    expect(full.frameRateFps, 30.0);
    expect(full.hasAudio, true);
    expect(full.isHdr, false);
  });

  test('nullable fields accept null', () {
    final MediaInfoMessage minimal = MediaInfoMessage(
      durationMs: 3000,
      widthPx: 1280,
      heightPx: 720,
      rotationDegrees: 0,
      sizeBytes: 30618,
      hasAudio: false,
      isHdr: false,
    );

    expect(minimal.videoCodec, isNull);
    expect(minimal.videoBitrateBps, isNull);
    expect(minimal.frameRateFps, isNull);
  });
}
