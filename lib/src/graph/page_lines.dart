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

/// La ligne (à partir de 1) de la partie [section] (`action`, `entree`,
/// `acces`...) de la page [page], ou de sa règle numéro [rule] (à partir de 0)
/// si [section] est `action`, ou de son instruction numéro [rule] si c'est
/// `ecran`. Si la partie n'existe pas, la ligne de la page ;
/// `null` si la page n'existe pas.
int? pageSectionLine(String text, String page, {String? section, int? rule}) {
  final start = pageLines(text)[page];
  if (start == null || section == null) return start;
  try {
    final root = loadYamlNode(text) as YamlMap;
    final node = (root.nodes['pages'] as YamlMap).nodes[page];
    if (node is! YamlMap) return start;
    for (final key in node.nodes.keys) {
      if (key is YamlNode && '${key.value}' == section) {
        if (rule != null && section == 'ecran') {
          final list = node.nodes[key];
          if (list is YamlList && rule >= 0 && rule < list.length) {
            return list.nodes[rule].span.start.line + 1;
          }
        }
        if (rule != null && section == 'action') {
          final saisies = (node.nodes[key] as YamlMap?)?.nodes['saisies'];
          if (saisies is YamlList && rule >= 0 && rule < saisies.length) {
            return saisies.nodes[rule].span.start.line + 1;
          }
        }
        return key.span.start.line + 1;
      }
    }
  } on Object {
    return start;
  }
  return start;
}
