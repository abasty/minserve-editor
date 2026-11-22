import 'package:flutter/material.dart';
import 'package:minserve_core/minserve_core.dart' show isValidVariableName;

import '../graph/page_lines.dart';

final _reference = RegExp(r'(?<!\$)\$\{([A-Za-z_][A-Za-z0-9_]{0,31})\}');

/// Les variables `${nom}` citées dans [text] (`$${` n'en est pas une).
Set<String> variableNames(String text) => {
  for (final m in _reference.allMatches(text)) m.group(1)!,
};

/// Les variables citées par la page [page] du service [text] (`here`), et
/// celles que cite le reste du service, macros comprises (`elsewhere`).
({List<String> here, List<String> elsewhere}) variablesFor(
  String text,
  String page,
) {
  final lines = pageLines(text);
  final start = lines[page];
  if (start == null) {
    return (here: const [], elsewhere: variableNames(text).toList()..sort());
  }
  final after = [
    for (final l in lines.values)
      if (l > start) l,
  ]..sort();
  final all = text.split('\n');
  final end = after.isEmpty ? all.length : after.first - 1;
  final here = variableNames(all.sublist(start - 1, end).join('\n'));
  final elsewhere = variableNames(text).difference(here);
  return (here: here.toList()..sort(), elsewhere: elsewhere.toList()..sort());
}

/// Le panneau des données de test : une valeur par variable, pour voir la page
/// remplie. Ces valeurs ne sont pas dans le `service.yaml` : l'éditeur les
/// garde le temps de la session.
class TestDataPanel extends StatefulWidget {
  const TestDataPanel({
    super.key,
    required this.here,
    required this.elsewhere,
    required this.values,
    required this.onChanged,
  });

  final List<String> here;
  final List<String> elsewhere;
  final Map<String, String> values;

  /// Une valeur change ; `null` retire la variable ajoutée à la main.
  final void Function(String name, String? value) onChanged;

  @override
  State<TestDataPanel> createState() => _TestDataPanelState();
}

class _TestDataPanelState extends State<TestDataPanel> {
  final _newName = TextEditingController();

  @override
  void dispose() {
    _newName.dispose();
    super.dispose();
  }

  String? get _newError {
    final name = _newName.text.trim();
    if (name.isEmpty) return null;
    if (!isValidVariableName(name)) return 'Nom invalide';
    if (widget.here.contains(name) ||
        widget.elsewhere.contains(name) ||
        widget.values.containsKey(name)) {
      return 'Déjà dans la liste';
    }
    return null;
  }

  void _add() {
    final name = _newName.text.trim();
    if (name.isEmpty || _newError != null) return;
    widget.onChanged(name, '');
    _newName.clear();
    setState(() {});
  }

  Widget _field(String name, {bool removable = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        key: Key('test-var-$name'),
        initialValue: widget.values[name] ?? '',
        decoration: InputDecoration(
          labelText: '\${$name}',
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: removable
              ? IconButton(
                  key: Key('test-var-remove-$name'),
                  tooltip: 'Retirer',
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => widget.onChanged(name, null),
                )
              : null,
        ),
        onChanged: (v) => widget.onChanged(name, v),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final known = {...widget.here, ...widget.elsewhere};
    final added = [
      for (final n in widget.values.keys)
        if (!known.contains(n)) n,
    ];
    return Material(
      key: const Key('test-data'),
      color: theme.colorScheme.surfaceContainerLow,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('Données de test', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Valeurs des variables pour l\'aperçu. Elles ne sont pas '
            'enregistrées dans le service.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          if (widget.here.isNotEmpty) ...[
            Text('Dans cette page', style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            for (final n in widget.here) _field(n),
          ],
          if (widget.elsewhere.isNotEmpty) ...[
            Text(
              'Ailleurs dans le service',
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 6),
            for (final n in widget.elsewhere) _field(n),
          ],
          if (added.isNotEmpty) ...[
            Text('Ajoutées', style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            for (final n in added) _field(n, removable: true),
          ],
          if (known.isEmpty && added.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Aucune variable citée dans le service.'),
            ),
          TextField(
            key: const Key('test-var-new'),
            controller: _newName,
            decoration: InputDecoration(
              labelText: 'Nouvelle variable',
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: _newError,
              suffixIcon: IconButton(
                key: const Key('test-var-add'),
                tooltip: 'Ajouter',
                icon: const Icon(Icons.add, size: 18),
                onPressed: _add,
              ),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _add(),
          ),
        ],
      ),
    );
  }
}
