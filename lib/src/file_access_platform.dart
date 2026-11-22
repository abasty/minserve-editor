// Le système de fichiers de la plateforme : le navigateur ou le bureau.
// (`dart:io` n'existe pas dans le navigateur : l'import est conditionnel.)
export 'file_access_stub.dart' if (dart.library.io) 'file_access_io.dart';
