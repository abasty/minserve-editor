import 'dart:convert';

import 'package:file_picker/file_picker.dart';

import 'assets.dart';

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

  /// Les assets du service enregistré à [servicePath] : ceux du dossier
  /// [folder] s'il est donné, sinon de `assets/` à côté du service. `null` si
  /// on ne les a pas (le navigateur, ou un service pas encore enregistré).
  AssetSource? assetsFor(String? servicePath, {String? folder});

  /// Demande un dossier (à partir de [start]) ; `null` si on annule ou si le
  /// navigateur ne sait pas.
  Future<String?> chooseFolder(String? start);

  /// Lit le fichier [path] ; `null` s'il n'existe plus ou si le navigateur ne
  /// sait pas lire un chemin.
  Future<OpenedFile?> openPath(String path);

  /// Signale (après une courte pause) que le fichier [path] a peut-être changé
  /// sur le disque ; `null` si on ne peut pas le surveiller.
  Stream<void>? changes(String path);

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
  AssetSource? assetsFor(String? servicePath, {String? folder}) => null;

  @override
  Future<String?> chooseFolder(String? start) async => null;

  @override
  Future<OpenedFile?> openPath(String path) async => null;

  @override
  Stream<void>? changes(String path) => null;

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
