// Basic smoke test for the compress_video example app shell.
//
// Full state coverage (all seven screen states, the two breakpoint sides and both backstop
// considerations) lives in `main_screen_test.dart`, which drives `MainScreen` directly with an
// injectable fake `CompressionRunner` -- no platform channel needed.

import 'package:flutter_test/flutter_test.dart';

import 'package:compress_video_example/main.dart';

void main() {
  testWidgets('renders the compress_video example app shell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const CompressVideoExampleApp());
    await tester.pump();

    expect(find.text('compress_video example'), findsOneWidget);
    expect(find.text('Use bundled sample clip →'), findsOneWidget);
  });
}
