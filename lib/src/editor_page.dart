import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'assets.dart';
import 'code_editor.dart';
import 'diagnostics.dart';
import 'file_access.dart';
import 'graph/graph_panel.dart';
import 'history.dart';
import 'settings.dart';
import 'split_handle.dart';
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
    FileAccess? files,
    this.initialFile,
    this.startupMessage,
    this.guardClose = false,
    this.settings,
  }) : files = files ?? const BrowserFileAccess();

  final FileAccess files;

  /// Ce que l'éditeur retient d'une fois sur l'autre (fichiers récents, dossier
  /// assets de chaque service).
  final AppSettings? settings;

  /// Le fichier à montrer au départ (nommé sur la ligne de commande) ; sinon
  /// un nouveau service.
  final OpenedFile? initialFile;

  /// Un message à montrer au départ (le fichier de la ligne de commande n'a pas
  /// pu être lu, par exemple).
  final String? startupMessage;

  /// Vrai sur le bureau : la fermeture de la fenêtre demande confirmation
  /// s'il reste des modifications non enregistrées.
  final bool guardClose;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final _settings = widget.settings ?? AppSettings();
  late final _text = TextEditingController(text: _initialText);
  final _commands = CodeEditorController();
  Timer? _timer;
  late Diagnostics _diagnostics = diagnose(_initialText);
  ViewMode _mode = ViewMode.both;

  /// Le graphe du dernier texte valide : il reste affiché tant que le texte
  /// est invalide.
  ServiceGraph? _graph;
  GraphLayout? _layout;
  late String _name = widget.initialFile?.name ?? 'service.yaml';

  /// Le chemin du fichier ouvert, sur le bureau : « Enregistrer » le réécrit.
  late String? _path = widget.initialFile?.path;
  late String _saved = _initialText;
  AppLifecycleListener? _exitListener;

  String get _initialText => widget.initialFile?.text ?? newServiceText;

  bool get _dirty => _text.text != _saved;

  @override
  void initState() {
    super.initState();
    _text.addListener(_edited);
    FocusManager.instance.addListener(_focusChanged);
    _useGraph(_diagnostics);
    if (widget.guardClose) {
      // Le moteur du bureau transmet la fermeture de la fenêtre au cadre
      // d'application, qui la demande ici.
      _exitListener = AppLifecycleListener(
        onExitRequested: () async => await _confirmDiscard()
            ? AppExitResponse.exit
            : AppExitResponse.cancel,
      );
    }
    final path = _path;
    if (path != null) _settings.addRecent(path);
    _watchPath();
    final message = widget.startupMessage;
    if (message != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tell(message));
    }
  }

  void _tell(String message) {
    if (!mounted) return;
    // Assez long pour être lu, et à fermer à la main.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 12),
        showCloseIcon: true,
      ),
    );
  }

  /// Un champ qui se ferme (Entrée dans un formulaire, par exemple) laisse le
  /// focus à personne : sans lui, Ctrl+Z n'arrive plus à la page. On le rend à
  /// la page.
  void _focusChanged() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null && focus is! FocusScopeNode) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final now = FocusManager.instance.primaryFocus;
      if (now == null || now is FocusScopeNode) _pageFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _typingTimer?.cancel();
    FocusManager.instance.removeListener(_focusChanged);
    _exitListener?.dispose();
    _watch?.cancel();
    _pageFocus.dispose();
    _text.dispose();
    super.dispose();
  }

  late String _lastSeen = _initialText;
  TextSelection _lastSelection = const TextSelection.collapsed(offset: 0);

  final _history = EditHistory();

  /// Part de la largeur donnée au texte quand texte et graphe sont côte à côte
  /// (réglée en tirant la poignée entre les deux).
  double _textShare = 0.5;
  double _shareAtDragStart = 0.5;
  static const _minPane = 260.0;

  /// Reçoit les touches quand rien d'autre n'a le focus (graphe seul, par
  /// exemple), pour que Ctrl+Z et Ctrl+Y marchent partout.
  final _pageFocus = FocusNode(debugLabel: 'page');

  /// Vrai pendant une série de frappes : elle ne fait qu'une étape d'historique.
  bool _typing = false;
  Timer? _typingTimer;
  static const _typingPause = Duration(seconds: 1);

  Snapshot get _snapshot => Snapshot(_text.text, _text.selection);

  void _restore(Snapshot s) {
    _timer?.cancel();
    _typingTimer?.cancel();
    _typing = false;
    _lastSeen = s.text;
    final end = s.text.length;
    _text.value = TextEditingValue(
      text: s.text,
      selection: s.selection.isValid
          ? TextSelection(
              baseOffset: s.selection.baseOffset.clamp(0, end),
              extentOffset: s.selection.extentOffset.clamp(0, end),
            )
          : TextSelection.collapsed(offset: end),
    );
    setState(() => _setDiagnostics(s.text));
  }

  void _undoEdit() {
    final s = _history.undo(_snapshot);
    if (s != null) _restore(s);
  }

  void _redoEdit() {
    final s = _history.redo(_snapshot);
    if (s != null) _restore(s);
  }

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

  void _goToPage(String name, {String? section, int? rule}) {
    final line = pageSectionLine(
      _text.text,
      name,
      section: section,
      rule: rule,
    );
    if (line == null) return;
    // En vue « graphe » seule, il faut montrer le texte pour y aller.
    if (_mode == ViewMode.graph) setState(() => _mode = ViewMode.both);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _commands.goToLine(line),
    );
  }

  void _goToMacro(String name) {
    final line = macroLines(_text.text)[name];
    if (line == null) return;
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
    // Une modification qui ne change rien (un champ validé deux fois, par
    // Entrée puis en perdant le focus) n'est pas une étape d'historique.
    if (result == _text.text) return true;
    // Le graphe suit tout de suite, sans attendre la fin d'une frappe.
    _history.record(_snapshot);
    _typing = false;
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

  /// Largeur du texte dans [total] pixels : la part choisie, sans qu'aucun des
  /// deux volets ne devienne trop étroit.
  double _textWidthIn(double total) {
    final usable = total - SplitHandle.thickness;
    final width = (usable * _textShare).clamp(_minPane, usable - _minPane);
    return width.toDouble();
  }

  void _edited() {
    // Le contrôleur prévient aussi des déplacements du curseur.
    if (_text.text == _lastSeen) {
      _lastSelection = _text.selection;
      return;
    }
    // Une série de frappes ne fait qu'une étape ; un changement de nombre de
    // lignes (Entrée, collage) en commence une autre.
    final lines = '\n'.allMatches(_text.text).length;
    final before = '\n'.allMatches(_lastSeen).length;
    if (!_typing || lines != before) {
      _history.record(Snapshot(_lastSeen, _lastSelection));
      _typing = true;
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(_typingPause, () => _typing = false);
    _lastSeen = _text.text;
    _lastSelection = _text.selection;
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

  void _load(String name, String text, {String? path}) {
    _timer?.cancel();
    _typingTimer?.cancel();
    _typing = false;
    _lastSeen = text;
    _text.text = text;
    _typingTimer?.cancel();
    _typing = false;
    _history.clear();
    setState(() {
      _name = name;
      _path = path;
      _saved = text;
      _seenOnDisk = null;
      _setDiagnostics(text);
    });
    if (path != null) _settings.addRecent(path);
    _watchPath();
  }

  /// Le fichier ouvert est surveillé : quelqu'un d'autre (un autre éditeur, git)
  /// peut le changer.
  StreamSubscription<void>? _watch;
  String? _watched;

  /// Le dernier texte vu sur le disque et laissé de côté (« garder ma version ») :
  /// on ne redemande pas pour le même.
  String? _seenOnDisk;
  bool _asking = false;

  void _watchPath() {
    if (_path == _watched) return;
    _watch?.cancel();
    _watch = null;
    _watched = _path;
    final path = _path;
    if (path != null) {
      _watch = widget.files.changes(path)?.listen((_) => _diskChanged(path));
    }
  }

  Future<void> _diskChanged(String path) async {
    if (_asking || !mounted || path != _path) return;
    final OpenedFile? disk;
    try {
      disk = await widget.files.openPath(path);
    } on FileAccessException {
      return;
    }
    if (disk == null || !mounted || path != _path) return;
    // Notre propre enregistrement, ou un texte déjà vu : rien à faire.
    if (disk.text == _saved || disk.text == _seenOnDisk) return;
    if (!_dirty) {
      _load(disk.name, disk.text, path: path);
      _tell('« ${disk.name} » a changé sur le disque : rechargé.');
      return;
    }
    _asking = true;
    final reload = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Le fichier a changé sur le disque'),
        content: Text(
          '« ${disk!.name} » a été modifié ailleurs, et vous avez des '
          'modifications non enregistrées. Recharger les perd.',
        ),
        actions: [
          TextButton(
            key: const Key('keep-mine'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Garder ma version'),
          ),
          FilledButton(
            key: const Key('reload-disk'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Recharger'),
          ),
        ],
      ),
    );
    _asking = false;
    if (!mounted || path != _path) return;
    if (reload == true) {
      _load(disk.name, disk.text, path: path);
    } else {
      _seenOnDisk = disk.text;
    }
  }

  Future<void> _openRecent(String path) async {
    if (!await _confirmDiscard()) return;
    try {
      final file = await widget.files.openPath(path);
      if (file == null) {
        _settings.removeRecent(path);
        if (mounted) setState(() {});
        _tell('Fichier introuvable : $path');
        return;
      }
      _load(file.name, file.text, path: file.path);
    } on FileAccessException catch (e) {
      _tell(e.message);
    }
  }

  AssetSource? get _assetSource => widget.files.assetsFor(
    _path,
    folder: _path == null ? null : _settings.assetsFolders[_path],
  );

  AssetsSetup? get _assetsSetup => _path == null || !widget.files.savesInPlace
      ? null
      : AssetsSetup(
          custom: _settings.assetsFolders.containsKey(_path),
          choose: () async {
            final folder = await widget.files.chooseFolder(_assetSource?.label);
            if (folder == null || _path == null) return null;
            _settings.setAssetsFolder(_path!, folder);
            if (mounted) setState(() {});
            return _assetSource;
          },
          reset: () {
            if (_path != null) _settings.setAssetsFolder(_path!, null);
            if (mounted) setState(() {});
            return _assetSource;
          },
        );

  Future<void> _new() async {
    if (await _confirmDiscard()) _load('service.yaml', newServiceText);
  }

  Future<void> _open() async {
    if (!await _confirmDiscard()) return;
    try {
      final file = await widget.files.open();
      if (file != null) _load(file.name, file.text, path: file.path);
    } on FileAccessException catch (e) {
      _tell(e.message);
    }
  }

  /// Enregistre le texte : en place si on connaît le fichier (bureau), sinon
  /// la personne choisit le nom. [saveAs] demande toujours le nom.
  Future<void> _save({bool saveAs = false}) async {
    final text = _text.text;
    try {
      final file = await widget.files.save(
        _name,
        text,
        path: _path,
        saveAs: saveAs,
      );
      if (file == null || !mounted) return;
      setState(() {
        _saved = text;
        _name = file.name;
        _path = file.path;
      });
      final saved = file.path;
      if (saved != null) _settings.addRecent(saved);
      _watchPath();
    } on FileAccessException catch (e) {
      _tell(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Title(
      // Le titre de la fenêtre (ou de l'onglet) : le fichier, et un point s'il
      // reste des modifications à enregistrer.
      title: '${_dirty ? '• ' : ''}$_name — Minserve Editor',
      color: scheme.primary,
      child: AssetsScope(
        source: _assetSource,
        setup: _assetsSetup,
        child: CallbackShortcuts(
          // Notre historique remplace celui du champ de texte, qui ne voit pas les
          // modifications du graphe.
          bindings: {
            for (final m in [
              (control: true, meta: false),
              (control: false, meta: true),
            ]) ...{
              SingleActivator(
                LogicalKeyboardKey.keyZ,
                control: m.control,
                meta: m.meta,
              ): _undoEdit,
              SingleActivator(
                LogicalKeyboardKey.keyY,
                control: m.control,
                meta: m.meta,
              ): _redoEdit,
              SingleActivator(
                LogicalKeyboardKey.keyZ,
                control: m.control,
                meta: m.meta,
                shift: true,
              ): _redoEdit,
              SingleActivator(
                LogicalKeyboardKey.keyS,
                control: m.control,
                meta: m.meta,
              ): _save,
              SingleActivator(
                LogicalKeyboardKey.keyS,
                control: m.control,
                meta: m.meta,
                shift: true,
              ): () =>
                  _save(saveAs: true),
            },
          },
          child: Focus(
            focusNode: _pageFocus,
            autofocus: true,
            // Un clic hors d'un champ de texte rend le focus à la page.
            child: Listener(
              onPointerDown: (_) =>
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    final focus = FocusManager.instance.primaryFocus;
                    if (mounted && (focus == null || focus is FocusScopeNode)) {
                      _pageFocus.requestFocus();
                    }
                  }),
              child: Scaffold(
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
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
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
                      onSelectionChanged: (m) =>
                          setState(() => _mode = m.single),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      key: const Key('undo'),
                      tooltip: 'Défaire (Ctrl+Z)',
                      icon: const Icon(Icons.undo),
                      onPressed: _history.canUndo ? _undoEdit : null,
                    ),
                    IconButton(
                      key: const Key('redo'),
                      tooltip: 'Refaire (Ctrl+Y)',
                      icon: const Icon(Icons.redo),
                      onPressed: _history.canRedo ? _redoEdit : null,
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
                    if (widget.files.savesInPlace &&
                        _settings.recent.isNotEmpty)
                      PopupMenuButton<String>(
                        key: const Key('recent'),
                        tooltip: 'Fichiers récents',
                        icon: const Icon(Icons.history),
                        onSelected: (path) => path.isEmpty
                            ? setState(_settings.clearRecent)
                            : _openRecent(path),
                        itemBuilder: (context) => [
                          for (final path in _settings.recent)
                            PopupMenuItem(
                              key: Key('recent-$path'),
                              value: path,
                              child: Text(
                                path,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            key: Key('recent-clear'),
                            value: '',
                            child: Text('Vider la liste'),
                          ),
                        ],
                      ),
                    IconButton(
                      tooltip: 'Enregistrer',
                      icon: const Icon(Icons.save_alt),
                      onPressed: _save,
                    ),
                    if (widget.files.savesInPlace)
                      IconButton(
                        key: const Key('save-as'),
                        tooltip: 'Enregistrer sous…',
                        icon: const Icon(Icons.save_as),
                        onPressed: () => _save(saveAs: true),
                      ),
                    const SizedBox(width: 8),
                  ],
                ),
                body: LayoutBuilder(
                  builder: (context, box) {
                    final wide = box.maxWidth >= _splitWidth;
                    final shown = _mode == ViewMode.both && !wide
                        ? ViewMode.text
                        : _mode;
                    final graph = _graph;
                    // Les deux volets restent dans l'arbre (le texte garde son défilement,
                    // le graphe sa sélection) : celui qu'on ne montre pas a une largeur
                    // nulle.
                    final textWidth = switch (shown) {
                      ViewMode.text => box.maxWidth,
                      ViewMode.graph => 0.0,
                      ViewMode.both => _textWidthIn(box.maxWidth),
                    };
                    final graphWidth = switch (shown) {
                      ViewMode.text => 0.0,
                      ViewMode.graph => box.maxWidth,
                      ViewMode.both =>
                        box.maxWidth -
                            _textWidthIn(box.maxWidth) -
                            SplitHandle.thickness,
                    };
                    return Stack(
                      children: [
                        Positioned(
                          key: const ValueKey('pane-text'),
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
                            width: SplitHandle.thickness,
                            child: SplitHandle(
                              key: const Key('split-text-graph'),
                              axis: Axis.horizontal,
                              onStart: () => _shareAtDragStart = _textShare,
                              onDrag: (dx) => setState(
                                () => _textShare =
                                    _shareAtDragStart + dx / box.maxWidth,
                              ),
                            ),
                          ),
                        // Des clés : la poignée n'existe que dans un des modes, et sans
                        // elles le graphe serait reconstruit (et sa page ouverte
                        // perdue) à chaque changement de mode.
                        Positioned(
                          key: const ValueKey('pane-graph'),
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
                                    service: _diagnostics.service,
                                    onGoToPage: _goToPage,
                                    onGoToMacro: _goToMacro,
                                    editing: _diagnostics.isValid
                                        ? GraphEditing(
                                            text: () => _text.text,
                                            apply: _applyEdit,
                                          )
                                        : null,
                                    stale: _diagnostics.isValid
                                        ? null
                                        : _statusText(),
                                  ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
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
