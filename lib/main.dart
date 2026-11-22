import 'package:flutter/material.dart';

import 'src/editor_page.dart';
import 'src/file_access.dart';
import 'src/file_access_platform.dart';
import 'src/settings.dart';

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
  final settings = AppSettings(platformSettingsStorage());
  final files = platformFileAccess();
  if (file == null && args.isEmpty && files.savesInPlace) {
    // Sans fichier demandé, on rouvre le dernier service s'il existe encore.
    final last = settings.recent.firstOrNull;
    if (last != null) {
      try {
        file = await files.openPath(last);
      } on FileAccessException catch (e) {
        message = e.message;
      }
    }
  }
  runApp(
    MinserveEditorApp(
      file: file,
      message: message,
      files: files,
      settings: settings,
    ),
  );
}

class MinserveEditorApp extends StatelessWidget {
  const MinserveEditorApp({
    super.key,
    this.file,
    this.message,
    this.files,
    this.settings,
  });

  final FileAccess? files;
  final AppSettings? settings;
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
        files: files,
        settings: settings,
        initialFile: file,
        startupMessage: message,
        guardClose: isDesktopApp,
      ),
    );
  }
}
