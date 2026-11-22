import 'file_access.dart';
import 'settings.dart';

/// Le navigateur : pas de système de fichiers, pas de ligne de commande.
FileAccess platformFileAccess() => const BrowserFileAccess();

/// Le fichier nommé sur la ligne de commande : jamais dans le navigateur.
Future<OpenedFile?> readStartupFile(List<String> args) async => null;

/// Vrai pour une application de bureau (qui peut refuser de se fermer).
const bool isDesktopApp = false;

/// Pas de réglages gardés dans le navigateur.
SettingsStorage? platformSettingsStorage() => null;
