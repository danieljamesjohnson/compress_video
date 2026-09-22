// Widget coverage of every screen state main_screen.dart drives, plus both breakpoint sides
// and both backstop UI considerations -- runnable by `flutter test` with no device and no
// platform channel, via a fake CompressionRunner (compress/estimate/clearCache) and a fake
// ImagePickerPlatform (pick results only -- MockPlatformInterfaceMixin, the idiomatic
// image_picker test seam; not the same abstraction as CompressionRunner).
//
// Real dart:io work (temp-file creation, `File.length()`/`writeAsBytes()`) only ever
// completes if BOTH the call that starts it AND the wait for it run inside the SAME
// `WidgetTester.runAsync` block: `AutomatedTestWidgetsFlutterBinding` runs the whole test
// body inside a `FakeAsync` zone, and an async function's continuations stay bound to
// whichever zone was active when it started. A `tester.tap()` issued outside `runAsync`
// starts the tapped callback's async chain in the fake zone, where a genuine OS-backed
// Future never gets a real event-loop turn to complete -- no amount of `pump()` afterward,
// nor a *separate* later `runAsync` call, unblocks it. `pickClip` below does the tap AND the
// wait together, in one real zone, for exactly this reason. Every pick in this file also
// uses a tiny (1-byte) real file rather than the 4.45MB bundled corpus asset, so the real
// work involved is minimal and fast regardless of machine load.

import 'dart:async';
import 'dart:io';

import 'package:compress_video/compress_video.dart';
import 'package:compress_video_example/src/compression_runner.dart';
import 'package:compress_video_example/src/main_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// A fully test-controlled [CompressionRunner]: holds progress/result/estimate exactly where
/// the test puts them, with no platform channel.
class FakeCompressionRunner implements CompressionRunner {
  /// Set before calling [compress] to make it throw synchronously instead of returning a
  /// handle -- mirrors `CompressOptions.validate()`'s synchronous throw.
  CompressVideoException? compressSyncError;

  /// Set before calling [estimate] to make it fail. Fails synchronously when
  /// [estimateSyncThrow] is true, otherwise via the returned `Future`'s error channel.
  CompressVideoException? estimateError;
  bool estimateSyncThrow = false;

  /// Resolved by [estimate] when [estimateError] is unset.
  CompressEstimate? estimateValue;

  StreamController<double>? _progressController;
  Completer<CompressResult>? _resultCompleter;

  /// Whether [CompressionHandle.cancel] was invoked on the most recently started job.
  bool cancelCalled = false;

  @override
  CompressionHandle compress(String path, {required CompressOptions options}) {
    final CompressVideoException? syncError = compressSyncError;
    if (syncError != null) {
      throw syncError;
    }
    final StreamController<double> progressController =
        StreamController<double>.broadcast();
    final Completer<CompressResult> resultCompleter =
        Completer<CompressResult>();
    _progressController = progressController;
    _resultCompleter = resultCompleter;
    cancelCalled = false;
    return CompressionHandle(
      progress: progressController.stream,
      result: resultCompleter.future,
      cancel: () async {
        cancelCalled = true;
      },
    );
  }

  /// Emits a progress value on the most recently started job.
  void emitProgress(double percent) {
    _progressController?.add(percent);
  }

  /// Completes the most recently started job successfully.
  Future<void> completeWith(CompressResult result) async {
    final StreamController<double>? controller = _progressController;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
    _resultCompleter?.complete(result);
  }

  /// Fails the most recently started job.
  Future<void> failWith(CompressVideoException exception) async {
    final StreamController<double>? controller = _progressController;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
    _resultCompleter?.completeError(exception);
  }

  @override
  Future<CompressEstimate> estimate(
    String path, {
    required CompressOptions options,
  }) {
    final CompressVideoException? error = estimateError;
    if (error != null) {
      if (estimateSyncThrow) {
        throw error;
      }
      return Future<CompressEstimate>.error(error);
    }
    return Future<CompressEstimate>.value(
      estimateValue ??
          const CompressEstimate(
            outputBytes: 1000000,
            durationMs: 4000,
            widthPx: 1280,
            heightPx: 720,
            wouldTransmux: false,
            wouldUseOriginal: false,
          ),
    );
  }

  @override
  Future<void> clearCache() async {}
}

/// A fake [ImagePickerPlatform] the test fully controls: hold a pick pending, return a null
/// pick, or throw from a pick -- `MainScreen` reaches `image_picker` directly (D-25, so one
/// widget tree has no platform branch of its own), so this is the seam a widget test uses to
/// control it instead.
class FakeImagePickerPlatform extends ImagePickerPlatform
    with MockPlatformInterfaceMixin {
  /// Set by [getVideo] each call so the test can resolve it later, simulating the Picking
  /// state (pick call in flight).
  Completer<XFile?>? pendingCompleter;

  /// Set to make the next [getVideo] call fail instead of returning a pending future.
  Object? nextError;

  @override
  Future<XFile?> getVideo({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    Duration? maxDuration,
  }) {
    final Object? error = nextError;
    if (error != null) {
      nextError = null;
      return Future<XFile?>.error(error);
    }
    final Completer<XFile?> completer = Completer<XFile?>();
    pendingCompleter = completer;
    return completer.future;
  }
}

CompressResult _sampleResult({
  bool transmuxed = false,
  bool usedOriginal = false,
  bool audioReencoded = false,
}) => CompressResult(
  outputPath: '/tmp/compress_video_example_test_output.mp4',
  inputBytes: 4454349,
  outputBytes: 814822,
  widthPx: 720,
  heightPx: 1280,
  durationMs: 4000,
  videoCodec: 'h264',
  audioCodec: 'aac',
  transmuxed: transmuxed,
  usedOriginal: usedOriginal,
  toneMapped: false,
  hevcFallback: false,
  audioReencoded: audioReencoded,
  elapsedMs: 5877,
);

/// Picks a clip through the real "Pick video" button, backed by the [FakeImagePickerPlatform]
/// currently installed as [ImagePickerPlatform.instance], using a tiny real file (not the
/// 4.45MB bundled corpus asset). The tap AND the wait for `_setPickedFile`'s real
/// `File.length()` call run inside ONE [WidgetTester.runAsync] block -- see the file header
/// comment for why splitting them across separate real/fake zones leaves the pick stuck.
Future<void> pickClip(WidgetTester tester, {String name = 'clip.mp4'}) async {
  final FakeImagePickerPlatform fakePicker =
      ImagePickerPlatform.instance as FakeImagePickerPlatform;
  await tester.runAsync(() async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'compress_video_test_',
    );
    final File file = File('${tempDir.path}/$name');
    await file.writeAsBytes(<int>[0]);
    await tester.tap(find.text('Pick video'));
    fakePicker.pendingCompleter?.complete(XFile(file.path));
    // Give `_setPickedFile`'s real `File.length()` call (and the widget's own subsequent
    // real work) a moment to actually finish before leaving the real zone.
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await pumpUntilFound(tester, find.text('Compress video'));
}

/// Waits for the estimate debounce `Timer` (300ms) and the estimate `Future` it triggers to
/// resolve. Because the pick that scheduled this timer happened inside [pickClip]'s
/// `runAsync` block, the timer itself is a REAL timer bound to that same real zone (zones are
/// fixed at Timer-creation time, not at the call site awaiting it) -- ordinary fake-time
/// `pump(duration)` calls never advance it, so this needs its own `runAsync` wait too.
Future<void> waitForEstimateDebounce(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 400)),
  );
  await tester.pump();
}

/// Pumps fake-time steps until [finder] matches at least one widget or [maxPumps] is reached.
/// Only for state transitions that resolve via fake timers / already-real work (a
/// [FakeCompressionRunner] completer, a debounce `Timer`, a synchronously-thrown
/// `UnimplementedError`) -- never for genuine dart:io work, which needs [pickClip]'s
/// `runAsync` pattern instead.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 20,
}) async {
  for (int i = 0; i < maxPumps; i++) {
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Pumps [MainScreen] with a generously tall viewport (the default 800x600 test surface is
/// too short for the fully-populated screen -- Options panel + Estimate + Result + Player --
/// to fit without scrolling, which left `tester.tap(find.text('Compress video'))` silently
/// missing an off-screen button in earlier runs). Tests that manage their own
/// `tester.view` size (the breakpoint and 200-char-filename tests) do not use this.
Future<void> pumpMainScreen(
  WidgetTester tester,
  CompressionRunner runner, {
  Size viewSize = const Size(800, 2400),
}) async {
  tester.view.physicalSize = viewSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: MainScreen(runner: runner)));
  await tester.pump();
}

void main() {
  setUp(() {
    // Reset to a fresh fake before every test so no pending completer or queued error leaks
    // across tests.
    ImagePickerPlatform.instance = FakeImagePickerPlatform();
  });

  testWidgets(
    'Idle: empty state renders with no options/estimate/progress/result/player',
    (WidgetTester tester) async {
      await pumpMainScreen(tester, FakeCompressionRunner());

      expect(find.text('No video selected'), findsOneWidget);
      expect(find.text('Pick video'), findsOneWidget);
      expect(find.text('Use bundled sample clip →'), findsOneWidget);
      expect(find.text('Compress video'), findsNothing);
      expect(find.byType(SegmentedButton<CompressPreset>), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(Card), findsNothing);
      expect(find.byType(AspectRatio), findsNothing);
    },
  );

  testWidgets(
    'Picking: pick button shows a spinner and both actions are disabled while the pick call '
    'is in flight',
    (WidgetTester tester) async {
      final FakeImagePickerPlatform fakePicker = FakeImagePickerPlatform();
      ImagePickerPlatform.instance = fakePicker;

      await pumpMainScreen(tester, FakeCompressionRunner());

      await tester.tap(find.text('Pick video'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final ElevatedButton pickButton = tester.widget(
        find.byType(ElevatedButton),
      );
      expect(pickButton.onPressed, isNull);
      final TextButton bundledButton = tester.widget(find.byType(TextButton));
      expect(bundledButton.onPressed, isNull);

      fakePicker.pendingCompleter?.complete(null);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('picker error: a null pick leaves the screen in Idle', (
    WidgetTester tester,
  ) async {
    final FakeImagePickerPlatform fakePicker = FakeImagePickerPlatform();
    ImagePickerPlatform.instance = fakePicker;

    await pumpMainScreen(tester, FakeCompressionRunner());

    await tester.tap(find.text('Pick video'));
    await tester.pump();
    fakePicker.pendingCompleter?.complete(null);
    await tester.pumpAndSettle();

    expect(find.text('No video selected'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
    'picker error: a thrown pick leaves the screen in Idle with no snackbar and no error card',
    (WidgetTester tester) async {
      final FakeImagePickerPlatform fakePicker = FakeImagePickerPlatform()
        ..nextError = Exception('permission denied');
      ImagePickerPlatform.instance = fakePicker;

      await pumpMainScreen(tester, FakeCompressionRunner());

      await tester.tap(find.text('Pick video'));
      await tester.pumpAndSettle();

      expect(find.text('No video selected'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(Card), findsNothing);
    },
  );

  testWidgets(
    'options-panel/empty: the panel renders only after a clip is picked, pre-filled with '
    "CompressOptions()'s own defaults",
    (WidgetTester tester) async {
      const CompressOptions defaults = CompressOptions();
      await pumpMainScreen(tester, FakeCompressionRunner());
      expect(find.byType(SegmentedButton<CompressPreset>), findsNothing);

      await pickClip(tester);

      final SegmentedButton<CompressPreset> presetButton = tester.widget(
        find.byType(SegmentedButton<CompressPreset>),
      );
      expect(presetButton.selected, <CompressPreset>{defaults.preset});

      final SegmentedButton<AudioMode> audioButton = tester.widget(
        find.byType(SegmentedButton<AudioMode>),
      );
      expect(audioButton.selected, <AudioMode>{defaults.audio.mode});

      final TextField maxFpsField = tester.widget(
        find.widgetWithText(TextField, 'Max frame rate (fps)'),
      );
      expect(maxFpsField.controller!.text, defaults.maxFps.toString());
    },
  );

  testWidgets(
    'Estimating: shows "Estimating…" with the 12px spinner, then the resolved estimate',
    (WidgetTester tester) async {
      final FakeCompressionRunner runner = FakeCompressionRunner()
        ..estimateValue = const CompressEstimate(
          outputBytes: 2000000,
          durationMs: 4000,
          widthPx: 1280,
          heightPx: 720,
          wouldTransmux: false,
          wouldUseOriginal: false,
        );
      await pumpMainScreen(tester, runner);

      // pickClip already pumps until "Compress video" appears, by which point the
      // synchronous part of _scheduleEstimate (setting _isEstimating = true) has already run
      // too, so "Estimating…" is present as soon as the pick completes.
      await pickClip(tester);
      expect(find.text('Estimating…'), findsOneWidget);

      await waitForEstimateDebounce(tester);
      expect(find.textContaining('≈'), findsOneWidget);
      expect(find.text('Estimating…'), findsNothing);
    },
  );

  testWidgets(
    'estimate-line/error: a failed estimate() shows the fallback line without blocking Compress',
    (WidgetTester tester) async {
      final FakeCompressionRunner runner = FakeCompressionRunner()
        ..estimateError = const CompressVideoException(
          reason: CompressVideoErrorReason.io,
          message: 'estimate failed',
        );
      await pumpMainScreen(tester, runner);
      await pickClip(tester);
      await waitForEstimateDebounce(tester);

      expect(
        find.text('Estimate unavailable — Compress still works.'),
        findsOneWidget,
      );
      final ElevatedButton compressButton = tester.widget(
        find.widgetWithText(ElevatedButton, 'Compress video'),
      );
      expect(compressButton.onPressed, isNotNull);
    },
  );

  testWidgets(
    'backstop: targetSizeMb and videoBitrateBps together show the validation SnackBar and '
    'never enter Compressing',
    (WidgetTester tester) async {
      const String message =
          'videoBitrateBps and targetSizeMb are contradictory targets for the same '
          'output size; set at most one';
      final FakeCompressionRunner runner = FakeCompressionRunner()
        ..compressSyncError = const CompressVideoException(
          reason: CompressVideoErrorReason.unsupportedInput,
          message: message,
        );
      await pumpMainScreen(tester, runner);
      await pickClip(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Target size (MB, optional)'),
        '5',
      );
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Video bitrate (bps, optional)'),
        '500000',
      );
      await tester.pump();

      await tester.tap(find.text('Compress video'));
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(message), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'Compressing: options disabled, CTA hidden, live progress bar + integer percent + '
    'enabled Cancel',
    (WidgetTester tester) async {
      final FakeCompressionRunner runner = FakeCompressionRunner();
      await pumpMainScreen(tester, runner);
      await pickClip(tester);

      await tester.tap(find.text('Compress video'));
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Compress video'), findsNothing);
      final SegmentedButton<CompressPreset> presetButton = tester.widget(
        find.byType(SegmentedButton<CompressPreset>),
      );
      expect(presetButton.onSelectionChanged, isNull);

      runner.emitProgress(42);
      await tester.pump();
      expect(find.text('42%'), findsOneWidget);

      final OutlinedButton cancelButton = tester.widget(
        find.widgetWithText(OutlinedButton, 'Cancel'),
      );
      expect(cancelButton.onPressed, isNotNull);

      await runner.completeWith(_sampleResult());
      await tester.pump();
      await tester.pump();
    },
  );

  testWidgets(
    'Cancelled: pressing Cancel shows the SnackBar with no result card, options re-enabled',
    (WidgetTester tester) async {
      final FakeCompressionRunner runner = FakeCompressionRunner();
      await pumpMainScreen(tester, runner);
      await pickClip(tester);
      await tester.tap(find.text('Compress video'));
      await tester.pump();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pump();
      expect(runner.cancelCalled, isTrue);

      await runner.failWith(
        const CompressVideoException(
          reason: CompressVideoErrorReason.cancelled,
          message: 'cancelled',
        ),
      );
      await tester.pump();

      expect(find.text('Compression cancelled.'), findsOneWidget);
      expect(find.text('Compression failed.'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      final SegmentedButton<CompressPreset> presetButton = tester.widget(
        find.byType(SegmentedButton<CompressPreset>),
      );
      expect(presetButton.onSelectionChanged, isNotNull);
    },
  );

  /// Shared body for the three "Failed" cases below -- kept as three separate [testWidgets]
  /// rather than one test looping three times, since each iteration's real (runAsync-bound)
  /// work from [pickClip] should fully settle within its own isolated test rather than risk
  /// interleaving with the next iteration's fresh widget tree.
  Future<void> expectFailedReason(
    WidgetTester tester,
    CompressVideoErrorReason reason,
    String expectedBody,
  ) async {
    final FakeCompressionRunner runner = FakeCompressionRunner();
    await pumpMainScreen(tester, runner);
    await pickClip(tester);
    await tester.tap(find.text('Compress video'));
    await tester.pump();

    await runner.failWith(
      CompressVideoException(reason: reason, message: 'native failure'),
    );
    await tester.pump();

    expect(find.text('Compression failed.'), findsOneWidget);
    expect(find.text(expectedBody), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Try again'), findsOneWidget);
    final SegmentedButton<CompressPreset> presetButton = tester.widget(
      find.byType(SegmentedButton<CompressPreset>),
    );
    expect(presetButton.onSelectionChanged, isNotNull);
  }

  testWidgets(
    'Failed: decoderUnavailable renders its reason-mapped body, options re-enabled',
    (WidgetTester tester) async {
      await expectFailedReason(
        tester,
        CompressVideoErrorReason.decoderUnavailable,
        "This device can't decode that file's video track — try a different clip.",
      );
    },
  );

  testWidgets(
    'Failed: encoderUnavailable renders its reason-mapped body, options re-enabled',
    (WidgetTester tester) async {
      await expectFailedReason(
        tester,
        CompressVideoErrorReason.encoderUnavailable,
        "The encoder isn't available right now — try again in a moment.",
      );
    },
  );

  testWidgets(
    'Failed: outOfSpace renders its reason-mapped body, options re-enabled',
    (WidgetTester tester) async {
      await expectFailedReason(
        tester,
        CompressVideoErrorReason.outOfSpace,
        'Not enough free storage to finish — free up space and try again.',
      );
    },
  );

  testWidgets(
    'Done: savings headline, stat rows, only-true badges rendered in a Wrap',
    (WidgetTester tester) async {
      final FakeCompressionRunner runner = FakeCompressionRunner();
      await pumpMainScreen(tester, runner);
      await pickClip(tester);
      await tester.tap(find.text('Compress video'));
      await tester.pump();

      await runner.completeWith(
        _sampleResult(transmuxed: true, audioReencoded: true),
      );
      await tester.pump();

      expect(find.textContaining('smaller'), findsOneWidget);
      expect(find.text('transmuxed'), findsOneWidget);
      expect(find.text('audioReencoded'), findsOneWidget);
      expect(find.text('usedOriginal'), findsNothing);
      expect(find.byType(Wrap), findsOneWidget);
    },
  );

  testWidgets(
    'video-player: not rendered outside Done; loading spinner then the unavailable line, '
    'result card still present',
    (WidgetTester tester) async {
      final FakeCompressionRunner runner = FakeCompressionRunner();
      await pumpMainScreen(tester, runner);
      expect(find.byType(AspectRatio), findsNothing);

      await pickClip(tester);
      expect(find.byType(AspectRatio), findsNothing);

      await tester.tap(find.text('Compress video'));
      await tester.pump();
      expect(find.byType(AspectRatio), findsNothing);

      await runner.completeWith(_sampleResult());
      await tester.pump();
      // The AspectRatio(+loading spinner) is present for at most one frame between the Done
      // transition and initialize() rejecting -- pumpUntilFound tolerates whichever of the
      // two frames (loading or already-failed) this pump lands on.
      await pumpUntilFound(
        tester,
        find.text(
          'Playback unavailable — the compressed file was still written.',
        ),
      );
      expect(
        find.text(
          'Playback unavailable — the compressed file was still written.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('smaller'), findsOneWidget);
    },
  );

  testWidgets(
    'ordering: sections render in the fixed order Picker, Options, Estimate, '
    'Progress-or-Result, Player',
    (WidgetTester tester) async {
      final FakeCompressionRunner runner = FakeCompressionRunner();
      await pumpMainScreen(tester, runner);
      await pickClip(tester);
      await waitForEstimateDebounce(tester);
      await tester.tap(find.text('Compress video'));
      await tester.pump();
      await runner.completeWith(_sampleResult());
      await tester.pump();
      // No real video_player platform is registered in this test binary, so the player area
      // settles on the "unavailable" line rather than staying on AspectRatio -- use that line
      // as the Player section's position marker instead.
      await pumpUntilFound(
        tester,
        find.text(
          'Playback unavailable — the compressed file was still written.',
        ),
      );

      final double pickerY = tester.getTopLeft(find.text('clip.mp4')).dy;
      final double optionsY = tester.getTopLeft(find.text('Options')).dy;
      final double estimateY = tester.getTopLeft(find.textContaining('≈')).dy;
      final double resultY = tester
          .getTopLeft(find.textContaining('smaller'))
          .dy;
      final double playerY = tester
          .getTopLeft(
            find.text(
              'Playback unavailable — the compressed file was still written.',
            ),
          )
          .dy;

      expect(pickerY, lessThan(optionsY));
      expect(optionsY, lessThan(estimateY));
      expect(estimateY, lessThan(resultY));
      expect(resultY, lessThan(playerY));
    },
  );

  testWidgets(
    'breakpoint: at exactly 600 the constrained desktop layout applies',
    (WidgetTester tester) async {
      await pumpMainScreen(
        tester,
        FakeCompressionRunner(),
        viewSize: const Size(600, 800),
      );

      expect(
        find.byWidgetPredicate(
          (Widget w) => w is ConstrainedBox && w.constraints.maxWidth == 640,
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('breakpoint: at 599 the full-bleed phone layout applies', (
    WidgetTester tester,
  ) async {
    await pumpMainScreen(
      tester,
      FakeCompressionRunner(),
      viewSize: const Size(599, 800),
    );

    expect(
      find.byWidgetPredicate(
        (Widget w) => w is ConstrainedBox && w.constraints.maxWidth == 640,
      ),
      findsNothing,
    );
  });

  testWidgets(
    'backstop: a 200-character filename renders ellipsised on one line with no overflow at '
    '360px',
    (WidgetTester tester) async {
      final FakeImagePickerPlatform fakePicker = FakeImagePickerPlatform();
      ImagePickerPlatform.instance = fakePicker;

      await pumpMainScreen(
        tester,
        FakeCompressionRunner(),
        viewSize: const Size(360, 800),
      );

      final String longName = '${'a' * 196}.mp4';
      expect(longName.length, 200);

      await tester.runAsync(() async {
        final Directory tempDir = await Directory.systemTemp.createTemp(
          'compress_video_longname_',
        );
        final File longFile = File('${tempDir.path}/$longName');
        await longFile.writeAsBytes(<int>[0]);
        await tester.tap(find.text('Pick video'));
        fakePicker.pendingCompleter?.complete(XFile(longFile.path));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await pumpUntilFound(tester, find.textContaining('a' * 50));

      expect(tester.takeException(), isNull);
      final Text nameText = tester.widget(find.textContaining('a' * 50));
      expect(nameText.overflow, TextOverflow.ellipsis);
      expect(nameText.maxLines, 1);
    },
  );
}
