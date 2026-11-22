import 'package:flutter/material.dart';
import 'package:minserve_core/minserve_core.dart' show isValidVariableName;

import 'service_edit.dart';

/// Ce qu'on a demandé pour extraire des instructions en minget.
class ExtractRequest {
  const ExtractRequest(this.name, this.description, this.params);

  final String name;
  final String? description;
  final List<ExtractParam> params;
}

/// Demande le nom du minget à créer et celles des [values] des instructions qui
/// deviennent des paramètres. Rend `null` si on annule.
Future<ExtractRequest?> askExtraction(
  BuildContext context, {
  required List<ExtractValue> values,
  required Iterable<String> existing,
  required int count,
}) => showDialog<ExtractRequest>(
  context: context,
  builder: (context) => _ExtractDialog(values, existing.toList(), count),
);

class _ExtractDialog extends StatefulWidget {
  const _ExtractDialog(this.values, this.existing, this.count);

  final List<ExtractValue> values;
  final List<String> existing;
  final int count;

  @override
  State<_ExtractDialog> createState() => _ExtractDialogState();
}

class _ExtractDialogState extends State<_ExtractDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  late final _use = List.filled(widget.values.length, false);
  late final _names = [
    for (final v in widget.values) TextEditingController(text: v.name),
  ];

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    for (final c in _names) {
      c.dispose();
    }
    super.dispose();
  }

  String? get _nameError {
    final text = _name.text.trim();
    return text.isEmpty ? null : macroNameError(text, widget.existing);
  }

  /// Pourquoi le nom du paramètre [i] ne convient pas, ou `null`.
  String? _paramError(int i) {
    if (!_use[i]) return null;
    final name = _names[i].text.trim();
    if (!isValidVariableName(name)) return 'Nom invalide';
    for (var j = 0; j < _names.length; j++) {
      if (j != i && _use[j] && _names[j].text.trim() == name) {
        return 'Déjà utilisé';
      }
    }
    return null;
  }

  bool get _ok =>
      _name.text.trim().isNotEmpty &&
      _nameError == null &&
      [for (var i = 0; i < _use.length; i++) _paramError(i)]
          .every((e) => e == null);

  void _submit() {
    if (!_ok) return;
    Navigator.pop(
      context,
      ExtractRequest(_name.text.trim(), _description.text, [
        for (var i = 0; i < _use.length; i++)
          if (_use[i]) ExtractParam(widget.values[i], _names[i].text.trim()),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(
        'Extraire ${widget.count} instruction${widget.count > 1 ? 's' : ''} '
        'en minget',
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('extract-name'),
                controller: _name,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Nom du minget',
                  errorText: _nameError,
                ),
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                key: const Key('extract-description'),
                controller: _description,
                decoration: const InputDecoration(
                  labelText: 'Description (facultatif)',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.values.isEmpty
                    ? 'Ces instructions n\'ont pas de valeur à rendre variable.'
                    : 'Valeurs qui varieront d\'un appel à l\'autre (cochez) :',
                style: theme.textTheme.labelLarge,
              ),
              for (var i = 0; i < widget.values.length; i++)
                Row(
                  children: [
                    Checkbox(
                      key: Key('extract-use-$i'),
                      value: _use[i],
                      onChanged: (v) => setState(() => _use[i] = v ?? false),
                    ),
                    Expanded(
                      flex: 5,
                      child: Text(
                        '${widget.values[i].item + 1} · '
                        '${widget.values[i].path.join('.')} = '
                        '${widget.values[i].value}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 4,
                      child: TextField(
                        key: Key('extract-pname-$i'),
                        controller: _names[i],
                        enabled: _use[i],
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: 'paramètre',
                          errorText: _paramError(i),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('dialog-ok'),
          onPressed: _ok ? _submit : null,
          child: const Text('Extraire'),
        ),
      ],
    );
  }
}
