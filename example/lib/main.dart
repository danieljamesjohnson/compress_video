import 'package:flutter/material.dart';

import 'src/main_screen.dart';

void main() {
  runApp(const CompressVideoExampleApp());
}

/// The `compress_video` example app.
///
/// A single Dart widget tree ([MainScreen]) shared, unmodified, by Android, iOS and macOS
/// (BULD-04). The only theming here is Flutter's stock Material 3 default -- no `colorScheme`
/// or `textTheme` override -- switching light/dark via [ThemeMode.system]
/// (03-UI-SPEC.md Design System).
class CompressVideoExampleApp extends StatelessWidget {
  /// Creates the example app.
  const CompressVideoExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'compress_video example',
      theme: ThemeData(useMaterial3: true, brightness: Brightness.light),
      darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      themeMode: ThemeMode.system,
      home: const MainScreen(),
    );
  }
}
