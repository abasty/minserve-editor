import 'package:flutter/services.dart';
import 'package:minserve_core/minserve_core.dart';

import 'service_edit.dart';

/// Le fichier de la bibliothèque, livré avec l'éditeur.
const libraryAsset = 'assets/library.yaml';

/// Un minget de la bibliothèque : une macro toute faite qu'on copie dans un
/// service pour l'utiliser.
class LibraryMinget {
  const LibraryMinget(this.definition, this.block);

  /// La macro, lue comme le serveur la lit.
  final MacroDefinition definition;

  /// Les lignes de sa définition (commentaires compris), telles qu'on les copie.
  final List<String> block;

  String get name => definition.name;
}

/// Les mingets du texte de bibliothèque [text]. Lève [EditException] ou
/// [ServiceException] si le texte n'est pas une bibliothèque valide.
List<LibraryMinget> parseLibrary(String text) {
  final blocks = libraryBlocks(text);
  // Le serveur sait lire des macros, pas une bibliothèque seule : on lui en
  // fait un service minimal.
  final service = Service.parseString(
    '$text\ndebut: a\npages:\n  a:\n    ecran: [efface]\n',
  );
  return [
    for (final e in blocks.entries)
      LibraryMinget(service.macros[e.key]!, e.value),
  ];
}

/// Lit la bibliothèque livrée avec l'éditeur.
Future<List<LibraryMinget>> loadLibrary([AssetBundle? bundle]) async =>
    parseLibrary(await (bundle ?? rootBundle).loadString(libraryAsset));

List<LibraryMinget>? _loaded;

/// La bibliothèque livrée, lue une seule fois (et partagée par les panneaux qui
/// la montrent).
Future<List<LibraryMinget>> libraryMingets() async =>
    _loaded ??= await loadLibrary();
