import 'package:compress_video/compress_video.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CompressVideoErrorReason', () {
    test('has exactly nine values', () {
      expect(CompressVideoErrorReason.values, hasLength(9));
    });

    test('the first six values are unchanged and in their original order', () {
      expect(
        CompressVideoErrorReason.values.sublist(0, 6),
        <CompressVideoErrorReason>[
          CompressVideoErrorReason.fileNotFound,
          CompressVideoErrorReason.unsupportedInput,
          CompressVideoErrorReason.decoderUnavailable,
          CompressVideoErrorReason.io,
          CompressVideoErrorReason.cancelled,
          CompressVideoErrorReason.unknown,
        ],
      );
    });

    test(
      'the three Phase 2 values follow, in order: encoderUnavailable, outOfSpace, interrupted',
      () {
        expect(
          CompressVideoErrorReason.values.sublist(6),
          <CompressVideoErrorReason>[
            CompressVideoErrorReason.encoderUnavailable,
            CompressVideoErrorReason.outOfSpace,
            CompressVideoErrorReason.interrupted,
          ],
        );
      },
    );
  });

  group('reasonFromPlatformCode', () {
    for (final CompressVideoErrorReason reason
        in CompressVideoErrorReason.values) {
      test('maps "${reason.name}" to $reason', () {
        expect(reasonFromPlatformCode(reason.name), reason);
      });
    }

    test('maps an unrecognised code to unknown', () {
      expect(
        reasonFromPlatformCode('someFutureCode'),
        CompressVideoErrorReason.unknown,
      );
    });
  });

  group('CompressVideoException', () {
    test(
      'retains the original platform code in platformDetail for an unknown reason',
      () {
        const String unrecognisedCode = 'someFutureCode';
        final CompressVideoException exception = CompressVideoException(
          reason: reasonFromPlatformCode(unrecognisedCode),
          message:
              'Native code reported an error this version does not recognise.',
          platformDetail: unrecognisedCode,
        );

        expect(exception.reason, CompressVideoErrorReason.unknown);
        expect(exception.platformDetail, unrecognisedCode);
      },
    );

    test('toString names the reason', () {
      const CompressVideoException exception = CompressVideoException(
        reason: CompressVideoErrorReason.fileNotFound,
        message: 'No file at the given path.',
      );

      expect(exception.toString(), contains('fileNotFound'));
    });
  });
}
