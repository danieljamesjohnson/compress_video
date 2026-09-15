// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compress_video_example/main.dart';

void main() {
  testWidgets('lists the bundled corpus assets with their byte sizes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const CompressVideoExampleApp());
    // Not pumpAndSettle(): the media-info panel below the asset list performs real
    // dart:io work (temp file + platform channel call) that needs the real event loop,
    // and shows an indeterminate CircularProgressIndicator meanwhile that never lets
    // pumpAndSettle's fake-clock loop converge. A bounded number of pumps is enough
    // for the asset list itself (rootBundle.load only) to resolve and render.
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('portrait_rot90.mp4'), findsOneWidget);
    expect(find.text('small_480p.mp4'), findsOneWidget);
    expect(find.text('noaudio_720p.mp4'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Text && (widget.data?.endsWith(' bytes') ?? false),
      ),
      findsNWidgets(3),
    );
  });
}
