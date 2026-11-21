import 'dart:math';

import 'package:flutter/material.dart';

import 'graph_dialogs.dart';
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
class GraphPanel extends StatefulWidget {
  const GraphPanel({
    super.key,
    required this.graph,
    required this.layout,
    this.onGoToPage,
    this.editing,
    this.stale,
  });

  final ServiceGraph graph;
  final GraphLayout layout;

  /// Demande d'aller à la déclaration de la page dans le texte.
  final void Function(String page)? onGoToPage;

  /// De quoi modifier le service depuis le graphe ; `null` : lecture seule.
  final GraphEditing? editing;

  /// Si le texte n'est plus valide : pourquoi ce graphe est celui d'avant.
  final String? stale;

  @override
  State<GraphPanel> createState() => _GraphPanelState();
}

class _GraphPanelState extends State<GraphPanel> {
  final _view = TransformationController();
  final _search = TextEditingController();
  Size _viewport = Size.zero;
  bool _fitted = false;
  String? _selected;
  bool _hideBack = false;
  Set<String> _marked = {};
  String _markedBy = '';

  /// Page à sélectionner dès qu'elle apparaît dans le graphe (créée ou
  /// renommée depuis ici).
  String? _pending;

  @override
  void dispose() {
    _view.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(GraphPanel old) {
    super.didUpdateWidget(old);
    final pending = _pending;
    if (pending != null && widget.graph.nodes.containsKey(pending)) {
      _pending = null;
      _selected = pending;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _center(pending);
      });
    }
    if (!widget.graph.nodes.containsKey(_selected)) _selected = null;
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
    setState(() => _selected = name);
    if (center && name != null) _center(name);
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

  Future<void> _removeRule(GraphEdge e, GraphRule rule) async {
    final editing = widget.editing!;
    var only = false;
    try {
      only = isOnlyRule(editing.text(), e.from);
    } on EditException {
      only = false;
    }
    if (only) {
      final ok = await confirmDialog(
        context,
        title: 'Supprimer la dernière règle de « ${e.from} » ?',
        body:
            'Une saisie ne peut pas rester sans règle : la page perd aussi sa '
            'zone de saisie (entree et action).',
        action: 'Supprimer',
      );
      if (!ok || !mounted) return;
    }
    editing.apply((t) => removeRule(t, e.from, rule.index, e.to));
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
        if (_selected != null) _details(_selected!),
      ],
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
                onTap: () => _select(node.name),
              ),
            ),
        ],
      ),
    );
  }

  Widget _details(String name) {
    final graph = widget.graph;
    final node = graph.nodes[name]!;
    final out = graph.outgoing(name).toList();
    final inn = graph.incoming(name).where((e) => !e.isLoop).toList();
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 190),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            key: const Key('details'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(name, style: theme.textTheme.titleMedium),
                  ),
                  if (widget.onGoToPage != null)
                    TextButton.icon(
                      onPressed: () => widget.onGoToPage!(name),
                      icon: const Icon(Icons.code, size: 18),
                      label: const Text('Aller au texte'),
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
              const SizedBox(height: 6),
              if (out.isEmpty)
                const Text('Aucune transition sortante.')
              else
                for (final e in out)
                  _edgeRow(
                    e.isLoop ? '↻ reste sur la page' : '→ ${e.to}',
                    e,
                    e.isLoop ? null : e.to,
                  ),
              if (widget.editing != null && !node.isProgram)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('add-rule'),
                    onPressed: () => _addRule(name),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Ajouter une transition'),
                  ),
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
          ),
        ),
      ),
    );
  }

  Widget _edgeRow(String target, GraphEdge e, String? goTo) {
    final what = e.labels.join(', ');
    final editable = widget.editing != null && e.rules.isNotEmpty;
    final line = InkWell(
      onTap: goTo == null ? null : () => _select(goTo, center: true),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          editable
              ? target
              : '$target   $what${e.conditional ? '  (sous condition)' : ''}',
        ),
      ),
    );
    if (!editable) return line;
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        line,
        for (final r in e.rules)
          InputChip(
            key: Key('rule-${e.from}-${r.index}'),
            visualDensity: VisualDensity.compact,
            label: Text('${r.label}${r.conditional ? ' (si)' : ''}'),
            deleteButtonTooltipMessage: 'Supprimer cette règle',
            onDeleted: () => _removeRule(e, r),
          ),
      ],
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
