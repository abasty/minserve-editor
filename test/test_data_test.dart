import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minserve_core/minserve_core.dart';
import 'package:minserve_editor/src/preview/page_preview.dart';
import 'package:minserve_editor/src/preview/test_data.dart';

import 'editor_page_test.dart' show pumpEditor, FakeFiles;
import 'page_preview_test.dart' show line;

const _service = r'''
debut: accueil
pages:
  accueil:
    ecran:
      - efface
      - position: {ligne: 3, col: 5}
      - ecrit: "Bonjour ${pseudo}"
    entree:
      zonesaisie: {ligne: 24, col: 1, longueur: 3}
      validation: [envoi]
    action:
      saisies:
        - {choix: "1", touche: envoi, suivant: autre, variable: pseudo}
  autre:
    ecran:
      - ecrit: "Total ${total} $${pas}"
    entree:
      zonesaisie: {ligne: 24, col: 1, longueur: 3}
      validation: [envoi]
    action:
      saisies:
        - {choix: "1", touche: envoi, suivant: accueil, variable: total}
''';

void main() {
  test('les variables citées : par page, puis ailleurs', () {
    final v = variablesFor(_service, 'accueil');
    expect(v.here, ['pseudo']);
    expect(v.elsewhere, ['total']);
    expect(variablesFor(_service, 'autre').here, ['total']);
    expect(variableNames(r'a $${x} ${y}'), {'y'});
  });

  test('l\'aperçu remplace les variables par les données de test', () {
    final service = Service.parseString(_service);
    final data = renderPreview(
      service,
      service.pages['accueil']!,
      variables: {'pseudo': 'Zoe'},
    );
    expect(line(data.minitel, 3, from: 5, length: 11), 'Bonjour Zoe');
  });

  testWidgets('le panneau des données de test change l\'aperçu', (
    tester,
  ) async {
    await pumpEditor(tester, FakeFiles());
    await tester.enterText(find.byKey(const Key('code')), _service);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('node-accueil')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('node-accueil')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('test-data')), findsNothing);
    await tester.tap(find.byKey(const Key('test-data-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('test-var-pseudo')), findsOneWidget);
    expect(find.byKey(const Key('test-var-total')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('test-var-pseudo')), 'Zoe');
    await tester.pumpAndSettle();
    final view = tester.widget<PagePreview>(find.byType(PagePreview));
    expect(view.variables, {'pseudo': 'Zoe'});
    // Une variable ajoutée à la main, puis retirée.
    await tester.enterText(find.byKey(const Key('test-var-new')), 'nb');
    await tester.tap(find.byKey(const Key('test-var-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('test-var-nb')), findsOneWidget);
    await tester.tap(find.byKey(const Key('test-var-remove-nb')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('test-var-nb')), findsNothing);
  });
}
