import 'dart:convert';

/// Où les réglages sont gardés (un petit texte JSON). Sur le bureau, un fichier
/// de `~/.config` ; dans le navigateur, nulle part.
abstract interface class SettingsStorage {
  String? read();
  void write(String text);
}

/// Des réglages gardés en mémoire (les essais).
class MemorySettingsStorage implements SettingsStorage {
  MemorySettingsStorage([this.text]);

  String? text;

  @override
  String? read() => text;

  @override
  void write(String text) => this.text = text;
}

/// Ce que l'éditeur retient d'une fois sur l'autre : les derniers fichiers
/// ouverts, et le dossier assets choisi pour chaque service.
///
/// Un confort : si le fichier est illisible ou ne peut pas être écrit, on s'en
/// passe sans rien dire.
class AppSettings {
  AppSettings([this._storage]) {
    _read();
  }

  final SettingsStorage? _storage;

  /// Nombre de fichiers récents gardés.
  static const maxRecent = 10;

  /// Les chemins des derniers services ouverts, le plus récent d'abord.
  List<String> get recent => List.unmodifiable(_recent);
  final _recent = <String>[];

  /// Le dossier assets choisi pour le service enregistré à tel chemin.
  Map<String, String> get assetsFolders => Map.unmodifiable(_folders);
  final _folders = <String, String>{};

  void addRecent(String path) {
    _recent
      ..remove(path)
      ..insert(0, path);
    if (_recent.length > maxRecent) _recent.length = maxRecent;
    _write();
  }

  void removeRecent(String path) {
    if (_recent.remove(path)) _write();
  }

  void clearRecent() {
    _recent.clear();
    _write();
  }

  /// Choisit le dossier assets du service [servicePath] ; `null` revient au
  /// dossier par défaut (`assets/` à côté du service).
  void setAssetsFolder(String servicePath, String? folder) {
    if (folder == null) {
      _folders.remove(servicePath);
    } else {
      _folders[servicePath] = folder;
    }
    _write();
  }

  void _read() {
    try {
      final data = jsonDecode(_storage?.read() ?? '{}');
      if (data is! Map) return;
      final recent = data['recent'];
      if (recent is List) {
        _recent.addAll(recent.whereType<String>().take(maxRecent));
      }
      final folders = data['assetsFolders'];
      if (folders is Map) {
        for (final e in folders.entries) {
          if (e.key is String && e.value is String) {
            _folders[e.key as String] = e.value as String;
          }
        }
      }
    } on Object {
      // Réglages illisibles : on repart de zéro.
    }
  }

  void _write() {
    try {
      _storage?.write(
        const JsonEncoder.withIndent('  ')
            .convert({'recent': _recent, 'assetsFolders': _folders}),
      );
    } on Object {
      // Pas de place, pas de droit : tant pis.
    }
  }
}
