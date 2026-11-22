import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import 'service_edit.dart';

/// Les formulaires d'une page : règles, saisie, accès. Chaque champ lit sa
/// valeur dans le texte et la réécrit seule : le reste de la page n'est pas
/// touché, et ce que le formulaire ne sait pas montrer reste dans le texte.

/// Applique une modification au texte ; rend faux si elle est refusée.
typedef ApplyEdit = bool Function(String Function(String text) edit);

/// Un champ de texte qui n'écrit sa valeur qu'à la fin de la saisie (Entrée ou
/// perte du focus), et qui reprend la valeur du texte si elle change ailleurs
/// ou si la modification est refusée.
class CommitField extends StatefulWidget {
  const CommitField({
    super.key,
    required this.value,
    required this.onCommit,
    this.width = 120,
    this.label,
    this.hint,
  });

  final String value;

  /// Rend faux si la valeur est refusée : le champ revient à [value].
  final bool Function(String text) onCommit;
  final double width;
  final String? label;
  final String? hint;

  @override
  State<CommitField> createState() => _CommitFieldState();
}

class _CommitFieldState extends State<CommitField> {
  late final _controller = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(CommitField old) {
    super.didUpdateWidget(old);
    // Le texte a changé ailleurs (défaire, refaire, le graphe) : le champ le
    // suit, sauf s'il porte une saisie pas encore validée.
    if (widget.value != old.value &&
        (!_focus.hasFocus || _controller.text == old.value)) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final text = _controller.text;
    if (text == widget.value) return;
    if (!widget.onCommit(text)) _controller.text = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _commit(),
      ),
    );
  }
}

/// Une liste déroulante compacte.
class _Pick extends StatelessWidget {
  const _Pick({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.width = 130,
    this.label,
  });

  final String value;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;
  final double width;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final entries = {...items};
    // Une valeur écrite à la main que la liste ne connaît pas reste visible.
    entries.putIfAbsent(value, () => value);
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        // Une autre valeur (changée ailleurs) refait la liste.
        key: ValueKey(value),
        initialValue: value,
        isExpanded: true,
        isDense: true,
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final e in entries.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) {
          if (v != null && v != value) onChanged(v);
        },
      ),
    );
  }
}

Map<String, String> _upper(Iterable<String> keys) => {
  for (final k in keys) k: k.toUpperCase(),
};

// --- Règles ---

/// Les règles de la page : saisie, touche, page suivante, ordre.
class RulesForm extends StatelessWidget {
  const RulesForm({
    super.key,
    required this.page,
    required this.text,
    required this.pages,
    required this.apply,
    required this.onRemove,
    this.onAdd,
    this.onGoToPage,
  });

  final String page;
  final String text;
  final List<String> pages;
  final ApplyEdit apply;

  /// Supprime la règle [index] (qui mène à `to`) : le panneau demande
  /// confirmation s'il le faut.
  final void Function(int index, String to) onRemove;

  /// Ajoute une règle ; `null` si la page n'en reçoit pas (page `exec`).
  final VoidCallback? onAdd;
  final void Function(String page, {String? section, int? rule})? onGoToPage;

  List<Object> get _base => ['pages', page, 'action'];

  @override
  Widget build(BuildContext context) {
    final saisies = valueAt(text, [..._base, 'saisies']);
    final add = onAdd == null
        ? null
        : TextButton.icon(
            key: const Key('add-rule'),
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Ajouter une règle'),
          );
    if (saisies is! YamlList) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            onAdd == null
                ? 'Cette page lance un programme : sa suite est le « suivant » '
                      'de son exec, à modifier dans le texte.'
                : 'Cette page n\'a pas de règles. En ajouter une lui donne '
                      'aussi sa zone de saisie.',
          ),
          ?add,
        ],
      );
    }
    final defaut = valueAt(text, [..._base, 'defaut']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < saisies.length; i++) _row(context, saisies, i),
        ?add,
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Message d\'erreur : '),
            CommitField(
              key: Key('rules-defaut-$page'),
              width: 260,
              value: defaut == null ? '' : '$defaut',
              hint: 'Saisie refusée (ligne 0)',
              onCommit: (v) => apply(
                (t) => v.isEmpty
                    ? removeValue(t, [..._base, 'defaut'])
                    : setValue(t, [..._base, 'defaut'], v),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _row(BuildContext context, YamlList saisies, int i) {
    final rule = saisies[i];
    if (rule is! YamlMap) {
      return Text('Règle ${i + 1} : à modifier dans le texte.');
    }
    final path = [..._base, 'saisies', i];
    final extra = [
      for (final k in rule.keys)
        if (k != 'choix' && k != 'touche' && k != 'suivant') '$k',
    ];
    final next = '${rule['suivant']}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${i + 1}.',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          IconButton(
            key: Key('rule-up-$i'),
            tooltip: 'Plus tôt',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_upward, size: 18),
            onPressed: i == 0
                ? null
                : () => apply((t) => moveRule(t, page, i, -1)),
          ),
          IconButton(
            key: Key('rule-down-$i'),
            tooltip: 'Plus tard',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_downward, size: 18),
            onPressed: i == saisies.length - 1
                ? null
                : () => apply((t) => moveRule(t, page, i, 1)),
          ),
          CommitField(
            key: Key('rule-choix-$i-$page'),
            width: 80,
            label: 'Saisie',
            value: rule['choix'] == null ? '' : '${rule['choix']}',
            onCommit: (v) => apply(
              (t) => v.trim().isEmpty
                  ? removeValue(t, [...path, 'choix'])
                  : setValue(
                      t,
                      [...path, 'choix'],
                      wrapAsYamlNode(
                        v.trim(),
                        scalarStyle: ScalarStyle.DOUBLE_QUOTED,
                      ),
                    ),
            ),
          ),
          _Pick(
            key: Key('rule-touche-$i'),
            width: 130,
            label: 'Touche',
            value: '${rule['touche']}',
            items: _upper(ruleKeys),
            onChanged: (v) => apply((t) => setValue(t, [...path, 'touche'], v)),
          ),
          const Icon(Icons.arrow_forward, size: 16),
          _Pick(
            key: Key('rule-suivant-$i'),
            width: 150,
            label: 'Page',
            value: next,
            items: {for (final p in pages) p: p},
            onChanged: (v) =>
                apply((t) => setValue(t, [...path, 'suivant'], v)),
          ),
          if (extra.isNotEmpty)
            Tooltip(
              message:
                  'Autres réglages de cette règle (${extra.join(', ')}) : '
                  'à modifier dans le texte.',
              child: ActionChip(
                key: Key('rule-extra-$i'),
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.code, size: 14),
                label: Text('+${extra.length}'),
                onPressed: onGoToPage == null
                    ? null
                    : () => onGoToPage!(page, section: 'action', rule: i),
              ),
            ),
          IconButton(
            key: Key('rule-delete-$i'),
            tooltip: 'Supprimer cette règle',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => onRemove(i, next),
          ),
        ],
      ),
    );
  }
}

// --- Saisie ---

const _casses = {
  '': 'Telle quelle',
  'majuscules': 'Majuscules',
  'minuscules': 'Minuscules',
  'capitale': 'Capitale',
};

/// La zone de saisie de la page et les touches qui la valident.
class InputForm extends StatelessWidget {
  const InputForm({
    super.key,
    required this.page,
    required this.text,
    required this.apply,
    this.onGoToPage,
  });

  final String page;
  final String text;
  final ApplyEdit apply;
  final void Function(String page, {String? section, int? rule})? onGoToPage;

  List<Object> get _base => ['pages', page, 'entree'];

  @override
  Widget build(BuildContext context) {
    final entree = valueAt(text, _base);
    if (entree is! YamlMap) {
      return const Text(
        'Cette page n\'a pas de saisie : on n\'y attend aucune touche. '
        'Ajouter une règle (onglet « Règles ») lui en donne une.',
      );
    }
    final zone = entree['zonesaisie'];
    final validation = entree['validation'];
    final keys = validation is YamlList
        ? [for (final k in validation) '$k']
        : <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (zone is YamlMap)
          _zone(context, zone)
        else
          _message(context, entree),
        const SizedBox(height: 8),
        const Text('Touches qui valident la saisie :'),
        Wrap(
          spacing: 6,
          children: [
            for (final k in ruleKeys)
              FilterChip(
                key: Key('input-key-$k'),
                visualDensity: VisualDensity.compact,
                label: Text(k.toUpperCase()),
                selected: keys.contains(k),
                onSelected: (on) => apply(
                  (t) => setValue(
                    t,
                    [..._base, 'validation'],
                    wrapAsYamlNode([
                      for (final x in ruleKeys)
                        if (x == k ? on : keys.contains(x)) x,
                      for (final x in keys)
                        if (!ruleKeys.contains(x)) x,
                    ], collectionStyle: CollectionStyle.FLOW),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _int(YamlMap zone, String key, String label, {double width = 80}) {
    return CommitField(
      key: Key('input-$key-$page'),
      width: width,
      label: label,
      value: zone[key] == null ? '' : '${zone[key]}',
      onCommit: (v) {
        final n = int.tryParse(v.trim());
        if (n == null) return false;
        return apply((t) => setValue(t, [..._base, 'zonesaisie', key], n));
      },
    );
  }

  Widget _zone(BuildContext context, YamlMap zone) {
    final known = {
      'ligne',
      'col',
      'longueur',
      'curseur',
      'casse',
      'regex',
      'erreur',
    };
    final other = [
      for (final k in zone.keys)
        if (!known.contains(k)) '$k',
    ];
    final path = [..._base, 'zonesaisie'];
    final regex = zone['regex'] == null ? '' : '${zone['regex']}';
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _int(zone, 'ligne', 'Ligne'),
        _int(zone, 'col', 'Colonne'),
        _int(zone, 'longueur', 'Longueur'),
        _Pick(
          key: const Key('input-curseur'),
          width: 130,
          label: 'Curseur',
          value: '${zone['curseur'] ?? 'visible'}',
          items: const {'visible': 'Visible', 'invisible': 'Invisible'},
          onChanged: (v) => apply(
            (t) => v == 'visible'
                ? removeValue(t, [...path, 'curseur'])
                : setValue(t, [...path, 'curseur'], v),
          ),
        ),
        _Pick(
          key: const Key('input-casse'),
          width: 140,
          label: 'Casse',
          value: '${zone['casse'] ?? ''}',
          items: _casses,
          onChanged: (v) => apply(
            (t) => v.isEmpty
                ? removeValue(t, [...path, 'casse'])
                : setValue(t, [...path, 'casse'], v),
          ),
        ),
        CommitField(
          key: Key('input-regex-$page'),
          width: 200,
          label: 'Forme attendue (regex)',
          value: regex,
          onCommit: (v) => apply(
            (t) => v.isEmpty
                ? removeValue(removeValue(t, [...path, 'erreur']), [
                    ...path,
                    'regex',
                  ])
                : setValue(t, [...path, 'regex'], v),
          ),
        ),
        if (regex.isNotEmpty)
          CommitField(
            key: Key('input-erreur-$page'),
            width: 220,
            label: 'Message si refusée',
            value: zone['erreur'] == null ? '' : '${zone['erreur']}',
            onCommit: (v) => apply(
              (t) => v.isEmpty
                  ? removeValue(t, [...path, 'erreur'])
                  : setValue(t, [...path, 'erreur'], v),
            ),
          ),
        if (other.isNotEmpty)
          Tooltip(
            message:
                'Autres réglages (${other.join(', ')}) : à modifier dans le '
                'texte.',
            child: ActionChip(
              key: const Key('input-extra'),
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.code, size: 14),
              label: Text('+${other.length}'),
              onPressed: onGoToPage == null
                  ? null
                  : () => onGoToPage!(page, section: 'entree'),
            ),
          ),
      ],
    );
  }

  Widget _message(BuildContext context, YamlMap entree) {
    return Row(
      children: [
        const Flexible(
          child: Text(
            'Cette page a une zone de message (plusieurs lignes) : elle se '
            'modifie dans le texte.',
          ),
        ),
        if (onGoToPage != null)
          TextButton(
            onPressed: () => onGoToPage!(page, section: 'entree'),
            child: const Text('Aller au texte'),
          ),
      ],
    );
  }
}

// --- Accès ---

/// Qui peut ouvrir la page.
class AccessForm extends StatelessWidget {
  const AccessForm({
    super.key,
    required this.page,
    required this.text,
    required this.pages,
    required this.apply,
  });

  final String page;
  final String text;
  final List<String> pages;
  final ApplyEdit apply;

  @override
  Widget build(BuildContext context) {
    final a = accessOf(text, page);
    bool change({
      AccessMode? mode,
      String? otherwise,
      String? message,
      bool? provisional,
      bool clearOtherwise = false,
    }) => apply(
      (t) => setAccess(
        t,
        page,
        mode: mode ?? a.mode,
        otherwise: clearOtherwise ? null : (otherwise ?? a.otherwise),
        message: message ?? a.message,
        provisional: provisional ?? a.provisional,
      ),
    );

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _Pick(
          key: const Key('access-mode'),
          width: 250,
          label: 'Accès',
          value: a.mode.name,
          items: const {
            'inherit': 'Comme le reste du service',
            'open': 'Ouverte à tous',
            'members': 'Réservée aux connectés',
          },
          onChanged: (v) =>
              change(mode: AccessMode.values.firstWhere((m) => m.name == v)),
        ),
        if (a.mode == AccessMode.members) ...[
          _Pick(
            key: const Key('access-sinon'),
            width: 200,
            label: 'Sinon, aller à',
            value: a.otherwise ?? '',
            items: {'': 'Message seulement', for (final p in pages) p: p},
            onChanged: (v) =>
                v.isEmpty ? change(clearOtherwise: true) : change(otherwise: v),
          ),
          CommitField(
            key: Key('access-message-$page'),
            width: 260,
            label: 'Message de refus',
            hint: 'Connexion requise',
            value: a.message ?? '',
            onCommit: (v) => change(message: v),
          ),
          FilterChip(
            key: const Key('access-prov'),
            label: const Text('Ouverte aux mots de passe provisoires'),
            selected: a.provisional,
            onSelected: (v) => change(provisional: v),
          ),
        ],
      ],
    );
  }
}
