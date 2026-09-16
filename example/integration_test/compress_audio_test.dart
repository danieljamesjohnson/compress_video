// Integration test for CompressVideo.compress's three audio modes -- passthrough, strip and
// reencode -- run on a real Android emulator. Every expectation is read from a corpus sidecar
// where one exists, exactly like compress_test.dart and media_info_test.dart, so this file and
// the sidecar can never silently drift apart.
//
// Neither `CompressResult` nor `MediaInfo` exposes an audio channel count or an audio-only
// bitrate (both are native-only facts used internally to build the encoder request, per
// TransformerEngine.kt's own doc comments) -- proving AUDO-02's "channels is honoured exactly"
// and "the bitrate knob reaches the encoder" truths therefore means reading the produced file's
// own bytes directly, the same "prove what actually came out of it" philosophy compress_test.dart
// applies to pixels for orientation. `_readMp4AudioTrackInfo` below walks the ISO/IEC 14496-12
// box tree (moov -> trak(soun) -> mdia -> minf -> stbl -> stsd/stsz) to read the `mp4a` sample
// entry's channel count and sum the audio track's own sample byte sizes directly.
import 'dart:io';
import 'dart:typed_data';

import 'package:compress_video/compress_video.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Copies a bundled corpus asset out of [rootBundle] into a fresh temporary file and returns
/// its filesystem path, since the platform compress call reads from a real file path, not
/// asset bytes.
Future<String> _copyAssetToTempFile(String assetPath, String fileName) async {
  final ByteData data = await rootBundle.load(assetPath);
  final Directory tempDir = await Directory.systemTemp.createTemp(
    'compress_video_audio_test_',
  );
  final File file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    flush: true,
  );
  return file.path;
}

int _u32(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes, offset, offset + 4).getUint32(0);

int _u16(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes, offset, offset + 2).getUint16(0);

/// A single top-level-or-nested MP4 box's byte range: [start] is the position of its 4-byte
/// size field, [end] is exclusive (`start + size`).
typedef _BoxRange = ({int start, int end});

/// Finds the first child box named [fourCc] directly inside `[start, end)`, or `null` if none
/// exists. Does not recurse -- callers walk one level at a time, matching the fixed box
/// hierarchy this file only ever descends through.
_BoxRange? _findBox(Uint8List bytes, String fourCc, int start, int end) {
  int offset = start;
  while (offset + 8 <= end) {
    final int size32 = _u32(bytes, offset);
    final String type = String.fromCharCodes(bytes, offset + 4, offset + 8);
    int boxSize;
    if (size32 == 1) {
      // ISO/IEC 14496-12 64-bit extended size: the real size is a big-endian uint64
      // immediately following the 8-byte header. `mdat` (the media data itself, easily
      // multiple megabytes) is the box that actually needs this in practice -- and with
      // streamable output disabled (TransformerEngine.kt's own `setAttemptStreamableOutputEnabled
      // (false)`), `moov` is written AFTER `mdat`, so correctly skipping over an extended-size
      // `mdat` is required to ever reach `moov` at all.
      if (offset + 16 > end) {
        break;
      }
      final int high = _u32(bytes, offset + 8);
      final int low = _u32(bytes, offset + 12);
      boxSize = (high << 32) + low;
    } else if (size32 == 0) {
      boxSize = end - offset;
    } else {
      boxSize = size32;
    }
    if (boxSize < 8 || offset + boxSize > end) {
      break;
    }
    if (type == fourCc) {
      return (start: offset, end: offset + boxSize);
    }
    offset += boxSize;
  }
  return null;
}

/// The audio track's structural facts read directly from the produced MP4's own bytes.
class _Mp4AudioTrackInfo {
  const _Mp4AudioTrackInfo({
    required this.channelCount,
    required this.totalSampleBytes,
  });

  /// Channel count from the `mp4a` sample entry (ISO/IEC 14496-12 `AudioSampleEntry`): 8-byte
  /// box header + 6-byte `SampleEntry.reserved` + 2-byte `data_reference_index` + 8-byte
  /// `AudioSampleEntry.reserved` lands exactly on `channelcount` at box-start-relative offset
  /// 24.
  final int channelCount;

  /// Sum of every audio sample's byte size, read from `stsz` -- the same sample-size-summation
  /// technique `Probe.kt`'s `estimateVideoBitrateBpsFromSamples` uses natively for video,
  /// applied here in Dart to the audio track because no API exposes an audio-only bitrate.
  final int totalSampleBytes;
}

/// Reads [path]'s first audio track's channel count and total sample-byte sum by walking the
/// box tree directly. Returns `null` if the file has no audio track at all (for example, after
/// [AudioStrip]).
Future<_Mp4AudioTrackInfo?> _readMp4AudioTrackInfo(String path) async {
  final Uint8List bytes = await File(path).readAsBytes();
  final int fileLen = bytes.length;

  final _BoxRange? moov = _findBox(bytes, 'moov', 0, fileLen);
  if (moov == null) {
    return null;
  }

  int trakOffset = moov.start + 8;
  while (trakOffset < moov.end) {
    final _BoxRange? trak = _findBox(bytes, 'trak', trakOffset, moov.end);
    if (trak == null) {
      break;
    }
    final _BoxRange? mdia = _findBox(bytes, 'mdia', trak.start + 8, trak.end);
    if (mdia != null) {
      final _BoxRange? hdlr = _findBox(bytes, 'hdlr', mdia.start + 8, mdia.end);
      if (hdlr != null) {
        // hdlr (FullBox): version+flags(4) + pre_defined(4) + handler_type(4), all measured
        // from the content start (box start + 8-byte header).
        final int handlerTypeOffset = hdlr.start + 8 + 4 + 4;
        final String handlerType = String.fromCharCodes(
          bytes,
          handlerTypeOffset,
          handlerTypeOffset + 4,
        );
        if (handlerType == 'soun') {
          final _BoxRange? minf = _findBox(
            bytes,
            'minf',
            mdia.start + 8,
            mdia.end,
          );
          final _BoxRange? stbl = minf == null
              ? null
              : _findBox(bytes, 'stbl', minf.start + 8, minf.end);
          final _BoxRange? stsd = stbl == null
              ? null
              : _findBox(bytes, 'stsd', stbl.start + 8, stbl.end);
          final _BoxRange? stsz = stbl == null
              ? null
              : _findBox(bytes, 'stsz', stbl.start + 8, stbl.end);
          if (stsd != null && stsz != null) {
            // stsd (FullBox): version+flags(4) + entry_count(4); the first sample entry
            // ('mp4a' for AAC, which is all this plugin ever produces) starts right after,
            // itself a box with its own 8-byte header.
            final int firstEntryStart = stsd.start + 8 + 4 + 4;
            final String entryType = String.fromCharCodes(
              bytes,
              firstEntryStart + 4,
              firstEntryStart + 8,
            );
            final int channelCountOffset = firstEntryStart + 24;
            if (entryType != 'mp4a' || channelCountOffset + 2 > stsd.end) {
              return null;
            }
            final int channelCount = _u16(bytes, channelCountOffset);

            // stsz (FullBox): version+flags(4) + sample_size(4) + sample_count(4). A nonzero
            // sample_size means every sample is that exact size (no per-sample array follows);
            // sample_size == 0 means a sample_count-length uint32 array follows, one entry per
            // sample.
            final int sampleSizeFieldOffset = stsz.start + 8 + 4;
            final int sampleCountFieldOffset = stsz.start + 8 + 4 + 4;
            final int uniformSampleSize = _u32(bytes, sampleSizeFieldOffset);
            final int sampleCount = _u32(bytes, sampleCountFieldOffset);
            int totalSampleBytes;
            if (uniformSampleSize != 0) {
              totalSampleBytes = uniformSampleSize * sampleCount;
            } else {
              totalSampleBytes = 0;
              final int arrayStart = stsz.start + 8 + 4 + 4 + 4;
              for (int i = 0; i < sampleCount; i++) {
                totalSampleBytes += _u32(bytes, arrayStart + i * 4);
              }
            }

            return _Mp4AudioTrackInfo(
              channelCount: channelCount,
              totalSampleBytes: totalSampleBytes,
            );
          }
        }
      }
    }
    trakOffset = trak.end;
  }
  return null;
}

/// Estimates the audio track's own average bitrate, in bits per second, from the sum of its
/// sample byte sizes over [result]'s own re-probed duration.
double _measuredAudioBitrateBps(
  _Mp4AudioTrackInfo info,
  CompressResult result,
) {
  final double durationSeconds = result.durationMs / 1000.0;
  return (info.totalSampleBytes * 8) / durationSeconds;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const CompressVideo compressVideo = CompressVideo();

  Future<String> copySmallClip() => _copyAssetToTempFile(
    'assets/corpus/small_480p.mp4',
    'audio_small_${DateTime.now().microsecondsSinceEpoch}.mp4',
  );

  // The AudioReencode cases below need a genuine, guaranteed re-encode of the VIDEO track too
  // (SizeGuard's audioPassthroughRequested condition disqualifies the whole job from the
  // transmux fast path whenever audio is being stripped or reencoded, per D-10) -- using
  // small_480p.mp4 risks the video portion alone landing at or above the input's own byte count
  // (this emulator's CBR software encoder measurably overshoots a bitrate request close to the
  // source's own, 02-03-SUMMARY.md), which would trip the unconditional never-larger post-check
  // and silently substitute the original file, defeating the whole point of these cases.
  // portrait_hibitrate_1080p60.mp4's ~8.7Mbps source is comfortably above every preset this
  // phase defines (corpus/README.md), so the video track shrinks by design regardless of what
  // the audio track does, and these cases can isolate the audio behaviour cleanly.
  Future<String> copyHiBitrateClip() => _copyAssetToTempFile(
    'assets/corpus/portrait_hibitrate_1080p60.mp4',
    'audio_hibitrate_${DateTime.now().microsecondsSinceEpoch}.mp4',
  );

  testWidgets(
    'default options (AudioPassthrough) on an AAC source copy the audio track: '
    'audioReencoded is false, audioCodec is aac, and the output still has audio',
    (WidgetTester tester) async {
      final String path = await copySmallClip();
      final CompressJob job = compressVideo.compress(path);
      final CompressResult result = await job.result;

      expect(result.audioReencoded, isFalse);
      expect(result.audioCodec, 'aac');

      final MediaInfo outputInfo = await compressVideo.getMediaInfo(
        result.outputPath,
      );
      expect(outputInfo.hasAudio, isTrue);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'AudioOptions.strip produces an output with no audio track at all: audioCodec '
    'null, audioReencoded false',
    (WidgetTester tester) async {
      final String path = await copySmallClip();
      final CompressJob job = compressVideo.compress(
        path,
        options: const CompressOptions(audio: AudioStrip()),
      );
      final CompressResult result = await job.result;

      expect(result.audioCodec, isNull);
      expect(result.audioReencoded, isFalse);

      final MediaInfo outputInfo = await compressVideo.getMediaInfo(
        result.outputPath,
      );
      expect(outputInfo.hasAudio, isFalse);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'AudioOptions.reencode at 64000bps/2 channels reports audioReencoded true and '
    're-probes as AAC with exactly 2 channels, within 25 percent of the requested bitrate',
    (WidgetTester tester) async {
      final String path = await copyHiBitrateClip();
      final CompressJob job = compressVideo.compress(
        path,
        options: const CompressOptions(
          audio: AudioReencode(bitrateBps: 64000, channels: 2),
        ),
      );
      final CompressResult result = await job.result;

      expect(result.audioReencoded, isTrue);
      expect(result.audioCodec, 'aac');

      final _Mp4AudioTrackInfo? info = await _readMp4AudioTrackInfo(
        result.outputPath,
      );
      expect(
        info,
        isNotNull,
        reason: 'expected an audio track in the reencoded output',
      );
      expect(info!.channelCount, 2);

      final double measuredBps = _measuredAudioBitrateBps(info, result);
      final double deviation = (measuredBps - 64000).abs() / 64000;
      expect(
        deviation,
        lessThanOrEqualTo(0.25),
        reason: 'measured $measuredBps bps vs requested 64000 bps',
      );
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'the same reencode request at 1 channel re-probes as exactly 1 channel',
    (WidgetTester tester) async {
      final String path = await copyHiBitrateClip();
      final CompressJob job = compressVideo.compress(
        path,
        options: const CompressOptions(
          audio: AudioReencode(bitrateBps: 64000, channels: 1),
        ),
      );
      final CompressResult result = await job.result;

      expect(result.audioReencoded, isTrue);
      final _Mp4AudioTrackInfo? info = await _readMp4AudioTrackInfo(
        result.outputPath,
      );
      expect(info, isNotNull);
      expect(info!.channelCount, 1);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'a reencode request at 1000bps succeeds with the bitrate clamped up into the '
    "encoder's range rather than failing",
    (WidgetTester tester) async {
      final String path = await copyHiBitrateClip();
      final CompressJob job = compressVideo.compress(
        path,
        options: const CompressOptions(
          audio: AudioReencode(bitrateBps: 1000, channels: 2),
        ),
      );
      final CompressResult result = await job.result;

      expect(result.audioReencoded, isTrue);
      expect(result.audioCodec, 'aac');
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'a source with no audio track at all completes with a null audioCodec and '
    'audioReencoded false rather than erroring',
    (WidgetTester tester) async {
      final String path = await _copyAssetToTempFile(
        'assets/corpus/noaudio_720p.mp4',
        'audio_noaudio_${DateTime.now().microsecondsSinceEpoch}.mp4',
      );
      final CompressJob job = compressVideo.compress(path);
      final CompressResult result = await job.result;

      expect(result.audioCodec, isNull);
      expect(result.audioReencoded, isFalse);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'a 64000bps and a 128000bps reencode of the same clip produce measurably '
    'different audio bitrates in the expected direction, each within 25 percent of its own '
    'request -- proving the bitrate knob reaches the encoder rather than being ignored '
    '(PITFALLS.md row 13, applied to audio)',
    (WidgetTester tester) async {
      Future<double> measuredBpsAt(int requestedBitrateBps) async {
        final String path = await copyHiBitrateClip();
        final CompressJob job = compressVideo.compress(
          path,
          options: CompressOptions(
            audio: AudioReencode(bitrateBps: requestedBitrateBps, channels: 2),
          ),
        );
        final CompressResult result = await job.result;
        final _Mp4AudioTrackInfo? info = await _readMp4AudioTrackInfo(
          result.outputPath,
        );
        expect(info, isNotNull);
        final double measuredBps = _measuredAudioBitrateBps(info!, result);
        final double deviation =
            (measuredBps - requestedBitrateBps).abs() / requestedBitrateBps;
        expect(
          deviation,
          lessThanOrEqualTo(0.25),
          reason:
              'measured $measuredBps bps vs requested $requestedBitrateBps bps',
        );
        return measuredBps;
      }

      final double lowBps = await measuredBpsAt(64000);
      final double highBps = await measuredBpsAt(128000);

      expect(
        lowBps,
        lessThan(highBps),
        reason:
            'the 64000bps request must measure lower than the 128000bps request',
      );
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );
}
