import 'package:flutter/material.dart';

import 'src/editor_page.dart';

void main() => runApp(const MinserveEditorApp());

class MinserveEditorApp extends StatelessWidget {
  const MinserveEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF3A5BA0),
        brightness: brightness,
      ),
      useMaterial3: true,
    );
    return MaterialApp(
      title: 'Minserve Editor',
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const EditorPage(),
    );
  }
}
