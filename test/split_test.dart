import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_page_test.dart' show pumpEditor, FakeFiles;

void main() {
  testWidgets('la poignée texte/graphe redimensionne les deux volets', (
    tester,
  ) async {
    await pumpEditor(tester, FakeFiles());
    final handle = find.byKey(const Key('split-text-graph'));
    final x0 = tester.getTopLeft(handle).dx;
    await tester.drag(handle, const Offset(120, 0));
    await tester.pump();
    expect(tester.getTopLeft(handle).dx, closeTo(x0 + 120, 1));
    // Le texte est plus large, le graphe plus étroit.
    expect(
      tester.getSize(find.byKey(const Key('summary'))).width,
      greaterThan(0),
    );
    // Au-delà d'un minimum, la poignée s'arrête.
    await tester.drag(handle, const Offset(2000, 0));
    await tester.pump();
    expect(tester.getTopLeft(handle).dx, lessThanOrEqualTo(1000 - 260 - 8 + 1));
    await tester.drag(handle, const Offset(-4000, 0));
    await tester.pump();
    expect(tester.getTopLeft(handle).dx, closeTo(260, 1));
  });

  testWidgets('la poignée du panneau de page change sa hauteur', (
    tester,
  ) async {
    await pumpEditor(tester, FakeFiles());
    await tester.tap(find.byKey(const Key('node-accueil')));
    await tester.pump();
    final handle = find.byKey(const Key('split-graph-details'));
    final y0 = tester.getTopLeft(handle).dy;
    await tester.drag(handle, const Offset(0, -80));
    await tester.pump();
    expect(tester.getTopLeft(handle).dy, closeTo(y0 - 80, 1));
    await tester.drag(handle, const Offset(0, 40));
    await tester.pump();
    expect(tester.getTopLeft(handle).dy, closeTo(y0 - 40, 1));
    // Le panneau reste utilisable : l'onglet Règles s'ouvre.
    await tester.tap(find.text('Règles'));
    await tester.pumpAndSettle();
  });
}
