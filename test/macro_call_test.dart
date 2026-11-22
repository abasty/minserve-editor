import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minserve_core/minserve_core.dart';
import 'package:minserve_editor/src/graph/macro_call.dart';

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
  vide:
    - efface
  oldie:
    - position: {ligne: $1, col: 1}
pages:
  a:
    ecran:
      - efface
      - macro: [trait, 7, "a, b"]
''';

Future<void> open(WidgetTester tester) async {
  await pumpEditor(tester, FakeFiles());
  await tester.enterText(find.byKey(const Key('code')), _service);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.byKey(const Key('node-a')));
  await tester.pump();
  final tab = find.descendant(
    of: find.byKey(const Key('page-tabs')),
    matching: find.text('Écran'),
  );
  await tester.ensureVisible(tab);
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

void main() {
  final macros = Service.parseString(_service).macros;

  test('écrire un appel : les derniers arguments par défaut sont omis', () {
    final trait = macros['trait']!;
    expect(macroCallText(trait, [7, 'salut', false]), 'macro: [trait, 7]');
    expect(macroCallText(trait, [5, 'salut', false]), 'macro: [trait]');
    expect(
      macroCallText(trait, [5, 'a, b', false]),
      'macro: [trait, 5, "a, b"]',
    );
    // Un argument différent garde ceux qui le précèdent, et ceux qui suivent.
    expect(
      macroCallText(trait, [5, 'salut', true]),
      'macro: [trait, 5, "salut", true]',
    );
    // Une macro en liste d'instructions n'a pas de défaut : tout est écrit.
    expect(macroCallText(macros['oldie']!, [1]), 'macro: [oldie, 1]');
    expect(macroCallText(macros['vide']!, []), 'macro: [vide]');
  });

  test('lire un appel, et ses arguments complets', () {
    final call = readMacroCall('macro: [trait, 7, "a, b"]')!;
    expect(call.name, 'trait');
    expect(call.args, [7, 'a, b']);
    expect(fullMacroArgs(macros['trait']!, call.args), [7, 'a, b', false]);
    expect(readMacroCall('efface'), isNull);
    expect(readMacroCall('macro: 3'), isNull);
    expect(readMacroCall('position: {ligne: 1, col: 1}'), isNull);
  });

  test('arguments refusés d\'après les paramètres déclarés', () {
    final trait = macros['trait']!;
    expect(macroArgsError(trait, [5, 'x', false]), isNull);
    expect(macroArgsError(trait, [99, 'x', false]), contains('entre 1 et 24'));
    expect(macroArgsError(macros['oldie']!, [99]), isNull);
  });

  testWidgets('insérer un minget : formulaire d\'appel', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('screen-add-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('instruction-filter')), 'tra');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('instruction-macro-trait')), findsOneWidget);
    expect(find.byKey(const Key('instruction-macro-oldie')), findsNothing);
    await tester.tap(find.byKey(const Key('instruction-macro-trait')));
    await tester.pumpAndSettle();
    // Le formulaire propose les valeurs par défaut.
    expect(find.text('Un trait horizontal'), findsOneWidget);
    // Un argument refusé empêche d'insérer.
    await tester.enterText(find.byKey(const Key('macro-arg-0')), '99');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('macro-call-error')), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('dialog-ok'))).onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(const Key('macro-arg-0')), '12');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dialog-ok')));
    await tester.pumpAndSettle();
    expect(
      codeText(tester),
      contains(
        '- efface\n      - macro: [trait, 12]\n      - macro: [trait, 7',
      ),
    );
  });

  testWidgets('un minget sans paramètre s\'insère tout de suite', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('screen-add-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('instruction-filter')), 'vid');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('instruction-macro-vide')));
    await tester.pumpAndSettle();
    expect(codeText(tester), contains('- efface\n      - macro: [vide]'));
  });

  testWidgets('un appel existant se modifie par champs', (tester) async {
    await open(tester);
    // Une ligne par paramètre : ligne, texte, gras.
    expect(find.byKey(const Key('screen-a-1-macro-name')), findsOneWidget);
    final ligne = find.byKey(const Key('screen-a-1-arg-0'));
    await tester.ensureVisible(ligne);
    await tester.enterText(ligne, '9');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(codeText(tester), contains('- macro: [trait, 9, "a, b"]'));
    // Remettre le texte par défaut raccourcit l'appel.
    final texte = find.byKey(const Key('screen-a-1-arg-1'));
    await tester.enterText(texte, 'salut');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(codeText(tester), contains('- macro: [trait, 9]\n'));
    // Un booléen : l'interrupteur.
    final gras = find.byKey(const Key('screen-a-1-arg-2'));
    await tester.ensureVisible(gras);
    await tester.tap(gras);
    await tester.pumpAndSettle();
    expect(codeText(tester), contains('- macro: [trait, 9, "salut", true]'));
  });
}
