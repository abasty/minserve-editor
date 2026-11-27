import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minserve_editor/src/editor_page.dart';
import 'package:minserve_editor/src/file_access.dart';

import 'editor_page_test.dart' show FakeFiles;

/// Un service assez large pour ne pas tenir à l'écran sans recadrage.
String _wide() {
  final b = StringBuffer('debut: p0\npages:\n');
  for (var i = 0; i < 12; i++) {
    b.write(
      '  p$i:\n    ecran: [efface]\n    entree:\n      zonesaisie: {ligne: 24, col: 1, longueur: 1}\n'
      '      validation: [envoi]\n    action:\n      saisies:\n'
      '        - {choix: "1", touche: envoi, suivant: p${(i + 1) % 12}}\n',
    );
  }
  return b.toString();
}

Future<void> pump(WidgetTester tester, {OpenedFile? file}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: EditorPage(files: FakeFiles(), initialFile: file),
    ),
  );
  await tester.pumpAndSettle();
}

/// Les cases des pages sont-elles toutes dans la fenêtre ?
bool allInside(WidgetTester tester, int count) {
  final area = tester.getRect(find.byKey(const Key('graph-area')));
  for (var i = 0; i < count; i++) {
    final r = tester.getRect(find.byKey(Key('node-p$i')));
    if (!area.contains(r.topLeft) || !area.contains(r.bottomRight)) {
      return false;
    }
  }
  return true;
}

void main() {
  testWidgets('au départ : le graphe seul, recadré sur la fenêtre', (
    tester,
  ) async {
    await pump(tester, file: OpenedFile('grand.yaml', _wide()));
    // Le graphe prend toute la largeur ; le texte est à largeur nulle.
    expect(tester.getSize(find.byKey(const Key('pane-graph'))).width, 1280);
    expect(tester.getSize(find.byKey(const Key('pane-text'))).width, 0);
    expect(allInside(tester, 12), true);
  });

  testWidgets('un autre fichier ouvert est recadré lui aussi', (tester) async {
    await pump(tester);
    final files = FakeFiles()..toOpen = OpenedFile('grand.yaml', _wide());
    await tester.pumpWidget(MaterialApp(home: EditorPage(files: files)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ouvrir'));
    await tester.pumpAndSettle();
    expect(allInside(tester, 12), true);
  });
}
