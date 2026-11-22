import 'package:flutter/material.dart';
import 'package:minserve_core/minserve_core.dart';

import '../preview/page_preview.dart';
import 'service_edit.dart';

const _numericKeys = {'ligne', 'col', 'largeur', 'hauteur', 'nombre', 'depuis'};

/// Le type de chaque paramètre de [macro] : celui qu'elle déclare, sinon celui
/// qu'on devine de la façon dont le corps s'en sert (un `ligne: $1` est un
/// entier, un `ecrit: "$3"` un texte). `null` : on ne sait pas.
List<MacroType?> mingetParamTypes(MacroDefinition macro) {
  final guessed = <int, MacroType>{};
  void note(int n, MacroType type) => guessed.putIfAbsent(n, () => type);

  final ref = RegExp(r'\$(?:\{(\d+)\}|(\d))');
  void scan(Object? node, String? key) {
    if (node is String) {
      for (final m in ref.allMatches(node)) {
        final n = int.parse(m.group(1) ?? m.group(2)!);
        final start = m.start;
        final before = node.substring(0, start);
        final inExpression = RegExp(r'\$\([^)]*$').hasMatch(before);
        if (before.endsWith('longueur(')) {
          note(n, MacroType.texte);
        } else if (inExpression) {
          note(n, MacroType.entier);
        } else if (node.trim() == m.group(0)) {
          note(
            n,
            key != null && _numericKeys.contains(key)
                ? MacroType.entier
                : MacroType.texte,
          );
        } else {
          note(n, MacroType.texte);
        }
      }
    } else if (node is Map) {
      for (final e in node.entries) {
        scan(e.value, '${e.key}');
      }
    } else if (node is List) {
      for (final e in node) {
        scan(e, key);
      }
    }
  }

  scan(macro.body, null);
  return [
    for (var i = 0; i < macro.parameters.length; i++)
      macro.parameters[i].type ?? guessed[i + 1],
  ];
}

/// Les arguments de départ d'un appel de [macro] : la valeur par défaut de
/// chaque paramètre, ou à défaut une valeur qui se voit (le plus petit entier
/// permis, le nom du paramètre pour un texte, faux pour un booléen).
List<Object?> defaultMingetArgs(MacroDefinition macro) {
  final types = mingetParamTypes(macro);
  return [
    for (var i = 0; i < macro.parameters.length; i++)
      macro.parameters[i].defaultValue ??
          switch (types[i]) {
            MacroType.entier => (macro.parameters[i].min ?? 1).clamp(
              macro.parameters[i].min ?? -1000000,
              macro.parameters[i].max ?? 1000000,
            ),
            MacroType.texte =>
              macro.extended ? macro.parameters[i].name : 'Texte',
            MacroType.booleen => false,
            null => 1,
          },
  ];
}

/// Les mingets du service (ses macros) : la liste à gauche ; à droite, celui
/// qu'on a choisi, montré avec des arguments d'essai qu'on peut changer.
class MingetPanel extends StatefulWidget {
  const MingetPanel({
    super.key,
    required this.service,
    required this.text,
    required this.onBack,
    this.onGoToMacro,
    this.color = false,
    this.onColorChanged,
    this.variables = const {},
  });

  final Service service;

  /// Le texte du service, pour fabriquer l'aperçu ; `null` s'il n'est pas
  /// valide.
  final String? text;
  final VoidCallback onBack;
  final void Function(String macro)? onGoToMacro;
  final bool color;
  final ValueChanged<bool>? onColorChanged;
  final Map<String, String> variables;

  @override
  State<MingetPanel> createState() => _MingetPanelState();
}

class _MingetPanelState extends State<MingetPanel> {
  String? _selected;

  /// Les arguments d'essai de chaque minget, gardés tant que le panneau est là.
  final _args = <String, List<Object?>>{};
  int _resets = 0;

  MacroDefinition? get _macro => widget.service.macros[_selected];

  List<Object?> _argsOf(MacroDefinition m) {
    final saved = _args[m.name];
    // La macro a changé de nombre de paramètres : on repart des défauts.
    if (saved == null || saved.length != m.arity) {
      return _args[m.name] = defaultMingetArgs(m);
    }
    return saved;
  }

  void _set(MacroDefinition m, int i, Object? value) {
    setState(() => _argsOf(m)[i] = value);
  }

  @override
  Widget build(BuildContext context) {
    final macros = widget.service.macros.values.toList();
    final selected = _macro;
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
          child: Row(
            children: [
              TextButton.icon(
                key: const Key('back-from-mingets'),
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Graphe'),
              ),
              Text('Mingets', style: theme.textTheme.titleSmall),
              const Spacer(),
              if (widget.onColorChanged != null)
                IconButton(
                  key: const Key('preview-colors'),
                  tooltip: widget.color
                      ? 'Couleur (passer en niveaux de gris)'
                      : 'Niveaux de gris (passer en couleur)',
                  isSelected: widget.color,
                  icon: const Icon(Icons.palette_outlined),
                  selectedIcon: const Icon(Icons.palette),
                  onPressed: () => widget.onColorChanged!(!widget.color),
                ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              SizedBox(width: 190, child: _list(macros, theme)),
              const VerticalDivider(width: 1),
              Expanded(
                child: selected == null
                    ? Center(
                        child: Text(
                          macros.isEmpty
                              ? 'Ce service n\'a pas de macro.'
                              : 'Choisissez un minget.',
                        ),
                      )
                    : _detail(selected, theme),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _list(List<MacroDefinition> macros, ThemeData theme) {
    if (macros.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'Aucune macro. Une macro se définit sous « macros: » en tête du '
          'service.',
        ),
      );
    }
    return ListView(
      children: [
        for (final m in macros)
          ListTile(
            key: Key('minget-${m.name}'),
            dense: true,
            selected: m.name == _selected,
            title: Text(m.name),
            subtitle: Text(
              m.description ??
                  '${m.arity} paramètre${m.arity > 1 ? 's' : ''}'
                      '${m.extended ? '' : ' (\$1…)'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => setState(() => _selected = m.name),
          ),
      ],
    );
  }

  Widget _detail(MacroDefinition m, ThemeData theme) {
    final args = _argsOf(m);
    return Column(
      children: [
        Expanded(child: _preview(m, args, theme)),
        const Divider(height: 1),
        Material(
          color: theme.colorScheme.surfaceContainer,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                key: const Key('minget-details'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 0,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(m.name, style: theme.textTheme.titleMedium),
                      if (m.arity > 0)
                        TextButton.icon(
                          key: const Key('minget-reset'),
                          onPressed: () => setState(() {
                            _args.remove(m.name);
                            _resets++;
                          }),
                          icon: const Icon(Icons.restart_alt, size: 18),
                          label: const Text('Valeurs par défaut'),
                        ),
                      if (widget.onGoToMacro != null)
                        TextButton.icon(
                          key: const Key('minget-goto'),
                          onPressed: () => widget.onGoToMacro!(m.name),
                          icon: const Icon(Icons.code, size: 18),
                          label: const Text('Dans le texte'),
                        ),
                    ],
                  ),
                  if (m.description != null) Text(m.description!),
                  if (!m.extended)
                    Text(
                      'Macro écrite en liste d\'instructions : ses paramètres '
                      'sont \$1, \$2… sans type.',
                      style: theme.textTheme.bodySmall,
                    ),
                  const SizedBox(height: 8),
                  if (m.arity == 0)
                    const Text('Cette macro n\'a pas de paramètre.')
                  else
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (var i = 0; i < m.arity; i++)
                          _argField(m, i, args[i]),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _hint(MacroParameter p, MacroType? type) {
    final parts = <String>[
      ?type?.label,
      if (p.min != null && p.max != null)
        '${p.min} à ${p.max}'
      else if (p.min != null)
        '≥ ${p.min}'
      else if (p.max != null)
        '≤ ${p.max}',
    ];
    final d = p.description;
    return [parts.join(' '), ?d].where((e) => e.isNotEmpty).join(' — ');
  }

  Widget _argField(MacroDefinition m, int i, Object? value) {
    final p = m.parameters[i];
    final type = mingetParamTypes(m)[i];
    final key = Key('minget-arg-${m.name}-$i-$_resets');
    if (type == MacroType.booleen) {
      return SizedBox(
        width: 190,
        child: Row(
          children: [
            Expanded(child: Text(p.name)),
            Switch(
              key: key,
              value: value == true,
              onChanged: (v) => _set(m, i, v),
            ),
          ],
        ),
      );
    }
    final numeric = type != MacroType.texte;
    return SizedBox(
      width: 190,
      child: TextFormField(
        key: key,
        initialValue: '$value',
        keyboardType: numeric ? TextInputType.number : null,
        decoration: InputDecoration(
          labelText: p.name,
          helperText: _hint(p, type).isEmpty ? null : _hint(p, type),
          helperMaxLines: 2,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        // Un entier mal écrit reste un texte : le serveur dit ce qui ne va pas.
        onChanged: (v) =>
            _set(m, i, numeric ? (int.tryParse(v.trim()) ?? v) : v),
      ),
    );
  }

  Widget _preview(MacroDefinition m, List<Object?> args, ThemeData theme) {
    final text = widget.text;
    if (text == null) {
      return const Center(
        child: Text(
          'Le texte n\'est pas valide : corrigez-le pour voir ce minget.',
          key: Key('minget-error'),
        ),
      );
    }
    Service? service;
    String? error;
    try {
      service = Service.parseString(mingetPreviewText(text, m.name, args));
    } on Object catch (e) {
      error = (e is ServiceException ? e.message : '$e').replaceFirst(
        RegExp(r'^pages\.' + mingetPage + r'\.ecran\[1\] \(macro\) : '),
        '',
      );
    }
    if (service == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Appel refusé : $error',
            key: const Key('minget-error'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      );
    }
    return PagePreview(
      service: service,
      page: mingetPage,
      large: true,
      color: widget.color,
      variables: widget.variables,
      inputZone: false,
      caption: 'Minget « ${m.name} »',
    );
  }
}
