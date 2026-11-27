import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minserve_core/minserve_core.dart';
import 'package:minserve_editor/src/graph/library.dart';
import 'package:minserve_editor/src/graph/minget_panel.dart';
import 'package:minserve_editor/src/graph/service_edit.dart';
import 'package:minserve_editor/src/preview/page_preview.dart';
import 'package:minterm_view/minterm_view.dart';

import 'editor_page_test.dart' show pumpEditor, FakeFiles, codeText, viewTab;

const _noMacros = '''
debut: a
pages:
  a:
    ecran: [efface]
''';

const _withMacros = '''
debut: a
macros:
  trait:
    - position: {ligne: 1, col: 1}
  # le dernier
  regle:
    - efface
pages:
  a:
    ecran: [efface]
''';

const _library = '''
# En-tête
macros:
  # Un cadre.
  cadre:
    description: "Un cadre"
    parametres:
      - {nom: ligne, type: entier, defaut: 3, min: 1, max: 20}
    ecran:
      - position: {ligne: \$1, col: 1}
      - ecrit: "+"

  regle:
    - efface
''';

void main() {
  pickerTests();
  sameNameTests();
  late List<LibraryMinget> library;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    library = await libraryMingets();
  });

  test('la bibliothèque livrée est valide, chaque minget se rend', () {
    expect(
      library.map((m) => m.name),
      containsAll(['titre-centre', 'titre-simple', 'regle', 'choix']),
    );
    for (final m in library) {
      final text = withLibraryMacro(_noMacros, m.name, m.block);
      final service = Service.parseString(
        mingetPreviewText(text, m.name, defaultMingetArgs(m.definition)),
      );
      expect(service.pages[mingetPage], isNotNull, reason: m.name);
      // Aucun paramètre sans type : la bibliothèque est en forme étendue.
      expect(m.definition.extended, true, reason: m.name);
    }
  });

  test(
    'titre-centre : la colonne se calcule d\'après la longueur du texte',
    () {
      final m = library.firstWhere((m) => m.name == 'titre-centre');
      String row(String text, int from, int length) {
        final service = Service.parseString(
          mingetPreviewText(
            withLibraryMacro(_noMacros, m.name, m.block),
            m.name,
            [4, text],
          ),
        );
        final minitel = renderPreview(
          service,
          service.pages[mingetPage]!,
        ).minitel;
        return String.fromCharCodes([
          for (var c = from; c < from + length; c++)
            minitel.screen[4][c].code & 0x7F,
        ]);
      }

      // 40 colonnes : « Menu » (4 lettres) commence en colonne 19, « Accueil » (7) en 17.
      expect(row('Menu', 19, 4), 'Menu');
      expect(row('Accueil', 17, 7), 'Accueil');
      // Un texte de 40 caractères commence en colonne 1.
      final long = 'x' * 40;
      expect(row(long, 1, 40), long);
    },
  );

  group('fond et cadre-3d', () {
    LibraryMinget named(String name) =>
        library.firstWhere((m) => m.name == name);

    TMinitel draw(String name, List<Object?> args) {
      final m = named(name);
      final service = Service.parseString(
        mingetPreviewText(
          withLibraryMacro(_noMacros, m.name, m.block),
          m.name,
          args,
        ),
      );
      final data = renderPreview(service, service.pages[mingetPage]!);
      expect(data.error, isNull);
      return data.minitel;
    }

    int code(TMinitel t, int r, int c) => t.screen[r][c].code & 0x7F;

    String row(TMinitel t, int r, int from, int length) => String.fromCharCodes(
      [for (var c = from; c < from + length; c++) code(t, r, c)],
    );

    test('fond par défaut : bande sur tout l\'écran, avec son bord', () {
      final t = draw('fond', [1, 1, 11, 36, 'rouge', 1]);
      expect(row(t, 1, 2, 37), '_' * 37);
      expect(row(t, 2, 1, 2), '}{');
      expect(row(t, 23, 1, 2), '}{');
      expect(row(t, 23, 39, 1), '{');
      expect(row(t, 24, 2, 37), '~' * 37);
    });

    test('fond : origine, taille et couleur', () {
      final base = draw('fond', [1, 1, 2, 8, 'rouge', 1]);
      final moved = draw('fond', [6, 20, 2, 8, 'rouge', 1]);
      // Le coin (1, 1) devient (6, 20) : tout glisse de 5 lignes et 19 colonnes.
      for (var r = 1; r <= 6; r++) {
        for (var c = 1; c <= 12; c++) {
          expect(
            [
              moved.screen[r + 5][c + 19].code,
              moved.screen[r + 5][c + 19].gAttr,
              moved.screen[r + 5][c + 19].lAttr,
            ],
            [
              base.screen[r][c].code,
              base.screen[r][c].gAttr,
              base.screen[r][c].lAttr,
            ],
            reason: 'case $r,$c',
          );
        }
      }
      final bleu = draw('fond', [1, 1, 2, 8, 'bleu', 1]);
      expect(bleu.screen[3][5].lAttr, isNot(base.screen[3][5].lAttr));
      expect(row(bleu, 3, 1, 2), row(base, 3, 1, 2));
    });

    test('fond sans bord : ni côtés ni traits', () {
      final t = draw('fond', [1, 1, 3, 10, 'rouge', 0]);
      for (var r = 1; r <= 24; r++) {
        for (var c = 1; c <= 40; c++) {
          expect(code(t, r, c), 0x20, reason: 'case $r,$c');
        }
      }
    });

    test('cadre-3d : position, taille, et pas de fond autour', () {
      // Coin (5, 3), 2 lignes de texte, 10 colonnes : lignes 5 à 5 + 3 + 2 = 10.
      final t = draw('cadre-3d', [5, 3, 2, 10, 'rouge']);
      expect(row(t, 5, 3, 10), '/' * 10);
      // Le bout de la barre du haut est un bloc plein, sur fond noir.
      expect(code(t, 5, 13), 0x7F);
      expect(row(t, 6, 3, 10), '|' * 10);
      expect(code(t, 6, 13), 0x6F);
      for (final r in [7, 8, 9]) {
        expect(code(t, r, 13), 0x6A, reason: 'ligne $r');
      }
      expect(row(t, 9, 3, 10), 'p' * 10);
      expect(row(t, 10, 3, 10), '#' * 10);
      expect(code(t, 10, 13), 0x6A);
      // Rien ailleurs : ni bloc plein, ni caractère hors du cadre.
      for (var r = 1; r <= 24; r++) {
        for (var c = 1; c <= 40; c++) {
          final dedans = r >= 5 && r <= 10 && c >= 3 && c <= 13;
          if (!(r == 5 && c == 13)) {
            expect(code(t, r, c), isNot(0x7F), reason: 'bloc plein $r,$c');
          }
          if (!dedans) expect(code(t, r, c), 0x20, reason: 'case $r,$c');
        }
      }
    });

    test('cadre-3d : la colonne et la ligne déplacent tout', () {
      List<int> cell(TMinitel t, int r, int c) => [
        t.screen[r][c].code,
        t.screen[r][c].gAttr,
        t.screen[r][c].lAttr,
      ];
      final base = draw('cadre-3d', [4, 3, 2, 10, 'cyan']);
      final moved = draw('cadre-3d', [9, 20, 2, 10, 'cyan']);
      for (var r = 4; r <= 9; r++) {
        for (var c = 3; c <= 13; c++) {
          expect(
            cell(moved, r + 5, c + 17),
            cell(base, r, c),
            reason: 'case $r,$c',
          );
        }
      }
    });
  });

  test(
    'les blocs : les commentaires du dessus viennent avec la définition',
    () {
      final blocks = libraryBlocks(_library);
      expect(blocks.keys, ['cadre', 'regle']);
      expect(blocks['cadre']!.first, '  # Un cadre.');
      expect(blocks['cadre']!.last, '      - ecrit: "+"');
      expect(blocks['regle'], ['  regle:', '    - efface']);
      expect(() => libraryBlocks('debut: a\n'), throwsA(isA<EditException>()));
    },
  );

  test('ajouter à un service sans macros : une section avant pages', () {
    final cadre = parseLibrary(_library).first;
    final out = addLibraryMacro(_noMacros, cadre.name, cadre.block);
    expect(
      out,
      'debut: a\n'
      'macros:\n'
      '  # Un cadre.\n'
      '  cadre:\n'
      '    description: "Un cadre"\n'
      '    parametres:\n'
      '      - {nom: ligne, type: entier, defaut: 3, min: 1, max: 20}\n'
      '    ecran:\n'
      '      - position: {ligne: \$1, col: 1}\n'
      '      - ecrit: "+"\n'
      '\n'
      'pages:\n'
      '  a:\n'
      '    ecran: [efface]\n',
    );
    expect(Service.parseString(out).macros.keys, ['cadre']);
  });

  test('ajouter à la suite des macros, sous un autre nom si on le demande', () {
    final cadre = parseLibrary(_library).first;
    final out = addLibraryMacro(_withMacros, 'cadre', cadre.block, as: 'boite');
    expect(Service.parseString(out).macros.keys, ['trait', 'regle', 'boite']);
    expect(out, contains('    - efface\n\n  # Un cadre.\n  boite:\n'));
    // Le reste du texte n'a pas bougé.
    expect(
      out.replaceAll(RegExp(r'\n\n  # Un cadre\.[\s\S]*?(?=pages:)'), '\n'),
      _withMacros,
    );
  });

  test('un nom pris ou invalide est refusé, le texte est inchangé', () {
    final cadre = parseLibrary(_library).first;
    expect(
      () => addLibraryMacro(_withMacros, 'cadre', cadre.block, as: 'trait'),
      throwsA(isA<EditException>()),
    );
    expect(
      () => addLibraryMacro(_withMacros, 'cadre', cadre.block, as: 'a b'),
      throwsA(isA<EditException>()),
    );
  });

  test('l\'état d\'un minget dans le service', () {
    final cadre = parseLibrary(_library).first;
    final regle = parseLibrary(_library).last;
    expect(libraryState(_noMacros, 'cadre', cadre.block), LibraryState.absent);
    final added = addLibraryMacro(_noMacros, 'cadre', cadre.block);
    expect(libraryState(added, 'cadre', cadre.block), LibraryState.same);
    // « regle » du service n'a pas la même définition que celle de la bibliothèque.
    expect(libraryState(_withMacros, 'regle', regle.block), LibraryState.same);
    final other = _withMacros.replaceFirst(
      '    - efface\npages',
      '    - efface\n    - ecrit: "x"\npages',
    );
    expect(libraryState(other, 'regle', regle.block), LibraryState.different);
  });

  Future<void> openLibrary(WidgetTester tester, String service) async {
    await pumpEditor(tester, FakeFiles());
    await tester.enterText(find.byKey(const Key('code')), service);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(viewTab('Mingets'));
    await tester.pumpAndSettle();
    // Le fichier de la bibliothèque se lit en vrai temps, pas en temps simulé.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('la bibliothèque dans le panneau : liste, aperçu, ajout', (
    tester,
  ) async {
    await openLibrary(tester, _noMacros);
    // Les deux sections : le service (vide ici) et la bibliothèque.
    expect(find.text('Du service (0)'), findsOneWidget);
    expect(find.byKey(const Key('no-macros')), findsOneWidget);
    expect(find.byKey(const Key('section-library')), findsOneWidget);
    expect(find.textContaining('Bibliothèque ('), findsOneWidget);
    expect(find.byKey(const Key('lib-titre-centre')), findsOneWidget);
    expect(find.byKey(const Key('lib-titre-simple')), findsOneWidget);
    expect(find.byKey(const Key('lib-new')), findsAtLeastNWidgets(3));
    await tester.tap(find.byKey(const Key('lib-titre-simple')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('library-note'))).data,
      contains('pas encore dans le service'),
    );
    expect(find.byKey(const Key('preview-screen')), findsOneWidget);
    expect(find.byKey(const Key('minget-error')), findsNothing);
    expect(codeText(tester), isNot(contains('titre-simple')));
    await tester.tap(find.byKey(const Key('library-add')));
    await tester.pumpAndSettle();
    // On revient aux mingets du service, le nouveau est choisi.
    expect(codeText(tester), contains('  titre-simple:\n'));
    expect(find.byKey(const Key('minget-titre-simple')), findsOneWidget);
    expect(find.byKey(const Key('minget-details')), findsOneWidget);
    // Dans la liste, il est maintenant marqué présent.
    expect(find.byKey(const Key('lib-in-service')), findsOneWidget);
    expect(find.byKey(const Key('lib-new')), findsAtLeastNWidgets(3));
    await tester.tap(find.byKey(const Key('lib-titre-simple')));
    await tester.pumpAndSettle();
    expect(find.text('Déjà dans le service'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('library-note'))).data,
      contains('déjà dans le service'),
    );
  });

  testWidgets('un minget différent de même nom : un autre nom est demandé', (
    tester,
  ) async {
    await openLibrary(
      tester,
      _noMacros.replaceFirst(
        'pages:',
        'macros:\n  titre-simple:\n    - efface\npages:',
      ),
    );
    expect(find.byKey(const Key('lib-differs')), findsOneWidget);
    await tester.tap(find.byKey(const Key('lib-titre-simple')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library-differs')), findsOneWidget);
    await tester.tap(find.byKey(const Key('library-add')));
    await tester.pumpAndSettle();
    expect(find.text('Un minget « titre-simple » existe déjà'), findsOneWidget);
    await tester.tap(find.byKey(const Key('dialog-ok')));
    await tester.pumpAndSettle();
    expect(codeText(tester), contains('  titre-simple-2:\n'));
    expect(codeText(tester), contains('  titre-simple:\n    - efface'));
    expect(find.byKey(const Key('minget-titre-simple-2')), findsOneWidget);
  });
}

/// Le sélecteur d'instruction de l'onglet Écran propose aussi la bibliothèque.
void pickerTests() {
  const service = r'''
debut: a
macros:
  regle:
    - efface
pages:
  a:
    ecran:
      - efface
''';

  Future<void> openScreen(WidgetTester tester, String text) async {
    await pumpEditor(tester, FakeFiles());
    await tester.enterText(find.byKey(const Key('code')), text);
    await tester.pump(const Duration(milliseconds: 400));
    // La bibliothèque se lit en vrai temps, pas en temps simulé.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('node-a')));
    await tester.pump();
    final tab = find.descendant(
      of: find.byKey(const Key('page-tabs')),
      matching: find.text('Écran'),
    );
    await tester.ensureVisible(tab);
    await tester.tap(tab);
    await tester.pumpAndSettle();
    final add = find.byKey(const Key('screen-add-1')).first;
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
  }

  testWidgets('le sélecteur propose les modèles qui ne sont pas au service', (
    tester,
  ) async {
    await openScreen(tester, service);
    await tester.enterText(
      find.byKey(const Key('instruction-filter')),
      'regle',
    );
    await tester.pumpAndSettle();
    // « regle » est déjà au service : une seule entrée, celle du service.
    expect(find.byKey(const Key('instruction-macro-regle')), findsOneWidget);
    expect(find.byKey(const Key('instruction-lib-titre-simple')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('instruction-filter')),
      'titre-c',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('instruction-lib-titre-centre')),
      findsOneWidget,
    );
    expect(find.textContaining('(bibliothèque)'), findsAtLeastNWidgets(1));
  });

  testWidgets('choisir un modèle l\'ajoute au service avec son appel', (
    tester,
  ) async {
    await openScreen(tester, service);
    await tester.enterText(
      find.byKey(const Key('instruction-filter')),
      'titre-s',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('instruction-lib-titre-simple')));
    await tester.pumpAndSettle();
    // Le formulaire d'appel, avec les valeurs par défaut du modèle.
    expect(find.byKey(const Key('macro-arg-0')), findsOneWidget);
    await tester.tap(find.byKey(const Key('dialog-ok')));
    await tester.pumpAndSettle();
    final text = codeText(tester);
    expect(text, contains('  titre-simple:\n'));
    expect(text, contains('- macro: [titre-simple]'));
    expect(Service.parseString(text).macros.keys, ['regle', 'titre-simple']);
    // Une seule modification : un « défaire » retire le minget et l'appel.
    await tester.tap(find.byKey(const Key('undo')));
    await tester.pumpAndSettle();
    expect(codeText(tester), service);
  });
}

/// Un minget du service qui a le nom d'un modèle de la bibliothèque, mais pas les
/// mêmes paramètres : l'essayer ne doit pas casser les appels du service.
void sameNameTests() {
  const service = r'''
debut: a
macros:
  titre-simple:
    - position: {ligne: $1, col: 1}
    - ecrit: "$2 $3 $4 $5"
pages:
  a:
    ecran:
      - macro: [titre-simple, 5, "x", "y", "z", "t"]
''';

  Future<void> open(WidgetTester tester) async {
    await pumpEditor(tester, FakeFiles());
    await tester.enterText(find.byKey(const Key('code')), service);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(viewTab('Mingets'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
  }

  test('l\'aperçu d\'un modèle n\'écrase pas le minget du service', () async {
    final lib = (await libraryMingets()).firstWhere(
      (m) => m.name == 'titre-simple',
    );
    final text = withLibraryMacro(
      service,
      lib.name,
      lib.block,
      as: libraryPreviewMacro,
    );
    final parsed = Service.parseString(
      mingetPreviewText(text, libraryPreviewMacro, [1, 'x']),
    );
    // Les deux existent : celle du service (5 paramètres) et celle du modèle (2).
    expect(parsed.macros['titre-simple']!.arity, 5);
    expect(parsed.macros[libraryPreviewMacro]!.arity, 2);
  });

  testWidgets('le modèle s\'affiche malgré le minget du même nom', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('lib-titre-simple')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('minget-error')), findsNothing);
    expect(find.byKey(const Key('preview-screen')), findsOneWidget);
    expect(find.byKey(const Key('library-differs')), findsOneWidget);
  });
}
