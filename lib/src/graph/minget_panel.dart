import 'package:flutter/material.dart';
import 'package:minserve_core/minserve_core.dart';

import '../preview/page_preview.dart';
import 'graph_dialogs.dart';
import 'graph_panel.dart' show GraphEditing;
import 'library.dart';
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
    this.onGoToMacro,
    this.onOpenPage,
    this.editing,
    this.color = false,
    this.onColorChanged,
    this.variables = const {},
    this.library,
  });

  /// La bibliothèque de mingets ; `null` : celle livrée avec l'éditeur, lue à
  /// l'ouverture.
  final List<LibraryMinget>? library;

  final Service service;

  /// Le texte du service, pour fabriquer l'aperçu ; `null` s'il n'est pas
  /// valide.
  final String? text;
  final void Function(String macro)? onGoToMacro;

  /// Ouvre une page (en grand) : un appel du minget y est écrit.
  final void Function(String page)? onOpenPage;

  /// De quoi modifier les macros (renommer, copier, supprimer) ; `null` : lecture
  /// seule.
  final GraphEditing? editing;
  final bool color;
  final ValueChanged<bool>? onColorChanged;
  final Map<String, String> variables;

  @override
  State<MingetPanel> createState() => _MingetPanelState();
}

class _MingetPanelState extends State<MingetPanel> {
  String? _selected;

  /// Le modèle de la bibliothèque choisi (au lieu d'un minget du service).
  String? _librarySelected;

  bool get _library => _librarySelected != null;
  List<LibraryMinget>? _lib;
  String? _libraryError;

  @override
  void initState() {
    super.initState();
    _lib = widget.library;
    if (_lib == null) {
      libraryMingets().then(
        (lib) {
          if (mounted) setState(() => _lib = lib);
        },
        onError: (Object e) {
          if (mounted) {
            setState(
              () => _libraryError = e is ServiceException ? e.message : '$e',
            );
          }
        },
      );
    }
  }

  /// Les arguments d'essai de chaque minget, gardés tant que le panneau est là.
  final _args = <String, List<Object?>>{};
  int _resets = 0;

  MacroDefinition? get _macro => widget.service.macros[_selected];

  /// Sous quel nom garder les arguments d'essai : un minget du service et un de
  /// la bibliothèque de même nom ne se mélangent pas.
  String _akey(MacroDefinition m) => _library ? 'bib:${m.name}' : m.name;

  List<Object?> _argsOf(MacroDefinition m) {
    final saved = _args[_akey(m)];
    // La macro a changé de nombre de paramètres : on repart des défauts.
    if (saved == null || saved.length != m.arity) {
      return _args[_akey(m)] = defaultMingetArgs(m);
    }
    return saved;
  }

  LibraryMinget? get _libraryChosen {
    for (final m in _lib ?? const <LibraryMinget>[]) {
      if (m.name == _librarySelected) return m;
    }
    return null;
  }

  /// Copie [lib] dans le service ; sous un autre nom s'il y en a déjà un
  /// différent.
  Future<void> _addLibrary(LibraryMinget lib) async {
    final editing = widget.editing!;
    final state = libraryState(editing.text(), lib.name, lib.block);
    if (state == LibraryState.same) {
      setState(() {
        _librarySelected = null;
        _selected = lib.name;
      });
      _say('« ${lib.name} » est déjà dans le service.');
      return;
    }
    String? as;
    if (state == LibraryState.different) {
      as = await askPageName(
        context,
        title: 'Un minget « ${lib.name} » existe déjà',
        action: 'Ajouter',
        existing: widget.service.macros.keys,
        initial: '${lib.name}-2',
        label: 'Nom dans le service',
        allowInitial: true,
        check: macroNameError,
      );
      if (as == null || !mounted) return;
    }
    if (editing.apply((t) => addLibraryMacro(t, lib.name, lib.block, as: as))) {
      setState(() {
        _librarySelected = null;
        _selected = as ?? lib.name;
      });
      _say('Minget « ${as ?? lib.name} » ajouté au service.');
    }
  }

  Future<void> _rename(MacroDefinition m) async {
    final editing = widget.editing!;
    final to = await askPageName(
      context,
      title: 'Renommer « ${m.name} »',
      action: 'Renommer',
      existing: widget.service.macros.keys,
      initial: m.name,
      label: 'Nom du minget',
      check: macroNameError,
    );
    if (to == null || !mounted) return;
    final uses = macroUses(editing.text(), m.name).length;
    if (editing.apply((t) => renameMacro(t, m.name, to))) {
      // Les arguments d'essai suivent le minget.
      final args = _args.remove(m.name);
      if (args != null) _args[to] = args;
      setState(() => _selected = to);
      _say(
        uses == 0
            ? 'Minget renommé.'
            : 'Minget renommé, $uses appel${uses > 1 ? 's' : ''} mis à jour.',
      );
    }
  }

  Future<void> _duplicate(MacroDefinition m) async {
    final editing = widget.editing!;
    final to = await askPageName(
      context,
      title: 'Copier « ${m.name} »',
      action: 'Copier',
      existing: widget.service.macros.keys,
      initial: '${m.name}-copie',
      label: 'Nom de la copie',
      allowInitial: true,
      check: macroNameError,
    );
    if (to == null || !mounted) return;
    if (editing.apply((t) => duplicateMacro(t, m.name, to))) {
      setState(() => _selected = to);
    }
  }

  Future<void> _remove(MacroDefinition m) async {
    final editing = widget.editing!;
    final uses = macroUses(editing.text(), m.name);
    if (uses.isNotEmpty) {
      final where = {for (final u in uses) u.where}.join(', ');
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Supprimer « ${m.name} » ?'),
          content: Text(
            'Ce minget est encore appelé (${uses.length} '
            'appel${uses.length > 1 ? 's' : ''}) : $where.\n\n'
            'Retirez ou remplacez ces appels d\'abord.',
            key: const Key('minget-used'),
          ),
          actions: [
            FilledButton(
              key: const Key('dialog-ok'),
              onPressed: () => Navigator.pop(context),
              child: const Text('Compris'),
            ),
          ],
        ),
      );
      return;
    }
    final ok = await confirmDialog(
      context,
      title: 'Supprimer « ${m.name} » ?',
      body: 'Le minget sera retiré du texte. Aucune page ne l\'appelle.',
      action: 'Supprimer',
    );
    if (!ok || !mounted) return;
    if (editing.apply((t) => removeMacro(t, m.name))) {
      _args.remove(m.name);
      setState(() => _selected = null);
    }
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _set(MacroDefinition m, int i, Object? value) {
    setState(() => _argsOf(m)[i] = value);
  }

  @override
  Widget build(BuildContext context) {
    final macros = widget.service.macros.values.toList();
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
          child: Row(
            children: [
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
              SizedBox(width: 220, child: _list(macros, theme)),
              const VerticalDivider(width: 1),
              Expanded(child: _right(macros, theme)),
            ],
          ),
        ),
      ],
    );
  }

  /// À droite : le modèle de la bibliothèque ou le minget du service choisi.
  Widget _right(List<MacroDefinition> macros, ThemeData theme) {
    final chosen = _libraryChosen;
    if (chosen != null) return _detail(chosen.definition, theme, lib: chosen);
    final selected = _macro;
    if (selected != null) return _detail(selected, theme);
    return const Center(child: Text('Choisissez un minget.'));
  }

  Widget _sectionTitle(String text, ThemeData theme, Key key) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
    child: Text(
      text,
      key: key,
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.primary,
      ),
    ),
  );

  /// La liste de gauche : les mingets du service, puis les modèles de la
  /// bibliothèque (marqués : à ajouter, déjà dans le service, ou différent).
  Widget _list(List<MacroDefinition> macros, ThemeData theme) {
    final lib = _lib;
    final text = widget.text;
    return ListView(
      children: [
        _sectionTitle(
          'Du service (${macros.length})',
          theme,
          const Key('section-service'),
        ),
        if (macros.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Text(
              'Aucune macro dans ce service. Ajoutez un modèle de la '
              'bibliothèque ci-dessous.',
              key: Key('no-macros'),
            ),
          ),
        for (final m in macros)
          ListTile(
            key: Key('minget-${m.name}'),
            dense: true,
            selected: _librarySelected == null && m.name == _selected,
            title: Text(m.name),
            subtitle: Text(
              m.description ??
                  '${m.arity} paramètre${m.arity > 1 ? 's' : ''}'
                      '${m.extended ? '' : ' (\$1…)'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => setState(() {
              _selected = m.name;
              _librarySelected = null;
            }),
          ),
        const Divider(),
        _sectionTitle(
          lib == null ? 'Bibliothèque' : 'Bibliothèque (${lib.length})',
          theme,
          const Key('section-library'),
        ),
        if (_libraryError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Text(
              'Bibliothèque illisible : $_libraryError',
              key: const Key('library-error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          )
        else if (lib == null)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Text('Chargement…'),
          )
        else
          for (final m in lib)
            ListTile(
              key: Key('lib-${m.name}'),
              dense: true,
              selected: m.name == _librarySelected,
              title: Text(m.name),
              subtitle: Text(
                m.definition.description ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: text == null
                  ? null
                  : switch (libraryState(text, m.name, m.block)) {
                      LibraryState.absent => const Tooltip(
                        message: 'Pas encore dans le service',
                        child: Icon(
                          Icons.add_circle_outline,
                          size: 18,
                          key: Key('lib-new'),
                        ),
                      ),
                      LibraryState.same => const Tooltip(
                        message: 'Déjà dans le service',
                        child: Icon(
                          Icons.check,
                          size: 18,
                          key: Key('lib-in-service'),
                        ),
                      ),
                      LibraryState.different => const Tooltip(
                        message: 'Le service a un minget de ce nom, différent',
                        child: Icon(
                          Icons.compare_arrows,
                          size: 18,
                          key: Key('lib-differs'),
                        ),
                      ),
                    },
              onTap: () => setState(() => _librarySelected = m.name),
            ),
      ],
    );
  }

  Widget _detail(MacroDefinition m, ThemeData theme, {LibraryMinget? lib}) {
    final args = _argsOf(m);
    final text = widget.text;
    final state = lib == null || text == null
        ? null
        : libraryState(text, lib.name, lib.block);
    return Column(
      children: [
        Expanded(child: _preview(m, args, theme, lib: lib)),
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
                            _args.remove(_akey(m));
                            _resets++;
                          }),
                          icon: const Icon(Icons.restart_alt, size: 18),
                          label: const Text('Valeurs par défaut'),
                        ),
                      if (lib != null && widget.editing != null && text != null)
                        FilledButton.icon(
                          key: const Key('library-add'),
                          onPressed: () => _addLibrary(lib),
                          icon: const Icon(Icons.add, size: 18),
                          label: Text(
                            state == LibraryState.same
                                ? 'Déjà dans le service'
                                : 'Ajouter au service',
                          ),
                        ),
                      if (lib == null && widget.editing != null) ...[
                        IconButton(
                          key: const Key('minget-rename'),
                          tooltip: 'Renommer le minget',
                          icon: const Icon(Icons.drive_file_rename_outline),
                          onPressed: () => _rename(m),
                        ),
                        IconButton(
                          key: const Key('minget-copy'),
                          tooltip: 'Copier le minget',
                          icon: const Icon(Icons.content_copy),
                          onPressed: () => _duplicate(m),
                        ),
                        IconButton(
                          key: const Key('minget-delete'),
                          tooltip: 'Supprimer le minget',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _remove(m),
                        ),
                      ],
                      if (lib == null && widget.onGoToMacro != null)
                        TextButton.icon(
                          key: const Key('minget-goto'),
                          onPressed: () => widget.onGoToMacro!(m.name),
                          icon: const Icon(Icons.code, size: 18),
                          label: const Text('Dans le texte'),
                        ),
                    ],
                  ),
                  if (m.description != null) Text(m.description!),
                  if (lib != null && state != null)
                    Text(
                      switch (state) {
                        LibraryState.absent =>
                          'Modèle de la bibliothèque, pas encore dans le '
                              'service.',
                        LibraryState.same =>
                          'Modèle de la bibliothèque, déjà dans le service.',
                        LibraryState.different => 'Modèle de la bibliothèque.',
                      },
                      key: const Key('library-note'),
                      style: theme.textTheme.bodySmall,
                    ),
                  if (state == LibraryState.different)
                    Text(
                      'Le service a déjà un minget « ${m.name} » différent : '
                      'il sera ajouté sous un autre nom.',
                      key: const Key('library-differs'),
                      style: theme.textTheme.bodySmall,
                    ),
                  if (lib == null) _usedBy(m, theme),
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

  /// Qui appelle ce minget : les pages, les autres macros. Toucher un nom y
  /// va.
  Widget _usedBy(MacroDefinition m, ThemeData theme) {
    final text = widget.text;
    if (text == null) return const SizedBox.shrink();
    final counts = <String, int>{};
    for (final u in macroUses(text, m.name)) {
      counts[u.where] = (counts[u.where] ?? 0) + 1;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        key: const Key('minget-used-by'),
        spacing: 6,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Appelé par :', style: theme.textTheme.labelMedium),
          if (counts.isEmpty)
            Text('personne', style: theme.textTheme.bodySmall),
          for (final e in counts.entries)
            ActionChip(
              key: Key('used-by-${e.key}'),
              visualDensity: VisualDensity.compact,
              label: Text(e.value > 1 ? '${e.key} ×${e.value}' : e.key),
              onPressed: switch (e.key.split(' ')) {
                ['page', final page] when widget.onOpenPage != null =>
                  () => widget.onOpenPage!(page),
                ['macro', final macro]
                    when widget.service.macros.containsKey(macro) =>
                  () => setState(() => _selected = macro),
                _ => null,
              },
            ),
        ],
      ),
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

  Widget _preview(
    MacroDefinition m,
    List<Object?> args,
    ThemeData theme, {
    LibraryMinget? lib,
  }) {
    var text = widget.text;
    // Un minget de la bibliothèque s'essaie dans le service, sans y être écrit.
    if (text != null && lib != null) {
      try {
        text = withLibraryMacro(text, lib.name, lib.block);
      } on Object {
        text = null;
      }
    }
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
      caption: lib == null
          ? 'Minget « ${m.name} »'
          : 'Bibliothèque : « ${m.name} »',
    );
  }
}
