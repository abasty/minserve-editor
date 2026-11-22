import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'file_access.dart';

/// Le bureau : le fichier ouvert est réécrit en place.
FileAccess platformFileAccess() =>
    isDesktopApp ? const DesktopFileAccess() : const BrowserFileAccess();

/// Vrai pour une application de bureau (qui peut refuser de se fermer).
final bool isDesktopApp =
    Platform.isLinux || Platform.isMacOS || Platform.isWindows;

/// Le fichier nommé sur la ligne de commande (le premier argument qui n'est
/// pas une option), ou `null`. Un fichier qui n'existe pas est rendu `created`
/// (il sera créé à l'enregistrement) ; une autre lecture impossible lève
/// [FileAccessException].
Future<OpenedFile?> readStartupFile(List<String> args) async {
  final path = args.where((a) => !a.startsWith('-')).firstOrNull;
  if (path == null) return null;
  final file = File(path).absolute;
  if (await FileSystemEntity.type(file.path) == FileSystemEntityType.notFound) {
    return OpenedFile(_baseName(file.path), '', path: file.path, created: true);
  }
  return readServiceFile(path);
}

/// Lit le fichier de service [path].
Future<OpenedFile> readServiceFile(String path) async {
  final file = File(path).absolute;
  try {
    final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
    return OpenedFile(_baseName(file.path), text, path: file.path);
  } on FileSystemException catch (e) {
    throw FileAccessException(
      'Lecture impossible : ${e.osError?.message ?? e.message} (${file.path})',
    );
  }
}

/// Écrit [text] dans [path] sans jamais laisser un fichier à moitié écrit :
/// d'abord un fichier voisin, puis un renommage. Un lien symbolique est suivi
/// (le lien reste, c'est sa cible qui change).
Future<void> writeServiceFile(String path, String text) async {
  var target = File(path).absolute;
  try {
    if (await FileSystemEntity.isLink(target.path)) {
      target = File(await target.resolveSymbolicLinks());
    }
    final temp = File('${target.path}.minserve-editor.tmp');
    await temp.writeAsBytes(utf8.encode(text), flush: true);
    try {
      await temp.rename(target.path);
    } on FileSystemException {
      await temp.delete().catchError((_) => temp);
      rethrow;
    }
  } on FileSystemException catch (e) {
    throw FileAccessException(
      'Enregistrement impossible : ${e.osError?.message ?? e.message} '
      '(${target.path})',
    );
  }
}

String _baseName(String path) => path.split(Platform.pathSeparator).last;

/// Sélecteurs de fichiers du système, lecture et écriture directes.
class DesktopFileAccess implements FileAccess {
  const DesktopFileAccess();

  @override
  bool get savesInPlace => true;

  @override
  Future<OpenedFile?> open() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Ouvrir un service',
      type: FileType.custom,
      allowedExtensions: const ['yaml', 'yml', 'txt'],
    );
    final path = result?.files.singleOrNull?.path;
    return path == null ? null : readServiceFile(path);
  }

  @override
  Future<OpenedFile?> save(
    String name,
    String text, {
    String? path,
    bool saveAs = false,
  }) async {
    var target = saveAs ? null : path;
    if (target == null) {
      target = await FilePicker.platform.saveFile(
        dialogTitle: 'Enregistrer le service',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: const ['yaml', 'yml', 'txt'],
      );
      if (target == null) return null;
      if (!_baseName(target).contains('.')) target = '$target.yaml';
    }
    await writeServiceFile(target, text);
    return OpenedFile(_baseName(target), text, path: target);
  }
}
