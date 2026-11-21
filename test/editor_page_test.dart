import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minserve_editor/src/editor_page.dart';
import 'package:minserve_editor/src/file_access.dart';

class FakeFiles implements FileAccess {
  OpenedFile? toOpen;
  final saved = <(String, String)>[];

  @override
  Future<OpenedFile?> open() async => toOpen;

  @override
  Future<void> save(String name, String text) async => saved.add((name, text));
}

Future<void> pumpEditor(WidgetTester tester, FakeFiles files) async {
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: EditorPage(files: files)));
}

String status(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(const Key('status')),
        matching: find.byType(Text),
      ),
    )
    .data!;

void main() {
  testWidgets('un nouveau service est valide', (tester) async {
    await pumpEditor(tester, FakeFiles());
    expect(status(tester), 'Service valide : 1 page, départ : accueil');
  });

  testWidgets('une erreur est affichée avec sa ligne', (tester) async {
    await pumpEditor(tester, FakeFiles());
    await tester.enterText(find.byType(TextField), 'debut: a\npages: 3\n');
    await tester.pump(const Duration(milliseconds: 400));
    expect(status(tester), startsWith('ligne '));
    expect(
      tester.widget<Text>(find.byKey(const Key('file-name'))).data,
      'service.yaml •',
    );
  });

  testWidgets('ouvrir un fichier remplace le texte', (tester) async {
    final files = FakeFiles()
      ..toOpen = const OpenedFile(
        'jeu.yaml',
        'debut: a\npages:\n  a:\n    ecran: [efface]\n  b:\n    ecran: [efface]\n',
      );
    await pumpEditor(tester, files);
    await tester.tap(find.byTooltip('Ouvrir'));
    await tester.pumpAndSettle();
    expect(status(tester), 'Service valide : 2 pages, départ : a');
    expect(
      tester.widget<Text>(find.byKey(const Key('file-name'))).data,
      'jeu.yaml',
    );
  });

  testWidgets('enregistrer envoie le texte et efface la marque', (
    tester,
  ) async {
    final files = FakeFiles();
    await pumpEditor(tester, files);
    await tester.enterText(find.byType(TextField), '$newServiceText# fin\n');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('Enregistrer'));
    await tester.pump();
    expect(files.saved.single.$1, 'service.yaml');
    expect(files.saved.single.$2, endsWith('# fin\n'));
    expect(
      tester.widget<Text>(find.byKey(const Key('file-name'))).data,
      'service.yaml',
    );
  });

  testWidgets('ouvrir demande confirmation si le texte a changé', (
    tester,
  ) async {
    final files = FakeFiles()
      ..toOpen = const OpenedFile('x.yaml', newServiceText);
    await pumpEditor(tester, files);
    await tester.enterText(find.byType(TextField), 'debut: a\n');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('Ouvrir'));
    await tester.pumpAndSettle();
    expect(find.text('Modifications non enregistrées'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('file-name'))).data,
      'service.yaml •',
    );
  });
}
