import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:minserve_core/minserve_core.dart';
import 'package:minserve_editor/src/graph/service_edit.dart';

const _service = r'''
debut: a
pages:
  a:
    ecran:
      - efface
      # le titre
      - position: {ligne: 3, col: 5}
      - couleur: {texte: jaune}
      - ecrit: "Menu"
      - repete: {caractere: "-", nombre: 10}
      - si:
          connecte: true
          alors:
            - ecrit: "oui"
      - ecrit: "fin"
    entree:
      zonesaisie: {ligne: 24, col: 1, longueur: 1}
      validation: [envoi]
    action:
      saisies:
        - {choix: "1", touche: envoi, suivant: a}
''';

List<int> bytes(String text, String page) {
  final s = Service.parseString(text);
  final w = VideotexWriter();
  renderScreen(
    s.pages[page]!.screen,
    w,
    assets: (_) => Uint8List(0),
    now: DateTime(2026, 1, 1, 12),
    init: s.initScreen,
  );
  return w.takeBytes();
}

void main() {
  test('les valeurs qu\'on peut rendre variables', () {
    final v = extractableValues(_service, 'a', 1, 4);
    expect(
      [for (final e in v) '${e.item}:${e.path.join('.')}=${e.value}'],
      [
        '1:position.ligne=3',
        '1:position.col=5',
        '2:couleur.texte=jaune',
        '3:ecrit=Menu',
        '4:repete.caractere=-',
        '4:repete.nombre=10',
      ],
    );
    expect(v.map((e) => e.name), [
      'ligne',
      'col',
      'texte',
      'texte2',
      'caractere',
      'nombre',
    ]);
    // Le bloc si n'a pas de valeur proposée.
    expect(extractableValues(_service, 'a', 5, 5), isEmpty);
  });

  test('extraire : la macro, l\'appel, et le même affichage', () {
    final values = extractableValues(_service, 'a', 1, 4);
    ExtractParam param(int i, String name) => ExtractParam(values[i], name);
    final out = extractMinget(
      _service,
      'a',
      1,
      4,
      name: 'titre-menu',
      description: 'Le titre',
      params: [param(0, 'ligne'), param(1, 'col'), param(3, 'texte')],
    );
    final s = Service.parseString(out);
    final m = s.macros['titre-menu']!;
    expect(m.extended, isTrue);
    expect(m.description, 'Le titre');
    expect(m.parameters.map((p) => p.name), ['ligne', 'col', 'texte']);
    expect(m.parameters.map((p) => p.defaultValue), [3, 5, 'Menu']);
    expect(m.parameters.map((p) => p.type), [
      MacroType.entier,
      MacroType.entier,
      MacroType.texte,
    ]);
    // L'appel remplace les 4 instructions, sans argument.
    expect(
      out,
      contains(
        '      - efface\n      # le titre\n      - macro: [titre-menu]\n      - si:',
      ),
    );
    // Les valeurs non choisies restent dans le corps ; les autres deviennent $n.
    expect(out, contains(r'- position: {ligne: $1, col: $2}'));
    expect(out, contains('- couleur: {texte: jaune}'));
    expect(out, contains(r'- ecrit: "$3"'));
    expect(out, contains('- repete: {caractere: "-", nombre: 10}'));
    // Le commentaire d'une instruction extraite est conservé hors de l'appel.
    expect(out, contains('# le titre'));
    // La macro est avant les pages, et l'affichage est identique.
    expect(out.indexOf('macros:') < out.indexOf('pages:'), isTrue);
    expect(bytes(out, 'a'), bytes(_service, 'a'));
    // Avec d'autres arguments, la page change.
    final other = out.replaceFirst(
      '- macro: [titre-menu]',
      '- macro: [titre-menu, 9]',
    );
    expect(bytes(other, 'a'), isNot(bytes(out, 'a')));
  });

  test('extraire un bloc si, et dans un service qui a déjà des macros', () {
    const text = r'''
debut: a
macros:
  # la première
  vieille:
    - efface
pages:
  a:
    ecran:
      - macro: [vieille]
      - si:
          connecte: true
          alors:
            - ecrit: "oui"
          sinon:
            - ecrit: "non"
      - ecrit: "fin"
''';
    final out = extractMinget(text, 'a', 1, 1, name: 'condition');
    final s = Service.parseString(out);
    expect(s.macros.keys, ['vieille', 'condition']);
    expect(out, contains('  # la première\n  vieille:'));
    expect(out.indexOf('condition:') < out.indexOf('pages:'), isTrue);
    expect(
      out,
      contains(
        '      - macro: [vieille]\n      - macro: [condition]\n      - ecrit: "fin"',
      ),
    );
    expect(bytes(out, 'a'), bytes(text, 'a'));
    expect(s.macros['condition']!.arity, 0);
  });

  test('extraire : refus d\'un nom pris, de noms de paramètres invalides', () {
    final values = extractableValues(_service, 'a', 1, 1);
    expect(
      () => extractMinget(_service, 'a', 1, 1, name: 'a b'),
      throwsA(isA<EditException>()),
    );
    expect(
      () => extractMinget(
        _service,
        'a',
        1,
        1,
        name: 'm',
        params: [ExtractParam(values[0], '1x'), ExtractParam(values[1], 'ok')],
      ),
      throwsA(isA<EditException>()),
    );
    expect(
      () => extractMinget(
        _service,
        'a',
        1,
        1,
        name: 'm',
        params: [ExtractParam(values[0], 'x'), ExtractParam(values[1], 'x')],
      ),
      throwsA(isA<EditException>()),
    );
    expect(
      () => extractMinget(_service, 'a', 3, 99, name: 'm'),
      throwsA(isA<EditException>()),
    );
  });
}
