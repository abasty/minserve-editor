import 'package:flutter/material.dart';

import 'src/editor_page.dart';
import 'src/file_access.dart';
import 'src/file_access_platform.dart';

Future<void> main(List<String> args) async {
  // Sur le bureau, un fichier nommé sur la ligne de commande s'ouvre au départ.
  OpenedFile? file;
  String? message;
  try {
    file = await readStartupFile(args);
    if (file != null && file.created) {
      // Un nom qui n'existe pas encore : un nouveau service, créé à
      // l'enregistrement.
      message = 'Nouveau fichier : ${file.path} (créé à l\'enregistrement)';
      file = OpenedFile(file.name, newServiceText, path: file.path);
    }
  } on FileAccessException catch (e) {
    message = e.message;
  }
  runApp(MinserveEditorApp(file: file, message: message));
}

class MinserveEditorApp extends StatelessWidget {
  const MinserveEditorApp({super.key, this.file, this.message});

  final OpenedFile? file;
  final String? message;

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
      home: EditorPage(
        files: platformFileAccess(),
        initialFile: file,
        startupMessage: message,
        guardClose: isDesktopApp,
      ),
    );
  }
}
