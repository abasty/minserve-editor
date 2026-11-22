/// Les modifications du graphe, faites **dans le texte** du service : chacune
/// prend le texte YAML et rend le nouveau texte, en ne touchant que les lignes
/// concernées (commentaires et mise en forme du reste sont conservés).
///
/// Chaque fonction vérifie que le texte de départ est un service valide, et que
/// le résultat l'est aussi : sinon elle lance [EditException] et le texte n'est
/// pas modifié.
library;

import 'dart:convert';

import 'package:minserve_core/minserve_core.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// Une modification refusée, avec la raison en français.
class EditException implements Exception {
  EditException(this.message);

  final String message;

  @override
  String toString() => message;
}

final _nameRe = RegExp(r'^[A-Za-z0-9_-]+$');

/// Pourquoi [name] n'est pas un nom de page utilisable, ou `null` s'il l'est.
String? pageNameError(String name, Iterable<String> existing) {
  if (name.isEmpty) return 'Un nom est nécessaire.';
  if (!_nameRe.hasMatch(name)) {
    return 'Lettres, chiffres, « - » et « _ » seulement.';
  }
  if (existing.contains(name)) return 'Une page porte déjà ce nom.';
  return null;
}

/// Les touches qu'une règle peut utiliser.
const ruleKeys = [
  'envoi',
  'retour',
  'repetition',
  'annulation',
  'sommaire',
  'correction',
  'suite',
];

/// Un endroit du texte qui désigne une page.
class PageRef {
  PageRef(this.path, this.where, {this.removable = false});

  /// Chemin dans le YAML de la valeur qui contient le nom de la page.
  final List<Object> path;

  /// Où c'est, pour l'afficher (`page a, règle 3`, `debut`...).
  final String where;

  /// Vrai si c'est une règle (élément d'une liste) qu'on peut supprimer avec
  /// la page ; faux si c'est une valeur seule (`debut`, `exec.suivant`...) qu'il
  /// faut changer à la main.
  final bool removable;
}

// --- Lecture ---

YamlMap _rootOf(String text) {
  final doc = loadYaml(text);
  if (doc is! YamlMap) throw EditException('Le texte n\'est pas un service.');
  return doc;
}

YamlMap _pagesOf(YamlMap root) {
  final pages = root['pages'];
  if (pages is! YamlMap) throw EditException('Le service n\'a pas de pages.');
  return pages;
}

bool _names(Object? value, String page) =>
    value != null && (value is String || value is int) && '$value' == page;

/// Valide [text] avec le code du serveur.
void _requireValid(String text) {
  try {
    Service.parseString(text);
  } on Object catch (e) {
    throw EditException(
      'Corrigez d\'abord les erreurs du texte : ${_message(e)}',
    );
  }
}

String _message(Object e) => e is ServiceException ? e.message : '$e';

String _checked(String result) {
  try {
    Service.parseString(result);
  } on Object catch (e) {
    throw EditException('Le service ne serait plus valide : ${_message(e)}');
  }
  return result;
}

/// Tous les endroits de [text] qui désignent la page [page].
List<PageRef> pageReferences(String text, String page) {
  final root = _rootOf(text);
  final refs = <PageRef>[];

  void scalar(List<Object> path, String where) {
    Object? node = root;
    for (final key in path) {
      if (node is YamlMap) {
        node = node[key];
      } else if (node is YamlList && key is int && key < node.length) {
        node = node[key];
      } else {
        return;
      }
    }
    if (_names(node, page)) refs.add(PageRef(path, where));
  }

  void rules(List<Object> listPath, String where) {
    Object? list = root;
    for (final key in listPath) {
      list = list is YamlMap ? list[key] : null;
    }
    if (list is! YamlList) return;
    for (var i = 0; i < list.length; i++) {
      final rule = list[i];
      if (rule is YamlMap && _names(rule['suivant'], page)) {
        refs.add(
          PageRef(
            [...listPath, i, 'suivant'],
            '$where, règle ${i + 1}',
            removable: true,
          ),
        );
      }
    }
  }

  scalar(['debut'], 'debut');
  scalar(['guide'], 'guide');
  scalar(['mdp_obligatoire'], 'mdp_obligatoire');
  scalar(['acces', 'sinon'], 'acces (défaut), sinon');
  rules(['raccourcis'], 'raccourcis');
  for (final name in _pagesOf(root).keys) {
    scalar(['pages', name, 'acces', 'sinon'], 'page $name, acces.sinon');
    scalar(['pages', name, 'exec', 'suivant'], 'page $name, exec.suivant');
    rules(['pages', name, 'action', 'saisies'], 'page $name');
  }
  return refs;
}

// --- Aides d'édition ---

/// La dernière ligne (à partir de 0) de [node] : sa fin est parfois au début de
/// la ligne suivante, devant l'indentation.
int _lastLine(YamlNode node, List<String> lines, int start) {
  final end = node.span.end;
  var line = end.line;
  if (line > start &&
      line < lines.length &&
      lines[line]
          .substring(0, end.column.clamp(0, lines[line].length))
          .trim()
          .isEmpty) {
    line--;
  }
  return line;
}

/// Retire du texte l'élément en [path] : ses lignes entières, avec les
/// commentaires collés au-dessus si [comments]. C'est le texte qui est coupé,
/// pas yaml_edit qui retire : il emporterait aussi le commentaire qui suit.
///
/// Si l'élément (d'une liste) n'est pas seul sur ses lignes, comme dans
/// `[a, b]`, yaml_edit s'en charge.
String _cut(String text, List<Object> path, {required bool comments}) {
  final e = YamlEditor(text);
  final node = e.parseAt(path);
  final lines = text.split('\n');
  var start = node.span.start.line;
  final key = path.last;
  if (key is String) {
    final parent = e.parseAt(path.sublist(0, path.length - 1)) as YamlMap;
    for (final k in parent.nodes.keys) {
      if (k is YamlScalar && '${k.value}' == key) start = k.span.start.line;
    }
  }
  final end = _lastLine(node, lines, start);
  if (key is int) {
    final before = lines[node.span.start.line].substring(
      0,
      node.span.start.column,
    );
    final after = lines[end].substring(
      node.span.end.column.clamp(0, lines[end].length),
    );
    final alone =
        RegExp(r'^\s*-\s*$').hasMatch(before) &&
        (after.trim().isEmpty || after.trim().startsWith('#'));
    if (!alone) return (e..remove(path)).toString();
  }
  if (comments) {
    while (start > 0 && lines[start - 1].trimLeft().startsWith('#')) {
      start--;
    }
  }
  lines.removeRange(start, end + 1);
  return lines.join('\n');
}

// --- Modifications ---

/// Ajoute une page [name] sans saisie (une page d'affichage), à la fin de
/// `pages`.
String addPage(String text, String name) {
  final error = pageNameError(name, _pagesOf(_rootOf(text)).keys.cast());
  if (error != null) throw EditException('Nom « $name » : $error');
  _requireValid(text);
  final e = YamlEditor(text);
  e.update(
    ['pages', name],
    {
      'ecran': [
        'efface',
        {'ecrit': name},
      ],
    },
  );
  return _checked(e.toString());
}

/// Renomme la page [from] en [to], et toutes les références à elle.
String renamePage(String text, String from, String to) {
  final pages = _pagesOf(_rootOf(text));
  if (!pages.containsKey(from)) {
    throw EditException('Il n\'y a pas de page « $from ».');
  }
  final error = pageNameError(to, pages.keys.cast());
  if (error != null) throw EditException('Nom « $to » : $error');
  _requireValid(text);

  final e = YamlEditor(text);
  for (final ref in pageReferences(text, from)) {
    e.update(ref.path, to);
  }
  // Le nom de la page est une clé : yaml_edit ne sait pas la renommer, on
  // remplace son texte à la place.
  final result = e.toString();
  for (final key in _pagesOf(_rootOf(result)).nodes.keys) {
    if (key is YamlScalar && '${key.value}' == from) {
      final span = key.span;
      return _checked(
        result.replaceRange(span.start.offset, span.end.offset, to),
      );
    }
  }
  throw EditException('Il n\'y a pas de page « $from ».');
}

/// Supprime la page [name], avec les commentaires qui la précèdent, et les
/// règles qui y mènent. Refuse si une autre valeur y renvoie (page de départ,
/// `exec.suivant`...) : [pageReferences] dit lesquelles.
String removePage(String text, String name) {
  final pages = _pagesOf(_rootOf(text));
  if (!pages.containsKey(name)) {
    throw EditException('Il n\'y a pas de page « $name ».');
  }
  _requireValid(text);

  final refs = [
    for (final r in pageReferences(text, name))
      if (!(r.path.length > 1 && r.path[0] == 'pages' && r.path[1] == name)) r,
  ];
  final blocking = [
    for (final r in refs)
      if (!r.removable) r.where,
  ];
  if (blocking.isNotEmpty) {
    throw EditException(
      'La page « $name » est encore utilisée par : ${blocking.join(', ')}. '
      'Changez-le d\'abord dans le texte.',
    );
  }

  var current = text;
  // De la fin au début : les numéros des règles restent justes.
  final rules = [for (final r in refs) r.path.sublist(0, r.path.length - 1)]
    ..sort(_laterFirst);
  for (final path in rules) {
    current = _removeItem(current, path);
  }

  return _checked(_cut(current, ['pages', name], comments: true));
}

/// Ordre des chemins d'éléments de liste : les listes l'une après l'autre, et
/// dans chacune le dernier élément d'abord.
int _laterFirst(List<Object> a, List<Object> b) {
  final listA = a.sublist(0, a.length - 1).join('/');
  final listB = b.sublist(0, b.length - 1).join('/');
  if (listA != listB) return listA.compareTo(listB);
  return (b.last as int).compareTo(a.last as int);
}

/// Supprime l'élément de liste en [path] (dernier élément : son numéro).
/// Retirer la dernière règle d'une page lui retire aussi sa saisie : le service
/// n'accepte pas de saisie sans règle.
String _removeItem(String text, List<Object> path) {
  final listPath = path.sublist(0, path.length - 1);
  final index = path.last as int;
  final list = YamlEditor(text).parseAt(listPath) as YamlList;
  if (list.length == 1) {
    // Les raccourcis ne peuvent pas être une liste vide : on retire la clé.
    if (listPath.length == 1 && listPath[0] == 'raccourcis') {
      return _cut(text, listPath, comments: false);
    }
    if (listPath.length == 4 && listPath[0] == 'pages') {
      final page = listPath.sublist(0, 2);
      return _cut(_cut(text, [...page, 'action'], comments: false), [
        ...page,
        'entree',
      ], comments: false);
    }
  }
  // Les commentaires au-dessus du premier élément décrivent plutôt la liste.
  return _cut(text, path, comments: index > 0);
}

/// Les pages qui perdraient leur saisie si on supprimait la page [name] : celles
/// dont toutes les règles y mènent.
List<String> pagesLosingInput(String text, String name) {
  final pages = _pagesOf(_rootOf(text));
  final lost = <String>[];
  for (final entry in pages.entries) {
    if (entry.key == name) continue;
    final page = entry.value;
    final action = page is YamlMap ? page['action'] : null;
    final saisies = action is YamlMap ? action['saisies'] : null;
    if (saisies is! YamlList || saisies.isEmpty) continue;
    if (saisies.every((r) => r is YamlMap && _names(r['suivant'], name))) {
      lost.add('${entry.key}');
    }
  }
  return lost;
}

/// Vrai si la page [from] n'a qu'une règle de la page [from].
bool isOnlyRule(String text, String from) {
  final page = _pagesOf(_rootOf(text))[from];
  final action = page is YamlMap ? page['action'] : null;
  final saisies = action is YamlMap ? action['saisies'] : null;
  return saisies is YamlList && saisies.length == 1;
}

/// Le nom d'une page tel qu'on l'écrit dans une valeur : tel quel, sauf s'il se
/// lirait comme autre chose qu'une chaîne (`123`, `true`...).
String _pageScalar(String name) =>
    RegExp(r'^[A-Za-z_][A-Za-z0-9_-]*$').hasMatch(name) &&
        !const {
          'true',
          'false',
          'null',
          'yes',
          'no',
          'on',
          'off',
          'y',
          'n',
        }.contains(name.toLowerCase())
    ? name
    : yamlString(name);

/// Une règle, écrite comme dans les services : `{choix: "1", touche: envoi,
/// suivant: page}`.
String _ruleText(String? choice, String key, String to) =>
    '{${choice == null ? '' : 'choix: ${yamlString(choice)}, '}touche: $key, '
    'suivant: ${_pageScalar(to)}}';

/// Ajoute à la page [from] une règle : la touche [key] (et la saisie [choice]
/// si elle est donnée) mène à la page [to]. Une page sans saisie en reçoit une.
String addRule(
  String text,
  String from,
  String to, {
  String key = 'envoi',
  String? choice,
}) {
  final pages = _pagesOf(_rootOf(text));
  final page = pages[from];
  if (page is! YamlMap) throw EditException('Il n\'y a pas de page « $from ».');
  if (!pages.containsKey(to)) {
    throw EditException('Il n\'y a pas de page « $to ».');
  }
  if (!ruleKeys.contains(key)) throw EditException('Touche inconnue : $key.');
  if (page.containsKey('exec')) {
    throw EditException(
      'La page « $from » lance un programme : sa suite est le « suivant » de '
      'son exec (à changer dans le texte).',
    );
  }
  _requireValid(text);

  final c = (choice == null || choice.isEmpty) ? null : choice;
  final rule = loadYamlNode(_ruleText(c, key, to));
  final e = YamlEditor(text);
  final base = ['pages', from];
  if (!page.containsKey('action')) {
    // Une zone d'une ligne en bas de l'écran, juste assez large pour le choix,
    // écrite à la suite de la page : yaml_edit rangerait les clés par ordre
    // alphabétique.
    final pad = ' ' * page.span.start.column;
    final lines = text.split('\n');
    final last = _lastLine(page, lines, page.span.start.line);
    lines.insertAll(last + 1, [
      '${pad}entree:',
      '$pad  zonesaisie: {ligne: 24, col: 1, longueur: ${c?.length ?? 1}, '
          'curseur: ${c != null ? 'visible' : 'invisible'}}',
      '$pad  validation: [$key]',
      '${pad}action:',
      '$pad  saisies:',
      '$pad    - ${_ruleText(c, key, to)}',
    ]);
    return _checked(lines.join('\n'));
  }

  final validation = (page['entree'] as YamlMap?)?['validation'];
  if (validation is YamlList && !validation.value.contains(key)) {
    e.appendToList([...base, 'entree', 'validation'], key);
  }
  final action = page['action'] as YamlMap;
  if (action['saisies'] is YamlList) {
    e.appendToList([...base, 'action', 'saisies'], rule);
  } else {
    e.update([...base, 'action', 'saisies'], [rule]);
  }
  return _checked(e.toString());
}

/// Supprime la règle [index] de la page [from] (avec les commentaires qui la
/// précèdent). [to] est la page qu'elle devait désigner : une garde contre un
/// texte qui aurait changé entre-temps.
String removeRule(String text, String from, int index, String to) {
  final pages = _pagesOf(_rootOf(text));
  final page = pages[from];
  final action = page is YamlMap ? page['action'] : null;
  final saisies = action is YamlMap ? action['saisies'] : null;
  if (saisies is! YamlList || index < 0 || index >= saisies.length) {
    throw EditException('La règle ${index + 1} de « $from » n\'existe plus.');
  }
  final rule = saisies[index];
  if (rule is! YamlMap || !_names(rule['suivant'], to)) {
    throw EditException('La règle ${index + 1} de « $from » a changé.');
  }
  _requireValid(text);
  return _checked(
    _removeItem(text, ['pages', from, 'action', 'saisies', index]),
  );
}

// --- Valeurs d'une page (formulaires) ---

/// La valeur en [path] dans [text], ou `null` si elle n'existe pas. Tables et
/// listes sont rendues telles que lues (`YamlMap`, `YamlList`).
Object? valueAt(String text, List<Object> path) {
  Object? node = loadYaml(text);
  for (final key in path) {
    if (node is YamlMap) {
      node = node[key];
    } else if (node is YamlList &&
        key is int &&
        key >= 0 &&
        key < node.length) {
      node = node[key];
    } else {
      return null;
    }
  }
  return node;
}

/// Écrit [value] en [path] (une clé d'une table), en créant les tables qui
/// manquent sur le chemin. Le reste du texte ne change pas.
String setValue(String text, List<Object> path, Object value) {
  _requireValid(text);
  final e = YamlEditor(text);
  // La première table du chemin qui n'existe pas : on y écrit tout le reste.
  for (var i = 1; i < path.length; i++) {
    if (valueAt(text, path.sublist(0, i + 1)) != null) continue;
    Object nested = value;
    for (var j = path.length - 1; j > i; j--) {
      nested = {path[j]: nested};
    }
    e.update(path.sublist(0, i + 1), nested);
    return _checked(e.toString());
  }
  e.update(path, value);
  return _checked(e.toString());
}

/// Retire la clé en [path], et les tables que ça laisse vides (jusqu'à la page
/// exclue). Sans effet si la clé n'existe pas.
String removeValue(String text, List<Object> path) {
  _requireValid(text);
  if (valueAt(text, path) == null) return text;
  var target = path;
  while (target.length > 3) {
    final parent = valueAt(text, target.sublist(0, target.length - 1));
    if (parent is YamlMap && parent.length == 1) {
      target = target.sublist(0, target.length - 1);
    } else {
      break;
    }
  }
  final parent = valueAt(text, target.sublist(0, target.length - 1));
  if (parent is YamlMap && parent.style == CollectionStyle.FLOW) {
    final out = (YamlEditor(text)..remove(target)).toString();
    return _checked(_tidyFlow(out, target.sublist(0, target.length - 1)));
  }
  return _checked(_cut(text, target, comments: false));
}

/// Retire l'espace que `yaml_edit` laisse après `{` quand on retire la
/// première clé d'une table en ligne.
String _tidyFlow(String text, List<Object> mapPath) {
  final node = YamlEditor(text).parseAt(mapPath);
  final span = node.span;
  if (span.text.startsWith('{ ')) {
    return text.replaceRange(span.start.offset + 1, span.start.offset + 2, '');
  }
  return text;
}

/// Déplace la règle [index] de la page [page] de [delta] places (-1 : plus
/// tôt, +1 : plus tard) : l'ordre des règles compte (la première qui convient
/// l'emporte).
String moveRule(String text, String page, int index, int delta) {
  final saisies = valueAt(text, ['pages', page, 'action', 'saisies']);
  final to = index + delta;
  if (saisies is! YamlList ||
      index < 0 ||
      index >= saisies.length ||
      to < 0 ||
      to >= saisies.length) {
    throw EditException('Cette règle ne peut pas bouger.');
  }
  _requireValid(text);
  // On échange les lignes des deux règles : seul le texte change de place.
  final e = YamlEditor(text);
  final a = e.parseAt(['pages', page, 'action', 'saisies', index]);
  final b = e.parseAt(['pages', page, 'action', 'saisies', to]);
  final first = a.span.start.offset < b.span.start.offset ? a : b;
  final second = identical(first, a) ? b : a;
  final firstText = first.span.text;
  final secondText = second.span.text;
  if (firstText.contains('\n') || secondText.contains('\n')) {
    throw EditException(
      'Cette règle s\'écrit sur plusieurs lignes : déplacez-la dans le texte.',
    );
  }
  final out = text.replaceRange(
    second.span.start.offset,
    second.span.end.offset,
    firstText,
  );
  return _checked(
    out.replaceRange(
      first.span.start.offset,
      first.span.end.offset,
      secondText,
    ),
  );
}

/// Qui peut ouvrir une page.
enum AccessMode {
  /// La page n'écrit pas d'`acces` : elle suit le défaut du service.
  inherit,

  /// `acces: {connecte: false}` : ouverte à tous, même si le défaut ferme.
  open,

  /// `acces: {connecte: true, ...}` : réservée aux utilisateurs connectés.
  members,
}

/// Réécrit l'`acces` de la page [page] d'après [mode] et, pour [AccessMode.members],
/// la page de renvoi [otherwise], le [message] et [provisional] (ouvert aux mots de
/// passe provisoires). Les autres clés de la page ne changent pas.
String setAccess(
  String text,
  String page, {
  required AccessMode mode,
  String? otherwise,
  String? message,
  bool provisional = false,
}) {
  final path = ['pages', page, 'acces'];
  if (mode == AccessMode.inherit) return removeValue(text, path);
  final value = {
    'connecte': mode == AccessMode.members,
    if (mode == AccessMode.members && otherwise != null) 'sinon': otherwise,
    if (mode == AccessMode.members && message != null && message.isNotEmpty)
      'message': message,
    if (mode == AccessMode.members && provisional) 'mdp_provisoire': true,
  };
  return setValue(
    text,
    path,
    wrapAsYamlNode(value, collectionStyle: CollectionStyle.FLOW),
  );
}

/// Le mode d'accès écrit dans la page [page], et ses réglages.
({AccessMode mode, String? otherwise, String? message, bool provisional})
accessOf(String text, String page) {
  final node = valueAt(text, ['pages', page, 'acces']);
  if (node == null) {
    return (
      mode: AccessMode.inherit,
      otherwise: null,
      message: null,
      provisional: false,
    );
  }
  if (node is YamlMap) {
    final members = node['connecte'] != false;
    return (
      mode: members ? AccessMode.members : AccessMode.open,
      otherwise: node['sinon'] == null ? null : '${node['sinon']}',
      message: node['message'] == null ? null : '${node['message']}',
      provisional: node['mdp_provisoire'] == true,
    );
  }
  // La forme courte `acces: connecte`.
  return (
    mode: AccessMode.members,
    otherwise: null,
    message: null,
    provisional: false,
  );
}

// --- L'écran d'une page ---

/// Une instruction de l'`ecran` d'une page, telle qu'elle est écrite dans le
/// texte : `efface`, `position: {ligne: 3, col: 5}`...
class ScreenItem {
  const ScreenItem(this.index, this.text, this.name, this.multiline);

  final int index;

  /// Son texte, sans le tiret de liste.
  final String text;

  /// Le nom de l'instruction (`position`, `ecrit`...).
  final String name;

  /// Vrai si elle s'écrit sur plusieurs lignes (`si`, `fois`...).
  final bool multiline;
}

/// Les instructions de l'`ecran` de la page [page] ; vide si elle n'en a pas ou
/// si le texte n'est pas lisible.
List<ScreenItem> screenItems(String text, String page) {
  try {
    final list = YamlEditor(text).parseAt(['pages', page, 'ecran']);
    if (list is! YamlList) return const [];
    final lines = text.split('\n');
    return [
      for (var i = 0; i < list.nodes.length; i++)
        _screenItem(i, list.nodes[i], lines),
    ];
  } on Object {
    return const [];
  }
}

ScreenItem _screenItem(int index, YamlNode node, List<String> lines) {
  final start = node.span.start.line;
  final end = _contentEnd(node, lines);
  final multiline = end > start;
  final text = multiline
      ? [
          lines[start].substring(node.span.start.column),
          ...lines.sublist(start + 1, end + 1),
        ].join('\n')
      : _oneLine(node);
  final value = node is YamlMap
      ? (node.keys.isEmpty ? '' : '${node.keys.first}')
      : '${node.value}';
  return ScreenItem(index, text, value, multiline);
}

/// La dernière ligne d'écriture de [node] : l'étendue d'une table peut englober
/// les lignes vides ou les commentaires qui la suivent.
int _contentEnd(YamlNode node, List<String> lines) {
  final start = node.span.start.line;
  var end = _lastLine(node, lines, start);
  while (end > start &&
      (lines[end].trim().isEmpty || lines[end].trimLeft().startsWith('#'))) {
    end--;
  }
  return end;
}

/// Le texte d'une instruction écrite sur une seule ligne : l'étendue d'une
/// table ne s'arrête pas toujours à sa dernière ligne, on la coupe.
String _oneLine(YamlNode node) => node.span.text.split('\n').first.trimRight();

/// Vérifie que [item] est une instruction écrite sur une ligne : un mot, ou
/// `mot: valeur`.
void _checkInstruction(String item) {
  final text = item.trim();
  if (text.isEmpty) {
    throw EditException('Une instruction ne peut pas être vide.');
  }
  if (text.contains('\n')) {
    throw EditException('Une instruction tient sur une ligne ici.');
  }
  Object? value;
  try {
    value = loadYaml(text);
  } on YamlException catch (e) {
    throw EditException('Instruction illisible : ${e.message}');
  }
  if (value is YamlMap) {
    if (value.length != 1) {
      throw EditException('Une instruction n\'a qu\'une clé : `nom: valeur`.');
    }
  } else if (value is! String) {
    throw EditException('Une instruction est un mot ou `nom: valeur`.');
  }
}

/// Le texte de la liste `ecran` de [page], ses éléments et les lignes du texte.
({YamlList list, List<String> lines}) _screenOf(String text, String page) {
  final list = YamlEditor(text).parseAt(['pages', page, 'ecran']);
  if (list is! YamlList) throw EditException('Cet écran n\'a pas de liste.');
  return (list: list, lines: text.split('\n'));
}

/// Le texte qui précède l'élément [node] sur sa ligne (`      - `), ou `null` si
/// la liste n'est pas écrite un élément par ligne.
String? _dash(YamlNode node, List<String> lines) {
  final before = lines[node.span.start.line].substring(
    0,
    node.span.start.column,
  );
  return RegExp(r'^\s*-\s+$').hasMatch(before) ? before : null;
}

/// La clé `ecran` d'une page.
YamlNode _screenKey(YamlMap page) =>
    page.nodes.keys.cast<YamlNode>().firstWhere((k) => k.value == 'ecran');

/// Ajoute l'instruction [item] à l'écran de [page], en position [index] (la
/// fin si [index] vaut le nombre d'instructions).
String insertScreenItem(String text, String page, int index, String item) {
  _requireValid(text);
  _checkInstruction(item);
  final line = item.trim();
  final node = YamlEditor(text).parseAt(['pages', page]);
  if (node is! YamlMap) throw EditException('Il n\'y a pas de page « $page ».');
  final lines = text.split('\n');
  final ecran = node.nodes['ecran'];
  if (ecran is! YamlList) throw EditException('L\'écran n\'est pas une liste.');
  if (index < 0 || index > ecran.length) {
    throw EditException('Cette place n\'existe pas.');
  }
  if (ecran.isEmpty) {
    // `ecran: []` : on le remplace par une liste, une instruction par ligne.
    final key = _screenKey(node);
    final pad = ' ' * key.span.start.column;
    lines.replaceRange(key.span.start.line, key.span.start.line + 1, [
      '${pad}ecran:',
      '$pad  - $line',
    ]);
    return _checked(lines.join('\n'));
  }
  final dash = _dash(ecran.nodes[0], lines);
  if (dash == null) {
    throw EditException(
      'Cet écran est écrit en ligne : ajoutez l\'instruction dans le texte.',
    );
  }
  final at = index < ecran.length
      ? ecran.nodes[index].span.start.line
      : _lastLine(ecran.nodes.last, lines, ecran.nodes.last.span.start.line) +
            1;
  lines.insert(at, '$dash$line');
  return _checked(lines.join('\n'));
}

/// Retire l'instruction [index] de l'écran de [page]. La dernière retirée,
/// l'écran reste, vide (`ecran: []`) : le service exige la clé.
String removeScreenItem(String text, String page, int index) {
  _requireValid(text);
  final s = _screenOf(text, page);
  if (index < 0 || index >= s.list.length) {
    throw EditException('Cette instruction n\'existe pas.');
  }
  final base = ['pages', page, 'ecran'];
  if (s.list.length == 1) {
    final node = YamlEditor(text).parseAt(['pages', page]) as YamlMap;
    final key = _screenKey(node);
    final first = key.span.start.line;
    final last = _lastLine(s.list, s.lines, first);
    s.lines.replaceRange(first, last + 1, [
      '${' ' * key.span.start.column}ecran: []',
    ]);
    return _checked(s.lines.join('\n'));
  }
  return _checked(_cut(text, [...base, index], comments: index > 0));
}

/// Remplace l'instruction [index] par [item] (une ligne).
String replaceScreenItem(String text, String page, int index, String item) {
  _requireValid(text);
  _checkInstruction(item);
  final s = _screenOf(text, page);
  if (index < 0 || index >= s.list.length) {
    throw EditException('Cette instruction n\'existe pas.');
  }
  final node = s.list.nodes[index];
  final start = node.span.start.line;
  if (_contentEnd(node, s.lines) > start) {
    throw EditException(
      'Cette instruction s\'écrit sur plusieurs lignes : modifiez-la dans le '
      'texte.',
    );
  }
  return _checked(
    text.replaceRange(
      node.span.start.offset,
      node.span.start.offset + _oneLine(node).length,
      item.trim(),
    ),
  );
}

/// Les lignes (à partir de 0) de l'instruction [i] : de sa ligne de tiret à sa
/// dernière ligne.
(int, int) _screenSpan(YamlList list, int i, List<String> lines) {
  final node = list.nodes[i];
  return (node.span.start.line, _contentEnd(node, lines));
}

/// Copie l'instruction [index] juste après elle.
String duplicateScreenItem(String text, String page, int index) {
  _requireValid(text);
  final s = _screenOf(text, page);
  if (index < 0 || index >= s.list.length) {
    throw EditException('Cette instruction n\'existe pas.');
  }
  if (_dash(s.list.nodes[index], s.lines) == null) {
    throw EditException('Cet écran est écrit en ligne : copiez dans le texte.');
  }
  final (start, end) = _screenSpan(s.list, index, s.lines);
  s.lines.insertAll(end + 1, s.lines.sublist(start, end + 1));
  return _checked(s.lines.join('\n'));
}

/// Déplace l'instruction [index] de [delta] places. L'ordre compte : une
/// `position` ou une couleur n'agit que sur ce qui suit. Les commentaires
/// au-dessus d'une instruction la suivent.
String moveScreenItem(String text, String page, int index, int delta) {
  _requireValid(text);
  final s = _screenOf(text, page);
  final to = index + delta;
  if (index < 0 ||
      index >= s.list.length ||
      to < 0 ||
      to >= s.list.length ||
      delta == 0) {
    throw EditException('Cette instruction ne peut pas bouger.');
  }
  for (final i in [index, to]) {
    if (_dash(s.list.nodes[i], s.lines) == null) {
      throw EditException(
        'Cet écran est écrit en ligne : déplacez dans le texte.',
      );
    }
  }
  final a = index < to ? index : to;
  final (aStart, aEnd) = _screenSpan(s.list, a, s.lines);
  final (bStart, bEnd) = _screenSpan(s.list, a + 1, s.lines);
  final first = s.lines.sublist(aStart, aEnd + 1);
  final gap = s.lines.sublist(aEnd + 1, bStart);
  final second = s.lines.sublist(bStart, bEnd + 1);
  s.lines.replaceRange(aStart, bEnd + 1, [...gap, ...second, ...first]);
  return _checked(s.lines.join('\n'));
}

/// Écrit le paramètre [key] de l'instruction [index] de l'écran de [page], par
/// exemple `ligne` de `position: {ligne: 3, col: 5}` ([name] est `position`).
/// [value] à `null` retire le paramètre. Seules les tables écrites en ligne
/// (`{...}`) se modifient ainsi ; le reste du texte ne change pas.
String setScreenParam(
  String text,
  String page,
  int index,
  String name,
  String key,
  Object? value,
) {
  _requireValid(text);
  final path = ['pages', page, 'ecran', index, name];
  final map = valueAt(text, path);
  if (map is! YamlMap || map.style != CollectionStyle.FLOW) {
    throw EditException(
      'Cette instruction n\'est pas écrite en ligne : modifiez-la dans le texte.',
    );
  }
  final e = YamlEditor(text);
  if (value == null) {
    if (!map.containsKey(key)) return text;
    e.remove([...path, key]);
    return _checked(_tidyFlow(e.toString(), path));
  }
  if (!map.containsKey(key)) {
    // À la fin de la table : yaml_edit rangerait la clé par ordre alphabétique.
    final end = map.span.end.offset - 1;
    final out = text.replaceRange(end, end, ', $key: ${_flowScalar(value)}');
    return _checked(out);
  }
  e.update([...path, key], value);
  return _checked(e.toString());
}

/// Une valeur écrite dans une table en ligne : un nombre tel quel, un mot sans
/// guillemets s'il se lit comme une chaîne, sinon entre guillemets.
String _flowScalar(Object value) {
  if (value is num) return '$value';
  final text = '$value';
  return RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(text) &&
          !const {
            'true',
            'false',
            'null',
            'yes',
            'no',
            'on',
            'off',
            'y',
            'n',
          }.contains(text)
      ? text
      : yamlString(text);
}

/// Une valeur lue par `loadYaml`, en listes et tables ordinaires.
Object? _plain(Object? v) {
  if (v is YamlMap) {
    return {for (final e in v.entries) '${e.key}': _plain(e.value)};
  }
  if (v is YamlList) return [for (final e in v) _plain(e)];
  return v;
}

/// Le texte du service où l'écran de [page] ne garde que les instructions de
/// [from] à [to] (comprises), pour montrer un morceau de l'écran. Ce texte ne
/// sert qu'à l'aperçu : il n'est jamais écrit dans le service.
String screenSlice(String text, String page, int from, int to) {
  final list = valueAt(text, ['pages', page, 'ecran']);
  if (list is! YamlList) throw EditException('Cet écran n\'a pas de liste.');
  if (from < 0 || to >= list.length || from > to) {
    throw EditException('Ces instructions n\'existent pas.');
  }
  final e = YamlEditor(text)
    ..update(
      ['pages', page, 'ecran'],
      [for (var i = from; i <= to; i++) _plain(list[i])],
    );
  return e.toString();
}

/// Le nom de la page temporaire qui sert à montrer un minget.
const mingetPage = '__minget__';

/// Le texte du service avec, en plus, une page [mingetPage] qui efface l'écran
/// puis appelle la macro [name] avec [args] : de quoi la voir sans l'avoir mise
/// dans une vraie page. Ce texte ne sert qu'à l'aperçu ; il est écrit en JSON
/// (qui est du YAML) pour ne dépendre d'aucune mise en forme.
String mingetPreviewText(String text, String name, List<Object?> args) {
  final root = _plain(loadYaml(text));
  if (root is! Map || root['pages'] is! Map) {
    throw EditException('Le texte n\'est pas un service.');
  }
  (root['pages'] as Map)[mingetPage] = {
    'ecran': [
      'efface',
      {
        'macro': [name, ...args],
      },
    ],
  };
  return jsonEncode(root);
}
