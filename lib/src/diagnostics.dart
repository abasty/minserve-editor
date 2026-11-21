import 'package:minserve_core/minserve_core.dart';

/// Résultat de la lecture d'un texte de service : soit un [service], soit une
/// erreur ([message], et [line] si elle est localisée).
class Diagnostics {
  const Diagnostics.valid(Service this.service) : message = null, line = null;
  const Diagnostics.invalid(String this.message, {this.line}) : service = null;

  final Service? service;
  final String? message;

  /// Numéro de ligne (à partir de 1) de l'erreur, si connu.
  final int? line;

  bool get isValid => service != null;
}

/// Lit [text] comme un service Minserve, avec le code du serveur : un texte
/// accepté ici l'est aussi par le serveur (hors programmes `exec` et fichiers
/// `affiche`, qui dépendent de sa configuration).
Diagnostics diagnose(String text) {
  try {
    return Diagnostics.valid(Service.parseString(text));
  } on ServiceException catch (e) {
    return Diagnostics.invalid(e.message, line: e.line);
  }
}
