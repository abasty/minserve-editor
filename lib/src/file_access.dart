import 'dart:convert';

import 'package:file_picker/file_picker.dart';

/// Un fichier ouvert : son nom et son texte.
class OpenedFile {
  const OpenedFile(this.name, this.text);

  final String name;
  final String text;
}

/// Ouvrir et enregistrer un fichier de service. Une interface pour que le
/// dossier local ou le brouillon du navigateur puissent s'ajouter plus tard
/// sans toucher à l'éditeur.
abstract interface class FileAccess {
  /// Demande un fichier à la personne ; `null` si elle annule.
  Future<OpenedFile?> open();

  /// Enregistre [text] sous [name] (un téléchargement dans le navigateur).
  Future<void> save(String name, String text);
}

/// Sélecteur de fichier et téléchargement : marche dans tous les navigateurs.
class BrowserFileAccess implements FileAccess {
  const BrowserFileAccess();

  @override
  Future<OpenedFile?> open() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['yaml', 'yml', 'txt'],
      withData: true,
    );
    final file = result?.files.singleOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return null;
    return OpenedFile(file.name, utf8.decode(bytes, allowMalformed: true));
  }

  @override
  Future<void> save(String name, String text) async {
    await FilePicker.platform.saveFile(
      fileName: name,
      bytes: utf8.encode(text),
    );
  }
}
