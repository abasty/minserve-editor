import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minserve_core/minserve_core.dart';
import 'package:minserve_editor/src/preview/page_preview.dart';
import 'package:minterm_view/minterm_view.dart';

import 'editor_page_test.dart' show pumpEditor, FakeFiles;

const _service = '''
debut: accueil
pages:
  accueil:
    ecran:
      - efface
      - position: {ligne: 3, col: 5}
      - ecrit: "Bonjour"
      - affiche: absent.vdt
    entree:
      zonesaisie: {ligne: 24, col: 1, longueur: 3}
      validation: [envoi]
    action:
      saisies:
        - {choix: "1", touche: envoi, suivant: accueil}
''';

String line(TMinitel m, int row, {int from = 1, int length = 40}) =>
    String.fromCharCodes([
      for (var c = from; c < from + length; c++) m.screen[row][c].code & 0x7F,
    ]);

void main() {
  test('rend la page comme le serveur : texte, zone de saisie', () {
    final service = Service.parseString(_service);
    final data = renderPreview(service, service.pages['accueil']!);
    expect(data.error, isNull);
    expect(line(data.minitel, 3, from: 5, length: 7), 'Bonjour');
    // La zone de saisie vide : trois points en ligne 24, colonne 1.
    expect(line(data.minitel, 24, length: 3), '...');
    expect(data.missing, ['absent.vdt']);
  });

  testWidgets('l\'onglet Rendu montre l\'écran de la page', (tester) async {
    await pumpEditor(tester, FakeFiles());
    await tester.enterText(find.byKey(const Key('code')), _service);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('node-accueil')));
    await tester.pump();
    await tester.ensureVisible(find.text('Rendu'));
    await tester.tap(find.text('Rendu'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preview-screen')), findsOneWidget);
    expect(find.byType(MinitelView), findsOneWidget);
    expect(find.byKey(const Key('preview-missing')), findsOneWidget);
    final size = tester.getSize(find.byType(MinitelView));
    expect(size.width / size.height, closeTo(4 / 3, 0.01));
  });

  testWidgets('le double clic ouvre la page en grand : rendu en haut, '
      'propriétés en bas', (tester) async {
    await pumpEditor(tester, FakeFiles());
    await tester.enterText(find.byKey(const Key('code')), _service);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('preview-screen')), findsNothing);
    await tester.tap(find.byKey(const Key('node-accueil')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('node-accueil')));
    await tester.pumpAndSettle();
    // Le graphe a laissé la place.
    expect(find.byKey(const Key('node-accueil')), findsNothing);
    expect(find.byKey(const Key('preview-screen')), findsOneWidget);
    expect(find.byKey(const Key('details')), findsOneWidget);
    final screen = tester.getRect(find.byKey(const Key('preview-screen')));
    final details = tester.getRect(find.byKey(const Key('details')));
    expect(screen.bottom, lessThanOrEqualTo(details.top));
    expect(screen.height, greaterThan(150));
    // Pas d'onglet Rendu en double.
    expect(find.text('Rendu'), findsNothing);
    // Niveaux de gris par défaut ; la palette bascule en couleur.
    final view = find.byType(MinitelView);
    expect(tester.widget<MinitelView>(view).colors, MinGrey);
    await tester.tap(find.byKey(const Key('preview-colors')));
    await tester.pumpAndSettle();
    expect(tester.widget<MinitelView>(view).colors, MinColors);
    // Retour au graphe.
    await tester.tap(find.byKey(const Key('back-to-graph')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('node-accueil')), findsOneWidget);
    expect(find.byKey(const Key('preview-screen')), findsNothing);
  });
}
