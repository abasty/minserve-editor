import 'package:flutter/material.dart';

import 'page_forms.dart';
import 'service_edit.dart';

/// Les instructions qu'on peut ajouter à un écran, avec de quoi les écrire :
/// le libellé du menu, et l'instruction avec des valeurs par défaut.
const screenPalette = <(String, String)>[
  ('efface — efface l\'écran', 'efface'),
  ('position — place le curseur', 'position: {ligne: 1, col: 1}'),
  ('ecrit — écrit du texte', 'ecrit: "Texte"'),
  ('couleur — couleur du texte ou du fond', 'couleur: {texte: blanc}'),
  (
    'rectangle — rectangle plein',
    'rectangle: {ligne: 1, col: 1, largeur: 10, hauteur: 1, couleur: blanc}',
  ),
  ('repete — répète un caractère', 'repete: {caractere: "-", nombre: 10}'),
  (
    'paragraphe — texte long plié aux mots',
    'paragraphe: {valeur: "Texte", ligne: 1, hauteur: 3, col: 1, largeur: 40}',
  ),
  ('deplace — déplace le curseur', 'deplace: {col: 1}'),
  ('doublehauteur', 'doublehauteur'),
  ('doublelargeur', 'doublelargeur'),
  ('doubletaille', 'doubletaille'),
  ('taillenormale', 'taillenormale'),
  ('souligne', 'souligne: actif'),
  ('clignote', 'clignote: actif'),
  ('inversion', 'inversion: actif'),
  ('curseur', 'curseur: invisible'),
  ('graphique — mode semi-graphique', 'graphique'),
  ('texte — mode texte', 'texte'),
  ('date', 'date'),
  ('heure', 'heure'),
  ('affiche — fichier Videotex', 'affiche: fichier.vdt'),
  ('effacefindeligne', 'effacefindeligne'),
];

/// L'écran d'une page : la liste de ses instructions, dans l'ordre où le
/// terminal les reçoit. On peut en ajouter, les changer de place, les copier, les
/// supprimer, ou écrire une instruction à la main. Une instruction sur plusieurs
/// lignes (`si`, `fois`) se modifie dans le texte.
class ScreenForm extends StatelessWidget {
  const ScreenForm({
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

  Widget _insert(BuildContext context, int at, {required Widget child}) {
    return PopupMenuButton<String>(
      key: Key('screen-add-$at'),
      tooltip: 'Insérer une instruction',
      onSelected: (item) => apply((t) => insertScreenItem(t, page, at, item)),
      itemBuilder: (context) => [
        for (final (label, item) in screenPalette)
          PopupMenuItem(value: item, child: Text(label)),
      ],
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = screenItems(text, page);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('Cet écran est vide.'),
          ),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  child: Text(
                    '${item.index + 1}',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: item.multiline
                      ? _block(context, item)
                      : CommitField(
                          key: Key('screen-$page-${item.index}'),
                          width: double.infinity,
                          value: item.text,
                          onCommit: (v) => apply(
                            (t) => replaceScreenItem(t, page, item.index, v),
                          ),
                        ),
                ),
                IconButton(
                  key: Key('screen-up-${item.index}'),
                  tooltip: 'Monter',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  onPressed: item.index == 0
                      ? null
                      : () => apply(
                          (t) => moveScreenItem(t, page, item.index, -1),
                        ),
                ),
                IconButton(
                  key: Key('screen-down-${item.index}'),
                  tooltip: 'Descendre',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.arrow_downward, size: 18),
                  onPressed: item.index == items.length - 1
                      ? null
                      : () => apply(
                          (t) => moveScreenItem(t, page, item.index, 1),
                        ),
                ),
                IconButton(
                  key: Key('screen-copy-${item.index}'),
                  tooltip: 'Dupliquer',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.content_copy, size: 18),
                  onPressed: () =>
                      apply((t) => duplicateScreenItem(t, page, item.index)),
                ),
                _insert(
                  context,
                  item.index + 1,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.add, size: 18),
                  ),
                ),
                IconButton(
                  key: Key('screen-delete-${item.index}'),
                  tooltip: 'Supprimer',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () =>
                      apply((t) => removeScreenItem(t, page, item.index)),
                ),
              ],
            ),
          ),
        _insert(
          context,
          items.length,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add, size: 18),
                const SizedBox(width: 6),
                Text(
                  'Ajouter une instruction',
                  style: TextStyle(color: theme.colorScheme.primary),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Une instruction sur plusieurs lignes : montrée, pas modifiable ici.
  Widget _block(BuildContext context, ScreenItem item) {
    final lines = item.text.split('\n');
    return InputDecorator(
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${item.name}  (${lines.length} lignes)',
              key: Key('screen-block-${item.index}'),
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onGoToPage != null)
            TextButton(
              onPressed: () =>
                  onGoToPage!(page, section: 'ecran', rule: item.index),
              child: const Text('Dans le texte'),
            ),
        ],
      ),
    );
  }
}
