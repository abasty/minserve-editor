import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minserve_core/minserve_core.dart'
    show MacroDefinition, MacroType, yamlString;
import 'package:yaml/yaml.dart';

import '../assets.dart';
import 'asset_dialog.dart';
import 'color_pick.dart';
import 'extract_dialog.dart';
import 'macro_call.dart';
import 'minget_panel.dart' show mingetParamTypes;
import 'page_forms.dart';
import 'service_edit.dart';

/// Les instructions qu'on peut ajouter à un écran, avec de quoi les écrire :
/// le libellé du menu, et l'instruction avec des valeurs par défaut.
const screenPalette = <(String, String)>[
  ('efface — efface l\'écran', 'efface'),
  ('position — place le curseur', 'position: {ligne: 1, col: 1}'),
  ('ecrit — écrit du texte', 'ecrit: "Texte"'),
  ('couleur — couleur du texte ou du fond', 'couleur: {texte: blanc}'),
  (
    'rectangle — rectangle plein',
    'rectangle: {ligne: 1, col: 1, largeur: 10, hauteur: 1, couleur: blanc}',
  ),
  ('repete — répète un caractère', 'repete: {caractere: "-", nombre: 10}'),
  (
    'paragraphe — texte long plié aux mots',
    'paragraphe: {valeur: "Texte", ligne: 1, hauteur: 3, col: 1, largeur: 40}',
  ),
  ('deplace — déplace le curseur', 'deplace: {col: 1}'),
  ('doublehauteur', 'doublehauteur'),
  ('doublelargeur', 'doublelargeur'),
  ('doubletaille', 'doubletaille'),
  ('taillenormale', 'taillenormale'),
  ('souligne', 'souligne: actif'),
  ('clignote', 'clignote: actif'),
  ('inversion', 'inversion: actif'),
  ('curseur', 'curseur: invisible'),
  ('graphique — mode semi-graphique', 'graphique'),
  ('texte — mode texte', 'texte'),
  ('date', 'date'),
  ('heure', 'heure'),
  ('affiche — fichier Videotex', 'affiche: fichier.vdt'),
  ('effacefindeligne', 'effacefindeligne'),
];

/// L'écran d'une page : la liste de ses instructions, dans l'ordre où le
/// terminal les reçoit. On peut en ajouter, les changer de place, les copier, les
/// supprimer, ou écrire une instruction à la main. Une instruction sur plusieurs
/// lignes (`si`, `fois`) se modifie dans le texte.
class ScreenForm extends StatefulWidget {
  const ScreenForm({
    super.key,
    required this.page,
    required this.text,
    required this.apply,
    this.onGoToPage,
    this.selected,
    this.onSelect,
    this.macros = const {},
  });

  final String page;
  final String text;
  final ApplyEdit apply;
  final void Function(String page, {String? section, int? rule})? onGoToPage;

  /// L'instruction choisie (dont l'aperçu peut montrer le morceau), et ce qui
  /// se passe quand on en choisit une autre.
  final int? selected;
  final ValueChanged<int>? onSelect;

  /// Les macros du service : on peut les insérer, et leurs appels se montrent
  /// avec un champ par paramètre.
  final Map<String, MacroDefinition> macros;

  @override
  State<ScreenForm> createState() => _ScreenFormState();
}

class _ScreenFormState extends State<ScreenForm> {
  String get page => widget.page;
  String get text => widget.text;
  ApplyEdit get apply => widget.apply;
  void Function(String page, {String? section, int? rule})? get onGoToPage =>
      widget.onGoToPage;

  /// Les instructions qu'on montre en texte plutôt qu'en champs.
  final _asText = <int>{};

  /// Les instructions cochées, pour les extraire en minget.
  final _checked = <int>{};
  int _count = -1;

  /// Les cochées forment-elles une suite sans trou ?
  bool get _contiguous =>
      _checked.isNotEmpty &&
      _checked.reduce((a, b) => a > b ? a : b) -
              _checked.reduce((a, b) => a < b ? a : b) +
              1 ==
          _checked.length;

  Future<void> _extract(BuildContext context) async {
    final from = _checked.reduce((a, b) => a < b ? a : b);
    final to = _checked.reduce((a, b) => a > b ? a : b);
    final request = await askExtraction(
      context,
      values: extractableValues(text, page, from, to),
      existing: widget.macros.keys,
      count: to - from + 1,
    );
    if (request == null) return;
    final done = apply(
      (t) => extractMinget(
        t,
        page,
        from,
        to,
        name: request.name,
        description: request.description,
        params: request.params,
      ),
    );
    if (done) setState(_checked.clear);
  }

  Widget _insert(BuildContext context, int at, {required Widget child}) {
    return InkWell(
      key: Key('screen-add-$at'),
      borderRadius: BorderRadius.circular(6),
      onTap: () async {
        final picked = await askInstruction(context, macros: widget.macros);
        if (picked == null || !context.mounted) return;
        var item = picked.text;
        final macro = picked.macro;
        if (macro != null) {
          // Un minget sans paramètre s'insère tout de suite ; sinon on demande
          // ses arguments.
          final args = macro.arity == 0
              ? <Object?>[]
              : await askMacroCall(context, macro);
          if (args == null) return;
          item = macroCallText(macro, args);
        }
        if (item != null) apply((t) => insertScreenItem(t, page, at, item!));
      },
      child: Tooltip(message: 'Insérer une instruction', child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = screenItems(text, page);
    // Le nombre d'instructions a changé : les numéros cochés ne valent plus.
    if (items.length != _count) {
      _count = items.length;
      _checked.clear();
    }
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('Cet écran est vide.'),
          ),
        for (final item in items)
          Listener(
            key: Key('screen-row-${item.index}'),
            // Toucher une ligne la choisit, sans gêner ses champs.
            onPointerDown: (_) => widget.onSelect?.call(item.index),
            child: Container(
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: item.index == widget.selected
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.6)
                    : null,
              ),
              child: Row(
                children: [
                  // Le numéro sert aussi de case à cocher (pour extraire en minget) :
                  // coché, il devient une pastille pleine.
                  Tooltip(
                    message: 'Cocher pour extraire en minget',
                    child: InkWell(
                      key: Key('screen-check-${item.index}'),
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() {
                        if (!_checked.remove(item.index)) {
                          _checked.add(item.index);
                        }
                      }),
                      child: Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _checked.contains(item.index)
                              ? theme.colorScheme.primary
                              : null,
                        ),
                        child: Text(
                          '${item.index + 1}',
                          style: _checked.contains(item.index)
                              ? TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onPrimary,
                                )
                              : theme.textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: item.multiline
                        ? _block(context, item)
                        : (_asText.contains(item.index)
                                  ? null
                                  : _fields(item)) ??
                              CommitField(
                                key: Key('screen-$page-${item.index}'),
                                width: double.infinity,
                                value: item.text,
                                onCommit: (v) => apply(
                                  (t) =>
                                      replaceScreenItem(t, page, item.index, v),
                                ),
                              ),
                  ),
                  if (!item.multiline && _fields(item) != null)
                    IconButton(
                      key: Key('screen-mode-${item.index}'),
                      tooltip: _asText.contains(item.index)
                          ? 'Montrer les champs'
                          : 'Écrire en texte',
                      visualDensity: VisualDensity.compact,
                      isSelected: _asText.contains(item.index),
                      icon: const Icon(Icons.code, size: 18),
                      onPressed: () => setState(() {
                        if (!_asText.remove(item.index)) {
                          _asText.add(item.index);
                        }
                      }),
                    ),
                  IconButton(
                    key: Key('screen-up-${item.index}'),
                    tooltip: 'Monter',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.arrow_upward, size: 18),
                    onPressed: item.index == 0
                        ? null
                        : () => apply(
                            (t) => moveScreenItem(t, page, item.index, -1),
                          ),
                  ),
                  IconButton(
                    key: Key('screen-down-${item.index}'),
                    tooltip: 'Descendre',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.arrow_downward, size: 18),
                    onPressed: item.index == items.length - 1
                        ? null
                        : () => apply(
                            (t) => moveScreenItem(t, page, item.index, 1),
                          ),
                  ),
                  IconButton(
                    key: Key('screen-copy-${item.index}'),
                    tooltip: 'Dupliquer',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.content_copy, size: 18),
                    onPressed: () =>
                        apply((t) => duplicateScreenItem(t, page, item.index)),
                  ),
                  _insert(
                    context,
                    item.index + 1,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.add, size: 18),
                    ),
                  ),
                  IconButton(
                    key: Key('screen-delete-${item.index}'),
                    tooltip: 'Supprimer',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () =>
                        apply((t) => removeScreenItem(t, page, item.index)),
                  ),
                ],
              ),
            ),
          ),
        if (_checked.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _contiguous
                ? TextButton.icon(
                    key: const Key('screen-extract'),
                    onPressed: () => _extract(context),
                    icon: const Icon(Icons.widgets_outlined, size: 18),
                    label: Text(
                      'Extraire en minget (${_checked.length} '
                      'instruction${_checked.length > 1 ? 's' : ''})',
                    ),
                  )
                : Text(
                    'Pour extraire en minget, cochez des instructions qui se '
                    'suivent.',
                    key: const Key('screen-extract-hint'),
                    style: theme.textTheme.bodySmall,
                  ),
          ),
        _insert(
          context,
          items.length,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add, size: 18),
                const SizedBox(width: 6),
                Text(
                  'Ajouter une instruction',
                  style: TextStyle(color: theme.colorScheme.primary),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Une instruction sur plusieurs lignes : montrée, pas modifiable ici.
  Widget _block(BuildContext context, ScreenItem item) {
    final lines = item.text.split('\n');
    return InputDecorator(
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${item.name}  (${lines.length} lignes)',
              key: Key('screen-block-${item.index}'),
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onGoToPage != null)
            TextButton(
              onPressed: () =>
                  onGoToPage!(page, section: 'ecran', rule: item.index),
              child: const Text('Dans le texte'),
            ),
        ],
      ),
    );
  }
}

// --- Les champs de chaque instruction ---

enum _Kind { integer, text, color }

class _Param {
  const _Param(this.key, this.kind, {this.required = false, this.width = 64});

  final String key;
  final _Kind kind;
  final bool required;
  final double width;
}

/// Les paramètres des instructions qui s'écrivent `nom: {clé: valeur, ...}`.
const _mapParams = <String, List<_Param>>{
  'position': [
    _Param('ligne', _Kind.integer, required: true),
    _Param('col', _Kind.integer, required: true),
  ],
  'deplace': [_Param('ligne', _Kind.integer), _Param('col', _Kind.integer)],
  'couleur': [_Param('texte', _Kind.color), _Param('fond', _Kind.color)],
  'repete': [
    _Param('caractere', _Kind.text, required: true, width: 80),
    _Param('nombre', _Kind.integer, required: true),
  ],
  'rectangle': [
    _Param('ligne', _Kind.integer, required: true),
    _Param('col', _Kind.integer, required: true),
    _Param('largeur', _Kind.integer, required: true),
    _Param('hauteur', _Kind.integer, required: true),
    _Param('couleur', _Kind.color, required: true),
  ],
  'paragraphe': [
    _Param('valeur', _Kind.text, required: true, width: 200),
    _Param('ligne', _Kind.integer, required: true),
    _Param('hauteur', _Kind.integer, required: true),
    _Param('col', _Kind.integer),
    _Param('largeur', _Kind.integer),
    _Param('couleur', _Kind.color),
  ],
};

/// Les instructions sans paramètre.
const _bare = {
  'efface',
  'effacefindeligne',
  'doublehauteur',
  'doublelargeur',
  'doubletaille',
  'taillenormale',
  'graphique',
  'texte',
  'date',
  'heure',
  'init',
};

/// Les instructions qui prennent un mot parmi quelques-uns.
const _choices = <String, List<String>>{
  'souligne': ['actif', 'inactif'],
  'clignote': ['actif', 'inactif'],
  'inversion': ['actif', 'inactif'],
  'curseur': ['visible', 'invisible'],
};

/// Les instructions qui prennent un texte.
const _texts = {'ecrit': 'Texte', 'affiche': 'Fichier'};

final _number = RegExp(r'^[+-]?\d+$');

extension on _ScreenFormState {
  /// Les champs de l'instruction [item], ou `null` si on ne sait pas les
  /// montrer (macro, octets, forme inhabituelle) : on écrit alors le texte.
  Widget? _fields(ScreenItem item) {
    final name = item.name;
    Object? value;
    try {
      value = loadYaml(item.text);
    } on YamlException {
      return null;
    }
    final label = SizedBox(
      width: 110,
      child: Text(
        name,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    );
    Widget row(List<Widget> children) => Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [label, ...children],
    );
    if (name == 'macro') {
      final fields = _macroFields(item);
      return fields == null ? null : row(fields);
    }
    if (_bare.contains(name) && value is String) return row(const []);
    final choices = _choices[name];
    if (choices != null && value is YamlMap && value.length == 1) {
      return row([
        Pick(
          key: Key('screen-$page-${item.index}-$name'),
          width: 120,
          value: '${value[name]}',
          items: {for (final c in choices) c: c},
          onChanged: (v) =>
              apply((t) => replaceScreenItem(t, page, item.index, '$name: $v')),
        ),
      ]);
    }
    if (name == 'affiche' && value is YamlMap && value.length == 1) {
      return row(_afficheFields(item, '${value[name] ?? ''}'));
    }
    final textLabel = _texts[name];
    if (textLabel != null && value is YamlMap && value.length == 1) {
      return row([
        SizedBox(
          width: 320,
          child: CommitField(
            key: Key('screen-$page-${item.index}-$name'),
            width: double.infinity,
            label: textLabel,
            value: '${value[name] ?? ''}',
            onCommit: (v) => apply(
              (t) => replaceScreenItem(
                t,
                page,
                item.index,
                '$name: ${yamlString(v)}',
              ),
            ),
          ),
        ),
      ]);
    }
    final params = _mapParams[name];
    if (params != null &&
        value is YamlMap &&
        value.length == 1 &&
        value[name] is YamlMap &&
        (value[name] as YamlMap).style == CollectionStyle.FLOW) {
      final map = value[name] as YamlMap;
      return row([for (final p in params) _param(item, name, map, p)]);
    }
    return null;
  }

  /// Le champ du fichier d'une instruction `affiche`, avec — quand on a le
  /// dossier assets du service — un bouton pour le choisir dans la liste et
  /// l'état du fichier (sa taille, ou pourquoi on ne peut pas le lire).
  List<Widget> _afficheFields(ScreenItem item, String path) {
    final source = AssetsScope.of(context);
    bool set(String v) => apply(
      (t) =>
          replaceScreenItem(t, page, item.index, 'affiche: ${yamlString(v)}'),
    );
    String? problem;
    int? size;
    if (source != null && path.isNotEmpty) {
      try {
        size = source.read(path).length;
      } on AssetException catch (e) {
        problem = e.message;
      }
    }
    return [
      SizedBox(
        width: 320,
        child: CommitField(
          key: Key('screen-$page-${item.index}-affiche'),
          width: double.infinity,
          label: 'Fichier',
          value: path,
          onCommit: set,
        ),
      ),
      if (source != null)
        IconButton(
          key: Key('screen-$page-${item.index}-affiche-pick'),
          tooltip: 'Choisir dans les assets',
          icon: const Icon(Icons.folder_open),
          onPressed: () async {
            final chosen = await askAsset(
              context,
              source,
              current: path,
              setup: AssetsScope.setupOf(context),
            );
            if (chosen != null) set(chosen);
          },
        ),
      if (size != null)
        Text(
          '$size octets',
          key: Key('screen-$page-${item.index}-affiche-status'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      if (problem != null)
        Text(
          problem,
          key: Key('screen-$page-${item.index}-affiche-status'),
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: 12,
          ),
        ),
    ];
  }

  /// Les champs d'un appel de macro : son nom puis un champ par paramètre, avec
  /// la valeur par défaut pour ceux que l'appel omet. `null` si la macro est
  /// inconnue ou l'appel écrit autrement.
  List<Widget>? _macroFields(ScreenItem item) {
    final call = readMacroCall(item.text);
    final macro = call == null ? null : widget.macros[call.name];
    if (call == null || macro == null) return null;
    final args = fullMacroArgs(macro, call.args);
    final types = mingetParamTypes(macro);
    bool write(int i, Object? v) {
      final next = [...args];
      next[i] = v;
      return apply(
        (t) =>
            replaceScreenItem(t, page, item.index, macroCallText(macro, next)),
      );
    }

    return [
      Tooltip(
        message: macro.description ?? 'Minget du service',
        child: Chip(
          key: Key('screen-$page-${item.index}-macro-name'),
          label: Text(macro.name),
          visualDensity: VisualDensity.compact,
          avatar: const Icon(Icons.widgets_outlined, size: 14),
        ),
      ),
      for (var i = 0; i < macro.arity; i++)
        if (types[i] == MacroType.booleen)
          SizedBox(
            width: 150,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(macro.parameters[i].name),
                Switch(
                  key: Key('screen-$page-${item.index}-arg-$i'),
                  value: args[i] == true,
                  onChanged: (v) => write(i, v),
                ),
              ],
            ),
          )
        else
          CommitField(
            key: Key('screen-$page-${item.index}-arg-$i'),
            width: 96,
            label: macro.parameters[i].name,
            value: '${args[i]}',
            onCommit: (v) => write(i, parseMacroArg(types[i], v)),
          ),
    ];
  }

  Widget _param(ScreenItem item, String name, YamlMap map, _Param p) {
    final key = Key('screen-$page-${item.index}-${p.key}');
    final current = map[p.key] == null ? '' : '${map[p.key]}';
    bool write(Object? v) =>
        apply((t) => setScreenParam(t, page, item.index, name, p.key, v));
    if (p.kind == _Kind.color) {
      return ColorPick(
        key: key,
        label: p.key,
        value: current,
        required: p.required,
        onChanged: (v) => write(v.isEmpty ? null : v),
      );
    }
    return CommitField(
      key: key,
      width: p.width,
      label: p.key,
      value: current,
      onCommit: (v) {
        final text = v.trim();
        if (text.isEmpty) return p.required ? false : write(null);
        if (p.kind == _Kind.integer) {
          return write(_number.hasMatch(text) ? int.parse(text) : text);
        }
        return write(v);
      },
    );
  }
}

/// Demande l'instruction à ajouter : on tape les premières lettres de son nom,
/// la liste se réduit, Entrée prend la première, ou on clique. Rend le texte de
/// l'instruction avec ses valeurs par défaut, ou `null` si on annule.
Future<PickedInstruction?> askInstruction(
  BuildContext context, {
  Map<String, MacroDefinition> macros = const {},
}) => showDialog<PickedInstruction>(
  context: context,
  builder: (context) => _InstructionDialog(macros),
);

/// L'instruction choisie : son texte (avec ses valeurs par défaut), ou un
/// minget dont il faut encore demander les arguments.
class PickedInstruction {
  const PickedInstruction.text(String this.text) : macro = null;
  const PickedInstruction.macro(MacroDefinition this.macro) : text = null;

  final String? text;
  final MacroDefinition? macro;
}

/// Les macros de [macros] qui conviennent à [query] : celles dont le nom
/// commence par la saisie d'abord, puis celles dont le nom ou la description la
/// contiennent. Sans saisie, toutes.
List<MacroDefinition> matchingMacros(
  Map<String, MacroDefinition> macros,
  String query,
) {
  final q = query.trim().toLowerCase();
  final all = macros.values.toList();
  if (q.isEmpty) return all;
  return [
    for (final m in all)
      if (m.name.toLowerCase().startsWith(q)) m,
    for (final m in all)
      if (!m.name.toLowerCase().startsWith(q) &&
          ('${m.name} macro minget ${m.description ?? ''}')
              .toLowerCase()
              .contains(q))
        m,
  ];
}

/// Les instructions de [screenPalette] qui conviennent à [query] : celles dont le
/// nom commence par la saisie d'abord, puis celles dont le nom ou la description
/// la contiennent. Sans saisie, toutes, dans l'ordre de la palette.
List<(String, String)> matchingInstructions(String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return screenPalette;
  String name((String, String) e) => e.$1.split(' — ').first.toLowerCase();
  return [
    for (final e in screenPalette)
      if (name(e).startsWith(q)) e,
    for (final e in screenPalette)
      if (!name(e).startsWith(q) && e.$1.toLowerCase().contains(q)) e,
  ];
}

class _InstructionDialog extends StatefulWidget {
  const _InstructionDialog(this.macros);

  final Map<String, MacroDefinition> macros;

  @override
  State<_InstructionDialog> createState() => _InstructionDialogState();
}

class _InstructionDialogState extends State<_InstructionDialog> {
  final _query = TextEditingController();
  int _chosen = 0;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Les entrées de la liste : les instructions, puis les mingets du service.
  List<({String label, String key, PickedInstruction pick})> get _matches => [
    for (final (label, item) in matchingInstructions(_query.text))
      (
        label: label,
        key: 'instruction-${label.split(' — ').first}',
        pick: PickedInstruction.text(item),
      ),
    for (final m in matchingMacros(widget.macros, _query.text))
      (
        label: 'macro ${m.name} — ${m.description ?? 'minget du service'}',
        key: 'instruction-macro-${m.name}',
        pick: PickedInstruction.macro(m),
      ),
  ];

  void _move(int delta) {
    final n = _matches.length;
    if (n > 0) setState(() => _chosen = (_chosen + delta).clamp(0, n - 1));
  }

  void _pick(int i) {
    final matches = _matches;
    if (i >= 0 && i < matches.length) Navigator.pop(context, matches[i].pick);
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 460),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyUpEvent) return KeyEventResult.ignored;
                  if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    _move(1);
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    _move(-1);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  key: const Key('instruction-filter'),
                  controller: _query,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Tapez le début du nom de l\'instruction',
                    prefixIcon: Icon(Icons.search, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() => _chosen = 0),
                  onSubmitted: (_) => _pick(_chosen),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: matches.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Aucune instruction ne commence ainsi.'),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (var i = 0; i < matches.length; i++)
                            ListTile(
                              key: Key(matches[i].key),
                              dense: true,
                              selected: i == _chosen,
                              selectedTileColor: scheme.primaryContainer,
                              selectedColor: scheme.onPrimaryContainer,
                              title: Text(matches[i].label),
                              onTap: () => _pick(i),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
