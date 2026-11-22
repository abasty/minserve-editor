import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Un fichier du dossier `assets` qu'on ne peut pas lire (introuvable, hors du
/// dossier, trop gros...), avec la raison à montrer.
class AssetException implements Exception {
  const AssetException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Taille maximale d'un fichier de `assets` : la même que dans le serveur.
const maxAssetSize = 256 * 1024;

/// Les fichiers du dossier `assets` d'un service, pour les instructions
/// `affiche` de l'aperçu.
abstract interface class AssetSource {
  /// Où ils sont, pour le dire à la personne (un chemin de dossier).
  String get label;

  /// Le contenu de [path] (relatif au dossier, avec des `/`). Lève
  /// [AssetException] s'il ne peut pas être lu.
  Uint8List read(String path);

  /// Les chemins de tous les fichiers du dossier (sous-dossiers compris, avec
  /// des `/`), triés.
  List<String> list();
}

/// Des assets en mémoire (les essais ; plus tard des fichiers choisis dans le
/// navigateur).
class MapAssets implements AssetSource {
  const MapAssets(this.files, {this.label = 'assets'});

  final Map<String, Uint8List> files;

  @override
  final String label;

  @override
  List<String> list() => files.keys.toList()..sort();

  @override
  Uint8List read(String path) {
    final bytes = files[path];
    if (bytes == null) {
      throw AssetException('fichier introuvable dans assets : $path');
    }
    if (bytes.length > maxAssetSize) {
      throw AssetException(
        'fichier trop gros (> $maxAssetSize octets) : $path',
      );
    }
    return bytes;
  }
}

/// Ce que la personne peut régler pour les assets du service ouvert : choisir un
/// autre dossier, ou revenir à `assets/` à côté du service.
class AssetsSetup {
  const AssetsSetup({
    required this.choose,
    required this.reset,
    required this.custom,
  });

  /// Demande un dossier ; rend les assets de ce dossier, ou `null` si on
  /// annule.
  final Future<AssetSource?> Function() choose;

  /// Revient au dossier par défaut et rend ses assets.
  final AssetSource? Function() reset;

  /// Vrai si le dossier a été choisi (ce n'est pas celui par défaut).
  final bool custom;
}

/// Donne aux aperçus les assets du service ouvert (ou rien : ils ne sont pas
/// disponibles, dans le navigateur par exemple).
class AssetsScope extends InheritedWidget {
  const AssetsScope({
    super.key,
    required this.source,
    this.setup,
    required super.child,
  });

  final AssetSource? source;
  final AssetsSetup? setup;

  static AssetsSetup? setupOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AssetsScope>()?.setup;

  static AssetSource? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AssetsScope>()?.source;

  @override
  bool updateShouldNotify(AssetsScope old) =>
      old.source != source || old.setup?.custom != setup?.custom;
}
