import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_page_test.dart' show pumpEditor, FakeFiles, codeText;

const _service = '''
debut: a
pages:
  a:
    ecran: [efface]
    entree:
      zonesaisie: {ligne: 24, col: 1, longueur: 1, couleur: rouge}
      validation: [envoi, retour]
    action:
      saisies:
        - {choix: "1", touche: envoi, suivant: b}
        - {choix: "2", touche: envoi, suivant: c, deconnexion: true}
        - {touche: retour, suivant: b}
  b:
    ecran: [efface]
  c:
    ecran: [efface]
''';

Future<void> open(WidgetTester tester, String tab, {String page = 'a'}) async {
  await pumpEditor(tester, FakeFiles());
  await tester.enterText(find.byKey(const Key('code')), _service);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.byKey(Key('node-$page')));
  await tester.pump();
  await tester.tap(find.text(tab));
  await tester.pumpAndSettle();
}

Future<void> submit(WidgetTester tester, Key key, String text) async {
  await tester.enterText(find.byKey(key), text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

Future<void> pick(WidgetTester tester, Key key, String label) async {
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('règles : changer la saisie d\'une règle', (tester) async {
    await open(tester, 'Règles');
    await submit(tester, const Key('rule-choix-0-a'), '5');
    expect(
      codeText(tester),
      contains('{choix: "5", touche: envoi, suivant: b}'),
    );
    // Vider la saisie retire la clé.
    await submit(tester, const Key('rule-choix-0-a'), '');
    expect(codeText(tester), contains('- {touche: envoi, suivant: b}'));
  });

  testWidgets('règles : changer la page suivante', (tester) async {
    await open(tester, 'Règles');
    await pick(tester, const Key('rule-suivant-0'), 'c');
    expect(
      codeText(tester),
      contains('{choix: "1", touche: envoi, suivant: c}'),
    );
  });

  testWidgets('règles : une touche refusée par le serveur ne change rien', (
    tester,
  ) async {
    await open(tester, 'Règles');
    final before = codeText(tester);
    // « sommaire » n'est pas dans la validation de la page.
    await pick(tester, const Key('rule-touche-0'), 'SOMMAIRE');
    expect(codeText(tester), before);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('règles : réordonner', (tester) async {
    await open(tester, 'Règles');
    await tester.tap(find.byKey(const Key('rule-down-0')));
    await tester.pumpAndSettle();
    final text = codeText(tester);
    expect(text.indexOf('choix: "2"'), lessThan(text.indexOf('choix: "1"')));
  });

  testWidgets('règles : les réglages inconnus sont signalés, pas perdus', (
    tester,
  ) async {
    await open(tester, 'Règles');
    expect(find.byKey(const Key('rule-extra-1')), findsOneWidget);
    expect(find.byKey(const Key('rule-extra-0')), findsNothing);
    await submit(tester, const Key('rule-choix-1-a'), '9');
    expect(
      codeText(tester),
      contains('{choix: "9", touche: envoi, suivant: c, deconnexion: true}'),
    );
  });

  testWidgets('saisie : changer la longueur et la casse', (tester) async {
    await open(tester, 'Saisie');
    await submit(tester, const Key('input-longueur-a'), '3');
    expect(codeText(tester), contains('longueur: 3'));
    await pick(tester, const Key('input-casse'), 'Majuscules');
    expect(codeText(tester), contains('casse: majuscules'));
    // Les autres réglages de la zone sont conservés.
    expect(codeText(tester), contains('couleur: rouge'));
    await pick(tester, const Key('input-casse'), 'Telle quelle');
    expect(codeText(tester), isNot(contains('casse')));
  });

  testWidgets('saisie : un nombre invalide revient à la valeur du texte', (
    tester,
  ) async {
    await open(tester, 'Saisie');
    await submit(tester, const Key('input-longueur-a'), 'abc');
    expect(codeText(tester), contains('longueur: 1'));
    await submit(tester, const Key('input-longueur-a'), '99');
    expect(codeText(tester), contains('longueur: 1'));
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('saisie : les touches qui valident', (tester) async {
    await open(tester, 'Saisie');
    await tester.ensureVisible(find.byKey(const Key('input-key-sommaire')));
    await tester.tap(find.byKey(const Key('input-key-sommaire')));
    await tester.pumpAndSettle();
    expect(codeText(tester), contains('validation: [envoi, retour, sommaire]'));
  });

  testWidgets('accès : réserver une page aux connectés', (tester) async {
    await open(tester, 'Accès', page: 'c');
    await pick(tester, const Key('access-mode'), 'Réservée aux connectés');
    expect(codeText(tester), contains('acces: {connecte: true}'));
    await pick(tester, const Key('access-sinon'), 'b');
    expect(codeText(tester), contains('acces: {connecte: true, sinon: b}'));
    await pick(tester, const Key('access-mode'), 'Comme le reste du service');
    expect(codeText(tester), isNot(contains('acces')));
  });

  testWidgets('les onglets n\'existent que si le graphe est modifiable', (
    tester,
  ) async {
    await open(tester, 'Règles');
    await tester.enterText(
      find.byKey(const Key('code')),
      'debut: a\npages: 3\n',
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('page-tabs')), findsNothing);
  });

  Future<int> goToText(WidgetTester tester) async {
    await tester.tap(find.text('Aller au texte'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final field = tester.widget<TextField>(find.byKey(const Key('code')));
    final text = field.controller!.text;
    return text
        .substring(0, field.controller!.selection.start)
        .split('\n')
        .length;
  }

  testWidgets('Aller au texte va à la partie de la page de l\'onglet', (
    tester,
  ) async {
    await open(tester, 'Résumé');
    expect(await goToText(tester), 3); // « a: »
    await tester.tap(find.text('Règles'));
    await tester.pumpAndSettle();
    expect(await goToText(tester), 8); // « action: »
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('page-tabs')),
        matching: find.text('Saisie'),
      ),
    );
    await tester.pumpAndSettle();
    expect(await goToText(tester), 5); // « entree: »
    await tester.tap(find.text('Accès'));
    await tester.pumpAndSettle();
    // La page n'a pas d'« acces » : on va à la page.
    expect(await goToText(tester), 3);
  });

  testWidgets('la puce « +n » d\'une règle va à cette règle', (tester) async {
    await open(tester, 'Règles');
    await tester.ensureVisible(find.byKey(const Key('rule-extra-1')));
    await tester.tap(find.byKey(const Key('rule-extra-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final field = tester.widget<TextField>(find.byKey(const Key('code')));
    final line = field.controller!.text
        .substring(0, field.controller!.selection.start)
        .split('\n')
        .length;
    expect(line, 11); // la deuxième règle
  });
}
