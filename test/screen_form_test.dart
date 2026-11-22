import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_page_test.dart' show pumpEditor, FakeFiles, codeText;

const _service = '''
debut: a
pages:
  a:
    ecran:
      - efface
      - position: {ligne: 3, col: 5}
      - ecrit: "Bonjour"
      - si:
          connecte: true
          alors:
            - ecrit: "oui"
    entree:
      zonesaisie: {ligne: 24, col: 1, longueur: 1}
      validation: [envoi]
    action:
      saisies:
        - {choix: "1", touche: envoi, suivant: a}
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

Future<void> tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('écran : la liste des instructions', (tester) async {
    await open(tester);
    expect(find.byKey(const Key('screen-a-0')), findsOneWidget);
    expect(find.byKey(const Key('screen-a-2')), findsOneWidget);
    // Le bloc si n'est pas modifiable ici.
    expect(find.byKey(const Key('screen-block-3')), findsOneWidget);
    expect(find.byKey(const Key('screen-a-3')), findsNothing);
  });

  testWidgets('écran : modifier une instruction', (tester) async {
    await open(tester);
    final field = find.byKey(const Key('screen-a-1'));
    await tester.ensureVisible(field);
    await tester.enterText(field, 'position: {ligne: 9, col: 2}');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(codeText(tester), contains('- position: {ligne: 9, col: 2}'));
  });

  testWidgets('écran : une instruction refusée ne change rien', (tester) async {
    await open(tester);
    final field = find.byKey(const Key('screen-a-1'));
    await tester.ensureVisible(field);
    await tester.enterText(field, 'inconnue: 3');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(codeText(tester), contains('- position: {ligne: 3, col: 5}'));
    expect(codeText(tester), isNot(contains('inconnue')));
  });

  testWidgets('écran : monter, copier, supprimer', (tester) async {
    await open(tester);
    await tapKey(tester, 'screen-up-2');
    expect(
      codeText(tester).indexOf('ecrit: "Bonjour"') <
          codeText(tester).indexOf('position:'),
      isTrue,
    );
    await tapKey(tester, 'screen-copy-0');
    expect('- efface'.allMatches(codeText(tester)).length, 2);
    await tapKey(tester, 'screen-delete-0');
    expect('- efface'.allMatches(codeText(tester)).length, 1);
  });

  testWidgets('écran : ajouter depuis le menu', (tester) async {
    await open(tester);
    await tapKey(tester, 'screen-add-1');
    await tester.tap(find.textContaining('couleur — '));
    await tester.pumpAndSettle();
    expect(
      codeText(tester),
      contains('- efface\n      - couleur: {texte: blanc}\n      - position'),
    );
  });

  testWidgets('écran : « Dans le texte » mène à la ligne de l\'instruction', (
    tester,
  ) async {
    await open(tester);
    await tester.ensureVisible(find.text('Dans le texte'));
    await tester.tap(find.text('Dans le texte'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final field = tester.widget<TextField>(find.byKey(const Key('code')));
    final text = field.controller!.text;
    final line = text
        .substring(0, field.controller!.selection.start)
        .split('\n')
        .length;
    expect(text.split('\n')[line - 1], contains('- si:'));
  });

  testWidgets('écran : Ctrl+Z et Ctrl+Y agissent depuis un champ', (
    tester,
  ) async {
    await open(tester);
    final field = find.byKey(const Key('screen-a-1'));
    await tester.ensureVisible(field);
    await tester.enterText(field, 'position: {ligne: 9, col: 2}');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(codeText(tester), contains('ligne: 9'));
    Future<void> ctrl(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    String shown() => tester
        .widget<TextField>(
          find.descendant(of: field, matching: find.byType(TextField)),
        )
        .controller!
        .text;

    await ctrl(LogicalKeyboardKey.keyZ);
    expect(codeText(tester), contains('ligne: 3, col: 5'));
    expect(shown(), 'position: {ligne: 3, col: 5}');
    await ctrl(LogicalKeyboardKey.keyY);
    expect(codeText(tester), contains('ligne: 9'));
    expect(shown(), 'position: {ligne: 9, col: 2}');
  });
}
