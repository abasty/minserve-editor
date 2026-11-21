import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minserve_editor/src/history.dart';

import 'editor_page_test.dart' show pumpEditor, FakeFiles, codeText, loadTwo;

Snapshot snap(String t) =>
    Snapshot(t, const TextSelection.collapsed(offset: 0));

void main() {
  test('défaire et refaire', () {
    final h = EditHistory();
    expect(h.canUndo, isFalse);
    h.record(snap('a'));
    expect(h.undo(snap('b'))!.text, 'a');
    expect(h.canRedo, isTrue);
    expect(h.redo(snap('a'))!.text, 'b');
    expect(h.undo(snap('b'))!.text, 'a');
    // Une nouvelle modification efface ce qu'on pouvait refaire.
    h.record(snap('a'));
    expect(h.canRedo, isFalse);
  });

  test('l\'historique est borné', () {
    final h = EditHistory(limit: 3);
    for (var i = 0; i < 10; i++) {
      h.record(snap('$i'));
    }
    final seen = <String>[];
    var cur = snap('fin');
    for (var s = h.undo(cur); s != null; s = h.undo(s)) {
      seen.add(s.text);
    }
    expect(seen.length, 3);
    expect(seen.first, '9');
  });

  testWidgets('défaire une modification du graphe, au bouton et au clavier', (
    tester,
  ) async {
    await loadTwo(tester);
    final before = codeText(tester);
    expect(
      tester.widget<IconButton>(find.byKey(const Key('redo'))).onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('add-page')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('page-name')), 'neuve');
    await tester.pump();
    await tester.tap(find.byKey(const Key('dialog-ok')));
    await tester.pumpAndSettle();
    expect(codeText(tester), contains('  neuve:'));

    await tester.tap(find.byKey(const Key('undo')));
    await tester.pumpAndSettle();
    expect(codeText(tester), before);
    expect(find.byKey(const Key('node-neuve')), findsNothing);

    await tester.tap(find.byKey(const Key('redo')));
    await tester.pumpAndSettle();
    expect(codeText(tester), contains('  neuve:'));
    expect(find.byKey(const Key('node-neuve')), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(codeText(tester), before);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(codeText(tester), contains('  neuve:'));
  });

  testWidgets('la frappe et le graphe partagent la même pile', (tester) async {
    await pumpEditor(tester, FakeFiles());
    final start = codeText(tester);
    await tester.enterText(find.byKey(const Key('code')), '$start# a\n');
    await tester.pump(const Duration(milliseconds: 400));
    final typed = codeText(tester);
    await tester.tap(find.byKey(const Key('add-page')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('page-name')), 'p');
    await tester.pump();
    await tester.tap(find.byKey(const Key('dialog-ok')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('undo')));
    await tester.pumpAndSettle();
    expect(codeText(tester), typed);
    await tester.tap(find.byKey(const Key('undo')));
    await tester.pumpAndSettle();
    expect(codeText(tester), start);
    expect(
      tester.widget<IconButton>(find.byKey(const Key('undo'))).onPressed,
      isNull,
    );
  });

  testWidgets('ouvrir un fichier vide l\'historique', (tester) async {
    final files = FakeFiles();
    await pumpEditor(tester, files);
    await tester.enterText(find.byKey(const Key('code')), 'debut: a\n');
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.widget<IconButton>(find.byKey(const Key('undo'))).onPressed,
      isNotNull,
    );
    await tester.tap(find.byTooltip('Nouveau'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<IconButton>(find.byKey(const Key('undo'))).onPressed,
      isNull,
    );
  });

  Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Ctrl+Z et Ctrl+Y marchent en vue graphe, sans focus sur le texte',
    (tester) async {
      await pumpEditor(tester, FakeFiles());
      await tester.tap(find.byTooltip('Graphe'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-page')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('page-name')), 'neuve');
      await tester.pump();
      await tester.tap(find.byKey(const Key('dialog-ok')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('node-neuve')), findsOneWidget);

      await ctrl(tester, LogicalKeyboardKey.keyZ);
      expect(find.byKey(const Key('node-neuve')), findsNothing);
      await ctrl(tester, LogicalKeyboardKey.keyY);
      expect(find.byKey(const Key('node-neuve')), findsOneWidget);

      // Après un clic sur le graphe (sélection d'une page), encore.
      await tester.tap(find.byKey(const Key('node-neuve')));
      await tester.pump();
      await ctrl(tester, LogicalKeyboardKey.keyZ);
      expect(find.byKey(const Key('node-neuve')), findsNothing);
    },
  );
}
