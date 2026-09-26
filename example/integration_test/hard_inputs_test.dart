// Integration test for the "hard input" corpus clips Phase 4 adds: HDR (HLG, PQ), unusual
// audio (LPCM, 5.1) and a 4K60 source. All of these cases live in ONE suite (D-13) rather than
// spread across the existing ones, because they share the same media-info-only shape (no
// compression happens here yet) and the phase's own decision text calls for a single new file.
// Every expected value is read from the corpus sidecar rather than hard-coded, exactly like
// media_info_test.dart, so this file and the sidecar can never silently drift apart.
//
// This plan (04-01) does NOT emit a cross-platform parity record: the Apple engine cannot yet
// produce matching values for these clips, and the parity gate treats a case present on one
// platform only as a failure. Emission is added in 04-05, once both engines agree.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:compress_video/compress_video.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// 04-02: this plan adds real compression cases (HDR tone-map, fidelity, unusual audio, 4K60)
// alongside 04-01's media-info-only cases above. Through 04-03, every new case asserted
// Android-only behaviour (the Apple engine did not implement HDR tone-mapping, keep-HDR, the
// HEVC opt-in or the forced audio downmix yet) with the same `skip: !Platform.isAndroid` guard
// commit 2007973 established for compress_test.dart's own transmux cases. 04-04 brings the
// Apple engine to parity and removes every one of those skip guards; this whole suite now runs
// on all three platforms.

/// Copies a bundled corpus asset out of [rootBundle] into a fresh temporary file and returns
/// its filesystem path, since the platform probe reads from a real file path, not asset bytes.
/// This file keeps its own copy rather than sharing one with media_info_test.dart or
/// compress_audio_test.dart, per this repository's no-shared-test-helpers convention.
Future<String> _copyAssetToTempFile(String assetPath, String fileName) async {
  final ByteData data = await rootBundle.load(assetPath);
  final Directory tempDir = await Directory.systemTemp.createTemp(
    'compress_video_hard_inputs_test_',
  );
  final File file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    flush: true,
  );
  return file.path;
}

/// Loads and decodes the `.expected.json` sidecar for [clipName] (without extension).
Future<Map<String, dynamic>> _loadSidecar(String clipName) async {
  final String raw = await rootBundle.loadString(
    'assets/corpus/$clipName.expected.json',
  );
  return jsonDecode(raw) as Map<String, dynamic>;
}

/// Runs `getMediaInfo` against [clipName] and asserts the sidecar's `crossPlatform` block:
/// width/height/codec/hasAudio/isHdr exactly, duration within its stated tolerance. Every case
/// below is a metadata read only -- no compression happens in this plan.
///
/// [extension] defaults to `mp4`; `pcm_audio_480p` is `mov` -- ffmpeg's ISO-MP4 PCM sample
/// entry isn't recognized by Android's MediaExtractor as an audio track (confirmed live during
/// this plan), so that one fixture is muxed as `.mov` instead (04-RESEARCH.md Pitfall 5's
/// pre-authorised contingency; same codec, different container/fourcc).
Future<void> _expectMediaInfoMatchesSidecar(
  CompressVideo compressVideo,
  String clipName, {
  String extension = 'mp4',
}) async {
  final String path = await _copyAssetToTempFile(
    'assets/corpus/$clipName.$extension',
    '$clipName.$extension',
  );
  final Map<String, dynamic> sidecar = await _loadSidecar(clipName);
  final Map<String, dynamic> expected =
      sidecar['crossPlatform'] as Map<String, dynamic>;

  final MediaInfo info = await compressVideo.getMediaInfo(path);

  expect(info.widthPx, expected['widthPx']);
  expect(info.heightPx, expected['heightPx']);
  expect(info.videoCodec, expected['videoCodec']);
  expect(info.hasAudio, expected['hasAudio']);
  expect(info.isHdr, expected['isHdr']);
  expect(
    info.durationMs.toDouble(),
    closeTo(
      (expected['durationMs'] as int).toDouble(),
      (expected['durationToleranceMs'] as int).toDouble(),
    ),
  );
}

/// Decodes [bytes] (JPEG, in this suite) into a [ui.Image]. This file keeps its own copy
/// rather than sharing one with compress_test.dart or thumbnail_test.dart, per this
/// repository's no-shared-test-helpers convention.
Future<ui.Image> _decodeImage(Uint8List bytes) async {
  final ui.Codec codec = await ui.instantiateImageCodec(bytes);
  final ui.FrameInfo frame = await codec.getNextFrame();
  return frame.image;
}

/// Samples the RGB value at ([x], [y]) in [image] from its raw, straight-alpha RGBA bytes.
Future<List<int>> _samplePixelRgb(ui.Image image, int x, int y) async {
  final ByteData? byteData = await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  if (byteData == null) {
    fail('Could not read raw pixel data from the decoded thumbnail');
  }
  final int offset = (y * image.width + x) * 4;
  return <int>[
    byteData.getUint8(offset),
    byteData.getUint8(offset + 1),
    byteData.getUint8(offset + 2),
  ];
}

/// Proves a tone-mapped OUTPUT is saturated and correctly hued rather than washed out, by
/// sampling the produced file's own pixels -- the same "prove what actually came out of it"
/// philosophy compress_test.dart's `_expectUprightAndUnpadded` applies to orientation.
///
/// Fetches a thumbnail of [result]'s own output, scales each of [sidecar]'s `hdrProbe` colour
/// patch coordinates from source-displayed to this output's own displayed space by the height
/// ratio (exactly as `_expectUprightAndUnpadded` does), and asserts three things per patch:
/// saturation -- (max channel minus min channel) divided by max channel, expressed as a
/// percentage of 0-255 -- is at or above `minSaturation`; the painted dominant channel exceeds
/// both other channels by at least `dominanceMargin`; and for the white patch (`dominantChannel`
/// `"none"`), the minimum channel is at or above `minWhiteLuma`.
///
/// Deliberately not an exact RGB match: the corpus tool cannot author a reference tone-map on
/// this machine (04-01-PLAN.md), so this asserts the PROPERTY that distinguishes a correct
/// tone-map (saturated, correctly-hued patches) from a washed-out passthrough, rather than
/// pinning one implementation's exact output.
Future<void> _expectHdrFidelity(
  CompressVideo compressVideo,
  CompressResult result,
  Map<String, dynamic> sidecar,
) async {
  final Map<String, dynamic> crossPlatform =
      sidecar['crossPlatform'] as Map<String, dynamic>;
  final Map<String, dynamic> hdrProbe =
      sidecar['hdrProbe'] as Map<String, dynamic>;

  final int sourceHeightPx = crossPlatform['heightPx'] as int;
  final double scale = result.heightPx / sourceHeightPx.toDouble();

  final double minSaturation = (hdrProbe['minSaturation'] as num).toDouble();
  final double minWhiteLuma = (hdrProbe['minWhiteLuma'] as num).toDouble();
  final double dominanceMargin = (hdrProbe['dominanceMargin'] as num)
      .toDouble();
  final List<dynamic> patches = hdrProbe['patches'] as List<dynamic>;

  final Uint8List thumbnailBytes = await compressVideo.getThumbnail(
    result.outputPath,
  );
  final ui.Image image = await _decodeImage(thumbnailBytes);

  for (final dynamic rawPatch in patches) {
    final Map<String, dynamic> patch = rawPatch as Map<String, dynamic>;
    final String dominantChannel = patch['dominantChannel'] as String;
    final int x = ((patch['xPx'] as int) * scale).toInt();
    final int y = ((patch['yPx'] as int) * scale).toInt();
    final List<int> rgb = await _samplePixelRgb(image, x, y);
    final int r = rgb[0];
    final int g = rgb[1];
    final int b = rgb[2];
    final int maxChannel = <int>[
      r,
      g,
      b,
    ].reduce((int a, int v) => a > v ? a : v);
    final int minChannel = <int>[
      r,
      g,
      b,
    ].reduce((int a, int v) => a < v ? a : v);

    if (dominantChannel == 'none') {
      // The white patch: saturation is deliberately NOT asserted here (a true white/near-white
      // patch has near-zero saturation by design) -- only the minimum channel must stay bright.
      expect(
        minChannel,
        greaterThanOrEqualTo(minWhiteLuma),
        reason:
            'white patch ($x,$y) minimum channel ($minChannel) below minWhiteLuma '
            '($minWhiteLuma): rgb=$rgb',
      );
      continue;
    }

    final double saturation = maxChannel == 0
        ? 0.0
        : (maxChannel - minChannel) / maxChannel.toDouble() * 255.0;
    expect(
      saturation,
      greaterThanOrEqualTo(minSaturation),
      reason:
          'patch ($x,$y) saturation ($saturation) below minSaturation '
          '($minSaturation): rgb=$rgb',
    );

    final int dominantValue = switch (dominantChannel) {
      'r' => r,
      'g' => g,
      'b' => b,
      _ => throw StateError('unknown dominantChannel: $dominantChannel'),
    };
    final List<int> otherValues = <int>[r, g, b]..remove(dominantValue);
    for (final int other in otherValues) {
      expect(
        (dominantValue - other).toDouble(),
        greaterThanOrEqualTo(dominanceMargin),
        reason:
            'patch ($x,$y) dominant channel $dominantChannel ($dominantValue) does not '
            'exceed other channel ($other) by dominanceMargin ($dominanceMargin): rgb=$rgb',
      );
    }
  }
}

int _u32(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes, offset, offset + 4).getUint32(0);

/// A single top-level-or-nested MP4 box's byte range: [start] is the position of its 4-byte
/// size field, [end] is exclusive (`start + size`). This file keeps its own copy of the box
/// walk rather than sharing one with compress_audio_test.dart, per this repository's
/// no-shared-test-helpers convention (04-02-PLAN.md task 3's own instruction).
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
      // immediately following the 8-byte header -- required to skip over an extended-size
      // `mdat` (streamable output is disabled, so `moov` is written AFTER `mdat`).
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

/// Reads an MPEG-4 "expandable" descriptor length (ISO/IEC 14496-1) starting at [offset]: each
/// length byte's high bit signals another byte follows, and the low 7 bits accumulate into the
/// value. Returns the decoded length and the offset of the descriptor's first content byte.
({int length, int contentStart}) _readDescriptorLength(
  Uint8List bytes,
  int offset,
) {
  int value = 0;
  int pos = offset;
  while (pos < bytes.length) {
    final int b = bytes[pos];
    pos++;
    value = (value << 7) | (b & 0x7F);
    if (b & 0x80 == 0) break;
  }
  return (length: value, contentStart: pos);
}

/// Reads the AAC channel configuration (1=mono, 2=stereo, ...) from an `esds` box's nested
/// DecoderSpecificInfo (tag 5) `AudioSpecificConfig`. This is the AUTHORITATIVE channel count
/// for an AAC track -- the `mp4a` sample entry's own `channelcount` field is not trustworthy on
/// every platform (compress_audio_test.dart's own comment documents Apple's muxer hardcoding it
/// to 2 regardless of the real stream). Returns `null` if the box is missing, malformed, or
/// reports an extended (non-standard) sampling-frequency index this minimal parser does not
/// decode -- none of this plugin's own requested rates ever produce one.
int? _readEsdsChannelConfig(Uint8List bytes, _BoxRange esds) {
  // esds (FullBox): version+flags(4), then one ES_Descriptor.
  int offset = esds.start + 8 + 4;

  int? walkToTag(int tagWanted) {
    while (offset + 2 <= esds.end) {
      final int tag = bytes[offset];
      final ({int length, int contentStart}) header = _readDescriptorLength(
        bytes,
        offset + 1,
      );
      final int contentEnd = header.contentStart + header.length;
      if (contentEnd > esds.end || contentEnd < header.contentStart) {
        return null;
      }
      if (tag == tagWanted) {
        offset = header.contentStart;
        return contentEnd;
      }
      offset = contentEnd;
    }
    return null;
  }

  // ES_DescrTag = 3.
  if (walkToTag(3) == null) return null;
  // ES_Descriptor content: ES_ID(2) + flags(1).
  offset += 2 + 1;

  // DecoderConfigDescrTag = 4.
  if (walkToTag(4) == null) return null;
  // DecoderConfigDescriptor content before its nested DecoderSpecificInfo: objectTypeIndication
  // (1) + streamType/upStream/reserved (1) + bufferSizeDB (3) + maxBitrate (4) + avgBitrate (4).
  offset += 1 + 1 + 3 + 4 + 4;

  // DecSpecificInfoTag = 5 -- its content IS the raw AudioSpecificConfig.
  if (walkToTag(5) == null || offset + 2 > bytes.length) return null;

  // AudioSpecificConfig: audioObjectType(5 bits), samplingFrequencyIndex(4 bits),
  // channelConfiguration(4 bits), ...
  final int byte0 = bytes[offset];
  final int byte1 = bytes[offset + 1];
  final int samplingFrequencyIndex = ((byte0 & 0x07) << 1) | (byte1 >> 7);
  if (samplingFrequencyIndex == 0xF) return null;
  return (byte1 >> 3) & 0x0F;
}

/// Reads [path]'s first audio track's channel count directly from its `esds`
/// AudioSpecificConfig by walking the ISO/IEC 14496-12 box tree (moov -> trak(soun) -> mdia ->
/// minf -> stbl -> stsd -> mp4a -> esds). Returns `null` if the file has no audio track at all.
Future<int?> _readMp4AudioChannelCount(String path) async {
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
        // hdlr (FullBox): version+flags(4) + pre_defined(4) + handler_type(4).
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
          if (stsd != null) {
            // stsd (FullBox): version+flags(4) + entry_count(4); the first sample entry
            // ('mp4a' for AAC, which is all this plugin ever produces) starts right after.
            final int firstEntryStart = stsd.start + 8 + 4 + 4;
            final String entryType = String.fromCharCodes(
              bytes,
              firstEntryStart + 4,
              firstEntryStart + 8,
            );
            if (entryType != 'mp4a') {
              return null;
            }
            final _BoxRange? mp4aEntry = _findBox(
              bytes,
              'mp4a',
              firstEntryStart,
              stsd.end,
            );
            final _BoxRange? esds = mp4aEntry == null
                ? null
                : _findBox(bytes, 'esds', mp4aEntry.start + 36, mp4aEntry.end);
            return esds == null ? null : _readEsdsChannelConfig(bytes, esds);
          }
        }
      }
    }
    trakOffset = trak.end;
  }
  return null;
}

/// Asserts CDEC-01/CDEC-03's cross-cutting reporting invariant (04-03-PLAN.md task 1): applied
/// to every codec/HDR case in this suite, exactly one coherent combination of
/// [CompressResult.hevcFallback]/[CompressResult.videoCodec] may hold. When [result.usedOriginal]
/// is true, no Transformer ever ran, so every conversion flag ([CompressResult.hevcFallback],
/// [CompressResult.toneMapped], [CompressResult.transmuxed]) must be false. Otherwise: either the
/// request's own codec was honoured ([CompressResult.hevcFallback] false,
/// [CompressResult.videoCodec] equal to [requestedCodec]), or it fell back
/// ([CompressResult.hevcFallback] true, [CompressResult.videoCodec] `'h264'`) -- a fallback can
/// never produce anything but H.264, and honouring the request can never itself be reported as a
/// fallback.
void _expectCodecFallbackInvariant(
  CompressResult result, {
  required String requestedCodec,
}) {
  if (result.usedOriginal) {
    expect(
      result.hevcFallback,
      isFalse,
      reason:
          'usedOriginal means no Transformer ever ran -- every conversion flag must be false',
    );
    expect(
      result.toneMapped,
      isFalse,
      reason:
          'usedOriginal means no Transformer ever ran -- every conversion flag must be false',
    );
    expect(
      result.transmuxed,
      isFalse,
      reason: 'usedOriginal and transmuxed are mutually exclusive outcomes',
    );
    return;
  }
  if (result.hevcFallback) {
    expect(
      result.videoCodec,
      'h264',
      reason:
          'a fallback always produces H.264 -- never HEVC 8-bit or any other codec',
    );
  } else {
    expect(
      result.videoCodec,
      requestedCodec,
      reason:
          'no fallback reported means the requested codec was honoured exactly',
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const CompressVideo compressVideo = CompressVideo();

  group('HDR clips report isHdr from a real platform media-info call', () {
    testWidgets(
      'hdr_hlg10.mp4 (HEVC Main10, HLG) reports isHdr, dimensions and codec',
      (WidgetTester tester) async {
        // A metadata read does not decode: a pass here proves MediaMetadataRetriever reports
        // the HDR transfer characteristic correctly, not that the goldfish HEVC decoder can
        // actually decode a Main10 stream (04-RESEARCH.md Open Question 1) -- that is a
        // separate, unproven risk this test does not exercise.
        await _expectMediaInfoMatchesSidecar(compressVideo, 'hdr_hlg10');
      },
    );

    testWidgets(
      'hdr_pq10.mp4 (HEVC Main10, PQ/HDR10) reports isHdr, dimensions and codec',
      (WidgetTester tester) async {
        await _expectMediaInfoMatchesSidecar(compressVideo, 'hdr_pq10');
      },
    );
  });

  group('Unusual audio and 4K60 clips report correct media info', () {
    testWidgets(
      'pcm_audio_480p.mov (LPCM audio) reports hasAudio and dimensions',
      (WidgetTester tester) async {
        await _expectMediaInfoMatchesSidecar(
          compressVideo,
          'pcm_audio_480p',
          extension: 'mov',
        );
      },
    );

    testWidgets(
      'surround51_480p.mp4 (5.1 AAC audio) reports hasAudio and dimensions',
      (WidgetTester tester) async {
        await _expectMediaInfoMatchesSidecar(compressVideo, 'surround51_480p');
      },
    );

    testWidgets('uhd_4k60.mp4 reports 3840x2160 with hasAudio: false', (
      WidgetTester tester,
    ) async {
      await _expectMediaInfoMatchesSidecar(compressVideo, 'uhd_4k60');
    });
  });

  group('An HDR clip either tone-maps to SDR honestly, or exhausts the fallback '
      'chain with a typed error -- never a third, uncontrolled outcome (04-02)', () {
    /// Compresses [clipName] with default options and asserts EXACTLY one of the two
    /// legitimate outcomes 04-02-PLAN.md's OpenGL-then-MediaCodec fallback chain can produce
    /// on a real device, matching this codebase's own established idiom for hardware-dependent
    /// divergence (compress_test.dart's/compress_audio_test.dart's AudioStrip cases): either
    /// the export succeeds and the fidelity assertion holds, or the chain is exhausted with a
    /// typed `unsupportedInput` error -- never a crash, never washed-out HDR passed through
    /// silently, and never any other reason.
    ///
    /// Confirmed live on the danserver emulator (compress_video_api35, API 35,
    /// swiftshader_indirect software GL): BOTH attempts fail on this specific hardware.
    /// `HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL` fails with `ExportException.errorCode`
    /// 5001 (`ERROR_CODE_VIDEO_FRAME_PROCESSING_FAILED`) -- logcat traces the root cause to the
    /// GL effects pipeline's input Surface being released before the goldfish HEVC decoder
    /// (which itself accepts the Main10 stream without complaint) can configure against it.
    /// The `HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_MEDIACODEC` retry then fails with code 3003
    /// (`ERROR_CODE_DECODING_FORMAT_UNSUPPORTED`) -- the decoder rejects the requested
    /// tone-mapped output colour-transfer configuration outright. Both failures are genuine
    /// software-GL/software-decoder capability gaps (04-RESEARCH.md Pitfall 3's "no synchronous
    /// capability check exists" and Pitfall 4's "whether the goldfish decoder handles Main10 is
    /// unproven" -- now proven, in the negative, for the full Transformer pipeline specifically;
    /// 04-01 already proved the METADATA read succeeds), not a bug in this plan's code: the
    /// fallback chain runs exactly as designed and correctly reports the typed, exhausted
    /// result rather than crashing or emitting washed-out HDR. This is a documented environment
    /// limitation (see `doc/HARDWARE_CHECKLIST.md` and `corpus/README.md`) -- the success branch
    /// below has never executed on this specific emulator, but stays in this test (not deleted,
    /// per 04-02-PLAN.md task 1's own instruction) so it runs for real the moment a hardware
    /// Android phone (QUESTIONS.md #3) or a future emulator/OS update makes tone-mapping
    /// available here.
    Future<void> expectToneMapOrExhaustedFallback(String clipName) async {
      final String path = await _copyAssetToTempFile(
        'assets/corpus/$clipName.mp4',
        '${clipName}_${DateTime.now().microsecondsSinceEpoch}.mp4',
      );
      final CompressJob job = compressVideo.compress(path);

      try {
        final CompressResult result = await job.result;

        // Asserted first, and loudly: if usedOriginal is true here the fixture is not
        // compressible enough for the tone-map path to have ever run at all -- a fixture bug
        // to fix in 04-01's generation script, not a result to accept.
        expect(
          result.usedOriginal,
          isFalse,
          reason:
              'usedOriginal:true means the tone-map path never ran -- a fixture bug, not a '
              'result to accept',
        );
        expect(result.transmuxed, isFalse);
        expect(result.toneMapped, isTrue);
        // requestedCodec: 'h264' -- this case uses default options (VideoCodec.h264), so the
        // invariant's only legitimate branch is "no fallback, videoCodec matches the request".
        _expectCodecFallbackInvariant(result, requestedCodec: 'h264');

        final MediaInfo outputInfo = await compressVideo.getMediaInfo(
          result.outputPath,
        );
        expect(outputInfo.isHdr, isFalse);

        final Map<String, dynamic> sidecar = await _loadSidecar(clipName);
        await _expectHdrFidelity(compressVideo, result, sidecar);
      } on CompressVideoException catch (e) {
        expect(
          e.reason,
          CompressVideoErrorReason.unsupportedInput,
          reason:
              'the only other legitimate outcome is an exhausted OpenGL-then-MediaCodec '
              'fallback chain reporting unsupportedInput -- any other reason is a real bug',
        );
        expect(
          e.message,
          contains('exhausted'),
          reason:
              'the exhausted-chain message names the chain it tried, per '
              'hdrFallbackExhaustedError',
        );
      }
    }

    testWidgets(
      'hdr_hlg10.mp4 (HLG) with default options',
      (WidgetTester tester) => expectToneMapOrExhaustedFallback('hdr_hlg10'),
      timeout: const Timeout(Duration(seconds: 60)),
    );

    testWidgets(
      'hdr_pq10.mp4 (PQ/HDR10) with default options',
      (WidgetTester tester) => expectToneMapOrExhaustedFallback('hdr_pq10'),
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });

  group('HdrMode.keepHdr either keeps genuine HDR HEVC on a capable device, or falls back to '
      'tone-mapped SDR H.264 with both flags saying so (04-03, CDEC-03, D-07/D-08)', () {
    /// Compresses [clipName] with `hdr: HdrMode.keepHdr` and asserts EXACTLY one of THREE
    /// legitimate outcomes: the keep branch (HEVC HDR preserved, `toneMapped: false`,
    /// `hevcFallback: false`), the tone-map fallback branch (tone-mapped SDR H.264,
    /// `toneMapped: true`, `hevcFallback: true`), or -- when keep-HDR is not achievable, an
    /// unachievable keep-HDR request takes the SAME OpenGL-then-MediaCodec fallback chain the
    /// plain `toneMapToSdr` HDR cases above do, and 04-02 already proved BOTH attempts exhaust
    /// on this specific emulator's software GL/decoder -- the exhausted-chain branch
    /// (`CompressVideoException` reason `unsupportedInput`, matching
    /// `expectToneMapOrExhaustedFallback`'s own dual-outcome idiom above). On the emulator the
    /// exhausted-chain branch is what executes; the keep branch exists so a capable device --
    /// the macOS host in 04-04, or a physical phone from the hardware checklist -- proves that
    /// half without a test rewrite.
    Future<void> expectKeepHdrOrFallback(String clipName) async {
      final String path = await _copyAssetToTempFile(
        'assets/corpus/$clipName.mp4',
        '${clipName}_keephdr_${DateTime.now().microsecondsSinceEpoch}.mp4',
      );
      final CompressJob job = compressVideo.compress(
        path,
        options: const CompressOptions(hdr: HdrMode.keepHdr),
      );

      try {
        final CompressResult result = await job.result;

        expect(
          result.usedOriginal,
          isFalse,
          reason:
              'usedOriginal:true means the keep-HDR gate never ran a real encode -- a fixture '
              'bug, not a result to accept',
        );
        expect(result.transmuxed, isFalse);
        // requestedCodec: 'hevc' -- a keep-HDR request's own non-fallback outcome is always
        // HEVC (D-07: keep-HDR output is HEVC Main10), so that is the codec the invariant
        // checks the keep branch against.
        _expectCodecFallbackInvariant(result, requestedCodec: 'hevc');

        if (result.hevcFallback) {
          // ignore: avoid_print
          print('KEEP_HDR_BRANCH=fallback');
          expect(result.toneMapped, isTrue);
          expect(result.videoCodec, 'h264');
          final MediaInfo outputInfo = await compressVideo.getMediaInfo(
            result.outputPath,
          );
          expect(outputInfo.isHdr, isFalse);

          final Map<String, dynamic> sidecar = await _loadSidecar(clipName);
          await _expectHdrFidelity(compressVideo, result, sidecar);
        } else {
          // ignore: avoid_print
          print('KEEP_HDR_BRANCH=keep');
          expect(result.toneMapped, isFalse);
          expect(result.videoCodec, 'hevc');
          final MediaInfo outputInfo = await compressVideo.getMediaInfo(
            result.outputPath,
          );
          expect(outputInfo.isHdr, isTrue);
        }
      } on CompressVideoException catch (e) {
        // ignore: avoid_print
        print('KEEP_HDR_BRANCH=exhausted');
        expect(
          e.reason,
          CompressVideoErrorReason.unsupportedInput,
          reason:
              'the only other legitimate outcome is an exhausted OpenGL-then-MediaCodec '
              'fallback chain reporting unsupportedInput -- any other reason is a real bug',
        );
        expect(
          e.message,
          contains('exhausted'),
          reason:
              'the exhausted-chain message names the chain it tried, per '
              'hdrFallbackExhaustedError',
        );
      }
    }

    testWidgets(
      'hdr_hlg10.mp4 (HLG) with HdrMode.keepHdr',
      (WidgetTester tester) => expectKeepHdrOrFallback('hdr_hlg10'),
      timeout: const Timeout(Duration(seconds: 60)),
    );

    testWidgets(
      'hdr_pq10.mp4 (PQ/HDR10) with HdrMode.keepHdr',
      (WidgetTester tester) => expectKeepHdrOrFallback('hdr_pq10'),
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });

  group('Unusual audio and 4K60 sources compress instead of failing (04-02 task 3)', () {
    testWidgets(
      'surround51_480p.mp4 (5.1 AAC) with default options downmixes to 2-channel AAC '
      'and reports audioReencoded: true, never taking the transmux fast path',
      (WidgetTester tester) async {
        final String path = await _copyAssetToTempFile(
          'assets/corpus/surround51_480p.mp4',
          'surround51_480p_${DateTime.now().microsecondsSinceEpoch}.mp4',
        );
        final CompressJob job = compressVideo.compress(path);
        final CompressResult result = await job.result;

        expect(result.audioReencoded, isTrue);
        expect(
          result.transmuxed,
          isFalse,
          reason:
              'a 5.1 source must never take the remux fast path with its six channels '
              'intact (AUDO-03, SizeGuard.wouldTransmux audio-channel-count condition)',
        );
        expect(result.audioCodec, 'aac');

        final int? channelCount = await _readMp4AudioChannelCount(
          result.outputPath,
        );
        expect(
          channelCount,
          2,
          reason:
              'read from the esds AudioSpecificConfig, the authoritative channel count '
              '-- not the mp4a sample entry\'s own (possibly unreliable) field',
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'pcm_audio_480p.mov (LPCM) with default options re-encodes to AAC and reports '
      'audioReencoded: true',
      (WidgetTester tester) async {
        final String path = await _copyAssetToTempFile(
          'assets/corpus/pcm_audio_480p.mov',
          'pcm_audio_480p_${DateTime.now().microsecondsSinceEpoch}.mov',
        );
        final CompressJob job = compressVideo.compress(path);
        final CompressResult result = await job.result;

        expect(result.audioReencoded, isTrue);
        expect(result.audioCodec, 'aac');
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'noaudio_720p.mp4 with default options compresses with no audio track and a '
      'null audioCodec, unchanged from Phases 2-3 (D-11)',
      (WidgetTester tester) async {
        final String path = await _copyAssetToTempFile(
          'assets/corpus/noaudio_720p.mp4',
          'noaudio_720p_${DateTime.now().microsecondsSinceEpoch}.mp4',
        );
        final CompressJob job = compressVideo.compress(path);
        final CompressResult result = await job.result;

        expect(result.audioCodec, isNull);
        expect(result.audioReencoded, isFalse);

        final MediaInfo outputInfo = await compressVideo.getMediaInfo(
          result.outputPath,
        );
        expect(outputInfo.hasAudio, isFalse);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'uhd_4k60.mp4 with default options compresses without error, honouring the '
      'never-larger contract either way, inside the suite\'s per-test bound',
      (WidgetTester tester) async {
        final String path = await _copyAssetToTempFile(
          'assets/corpus/uhd_4k60.mp4',
          'uhd_4k60_${DateTime.now().microsecondsSinceEpoch}.mp4',
        );
        final Stopwatch stopwatch = Stopwatch()..start();
        final CompressJob job = compressVideo.compress(path);
        final CompressResult result = await job.result;
        stopwatch.stop();
        // ignore: avoid_print
        print(
          'UHD_4K60_MEASURED elapsedMs=${stopwatch.elapsedMilliseconds} '
          'reportedElapsedMs=${result.elapsedMs}',
        );

        if (result.usedOriginal) {
          expect(result.outputBytes, result.inputBytes);
        } else {
          expect(
            result.widthPx,
            lessThanOrEqualTo(1280),
            reason: 'the default p720 preset caps the long side at 1280',
          );
        }
      },
      timeout: const Timeout(Duration(seconds: 120)),
    );
  });

  group('HEVC opt-in reports an honest hardware-only outcome, never a silent substitution '
      '(04-03, CDEC-01)', () {
    testWidgets(
      'portrait_hibitrate_1080p60.mp4 with VideoCodec.hevc either honours HEVC on a '
      'hardware encoder or reports the fallback to H.264',
      (WidgetTester tester) async {
        final String path = await _copyAssetToTempFile(
          'assets/corpus/portrait_hibitrate_1080p60.mp4',
          'portrait_hibitrate_hevc_${DateTime.now().microsecondsSinceEpoch}.mp4',
        );
        final CompressJob job = compressVideo.compress(
          path,
          options: const CompressOptions(codec: VideoCodec.hevc),
        );
        final CompressResult result = await job.result;

        // Asserted first, and loudly, exactly like the HDR tone-map cases above: if
        // usedOriginal is true here the codec gate never ran a real encode at all -- a
        // fixture bug, not a result to accept.
        expect(
          result.usedOriginal,
          isFalse,
          reason:
              'usedOriginal:true means the codec gate never ran a real encode -- a fixture '
              'bug, not a result to accept',
        );
        _expectCodecFallbackInvariant(result, requestedCodec: 'hevc');

        if (result.hevcFallback) {
          // ignore: avoid_print
          print('HEVC_BRANCH=fallback');
          expect(result.videoCodec, 'h264');
          expect(
            result.outputBytes,
            lessThan(result.inputBytes),
            reason:
                'a genuine H.264 re-encode of this hi-bitrate clip must still be smaller '
                'than the input',
          );
        } else {
          // ignore: avoid_print
          print('HEVC_BRANCH=success');
          final MediaInfo outputInfo = await compressVideo.getMediaInfo(
            result.outputPath,
          );
          expect(outputInfo.videoCodec, 'hevc');
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
