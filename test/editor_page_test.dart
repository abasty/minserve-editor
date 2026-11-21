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
  graphTests();
  testWidgets('un nouveau service est valide', (tester) async {
    await pumpEditor(tester, FakeFiles());
    expect(status(tester), 'Service valide : 1 page, départ : accueil');
  });

  testWidgets('une erreur est affichée avec sa ligne', (tester) async {
    await pumpEditor(tester, FakeFiles());
    await tester.enterText(
      find.byKey(const Key('code')),
      'debut: a\npages: 3\n',
    );
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
    await tester.enterText(
      find.byKey(const Key('code')),
      '$newServiceText# fin\n',
    );
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
    await tester.enterText(find.byKey(const Key('code')), 'debut: a\n');
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

const _two = '''
debut: a
pages:
  a:
    ecran: [efface]
    entree:
      zonesaisie: {ligne: 24, col: 1, longueur: 1}
      validation: [envoi]
    action:
      saisies:
        - {choix: "1", touche: envoi, suivant: b}
  b:
    ecran: [efface]
''';

void graphTests() {
  testWidgets('le graphe suit le texte et garde le dernier texte valide', (
    tester,
  ) async {
    await pumpEditor(tester, FakeFiles());
    expect(find.byKey(const Key('node-accueil')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('code')), _two);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('node-a')), findsOneWidget);
    expect(find.byKey(const Key('node-b')), findsOneWidget);
    expect(find.byKey(const Key('node-accueil')), findsNothing);
    expect(find.byKey(const Key('stale')), findsNothing);
    // Texte cassé : le graphe reste, avec un bandeau.
    await tester.enterText(
      find.byKey(const Key('code')),
      'debut: a\npages: 3\n',
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('node-b')), findsOneWidget);
    expect(find.byKey(const Key('stale')), findsOneWidget);
  });

  testWidgets('toucher une page affiche ses transitions', (tester) async {
    await pumpEditor(tester, FakeFiles());
    await tester.enterText(find.byKey(const Key('code')), _two);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('node-a')));
    await tester.pump();
    final details = find.byKey(const Key('details'));
    expect(details, findsOneWidget);
    expect(
      find.descendant(of: details, matching: find.textContaining('→ b')),
      findsOneWidget,
    );
    expect(find.text('page de départ'), findsOneWidget);
    expect(find.text('impasse : aucune saisie'), findsNothing);
    // b est une impasse (sans saisie) ; une pastille la signale.
    expect(find.byKey(const Key('dead-ends')), findsOneWidget);
  });

  testWidgets('Aller au texte met le curseur sur la page', (tester) async {
    await pumpEditor(tester, FakeFiles());
    await tester.enterText(find.byKey(const Key('code')), _two);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('node-b')));
    await tester.pump();
    await tester.tap(find.text('Aller au texte'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final field = tester.widget<TextField>(find.byKey(const Key('code')));
    final text = field.controller!.text;
    final line = text
        .substring(0, field.controller!.selection.start)
        .split('\n')
        .length;
    expect(line, 11); // la ligne « b: »
  });

  testWidgets('la vue texte seule cache le graphe', (tester) async {
    await pumpEditor(tester, FakeFiles());
    await tester.tap(find.byTooltip('Texte'));
    await tester.pump();
    expect(find.byKey(const Key('summary')).hitTestable(), findsNothing);
    await tester.tap(find.byTooltip('Graphe'));
    await tester.pump();
    expect(find.byKey(const Key('summary')).hitTestable(), findsOneWidget);
  });
}
