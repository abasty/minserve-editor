import 'dart:convert';

import 'package:file_picker/file_picker.dart';

/// Un fichier ouvert ou enregistré : son nom, son texte et, sur le bureau, son
/// chemin (le navigateur n'en a pas).
class OpenedFile {
  const OpenedFile(this.name, this.text, {this.path, this.created = false});

  final String name;
  final String text;
  final String? path;

  /// Vrai si le fichier n'existe pas encore (nommé sur la ligne de commande) :
  /// [text] est alors vide et il sera créé à l'enregistrement.
  final bool created;
}

/// Une lecture ou une écriture qui a échoué, avec une raison à montrer.
class FileAccessException implements Exception {
  const FileAccessException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Ouvrir et enregistrer un fichier de service. Une interface pour que le
/// navigateur (téléchargement) et le bureau (fichier en place) restent à part
/// de l'éditeur.
abstract interface class FileAccess {
  /// Vrai si « Enregistrer » réécrit le fichier ouvert (le bureau) ; faux si
  /// chaque enregistrement est un téléchargement (le navigateur).
  bool get savesInPlace;

  /// Demande un fichier à la personne ; `null` si elle annule.
  Future<OpenedFile?> open();

  /// Enregistre [text]. Si [path] est connu et [saveAs] faux, le fichier est
  /// réécrit en place ; sinon un nom est demandé (proposé : [name]). Rend le
  /// fichier enregistré, ou `null` si la personne annule.
  Future<OpenedFile?> save(
    String name,
    String text, {
    String? path,
    bool saveAs = false,
  });
}

/// Sélecteur de fichier et téléchargement : marche dans tous les navigateurs.
class BrowserFileAccess implements FileAccess {
  const BrowserFileAccess();

  @override
  bool get savesInPlace => false;

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
  Future<OpenedFile?> save(
    String name,
    String text, {
    String? path,
    bool saveAs = false,
  }) async {
    await FilePicker.platform.saveFile(
      fileName: name,
      bytes: utf8.encode(text),
    );
    return OpenedFile(name, text);
  }
}
