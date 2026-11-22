import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minserve_core/minserve_core.dart';
import 'package:minserve_editor/src/graph/minget_panel.dart';
import 'package:minserve_editor/src/preview/page_preview.dart';

import 'editor_page_test.dart' show pumpEditor, FakeFiles, codeText;

const _service = r'''
debut: a
macros:
  trait:
    description: "Un trait horizontal"
    parametres:
      - {nom: ligne, type: entier, defaut: 5, min: 1, max: 24}
      - {nom: texte, type: texte, defaut: "salut"}
      - {nom: gras, type: booleen, defaut: false}
    ecran:
      - position: {ligne: $1, col: 1}
      - ecrit: $2
  vieille:
    - position: {ligne: $1, col: $2}
    - ecrit: "x"
  fixe:
    parametres:
      - {nom: n, type: entier, min: 3, max: 9}
      - {nom: t}
      - {nom: b, type: booleen}
    ecran:
      - ecrit: "ok"
pages:
  a:
    ecran: [efface]
''';

Future<void> open(WidgetTester tester) async {
  await pumpEditor(tester, FakeFiles());
  await tester.enterText(find.byKey(const Key('code')), _service);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.byKey(const Key('open-mingets')));
  await tester.pumpAndSettle();
}

void main() {
  test('arguments de départ : défauts, sinon une valeur qui se voit', () {
    final s = Service.parseString(_service);
    expect(defaultMingetArgs(s.macros['trait']!), [5, 'salut', false]);
    // Sans défaut : le plus petit entier permis, le nom, faux.
    expect(defaultMingetArgs(s.macros['fixe']!), [3, 't', false]);
    // Forme liste : des entiers.
    expect(defaultMingetArgs(s.macros['vieille']!), [1, 1]);
  });

  test('les types devinés d\'une macro en liste d\'instructions', () {
    const text = r'''
debut: a
macros:
  option:
    - position: {ligne: $1, col: $2}
    - ecrit: "$3"
    - ecrit: "{$4"
    - repete: {caractere: " ", nombre: "$(max(0, 29 - longueur($4)))"}
    - repete: {caractere: "-", nombre: "$($5 + 1)"}
    - couleur: {texte: $6}
pages:
  a:
    ecran: [efface]
''';
    final s = Service.parseString(text);
    final m = s.macros['option']!;
    expect(mingetParamTypes(m), [
      MacroType.entier,
      MacroType.entier,
      MacroType.texte,
      MacroType.texte,
      MacroType.entier,
      MacroType.texte,
    ]);
    expect(defaultMingetArgs(m), [1, 1, 'Texte', 'Texte', 1, 'Texte']);
  });

  testWidgets('la liste des mingets du service', (tester) async {
    await open(tester);
    expect(find.text('Mingets (3)'), findsNothing); // on est dans le panneau
    expect(find.byKey(const Key('minget-trait')), findsOneWidget);
    expect(find.text('Un trait horizontal'), findsOneWidget);
    expect(find.byKey(const Key('minget-vieille')), findsOneWidget);
    expect(find.text('Choisissez un minget.'), findsOneWidget);
    // Retour au graphe.
    await tester.tap(find.byKey(const Key('back-from-mingets')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('node-a')), findsOneWidget);
  });

  testWidgets('aperçu d\'un minget avec ses arguments d\'essai', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('minget-trait')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preview-screen')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('preview-caption'))).data,
      'Minget « trait »',
    );
    expect(
      tester.widget<PagePreview>(find.byType(PagePreview)).inputZone,
      false,
    );
    // Un argument hors bornes est refusé par le serveur : la raison s'affiche.
    await tester.enterText(find.byKey(const Key('minget-arg-trait-0-0')), '99');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('minget-error')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('minget-error'))).data,
      contains('entre 1 et 24'),
    );
    // Un entier mal écrit : « un entier est attendu ».
    await tester.enterText(find.byKey(const Key('minget-arg-trait-0-0')), 'x');
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('minget-error'))).data,
      contains('un entier est attendu'),
    );
    // Les valeurs par défaut reviennent.
    await tester.tap(find.byKey(const Key('minget-reset')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('minget-error')), findsNothing);
    expect(find.byKey(const Key('preview-screen')), findsOneWidget);
    // Le vrai texte n'a pas changé.
    expect(codeText(tester), isNot(contains('__minget__')));
  });

  testWidgets('un minget en forme liste et un booléen', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('minget-vieille')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preview-screen')), findsOneWidget);
    await tester.tap(find.byKey(const Key('minget-fixe')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('minget-error')), findsNothing);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preview-screen')), findsOneWidget);
  });

  testWidgets('« Dans le texte » va à la définition de la macro', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('minget-vieille')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('minget-goto')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final field = tester.widget<TextField>(find.byKey(const Key('code')));
    final text = field.controller!.text;
    final line = text
        .substring(0, field.controller!.selection.start)
        .split('\n')
        .length;
    expect(text.split('\n')[line - 1], contains('vieille:'));
  });
}
