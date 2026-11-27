import 'dart:math';

import 'package:flutter/material.dart';
import 'package:minserve_core/minserve_core.dart'
    show Service, ServiceException;

import '../split_handle.dart';
import 'graph_dialogs.dart';
import '../preview/page_preview.dart';
import '../preview/test_data.dart';
import 'library.dart';
import 'minget_panel.dart';
import 'page_forms.dart';
import 'screen_form.dart';
import 'layout.dart';
import 'service_edit.dart';
import 'service_graph.dart';

/// Ce que le graphe peut demander au texte du service.
class GraphEditing {
  const GraphEditing({required this.text, required this.apply});

  /// Le texte actuel.
  final String Function() text;

  /// Remplace le texte par ce que [edit] en fait. Rend faux si la modification
  /// est refusée (la raison est alors déjà montrée à l'utilisateur).
  final bool Function(String Function(String text) edit) apply;
}

/// Le graphe des pages d'un service : une case par page, une flèche par
/// transition. Toucher une page la sélectionne et met ses flèches en avant.
enum _PageTab { overview, rules, input, access, screen, preview }

/// Ce que montre l'aperçu d'une page quand une instruction est choisie.
enum _Scope { page, upTo, only }

/// Les trois vues du volet, toujours accessibles par la barre du haut.
enum _View { graph, page, mingets }

class GraphPanel extends StatefulWidget {
  const GraphPanel({
    super.key,
    required this.graph,
    required this.layout,
    this.onGoToPage,
    this.onGoToMacro,
    this.editing,
    this.service,
    this.stale,
    this.fitToken = 0,
  });

  final ServiceGraph graph;
  final GraphLayout layout;

  /// Demande d'aller à la déclaration de la page dans le texte.
  final void Function(String page, {String? section, int? rule})? onGoToPage;

  /// Demande d'aller à la définition d'une macro dans le texte.
  final void Function(String macro)? onGoToMacro;

  /// De quoi modifier le service depuis le graphe ; `null` : lecture seule.
  final GraphEditing? editing;

  /// Le service du texte actuel, pour l'aperçu des pages ; `null` si le texte
  /// n'est pas valide.
  final Service? service;

  /// Si le texte n'est plus valide : pourquoi ce graphe est celui d'avant.
  final String? stale;

  /// Quand il change (un autre fichier est chargé), le graphe se recadre sur la
  /// fenêtre, comme « Tout voir ».
  final int fitToken;

  @override
  State<GraphPanel> createState() => _GraphPanelState();
}

class _GraphPanelState extends State<GraphPanel> {
  final _view = TransformationController();
  final _search = TextEditingController();
  Size _viewport = Size.zero;
  bool _fitted = false;
  String? _selected;

  /// La page ouverte en grand (vue « Page » : son rendu en haut, ses propriétés
  /// en bas), ou `null`. Elle reste ouverte quand on regarde une autre vue.
  String? _open;

  /// La vue montrée : le graphe, la page ouverte ou les mingets.
  _View _mode = _View.graph;

  /// Aperçu en couleur ou en niveaux de gris (par défaut).
  bool _previewColor = false;

  /// Le panneau des données de test est ouvert ; leurs valeurs (variables).
  bool _dataOpen = false;

  /// L'instruction choisie dans l'onglet Écran, et ce que l'aperçu en montre :
  /// la page entière, l'écran jusqu'à elle, ou elle seule.
  int? _instr;
  _Scope _scope = _Scope.page;
  final Map<String, String> _testVars = {};

  /// Le dernier clic sur un nœud, pour reconnaître le double clic sans
  /// retarder le clic simple.
  String? _lastTapped;
  DateTime _lastTapAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _hideBack = false;
  Set<String> _marked = {};
  String _markedBy = '';

  /// Page à sélectionner dès qu'elle apparaît dans le graphe (créée ou
  /// renommée depuis ici).
  String? _pending;

  /// L'onglet ouvert dans le panneau de la page sélectionnée.
  _PageTab _tab = _PageTab.overview;

  /// Hauteur du panneau de la page, une fois réglée en tirant sa poignée ;
  /// sinon il prend la hauteur de son contenu.
  double? _detailsHeight;
  double _heightAtDragStart = 0;
  final _detailsKey = GlobalKey();

  /// Les modèles de la bibliothèque, une fois lus.
  List<LibraryMinget> _library = const [];

  @override
  void initState() {
    super.initState();
    libraryMingets().then((lib) {
      if (mounted) setState(() => _library = lib);
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    _view.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(GraphPanel old) {
    super.didUpdateWidget(old);
    // Un autre fichier : on recadre dès que le graphe a une taille à l'écran (tout
    // de suite, ou quand on le montre si le texte seul est affiché).
    if (old.fitToken != widget.fitToken) _fitted = false;
    final pending = _pending;
    if (pending != null && widget.graph.nodes.containsKey(pending)) {
      _pending = null;
      _selected = pending;
      if (_open != null) _open = pending;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _center(pending);
      });
    }
    if (!widget.graph.nodes.containsKey(_selected)) _selected = null;
    if (!widget.graph.nodes.containsKey(_open)) {
      _open = null;
      if (_mode == _View.page) _mode = _View.graph;
    }
    if (widget.service == null && _mode == _View.mingets) _mode = _View.graph;
    _marked = _marked.intersection(widget.graph.nodes.keys.toSet());
  }

  void _fit() {
    final size = widget.layout.size;
    if (_viewport.isEmpty || size.isEmpty) return;
    final scale = min(
      1.0,
      min(_viewport.width / size.width, _viewport.height / size.height),
    );
    _view.value = Matrix4.identity()
      ..translateByDouble(
        (_viewport.width - size.width * scale) / 2,
        (_viewport.height - size.height * scale) / 2,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void _center(String name) {
    final rect = widget.layout.rects[name];
    if (rect == null || _viewport.isEmpty) return;
    final scale = _view.value.getMaxScaleOnAxis();
    _view.value = Matrix4.identity()
      ..translateByDouble(
        _viewport.width / 2 - rect.center.dx * scale,
        _viewport.height / 2 - rect.center.dy * scale,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void _select(String? name, {bool center = false}) {
    setState(() {
      _selected = name;
      if (_mode == _View.page && name != null && name != _open) {
        _open = name;
        _instr = null;
      }
    });
    if (center && name != null && _mode != _View.page) _center(name);
  }

  void _openPage(String name) => setState(() {
    _selected = name;
    _open = name;
    _mode = _View.page;
    _instr = null;
  });

  /// Montre le graphe, centré sur la page qu'on quitte s'il y en avait une.
  void _showGraph() {
    final name = _mode == _View.page ? _open : null;
    setState(() => _mode = _View.graph);
    if (name != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _center(name);
      });
    }
  }

  /// Ferme la page ouverte (l'onglet « Page ») et revient au graphe.
  void _closePage() {
    final name = _open;
    setState(() {
      _open = null;
      _mode = _View.graph;
    });
    if (name != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _center(name);
      });
    }
  }

  /// La barre qui ne bouge pas : le graphe, la page ouverte, les mingets.
  Widget _viewBar() {
    final macros = widget.service?.macros.length ?? 0;
    final open = _open;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
      child: Row(
        children: [
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<_View>(
                key: const Key('view-tabs'),
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  const ButtonSegment(
                    value: _View.graph,
                    icon: Icon(Icons.account_tree_outlined, size: 18),
                    label: Text('Graphe'),
                  ),
                  if (open != null)
                    ButtonSegment(
                      value: _View.page,
                      icon: const Icon(Icons.description_outlined, size: 18),
                      label: Text('Page « $open »'),
                    ),
                  ButtonSegment(
                    value: _View.mingets,
                    icon: const Icon(Icons.widgets_outlined, size: 18),
                    label: Text('Mingets ($macros)'),
                    enabled: widget.service != null,
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (v) {
                  final view = v.single;
                  if (view == _View.graph) {
                    _showGraph();
                  } else {
                    setState(() => _mode = view);
                  }
                },
              ),
            ),
          ),
          if (open != null)
            IconButton(
              key: const Key('close-page'),
              tooltip: 'Fermer la page « $open »',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 18),
              onPressed: _closePage,
            ),
        ],
      ),
    );
  }

  void _tapNode(String name) {
    final now = DateTime.now();
    final again =
        _lastTapped == name &&
        now.difference(_lastTapAt) < const Duration(milliseconds: 400);
    _lastTapped = again ? null : name;
    _lastTapAt = now;
    if (again) {
      _openPage(name);
    } else {
      _select(name);
    }
  }

  // --- Modifications ---

  Future<void> _addPage() async {
    final editing = widget.editing!;
    final name = await askPageName(
      context,
      title: 'Nouvelle page',
      action: 'Créer',
      existing: widget.graph.nodes.keys,
    );
    if (name == null) return;
    if (editing.apply((t) => addPage(t, name))) _pending = name;
  }

  Future<void> _renamePage(String from) async {
    final editing = widget.editing!;
    final to = await askPageName(
      context,
      title: 'Renommer « $from »',
      action: 'Renommer',
      existing: widget.graph.nodes.keys,
      initial: from,
    );
    if (to == null) return;
    if (editing.apply((t) => renamePage(t, from, to))) _pending = to;
  }

  Future<void> _removePage(String name) async {
    final editing = widget.editing!;
    List<PageRef> refs;
    try {
      refs = pageReferences(
        editing.text(),
        name,
      ).where((r) => !(r.path.length > 1 && r.path[1] == name)).toList();
    } on EditException {
      refs = const [];
    }
    final blocked = refs.any((r) => !r.removable);
    // Si une valeur y renvoie, la modification dira laquelle, sans confirmer.
    if (!blocked) {
      final rules = refs.length;
      List<String> lose;
      try {
        lose = pagesLosingInput(editing.text(), name);
      } on EditException {
        lose = const [];
      }
      final ok = await confirmDialog(
        context,
        title: 'Supprimer « $name » ?',
        body: rules == 0
            ? 'La page sera retirée du texte.'
            : 'La page sera retirée du texte, ainsi que '
                  '${rules == 1 ? 'la règle qui y mène' : '$rules règles qui y mènent'}'
                  ' (${{for (final r in refs) r.where}.join(' ; ')}).'
                  '${lose.isEmpty ? '' : ' Sans règle, ${lose.length == 1 ? 'la page ${lose.first} perd' : 'les pages ${lose.join(', ')} perdent'} sa saisie.'}',
        action: 'Supprimer',
      );
      if (!ok || !mounted) return;
    }
    editing.apply((t) => removePage(t, name));
  }

  Future<void> _addRule(String from) async {
    final editing = widget.editing!;
    final spec = await askRule(
      context,
      from: from,
      pages: widget.graph.nodes.keys.toList(),
    );
    if (spec == null) return;
    editing.apply(
      (t) => addRule(t, from, spec.to, key: spec.key, choice: spec.choice),
    );
  }

  Future<void> _removeRuleAt(String from, int index, String to) async {
    final editing = widget.editing!;
    var only = false;
    try {
      only = isOnlyRule(editing.text(), from);
    } on EditException {
      only = false;
    }
    if (only) {
      final ok = await confirmDialog(
        context,
        title: 'Supprimer la dernière règle de « $from » ?',
        body:
            'Une saisie ne peut pas rester sans règle : la page perd aussi sa '
            'zone de saisie (entree et action).',
        action: 'Supprimer',
      );
      if (!ok || !mounted) return;
    }
    editing.apply((t) => removeRule(t, from, index, to));
  }

  void _mark(String by, List<String> names) {
    setState(() {
      if (_markedBy == by) {
        _marked = {};
        _markedBy = '';
      } else {
        _marked = names.toSet();
        _markedBy = by;
      }
    });
    if (_marked.isNotEmpty) _center(_marked.first);
  }

  void _find(String text) {
    final q = text.trim().toLowerCase();
    if (q.isEmpty) return;
    final hits = [
      for (final n in widget.graph.nodes.keys)
        if (n.toLowerCase().contains(q)) n,
    ];
    if (hits.isNotEmpty) _select(hits.first, center: true);
  }

  Set<String> get _matches {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return const {};
    return {
      for (final n in widget.graph.nodes.keys)
        if (n.toLowerCase().contains(q)) n,
    };
  }

  @override
  Widget build(BuildContext context) {
    final graph = widget.graph;
    final deadEnds = graph.deadEnds;
    final unreachable = graph.unreachable;
    final matches = _matches;
    final service = widget.service;
    final open = _mode == _View.page ? _open : null;
    final mingets = service == null
        ? const SizedBox.shrink()
        : MingetPanel(
            service: service,
            text: widget.editing?.text(),
            onGoToMacro: widget.onGoToMacro,
            onOpenPage: (page) => setState(() {
              _mode = _View.page;
              _selected = page;
              _open = page;
              _instr = null;
              _tab = _PageTab.screen;
            }),
            editing: widget.editing,
            color: _previewColor,
            onColorChanged: (v) => setState(() => _previewColor = v),
            variables: _testVars,
          );
    final body = Column(
      children: [
        if (open != null && widget.service != null) ...[
          _pageBar(open),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _preview(open)),
                if (_dataOpen) _testPanel(open),
              ],
            ),
          ),
          SplitHandle(
            key: const Key('split-page-details'),
            axis: Axis.vertical,
            onStart: () => _heightAtDragStart =
                _detailsKey.currentContext?.size?.height ?? 300,
            onDrag: (dy) => setState(
              () => _detailsHeight = (_heightAtDragStart - dy).clamp(
                80.0,
                MediaQuery.sizeOf(context).height * 0.75,
              ),
            ),
          ),
          _details(open, pageMode: true),
        ] else ...[
          _toolbar(deadEnds, unreachable),
          if (graph.globals.isNotEmpty) _globals(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                _viewport = box.biggest;
                if (!_fitted && !_viewport.isEmpty) {
                  _fitted = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _fit();
                  });
                }
                return ClipRect(
                  key: const Key('graph-area'),
                  child: InteractiveViewer(
                    transformationController: _view,
                    constrained: false,
                    minScale: 0.15,
                    maxScale: 2.5,
                    boundaryMargin: const EdgeInsets.all(600),
                    child: SizedBox.fromSize(
                      size: widget.layout.size,
                      child: _canvas(matches),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_selected != null) ...[
            SplitHandle(
              key: const Key('split-graph-details'),
              axis: Axis.vertical,
              onStart: () => _heightAtDragStart =
                  _detailsKey.currentContext?.size?.height ?? 200,
              // Tirer vers le haut agrandit le panneau.
              onDrag: (dy) => setState(
                () => _detailsHeight = (_heightAtDragStart - dy).clamp(
                  80.0,
                  MediaQuery.sizeOf(context).height * 0.75,
                ),
              ),
            ),
            _details(_selected!),
          ],
        ],
      ],
    );
    return Column(
      children: [
        if (widget.stale != null)
          Material(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.history, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Texte invalide : graphe du dernier texte valide '
                      '(${widget.stale})',
                      key: const Key('stale'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (service != null) _viewBar(),
        Expanded(
          child: IndexedStack(
            sizing: StackFit.expand,
            index: _mode == _View.mingets ? 1 : 0,
            children: [body, mingets],
          ),
        ),
      ],
    );
  }

  /// L'aperçu de la page [name], ou d'un morceau de son écran si une instruction
  /// est choisie dans l'onglet Écran.
  Widget _preview(String name) {
    final service = widget.service!;
    final text = widget.editing?.text();
    final at = _instrIn(name);
    var shown = service;
    String? caption;
    String? notice;
    final partial =
        _tab == _PageTab.screen &&
        _scope != _Scope.page &&
        at != null &&
        text != null;
    if (partial) {
      final from = _scope == _Scope.only ? at : 0;
      try {
        shown = Service.parseString(screenSlice(text, name, from, at));
        caption = _scope == _Scope.only
            ? 'Instruction ${at + 1} seule'
            : 'Instructions 1 à ${at + 1}';
      } on Object catch (e) {
        notice =
            'Aperçu de ce morceau impossible : '
            '${e is ServiceException ? e.message : e}';
      }
    }
    return PagePreview(
      service: shown,
      page: name,
      large: true,
      color: _previewColor,
      variables: _testVars,
      caption: caption,
      notice: notice,
      inputZone: caption == null,
    );
  }

  /// L'instruction choisie, si elle existe encore dans la page [name].
  int? _instrIn(String name) {
    final at = _instr;
    final text = widget.editing?.text();
    final count = text == null ? 0 : screenItems(text, name).length;
    return at != null && at < count ? at : null;
  }

  void _selectInstruction(int i) {
    if (i != _instr) setState(() => _instr = i);
  }

  Widget _testPanel(String page) {
    final text = widget.editing?.text();
    final names = text == null
        ? (here: const <String>[], elsewhere: const <String>[])
        : variablesFor(text, page);
    return SizedBox(
      width: 280,
      child: TestDataPanel(
        here: names.here,
        elsewhere: names.elsewhere,
        values: _testVars,
        onChanged: (name, value) => setState(() {
          if (value == null) {
            _testVars.remove(name);
          } else {
            _testVars[name] = value;
          }
        }),
      ),
    );
  }

  Widget _pageBar(String name) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (_tab == _PageTab.screen && _instrIn(name) != null)
                  SegmentedButton<_Scope>(
                    key: const Key('preview-scope'),
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: [
                      const ButtonSegment(
                        value: _Scope.page,
                        label: Text('Page'),
                      ),
                      ButtonSegment(
                        value: _Scope.upTo,
                        label: Text('Jusqu\'à ${_instr! + 1}'),
                      ),
                      ButtonSegment(
                        value: _Scope.only,
                        label: Text('${_instr! + 1} seule'),
                      ),
                    ],
                    selected: {_scope},
                    onSelectionChanged: (v) =>
                        setState(() => _scope = v.single),
                  ),
              ],
            ),
          ),
          IconButton(
            key: const Key('test-data-toggle'),
            tooltip: 'Données de test (variables)',
            isSelected: _dataOpen,
            icon: const Icon(Icons.tune),
            selectedIcon: const Icon(Icons.tune, fill: 1),
            onPressed: () => setState(() => _dataOpen = !_dataOpen),
          ),
          IconButton(
            key: const Key('preview-colors'),
            tooltip: _previewColor
                ? 'Couleur (passer en niveaux de gris)'
                : 'Niveaux de gris (passer en couleur)',
            isSelected: _previewColor,
            icon: const Icon(Icons.palette_outlined),
            selectedIcon: const Icon(Icons.palette),
            onPressed: () => setState(() => _previewColor = !_previewColor),
          ),
        ],
      ),
    );
  }

  Widget _toolbar(List<String> deadEnds, List<String> unreachable) {
    final graph = widget.graph;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${graph.nodes.length} page${graph.nodes.length > 1 ? 's' : ''}, '
            '${graph.edges.length} transition${graph.edges.length > 1 ? 's' : ''}',
            key: const Key('summary'),
          ),
          if (deadEnds.isNotEmpty)
            FilterChip(
              key: const Key('dead-ends'),
              avatar: const Icon(Icons.block, size: 16),
              label: Text('Impasses (${deadEnds.length})'),
              selected: _markedBy == 'dead',
              onSelected: (_) => _mark('dead', deadEnds),
            ),
          if (unreachable.isNotEmpty)
            FilterChip(
              key: const Key('unreachable'),
              avatar: const Icon(Icons.link_off, size: 16),
              label: Text('Inaccessibles (${unreachable.length})'),
              selected: _markedBy == 'unreachable',
              onSelected: (_) => _mark('unreachable', unreachable),
            ),
          FilterChip(
            key: const Key('hide-back'),
            label: const Text('Masquer les retours'),
            selected: _hideBack,
            onSelected: (v) => setState(() => _hideBack = v),
          ),
          SizedBox(
            width: 170,
            height: 36,
            child: TextField(
              key: const Key('search'),
              controller: _search,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Chercher une page',
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: _find,
            ),
          ),
          if (widget.editing != null)
            IconButton(
              key: const Key('add-page'),
              tooltip: 'Nouvelle page',
              icon: const Icon(Icons.add_box_outlined),
              onPressed: _addPage,
            ),
          IconButton(
            tooltip: 'Tout voir',
            icon: const Icon(Icons.fit_screen),
            onPressed: _fit,
          ),
        ],
      ),
    );
  }

  Widget _globals() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Depuis toute page :',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (final g in widget.graph.globals)
            ActionChip(
              visualDensity: VisualDensity.compact,
              avatar: Icon(switch (g.kind) {
                GlobalKind.shortcut => Icons.keyboard,
                GlobalKind.guide => Icons.help_outline,
                GlobalKind.passwordChange => Icons.password,
              }, size: 14),
              label: Text('${g.label} → ${g.to}'),
              onPressed: () => _select(g.to, center: true),
            ),
        ],
      ),
    );
  }

  Widget _canvas(Set<String> matches) {
    final graph = widget.graph;
    final layout = widget.layout;
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _select(null),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _EdgesPainter(
                graph: graph,
                layout: layout,
                selected: _selected,
                hideBack: _hideBack,
                scheme: scheme,
              ),
            ),
          ),
          for (final node in graph.nodes.values)
            Positioned.fromRect(
              rect: layout.rects[node.name]!,
              child: _NodeBox(
                node: node,
                selected: node.name == _selected,
                marked: _marked.contains(node.name),
                matched: matches.contains(node.name),
                dimmed:
                    _selected != null &&
                    node.name != _selected &&
                    !graph.edges.any(
                      (e) =>
                          (e.from == _selected && e.to == node.name) ||
                          (e.to == _selected && e.from == node.name),
                    ),
                onTap: () => _tapNode(node.name),
              ),
            ),
        ],
      ),
    );
  }

  Widget _details(String name, {bool pageMode = false}) {
    final graph = widget.graph;
    final node = graph.nodes[name]!;
    final out = graph.outgoing(name).toList();
    final inn = graph.incoming(name).where((e) => !e.isLoop).toList();
    final theme = Theme.of(context);
    final editing = widget.editing;
    // En mode page, le rendu est déjà en haut : pas d'onglet « Rendu ».
    final tab = editing == null || (pageMode && _tab == _PageTab.preview)
        ? _PageTab.overview
        : _tab;
    final fixed = pageMode ? (_detailsHeight ?? 300) : _detailsHeight;
    return Material(
      key: _detailsKey,
      color: theme.colorScheme.surfaceContainer,
      child: ConstrainedBox(
        constraints: fixed != null
            ? BoxConstraints.tightFor(height: fixed)
            : BoxConstraints(
                maxHeight: editing == null
                    ? 190
                    : (tab == _PageTab.overview
                          ? 250
                          : (tab == _PageTab.preview ? 380 : 300)),
              ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            key: const Key('details'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(name, style: theme.textTheme.titleMedium),
                    ),
                    if (widget.onGoToPage != null)
                      TextButton.icon(
                        onPressed: () => widget.onGoToPage!(
                          name,
                          section: switch (_tab) {
                            _PageTab.overview => null,
                            _PageTab.rules => 'action',
                            _PageTab.input => 'entree',
                            _PageTab.access => 'acces',
                            _PageTab.screen => 'ecran',
                            _PageTab.preview => 'ecran',
                          },
                        ),
                        icon: const Icon(Icons.code, size: 18),
                        label: const Text('Aller au texte'),
                      ),
                    if (!pageMode && widget.service != null)
                      TextButton.icon(
                        key: const Key('open-page'),
                        onPressed: () => _openPage(name),
                        icon: const Icon(Icons.open_in_full, size: 18),
                        label: const Text('Ouvrir la page'),
                      ),
                    if (widget.editing != null) ...[
                      IconButton(
                        key: const Key('rename-page'),
                        tooltip: 'Renommer la page',
                        icon: const Icon(Icons.drive_file_rename_outline),
                        onPressed: () => _renamePage(name),
                      ),
                      IconButton(
                        key: const Key('delete-page'),
                        tooltip: 'Supprimer la page',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _removePage(name),
                      ),
                    ],
                  ],
                ),
              ),
              Wrap(
                spacing: 6,
                children: [
                  if (node.isStart) const Chip(label: Text('page de départ')),
                  if (node.requiresLogin)
                    Chip(
                      label: Text(
                        node.implicitLogin
                            ? 'réservée aux connectés (programme)'
                            : 'réservée aux connectés',
                      ),
                    ),
                  if (node.isProgram)
                    Chip(label: Text('programme ${node.program}')),
                  if (!node.hasInput && !node.isProgram)
                    const Chip(label: Text('impasse : aucune saisie')),
                  if (node.isProgram &&
                      out.every((e) => e.kind != EdgeKind.exec))
                    const Chip(label: Text('la voie se ferme à la fin')),
                  if (node.unreachable) const Chip(label: Text('inaccessible')),
                ],
              ),
              if (editing != null) ...[
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<_PageTab>(
                    key: const Key('page-tabs'),
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: [
                      const ButtonSegment(
                        value: _PageTab.overview,
                        label: Text('Résumé'),
                      ),
                      const ButtonSegment(
                        value: _PageTab.rules,
                        label: Text('Règles'),
                      ),
                      const ButtonSegment(
                        value: _PageTab.input,
                        label: Text('Saisie'),
                      ),
                      const ButtonSegment(
                        value: _PageTab.access,
                        label: Text('Accès'),
                      ),
                      const ButtonSegment(
                        value: _PageTab.screen,
                        label: Text('Écran'),
                      ),
                      if (!pageMode)
                        ButtonSegment(
                          value: _PageTab.preview,
                          label: Text('Rendu'),
                        ),
                    ],
                    selected: {tab},
                    onSelectionChanged: (v) => setState(() => _tab = v.single),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              if (editing != null && tab == _PageTab.rules)
                RulesForm(
                  page: name,
                  text: editing.text(),
                  pages: graph.nodes.keys.toList(),
                  apply: editing.apply,
                  onRemove: (i, to) => _removeRuleAt(name, i, to),
                  onAdd: node.isProgram ? null : () => _addRule(name),
                  onGoToPage: widget.onGoToPage,
                )
              else if (editing != null && tab == _PageTab.input)
                InputForm(
                  page: name,
                  text: editing.text(),
                  apply: editing.apply,
                  onGoToPage: widget.onGoToPage,
                )
              else if (editing != null && tab == _PageTab.screen)
                ScreenForm(
                  page: name,
                  text: editing.text(),
                  apply: editing.apply,
                  onGoToPage: widget.onGoToPage,
                  selected: pageMode ? _instr : null,
                  onSelect: pageMode ? _selectInstruction : null,
                  macros: widget.service?.macros ?? const {},
                  library: _library,
                )
              else if (tab == _PageTab.preview && widget.service != null)
                PagePreview(
                  service: widget.service!,
                  page: name,
                  color: _previewColor,
                  onColorChanged: (v) => setState(() => _previewColor = v),
                  variables: _testVars,
                )
              else if (editing != null && tab == _PageTab.access)
                AccessForm(
                  page: name,
                  text: editing.text(),
                  pages: graph.nodes.keys.toList(),
                  apply: editing.apply,
                )
              else ...[
                if (out.isEmpty)
                  const Text('Aucune transition sortante.')
                else
                  for (final e in out)
                    _edgeRow(
                      e.isLoop ? '↻ reste sur la page' : '→ ${e.to}',
                      e,
                      e.isLoop ? null : e.to,
                    ),
                if (inn.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Depuis :', style: theme.textTheme.labelMedium),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final from in {for (final e in inn) e.from})
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(from),
                          onPressed: () => _select(from, center: true),
                        ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _edgeRow(String target, GraphEdge e, String? goTo) {
    final what = e.labels.join(', ');
    return InkWell(
      onTap: goTo == null ? null : () => _select(goTo, center: true),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          '$target   $what${e.conditional ? '  (sous condition)' : ''}',
        ),
      ),
    );
  }
}

class _NodeBox extends StatelessWidget {
  const _NodeBox({
    required this.node,
    required this.selected,
    required this.marked,
    required this.matched,
    required this.dimmed,
    required this.onTap,
  });

  final GraphNode node;
  final bool selected;
  final bool marked;
  final bool matched;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = node.isStart
        ? scheme.primaryContainer
        : node.isProgram
        ? scheme.tertiaryContainer
        : scheme.surfaceContainerHighest;
    final border = selected
        ? scheme.primary
        : marked
        ? scheme.error
        : matched
        ? scheme.tertiary
        : node.unreachable
        ? scheme.error.withValues(alpha: 0.6)
        : scheme.outline;
    return Opacity(
      opacity: dimmed ? 0.35 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          key: Key('node-${node.name}'),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: border,
              width: selected || marked || matched ? 3 : 1.2,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  node.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: node.isStart ? FontWeight.bold : null,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              if (node.isStart) _badge(Icons.play_arrow, 'départ'),
              if (node.requiresLogin && !node.implicitLogin)
                _badge(Icons.lock_outline, 'réservée aux connectés'),
              if (node.isProgram) _badge(Icons.terminal, 'programme'),
              if (!node.hasInput && !node.isProgram)
                _badge(Icons.block, 'impasse'),
              if (node.unreachable) _badge(Icons.link_off, 'inaccessible'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(IconData icon, String tip) => Padding(
    padding: const EdgeInsets.only(left: 3),
    child: Tooltip(message: tip, child: Icon(icon, size: 15)),
  );
}

class _EdgesPainter extends CustomPainter {
  _EdgesPainter({
    required this.graph,
    required this.layout,
    required this.selected,
    required this.hideBack,
    required this.scheme,
  });

  final ServiceGraph graph;
  final GraphLayout layout;
  final String? selected;
  final bool hideBack;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final labels = <(Offset, String, Color)>[];
    // Les arêtes de la sélection en dernier : elles passent par-dessus.
    final ordered = [
      ...graph.edges.where((e) => !_active(e)),
      ...graph.edges.where(_active),
    ];
    for (final e in ordered) {
      if (e.isLoop) continue;
      final from = layout.rects[e.from];
      final to = layout.rects[e.to];
      if (from == null || to == null) continue;
      final back = layout.isBack(e);
      if (back && hideBack && !_active(e)) continue;
      final active = _active(e);
      final dim = selected != null && !active;
      final color = active
          ? scheme.primary
          : scheme.outline.withValues(alpha: dim ? 0.12 : (back ? 0.35 : 0.6));
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 2.4 : 1.2;

      final Offset p0, p1, c0, c1;
      if (back) {
        final lift =
            50.0 + 9 * (layout.layers[e.from]! - layout.layers[e.to]!).abs();
        p0 = from.topCenter;
        p1 = to.topCenter;
        c0 = p0 + Offset(0, -lift);
        c1 = p1 + Offset(0, -lift);
      } else {
        p0 = from.centerRight;
        p1 = to.centerLeft;
        final dx = max(40.0, (p1.dx - p0.dx) / 2);
        c0 = p0 + Offset(dx, 0);
        c1 = p1 - Offset(dx, 0);
      }
      final path = Path()
        ..moveTo(p0.dx, p0.dy)
        ..cubicTo(c0.dx, c0.dy, c1.dx, c1.dy, p1.dx, p1.dy);
      if (e.conditional || e.kind != EdgeKind.rule) {
        _dashed(canvas, path, paint);
      } else {
        canvas.drawPath(path, paint);
      }
      _arrow(canvas, p1, c1, color, active ? 9 : 6);
      if (active) {
        final mid = _cubic(p0, c0, c1, p1, 0.5);
        labels.add((mid, _short(e.labels.join(', ')), color));
      }
    }
    for (final (at, text, color) in labels) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(fontSize: 11, color: scheme.onSurface),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final box = Rect.fromCenter(
        center: at,
        width: tp.width + 8,
        height: tp.height + 4,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(4)),
        Paint()..color = scheme.surface,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(4)),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke,
      );
      tp.paint(canvas, box.topLeft + const Offset(4, 2));
      tp.dispose();
    }
  }

  bool _active(GraphEdge e) =>
      selected != null && (e.from == selected || e.to == selected);

  String _short(String s) => s.length > 34 ? '${s.substring(0, 33)}…' : s;

  Offset _cubic(Offset a, Offset b, Offset c, Offset d, double t) {
    final u = 1 - t;
    return a * (u * u * u) +
        b * (3 * u * u * t) +
        c * (3 * u * t * t) +
        d * (t * t * t);
  }

  void _arrow(
    Canvas canvas,
    Offset tip,
    Offset from,
    Color color,
    double size,
  ) {
    final d = tip - from;
    if (d.distance == 0) return;
    final u = d / d.distance;
    final n = Offset(-u.dy, u.dx);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        (tip - u * size + n * size / 2).dx,
        (tip - u * size + n * size / 2).dy,
      )
      ..lineTo(
        (tip - u * size - n * size / 2).dx,
        (tip - u * size - n * size / 2).dy,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _dashed(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 12) {
        canvas.drawPath(
          metric.extractPath(d, min(d + 7, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_EdgesPainter old) =>
      old.graph != graph ||
      old.layout != layout ||
      old.selected != selected ||
      old.hideBack != hideBack ||
      old.scheme != scheme;
}
