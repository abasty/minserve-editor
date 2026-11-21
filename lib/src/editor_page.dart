import 'dart:async';

import 'package:flutter/material.dart';

import 'code_editor.dart';
import 'diagnostics.dart';
import 'file_access.dart';
import 'version.dart';

/// Texte d'un nouveau service.
const newServiceText = '''debut: accueil
pages:
  accueil:
    ecran:
      - efface
      - ecrit: "Bonjour !"
''';

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
  String _name = 'service.yaml';
  late String _saved = widget.initialText;

  bool get _dirty => _text.text != _saved;

  @override
  void initState() {
    super.initState();
    _text.addListener(_edited);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _text.dispose();
    super.dispose();
  }

  String _lastSeen = '';

  void _edited() {
    // Le contrôleur prévient aussi des déplacements du curseur.
    if (_text.text == _lastSeen) return;
    _lastSeen = _text.text;
    _timer?.cancel();
    _timer = Timer(_diagnoseDelay, () {
      if (mounted) setState(() => _diagnostics = diagnose(_text.text));
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
      _diagnostics = diagnose(text);
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
      body: Column(
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
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
      ),
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
