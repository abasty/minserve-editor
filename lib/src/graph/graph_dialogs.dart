import 'package:flutter/material.dart';

import 'service_edit.dart';

/// Demande un nom de page. Rend `null` si on annule.
Future<String?> askPageName(
  BuildContext context, {
  required String title,
  required String action,
  required Iterable<String> existing,
  String initial = '',
  String label = 'Nom de la page',
  bool allowInitial = false,
  String? Function(String name, Iterable<String> existing)? check,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _NameDialog(
      title: title,
      action: action,
      existing: existing,
      initial: initial,
      label: label,
      allowInitial: allowInitial,
      check: check ?? pageNameError,
    ),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.action,
    required this.existing,
    required this.initial,
    required this.label,
    required this.allowInitial,
    required this.check,
  });

  final String label;

  /// Accepter le nom proposé tel quel (une copie : le nom est une suggestion).
  final bool allowInitial;
  final String? Function(String name, Iterable<String> existing) check;
  final String title;
  final String action;
  final Iterable<String> existing;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? get _error {
    final text = _name.text.trim();
    if (text == widget.initial && !widget.allowInitial) return null;
    return widget.check(text, widget.existing);
  }

  bool get _ok =>
      (widget.allowInitial || _name.text.trim() != widget.initial) &&
      _error == null;

  void _submit() {
    if (_ok) Navigator.pop(context, _name.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final showError = _name.text.isNotEmpty ? _error : null;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('page-name'),
        controller: _name,
        autofocus: true,
        decoration: InputDecoration(
          labelText: widget.label,
          errorText: showError,
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('dialog-ok'),
          onPressed: _ok ? _submit : null,
          child: Text(widget.action),
        ),
      ],
    );
  }
}

/// Une règle à ajouter : où elle mène, avec quelle touche, et quelle saisie.
class RuleSpec {
  const RuleSpec(this.to, this.key, this.choice);

  final String to;
  final String key;
  final String? choice;
}

/// Demande une règle pour la page [from]. Rend `null` si on annule.
Future<RuleSpec?> askRule(
  BuildContext context, {
  required String from,
  required List<String> pages,
}) {
  return showDialog<RuleSpec>(
    context: context,
    builder: (context) => _RuleDialog(from: from, pages: pages),
  );
}

class _RuleDialog extends StatefulWidget {
  const _RuleDialog({required this.from, required this.pages});

  final String from;
  final List<String> pages;

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  final _choice = TextEditingController();
  late String _to = widget.pages.firstWhere(
    (p) => p != widget.from,
    orElse: () => widget.pages.first,
  );
  String _key = 'envoi';

  @override
  void dispose() {
    _choice.dispose();
    super.dispose();
  }

  void _submit() {
    final choice = _choice.text.trim();
    Navigator.pop(context, RuleSpec(_to, _key, choice.isEmpty ? null : choice));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Nouvelle transition depuis « ${widget.from} »'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              key: const Key('rule-to'),
              initialValue: _to,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Va vers la page'),
              items: [
                for (final p in widget.pages)
                  DropdownMenuItem(value: p, child: Text(p)),
              ],
              onChanged: (v) => setState(() => _to = v ?? _to),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: const Key('rule-key'),
              initialValue: _key,
              decoration: const InputDecoration(labelText: 'Touche'),
              items: [
                for (final k in ruleKeys)
                  DropdownMenuItem(value: k, child: Text(k.toUpperCase())),
              ],
              onChanged: (v) => setState(() => _key = v ?? _key),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('rule-choice'),
              controller: _choice,
              decoration: const InputDecoration(
                labelText: 'Saisie (facultatif)',
                helperText:
                    'Ce que le visiteur tape avant la touche, ex. « 1 »',
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('dialog-ok'),
          onPressed: _submit,
          child: const Text('Ajouter'),
        ),
      ],
    );
  }
}

/// Demande confirmation. Rend vrai si on confirme.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('dialog-ok'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}
