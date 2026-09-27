// The incumbent's own documented usage, compiled and run against the compatibility library
// (06-01-PLAN.md task 3, RELS-03).
//
// Source: the README of video_compress 3.1.4 at commit 69c0e3f (MIT), snapshotted in
// .planning/research/sources/video_compress_3.1.4/README.md, sections "Video compression"
// through "Listen the compression progress".
//
// The rule: each snippet body below is the README's text, copied verbatim, with only the
// import line changed to the compatibility library. Where a snippet could not compile under
// null safety as printed, the one change made is named in a comment next to it. Whitespace is
// whatever `dart format` makes of it. Each snippet sits in its own function, which only adds
// what Dart needs around a statement: parameters for the README's free variables, and a
// `return` so the test can look at what the snippet produced.
//
// The snippets are then called against a fake host, so they are proven to run, not only to
// compile.
// ignore_for_file: deprecated_member_use_from_same_package
import 'dart:async';
import 'dart:io';

import 'package:compress_video/src/compress_job.dart'
    show CompressVideoFlutterApiImpl;
import 'package:compress_video/src/messages.g.dart';
import 'package:compress_video/video_compress_compat.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------------------
// The snippets.
// ---------------------------------------------------------------------------------------

/// README, "Video compression".
Future<MediaInfo> _videoCompression(String path) async {
  MediaInfo mediaInfo = await VideoCompress.compressVideo(
    path,
    quality: VideoQuality.DefaultQuality,
    deleteOrigin: false, // It's false by default
  );
  return mediaInfo;
}

/// README, "Check compress state".
bool _checkCompressState() {
  return VideoCompress.isCompressing;
}

/// README, "Get memory thumbnail from VideoPath".
Future<Uint8List> _getMemoryThumbnail(String videopath) async {
  final uint8list = await VideoCompress.getByteThumbnail(
    videopath,
    quality: 50, // default(100)
    position: -1, // default(-1)
  );
  return uint8list;
}

/// README, "Get File thumbnail from VideoPath".
Future<File> _getFileThumbnail(String videopath) async {
  final thumbnailFile = await VideoCompress.getFileThumbnail(
    videopath,
    quality: 50, // default(100)
    position: -1, // default(-1)
  );
  return thumbnailFile;
}

/// README, "Get media information".
Future<MediaInfo> _getMediaInformation(String videopath) async {
  final info = await VideoCompress.getMediaInfo(videopath);
  return info;
}

/// README, "delete all cache files". The README prints the statement without its semicolon.
Future<void> _deleteAllCacheFiles() async {
  await VideoCompress.deleteAllCache();
}

/// README, "Listen the compression progress", minus the `State<Compress>` wrapper (and with
/// it the `@override` annotations and `super` calls, which need a widget to refer to).
class _Compress {
  // `late` is the only change: the README predates null safety and declares this field with
  // no initializer.
  late Subscription _subscription;

  void initState() {
    _subscription = VideoCompress.compressProgress$.subscribe((progress) {
      debugPrint('progress: $progress');
    });
  }

  void dispose() {
    _subscription.unsubscribe();
  }
}

// ---------------------------------------------------------------------------------------
// The harness: a fake host for every call the snippets reach.
// ---------------------------------------------------------------------------------------

const String _getMediaInfoChannelName =
    'dev.flutter.pigeon.compress_video.ProbeHostApi.getMediaInfo';
const String _startCompressChannelName =
    'dev.flutter.pigeon.compress_video.CompressHostApi.startCompress';
const String _clearCacheChannelName =
    'dev.flutter.pigeon.compress_video.CompressHostApi.clearCache';
const String _getThumbnailChannelName =
    'dev.flutter.pigeon.compress_video.ThumbnailHostApi.getThumbnail';
const String _getThumbnailFileChannelName =
    'dev.flutter.pigeon.compress_video.ThumbnailHostApi.getThumbnailFile';
const MessageCodec<Object?> _codec = CompressHostApi.pigeonChannelCodec;

void _setHandler(
  String channelName,
  Future<ByteData?> Function(ByteData? message)? handler,
) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(channelName, handler);
}

/// Copied from test/video_compress_compat_test.dart's own fake (it is private to that file),
/// reduced to what the snippets call.
class _FakeHost {
  final List<String> startedJobIds = <String>[];
  final List<CompressRequestMessage> requests = <CompressRequestMessage>[];
  final List<List<Object?>> thumbnailCalls = <List<Object?>>[];
  final List<List<Object?>> thumbnailFileCalls = <List<Object?>>[];
  int clearCacheCalls = 0;
  final Map<String, Completer<ByteData?>> _pendingReplies =
      <String, Completer<ByteData?>>{};

  void install() {
    _setHandler(_getMediaInfoChannelName, (ByteData? message) async {
      return _codec.encodeMessage(<Object?>[
        MediaInfoMessage(
          durationMs: 4000,
          widthPx: 1080,
          heightPx: 1920,
          rotationDegrees: 90,
          sizeBytes: 150610,
          hasAudio: true,
          isHdr: false,
        ),
      ]);
    });
    _setHandler(_startCompressChannelName, (ByteData? message) async {
      final List<Object?> args =
          _codec.decodeMessage(message)! as List<Object?>;
      final String jobId = args[1]! as String;
      startedJobIds.add(jobId);
      requests.add(args[2]! as CompressRequestMessage);
      final Completer<ByteData?> completer = Completer<ByteData?>();
      _pendingReplies[jobId] = completer;
      return completer.future;
    });
    _setHandler(_clearCacheChannelName, (ByteData? message) async {
      clearCacheCalls++;
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
      return _codec.encodeMessage(<Object?>['/cache/thumb-1.jpg']);
    });
  }

  void uninstall() {
    _setHandler(_getMediaInfoChannelName, null);
    _setHandler(_startCompressChannelName, null);
    _setHandler(_clearCacheChannelName, null);
    _setHandler(_getThumbnailChannelName, null);
    _setHandler(_getThumbnailFileChannelName, null);
  }

  void completeSuccess(String jobId) {
    _pendingReplies
        .remove(jobId)!
        .complete(
          _codec.encodeMessage(<Object?>[
            CompressResultMessage(
              outputPath: '/tmp/fake-output.mp4',
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeHost fake;

  setUp(() {
    fake = _FakeHost()..install();
  });

  tearDown(() {
    VideoCompress.dispose();
    fake.uninstall();
  });

  test('"Video compression" and "Check compress state" run', () async {
    expect(_checkCompressState(), isFalse);

    final Future<MediaInfo> pending = _videoCompression('/tmp/in.mp4');
    expect(_checkCompressState(), isTrue);
    expect(fake.requests.single.presetMaxLongSidePx, 1280);

    fake.completeSuccess(fake.startedJobIds.single);
    final MediaInfo mediaInfo = await pending;

    expect(mediaInfo.path, '/tmp/fake-output.mp4');
    expect(mediaInfo.filesize, 500);
    expect(mediaInfo.isCancel, isFalse);
    expect(_checkCompressState(), isFalse);
  });

  test('"Get memory thumbnail from VideoPath" runs', () async {
    final Uint8List bytes = await _getMemoryThumbnail('/tmp/in.mp4');

    expect(bytes, <int>[0xFF, 0xD8, 0xFF]);
    expect(fake.thumbnailCalls.single, <Object?>['/tmp/in.mp4', 0, 50, null]);
  });

  test('"Get File thumbnail from VideoPath" runs', () async {
    final File file = await _getFileThumbnail('/tmp/in.mp4');

    expect(file.path, '/cache/thumb-1.jpg');
    expect(fake.thumbnailFileCalls.single, <Object?>[
      '/tmp/in.mp4',
      0,
      50,
      null,
      null,
    ]);
  });

  test('"Get media information" runs', () async {
    final MediaInfo info = await _getMediaInformation('/tmp/in.mp4');

    expect(info.path, '/tmp/in.mp4');
    expect(info.width, 1080);
    expect(info.height, 1920);
    expect(info.duration, 4000.0);
  });

  test('"delete all cache files" runs', () async {
    await _deleteAllCacheFiles();

    expect(fake.clearCacheCalls, 1);
  });

  test('"Listen the compression progress" runs: the subscriber prints each '
      'value until it unsubscribes', () async {
    final List<String?> printed = <String?>[];
    final DebugPrintCallback originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      printed.add(message);
    };
    addTearDown(() => debugPrint = originalDebugPrint);

    final _Compress state = _Compress()..initState();
    final Future<MediaInfo> pending = _videoCompression('/tmp/in.mp4');
    final String jobId = fake.startedJobIds.single;

    CompressVideoFlutterApiImpl().onProgress(jobId, 42.0);
    await pumpEventQueue();
    expect(printed, <String>['progress: 42.0']);

    state.dispose();
    CompressVideoFlutterApiImpl().onProgress(jobId, 77.0);
    await pumpEventQueue();
    expect(printed, <String>['progress: 42.0']);

    fake.completeSuccess(jobId);
    await pending;
  });
}
