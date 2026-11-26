import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_page_test.dart' show pumpEditor, FakeFiles, viewTab;

const _service = r'''
debut: a
macros:
  trait:
    - position: {ligne: 1, col: 1}
pages:
  a:
    ecran:
      - macro: [trait]
  b:
    ecran: [efface]
''';

Future<void> open(WidgetTester tester) async {
  await pumpEditor(tester, FakeFiles());
  await tester.enterText(find.byKey(const Key('code')), _service);
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('au départ : le graphe et les mingets, pas de page', (
    tester,
  ) async {
    await open(tester);
    expect(viewTab('Graphe'), findsOneWidget);
    expect(viewTab('Mingets (1)'), findsOneWidget);
    expect(viewTab('Page'), findsNothing);
    expect(find.byKey(const Key('close-page')), findsNothing);
    expect(find.byKey(const Key('node-a')), findsOneWidget);
  });

  testWidgets('la page ouverte a son onglet, qui reste en changeant de vue', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('node-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-page')));
    await tester.pumpAndSettle();
    expect(viewTab('Page « a »'), findsOneWidget);
    expect(find.byKey(const Key('node-a')), findsNothing);
    // Le graphe : la page reste ouverte dans son onglet.
    await tester.tap(viewTab('Graphe'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('node-a')), findsOneWidget);
    expect(viewTab('Page « a »'), findsOneWidget);
    // Toucher une autre page dans le graphe ne change pas la page de l'onglet.
    await tester.tap(find.byKey(const Key('node-b')));
    await tester.pumpAndSettle();
    expect(viewTab('Page « a »'), findsOneWidget);
    // Revenir à la page, puis la fermer.
    await tester.tap(viewTab('Page « a »'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('node-a')), findsNothing);
    await tester.tap(find.byKey(const Key('close-page')));
    await tester.pumpAndSettle();
    expect(viewTab('Page'), findsNothing);
    expect(find.byKey(const Key('node-a')), findsOneWidget);
  });

  testWidgets('« Ouvrir la page » ouvre l\'onglet de la page choisie', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('node-b')));
    await tester.pumpAndSettle();
    expect(find.text('Ouvrir la page'), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-page')));
    await tester.pumpAndSettle();
    expect(viewTab('Page « b »'), findsOneWidget);
  });

  testWidgets('les mingets gardent leur choix quand on change de vue', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(viewTab('Mingets'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('minget-trait')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('minget-details')), findsOneWidget);
    await tester.tap(viewTab('Graphe'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('minget-details')), findsNothing);
    await tester.tap(viewTab('Mingets'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('minget-details')), findsOneWidget);
  });
}
