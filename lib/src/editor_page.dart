import 'dart:async';

import 'package:flutter/material.dart';

import 'code_editor.dart';
import 'diagnostics.dart';
import 'file_access.dart';
import 'graph/graph_panel.dart';
import 'graph/layout.dart';
import 'graph/page_lines.dart';
import 'graph/service_edit.dart';
import 'graph/service_graph.dart';
import 'version.dart';

/// Texte d'un nouveau service.
const newServiceText = '''debut: accueil
pages:
  accueil:
    ecran:
      - efface
      - ecrit: "Bonjour !"
''';

/// Ce que l'écran montre : le texte, le graphe, ou les deux côte à côte (si la
/// place le permet).
enum ViewMode { text, graph, both }

/// Largeur à partir de laquelle texte et graphe tiennent côte à côte.
const _splitWidth = 900.0;

/// Délai entre la dernière frappe et la lecture du texte.
const _diagnoseDelay = Duration(milliseconds: 300);

/// L'écran de l'éditeur : le texte du service, et en dessous ce qu'en pense
/// le code du serveur.
class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    this.files = const BrowserFileAccess(),
    this.initialText = newServiceText,
  });

  final FileAccess files;
  final String initialText;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final _text = TextEditingController(text: widget.initialText);
  final _commands = CodeEditorController();
  Timer? _timer;
  late Diagnostics _diagnostics = diagnose(widget.initialText);
  ViewMode _mode = ViewMode.both;

  /// Le graphe du dernier texte valide : il reste affiché tant que le texte
  /// est invalide.
  ServiceGraph? _graph;
  GraphLayout? _layout;
  String _name = 'service.yaml';
  late String _saved = widget.initialText;

  bool get _dirty => _text.text != _saved;

  @override
  void initState() {
    super.initState();
    _text.addListener(_edited);
    _useGraph(_diagnostics);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _text.dispose();
    super.dispose();
  }

  String _lastSeen = '';

  void _useGraph(Diagnostics d) {
    final service = d.service;
    if (service == null) return;
    final graph = ServiceGraph.of(service);
    _graph = graph;
    _layout = layoutGraph(graph);
  }

  void _setDiagnostics(String text) {
    _diagnostics = diagnose(text);
    _useGraph(_diagnostics);
  }

  void _goToPage(String name) {
    final line = pageLines(_text.text)[name];
    if (line == null) return;
    // En vue « graphe » seule, il faut montrer le texte pour y aller.
    if (_mode == ViewMode.graph) setState(() => _mode = ViewMode.both);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _commands.goToLine(line),
    );
  }

  /// Modifie le texte à la demande du graphe. Rend faux, en disant pourquoi, si
  /// la modification est refusée : le texte n'a alors pas changé.
  bool _applyEdit(String Function(String text) edit) {
    final String result;
    try {
      result = edit(_text.text);
    } on EditException catch (e) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
      return false;
    }
    // Le graphe suit tout de suite, sans attendre la fin d'une frappe.
    _timer?.cancel();
    _lastSeen = result;
    final cursor = _text.selection.baseOffset.clamp(0, result.length);
    _text.value = TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: cursor),
    );
    setState(() => _setDiagnostics(result));
    return true;
  }

  void _edited() {
    // Le contrôleur prévient aussi des déplacements du curseur.
    if (_text.text == _lastSeen) return;
    _lastSeen = _text.text;
    _timer?.cancel();
    _timer = Timer(_diagnoseDelay, () {
      if (mounted) setState(() => _setDiagnostics(_text.text));
    });
    setState(() {});
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifications non enregistrées'),
        content: const Text('Elles seront perdues. Continuer ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _load(String name, String text) {
    _timer?.cancel();
    _text.text = text;
    _lastSeen = text;
    setState(() {
      _name = name;
      _saved = text;
      _setDiagnostics(text);
    });
  }

  Future<void> _new() async {
    if (await _confirmDiscard()) _load('service.yaml', newServiceText);
  }

  Future<void> _open() async {
    if (!await _confirmDiscard()) return;
    final file = await widget.files.open();
    if (file != null) _load(file.name, file.text);
  }

  Future<void> _save() async {
    final text = _text.text;
    await widget.files.save(_name, text);
    if (mounted) setState(() => _saved = text);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Minserve Editor  v$appVersion'),
        actions: [
          Center(
            child: Text(
              _dirty ? '$_name •' : _name,
              key: const Key('file-name'),
            ),
          ),
          const SizedBox(width: 8),
          SegmentedButton<ViewMode>(
            key: const Key('view-mode'),
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(
                value: ViewMode.text,
                icon: Icon(Icons.code),
                tooltip: 'Texte',
              ),
              ButtonSegment(
                value: ViewMode.both,
                icon: Icon(Icons.vertical_split),
                tooltip: 'Texte et graphe',
              ),
              ButtonSegment(
                value: ViewMode.graph,
                icon: Icon(Icons.account_tree_outlined),
                tooltip: 'Graphe',
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (m) => setState(() => _mode = m.single),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Nouveau',
            icon: const Icon(Icons.note_add_outlined),
            onPressed: _new,
          ),
          IconButton(
            tooltip: 'Ouvrir',
            icon: const Icon(Icons.folder_open),
            onPressed: _open,
          ),
          IconButton(
            tooltip: 'Enregistrer',
            icon: const Icon(Icons.save_alt),
            onPressed: _save,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= _splitWidth;
          final shown = _mode == ViewMode.both && !wide ? ViewMode.text : _mode;
          final graph = _graph;
          // Les deux volets restent dans l'arbre (le texte garde son défilement,
          // le graphe sa sélection) : celui qu'on ne montre pas a une largeur
          // nulle.
          final textWidth = switch (shown) {
            ViewMode.text => box.maxWidth,
            ViewMode.graph => 0.0,
            ViewMode.both => (box.maxWidth - 1) / 2,
          };
          final graphWidth = switch (shown) {
            ViewMode.text => 0.0,
            ViewMode.graph => box.maxWidth,
            ViewMode.both => (box.maxWidth - 1) / 2,
          };
          return Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: textWidth,
                child: Offstage(
                  offstage: textWidth == 0,
                  child: _textPane(scheme),
                ),
              ),
              if (shown == ViewMode.both)
                Positioned(
                  left: textWidth,
                  top: 0,
                  bottom: 0,
                  width: 1,
                  child: const VerticalDivider(width: 1),
                ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: graphWidth,
                child: Offstage(
                  offstage: graphWidth == 0,
                  child: graph == null
                      ? const Center(
                          child: Text(
                            "Aucun graphe : le texte n'est pas encore valide.",
                          ),
                        )
                      : GraphPanel(
                          graph: graph,
                          layout: _layout!,
                          onGoToPage: _goToPage,
                          editing: _diagnostics.isValid
                              ? GraphEditing(
                                  text: () => _text.text,
                                  apply: _applyEdit,
                                )
                              : null,
                          stale: _diagnostics.isValid ? null : _statusText(),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _textPane(ColorScheme scheme) {
    return Column(
      children: [
        Expanded(
          child: CodeEditor(
            controller: _text,
            commands: _commands,
            highlightLine: _diagnostics.line,
          ),
        ),
        Material(
          color: _diagnostics.isValid
              ? scheme.secondaryContainer
              : scheme.errorContainer,
          child: InkWell(
            key: const Key('status'),
            onTap: _diagnostics.line == null
                ? null
                : () => _commands.goToLine(_diagnostics.line!),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    _diagnostics.isValid
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_statusText())),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _statusText() {
    final service = _diagnostics.service;
    if (service != null) {
      final n = service.pages.length;
      return 'Service valide : $n page${n > 1 ? 's' : ''}, '
          'départ : ${service.start}';
    }
    final line = _diagnostics.line;
    return line == null
        ? _diagnostics.message!
        : 'ligne $line : ${_diagnostics.message}';
  }
}
