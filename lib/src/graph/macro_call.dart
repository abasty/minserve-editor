import 'package:flutter/material.dart';
import 'package:minserve_core/minserve_core.dart';
import 'package:yaml/yaml.dart';

import 'minget_panel.dart' show defaultMingetArgs, mingetParamTypes;

/// Un argument saisi : un entier s'il en est un, sinon le texte tel quel (le
/// serveur dit alors si ce n'est pas ce qu'il attend).
Object? parseMacroArg(MacroType? type, String text) {
  if (type == MacroType.texte) return text;
  return int.tryParse(text.trim()) ?? text;
}

/// Un argument écrit dans un appel : les textes entre guillemets, comme dans
/// les services.
String macroArgText(Object? value) =>
    value is String ? yamlString(value) : '$value';

final _plainName = RegExp(r'^[A-Za-z_][A-Za-z0-9_-]*$');

/// L'instruction qui appelle [macro] avec [args], écrite comme dans les
/// services : `macro: [nom, 12, "texte"]`. Les derniers arguments qui valent
/// la valeur par défaut de leur paramètre sont omis (la macro les complète) :
/// l'appel reste court.
String macroCallText(MacroDefinition macro, List<Object?> args) {
  var count = args.length;
  if (macro.extended) {
    while (count > 0 &&
        count <= macro.parameters.length &&
        macro.parameters[count - 1].defaultValue != null &&
        macro.parameters[count - 1].defaultValue == args[count - 1]) {
      count--;
    }
  }
  final name =
      _plainName.hasMatch(macro.name) &&
          !const {
            'true',
            'false',
            'null',
            'yes',
            'no',
            'on',
            'off',
            'y',
            'n',
          }.contains(macro.name.toLowerCase())
      ? macro.name
      : yamlString(macro.name);
  return 'macro: [${[name, for (var i = 0; i < count; i++) macroArgText(args[i])].join(', ')}]';
}

/// L'appel de macro écrit dans [itemText] (`macro: [nom, ...]`), ou `null` si
/// ce n'en est pas un.
({String name, List<Object?> args})? readMacroCall(String itemText) {
  try {
    final value = loadYaml(itemText);
    if (value is! YamlMap || value.length != 1) return null;
    final call = value['macro'];
    if (call is! YamlList || call.isEmpty || call.first is! String) {
      return null;
    }
    return (
      name: call.first as String,
      args: [for (final a in call.skip(1)) a],
    );
  } on YamlException {
    return null;
  }
}

/// Les arguments à montrer pour un appel de [macro] qui en donne [given] : ceux
/// de l'appel, complétés par les valeurs par défaut des paramètres omis.
List<Object?> fullMacroArgs(MacroDefinition macro, List<Object?> given) {
  final defaults = defaultMingetArgs(macro);
  return [
    for (var i = 0; i < macro.arity; i++)
      i < given.length ? given[i] : defaults[i],
    // Des arguments en trop (appel invalide) restent visibles.
    for (var i = macro.arity; i < given.length; i++) given[i],
  ];
}

/// Pourquoi [args] ne conviennent pas à [macro] d'après ses paramètres déclarés,
/// ou `null`. Une macro en liste d'instructions n'a rien à contrôler ici : c'est
/// le serveur qui dira.
String? macroArgsError(MacroDefinition macro, List<Object?> args) {
  if (!macro.extended) return null;
  try {
    checkMacroArguments(macro, args);
    return null;
  } on FormatException catch (e) {
    return e.message;
  }
}

/// Demande les arguments d'un appel de [macro] : un champ par paramètre, avec
/// la valeur par défaut. Rend les arguments, ou `null` si on annule.
Future<List<Object?>?> askMacroCall(
  BuildContext context,
  MacroDefinition macro,
) => showDialog<List<Object?>>(
  context: context,
  builder: (context) => _MacroCallDialog(macro),
);

class _MacroCallDialog extends StatefulWidget {
  const _MacroCallDialog(this.macro);

  final MacroDefinition macro;

  @override
  State<_MacroCallDialog> createState() => _MacroCallDialogState();
}

class _MacroCallDialogState extends State<_MacroCallDialog> {
  late final List<Object?> _args = defaultMingetArgs(widget.macro);

  @override
  Widget build(BuildContext context) {
    final m = widget.macro;
    final types = mingetParamTypes(m);
    final error = macroArgsError(m, _args);
    return AlertDialog(
      title: Text('Insérer « ${m.name} »'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (m.description != null) ...[
                Text(m.description!),
                const SizedBox(height: 8),
              ],
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < m.arity; i++)
                    _field(m.parameters[i], types[i], i),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error,
                  key: const Key('macro-call-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
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
          onPressed: error == null ? () => Navigator.pop(context, _args) : null,
          child: const Text('Insérer'),
        ),
      ],
    );
  }

  Widget _field(MacroParameter p, MacroType? type, int i) {
    final key = Key('macro-arg-$i');
    if (type == MacroType.booleen) {
      return SizedBox(
        width: 190,
        child: Row(
          children: [
            Expanded(child: Text(p.name)),
            Switch(
              key: key,
              value: _args[i] == true,
              onChanged: (v) => setState(() => _args[i] = v),
            ),
          ],
        ),
      );
    }
    final hint = [
      ?type?.label,
      if (p.min != null && p.max != null)
        '${p.min} à ${p.max}'
      else if (p.min != null)
        '≥ ${p.min}'
      else if (p.max != null)
        '≤ ${p.max}',
      ?p.description,
    ].join(' — ');
    return SizedBox(
      width: 190,
      child: TextFormField(
        key: key,
        initialValue: '${_args[i]}',
        keyboardType: type == MacroType.texte ? null : TextInputType.number,
        decoration: InputDecoration(
          labelText: p.name,
          helperText: hint.isEmpty ? null : hint,
          helperMaxLines: 2,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: (v) => setState(() => _args[i] = parseMacroArg(type, v)),
      ),
    );
  }
}
