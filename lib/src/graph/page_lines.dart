import 'package:yaml/yaml.dart';

/// La ligne (à partir de 1) où chaque page est déclarée dans [text], par nom.
/// Vide si le texte n'est pas un YAML lisible ou n'a pas de `pages`.
Map<String, int> pageLines(String text) {
  try {
    final root = loadYamlNode(text);
    if (root is! YamlMap) return const {};
    final pages = root.nodes['pages'];
    if (pages is! YamlMap) return const {};
    return {
      for (final key in pages.nodes.keys)
        if (key is YamlNode) '${key.value}': key.span.start.line + 1,
    };
  } on YamlException {
    return const {};
  }
}
