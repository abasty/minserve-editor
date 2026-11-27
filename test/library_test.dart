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
      containsAll([
        'titre-centre',
        'cadre-3d',
        'option',
        'titre-simple',
        'regle',
        'choix',
      ]),
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

  group('fond : position, taille, couleur, bord', () {
    LibraryMinget fond() => library.firstWhere((m) => m.name == 'fond');

    TMinitel draw(List<Object?> args) {
      final service = Service.parseString(
        mingetPreviewText(
          withLibraryMacro(_noMacros, fond().name, fond().block),
          fond().name,
          args,
        ),
      );
      final data = renderPreview(service, service.pages[mingetPage]!);
      expect(data.error, isNull);
      return data.minitel;
    }

    String row(TMinitel t, int r, int from, int length) => String.fromCharCodes(
      [for (var c = from; c < from + length; c++) t.screen[r][c].code & 0x7F],
    );

    List<int> cell(TMinitel t, int r, int c) => [
      t.screen[r][c].code,
      t.screen[r][c].gAttr,
      t.screen[r][c].lAttr,
    ];

    test('avec bord : traits, côtés, nombre de lignes et de colonnes', () {
      final t = draw([1, 1, 3, 10, 'rouge', 1]);
      // Trois lignes en double hauteur : lignes d'écran 2 à 7, trait du bas en 8.
      expect(row(t, 1, 2, 11), '_' * 11);
      for (var r = 2; r <= 7; r++) {
        expect(row(t, r, 1, 2), '}{', reason: 'ligne $r');
        expect(row(t, r, 13, 1), '{', reason: 'ligne $r');
      }
      expect(row(t, 8, 2, 11), '~' * 11);
      expect(row(t, 8, 1, 1), ' ');
      expect(row(t, 9, 1, 3), '   ');
    });

    test('par défaut : tout l\'écran, 11 lignes de 36 colonnes', () {
      final t = draw([1, 1, 11, 36, 'rouge', 1]);
      expect(row(t, 1, 2, 37), '_' * 37);
      expect(row(t, 23, 1, 2), '}{');
      expect(row(t, 23, 39, 1), '{');
      expect(row(t, 24, 2, 37), '~' * 37);
    });

    test('la ligne et la colonne d\'origine déplacent tout le fond', () {
      final base = draw([1, 1, 2, 8, 'rouge', 1]);
      final moved = draw([6, 20, 2, 8, 'rouge', 1]);
      // Le coin (1, 1) devient (6, 20) : tout glisse de 5 lignes et 19 colonnes.
      for (var r = 1; r <= 6; r++) {
        for (var c = 1; c <= 12; c++) {
          expect(
            cell(moved, r + 5, c + 19),
            cell(base, r, c),
            reason: 'case $r,$c',
          );
        }
      }
      // Rien n'est resté à l'ancienne place.
      expect(row(moved, 1, 1, 12), ' ' * 12);
      expect(row(moved, 2, 1, 3), '   ');
      // Le trait du bas : ligne + 2 * lignes + 1 = 11.
      expect(row(moved, 11, 21, 9), '~' * 9);
    });

    test('la couleur de la bande se choisit', () {
      final rouge = draw([1, 1, 1, 6, 'rouge', 1]);
      final bleu = draw([1, 1, 1, 6, 'bleu', 1]);
      final bleu2 = draw([1, 1, 1, 6, 'bleu', 1]);
      // La bande (colonnes 3 à 8, ligne d'écran 3) change avec la couleur...
      expect(cell(bleu, 3, 5), isNot(cell(rouge, 3, 5)));
      // ... et c'est la seule différence : les traits et le bord restent.
      expect(row(bleu, 3, 1, 2), row(rouge, 3, 1, 2));
      expect(cell(bleu, 3, 5), cell(bleu2, 3, 5));
      expect(() => draw([1, 1, 1, 6, 'turquoise', 1]), throwsA(anything));
    });

    test('sans bord : la bande reste en place, rien d\'autre', () {
      final avec = draw([1, 1, 3, 10, 'rouge', 1]);
      final sans = draw([1, 1, 3, 10, 'rouge', 0]);
      for (var r = 1; r <= 8; r++) {
        for (var c = 1; c <= 40; c++) {
          final bord = [1, 2, 13].contains(c) || r == 1 || r == 8;
          if (bord) {
            // Ni caractère ni trait : une case vide.
            expect(
              sans.screen[r][c].code & 0x7F,
              0x20,
              reason: 'ligne $r colonne $c',
            );
          } else if (c >= 3 && c <= 12) {
            // La bande est celle d'avant : mêmes attributs, mêmes cases.
            expect(
              cell(sans, r, c),
              cell(avec, r, c),
              reason: 'ligne $r colonne $c',
            );
          }
        }
      }
    });

    test('des valeurs hors bornes sont refusées', () {
      for (final args in [
        [0, 1, 3, 10, 'rouge', 1],
        [22, 1, 3, 10, 'rouge', 1],
        [1, 0, 3, 10, 'rouge', 1],
        [1, 38, 3, 10, 'rouge', 1],
        [1, 1, 12, 10, 'rouge', 1],
        [1, 1, 3, 37, 'rouge', 1],
        [1, 1, 3, 10, 'rouge', 2],
      ]) {
        expect(
          () => Service.parseString(
            mingetPreviewText(
              withLibraryMacro(_noMacros, fond().name, fond().block),
              fond().name,
              args,
            ),
          ),
          throwsA(isA<ServiceException>()),
          reason: '$args',
        );
      }
    });
  });

  test('cadre-3d : le cadre seul, sans le fond rouge autour', () {
    final m = library.firstWhere((m) => m.name == 'cadre-3d');
    expect(m.definition.parameters.map((p) => p.name), [
      'ligne',
      'col',
      'lignes',
      'colonnes',
    ]);
    final service = Service.parseString(
      mingetPreviewText(withLibraryMacro(_noMacros, m.name, m.block), m.name, [
        5,
        3,
        2,
      ]),
    );
    final data = renderPreview(service, service.pages[mingetPage]!);
    expect(data.error, isNull);
    int code(int r, int c) => data.minitel.screen[r][c].code & 0x7F;
    // Le cadre : lignes 5 à 5 + 3 + 2 = 10, colonnes 3 à 38 (« o » ou « j » en 39).
    final empty = data.minitel.screen[15][20];
    for (var r = 5; r <= 10; r++) {
      for (var c = 3; c <= 38; c++) {
        final cell = data.minitel.screen[r][c];
        if (r == 7 || r == 8) {
          // Les lignes de texte : des espaces, mais sur le fond du cadre.
          expect(
            [cell.gAttr, cell.lAttr],
            isNot([empty.gAttr, empty.lAttr]),
            reason: 'texte $r,$c',
          );
        } else {
          expect(code(r, c), isNot(0x20), reason: 'cadre $r,$c');
        }
      }
    }
    expect(
      [code(6, 39), code(7, 39), code(8, 39), code(9, 39)],
      [
        0x6F, // « o » après la bande foncée
        0x6A, // « j » après chaque ligne de texte
        0x6A,
        0x6A,
      ],
    );
    // Pas de bloc plein (0x7f) : ni sur les côtés, ni en dessous.
    for (var r = 1; r <= 24; r++) {
      for (var c = 1; c <= 40; c++) {
        expect(code(r, c), isNot(0x7F), reason: 'bloc plein $r,$c');
      }
    }
    // Rien en colonnes 1 et 2, rien avant ni après le cadre.
    for (var r = 5; r <= 10; r++) {
      expect([code(r, 1), code(r, 2), code(r, 40)], [0x20, 0x20, 0x20]);
    }
    expect([code(4, 10), code(11, 10)], [0x20, 0x20]);
  });

  test('cadre-3d : le nombre de colonnes', () {
    final m = library.firstWhere((m) => m.name == 'cadre-3d');
    TMinitel draw(int colonnes) {
      final service = Service.parseString(
        mingetPreviewText(
          withLibraryMacro(_noMacros, m.name, m.block),
          m.name,
          [2, 3, 3, colonnes],
        ),
      );
      final data = renderPreview(service, service.pages[mingetPage]!);
      expect(data.error, isNull);
      return data.minitel;
    }

    int code(TMinitel t, int r, int c) => t.screen[r][c].code & 0x7F;
    for (final colonnes in [1, 10, 36]) {
      final t = draw(colonnes);
      // Lignes 2 à 2 + 3 + 3 = 8 : la barre du haut (2) fait « colonnes » cases,
      // en colonnes 3 à colonnes + 2, et rien de plus loin.
      for (var c = 3; c <= colonnes + 2; c++) {
        expect(code(t, 2, c), 0x2F, reason: '$colonnes colonnes, haut $c');
      }
      expect(code(t, 2, colonnes + 3), 0x20, reason: '$colonnes colonnes');
      // Le bord de droite (« o » sous la barre, « j » ensuite) suit la bande.
      expect(code(t, 3, colonnes + 3), 0x6F, reason: '$colonnes colonnes');
      expect(code(t, 4, colonnes + 3), 0x6A, reason: '$colonnes colonnes');
      for (var r = 2; r <= 8; r++) {
        for (var c = colonnes + 4; c <= 40; c++) {
          expect(code(t, r, c), 0x20, reason: 'dehors $r,$c');
        }
      }
    }
  });

  test('cadre-3d : la colonne de gauche déplace tout le cadre', () {
    final m = library.firstWhere((m) => m.name == 'cadre-3d');
    TMinitel draw(int col) {
      final service = Service.parseString(
        mingetPreviewText(
          withLibraryMacro(_noMacros, m.name, m.block),
          m.name,
          [4, col, 2, 10],
        ),
      );
      final data = renderPreview(service, service.pages[mingetPage]!);
      expect(data.error, isNull);
      return data.minitel;
    }

    List<int> cell(TMinitel t, int r, int c) => [
      t.screen[r][c].code,
      t.screen[r][c].gAttr,
      t.screen[r][c].lAttr,
    ];

    final base = draw(3);
    final moved = draw(20);
    // Un décalage de 17 colonnes : le cadre (lignes 4 à 4 + 3 + 2 = 9, colonnes 3
    // à 13) se retrouve à l'identique en colonnes 20 à 30.
    for (var r = 4; r <= 9; r++) {
      for (var c = 2; c <= 14; c++) {
        expect(cell(moved, r, c + 17), cell(base, r, c), reason: 'case $r,$c');
      }
    }
    // Rien n'est resté à l'ancienne place, ni plus loin à droite.
    for (var r = 4; r <= 9; r++) {
      for (var c = 1; c <= 18; c++) {
        expect(moved.screen[r][c].code & 0x7F, 0x20, reason: 'avant $r,$c');
      }
      for (var c = 32; c <= 40; c++) {
        expect(moved.screen[r][c].code & 0x7F, 0x20, reason: 'après $r,$c');
      }
    }
    // Hors bornes : colonne 1 (pas de place pour le séparateur) ou 40.
    for (final col in [1, 40]) {
      expect(
        () => Service.parseString(
          mingetPreviewText(
            withLibraryMacro(_noMacros, m.name, m.block),
            m.name,
            [4, col, 2, 10],
          ),
        ),
        throwsA(isA<ServiceException>()),
        reason: 'col $col',
      );
    }
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
    expect(find.byKey(const Key('lib-cadre-3d')), findsOneWidget);
    expect(find.byKey(const Key('lib-option')), findsOneWidget);
    expect(find.byKey(const Key('lib-new')), findsAtLeastNWidgets(4));
    await tester.tap(find.byKey(const Key('lib-option')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('library-note'))).data,
      contains('pas encore dans le service'),
    );
    expect(find.byKey(const Key('preview-screen')), findsOneWidget);
    expect(find.byKey(const Key('minget-error')), findsNothing);
    expect(codeText(tester), isNot(contains('option')));
    await tester.tap(find.byKey(const Key('library-add')));
    await tester.pumpAndSettle();
    // On revient aux mingets du service, le nouveau est choisi.
    expect(codeText(tester), contains('  option:\n'));
    expect(find.byKey(const Key('minget-option')), findsOneWidget);
    expect(find.byKey(const Key('minget-details')), findsOneWidget);
    // Dans la liste, il est maintenant marqué présent.
    expect(find.byKey(const Key('lib-in-service')), findsOneWidget);
    expect(find.byKey(const Key('lib-new')), findsAtLeastNWidgets(3));
    await tester.tap(find.byKey(const Key('lib-option')));
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
        'macros:\n  option:\n    - efface\npages:',
      ),
    );
    expect(find.byKey(const Key('lib-differs')), findsOneWidget);
    await tester.tap(find.byKey(const Key('lib-option')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library-differs')), findsOneWidget);
    await tester.tap(find.byKey(const Key('library-add')));
    await tester.pumpAndSettle();
    expect(find.text('Un minget « option » existe déjà'), findsOneWidget);
    await tester.tap(find.byKey(const Key('dialog-ok')));
    await tester.pumpAndSettle();
    expect(codeText(tester), contains('  option-2:\n'));
    expect(codeText(tester), contains('  option:\n    - efface'));
    expect(find.byKey(const Key('minget-option-2')), findsOneWidget);
  });
}

/// Le sélecteur d'instruction de l'onglet Écran propose aussi la bibliothèque.
void pickerTests() {
  const service = r'''
debut: a
macros:
  option:
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
      'option',
    );
    await tester.pumpAndSettle();
    // « option » est déjà au service : une seule entrée, celle du service.
    expect(find.byKey(const Key('instruction-macro-option')), findsOneWidget);
    expect(find.byKey(const Key('instruction-lib-option')), findsNothing);
    await tester.enterText(find.byKey(const Key('instruction-filter')), 'cad');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('instruction-lib-cadre-3d')), findsOneWidget);
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
    expect(Service.parseString(text).macros.keys, ['option', 'titre-simple']);
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
  cadre-3d:
    - position: {ligne: $1, col: 1}
    - ecrit: "$2 $3 $4 $5"
pages:
  a:
    ecran:
      - macro: [cadre-3d, 5, "x", "y", "z", "t"]
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
      (m) => m.name == 'cadre-3d',
    );
    final text = withLibraryMacro(
      service,
      lib.name,
      lib.block,
      as: libraryPreviewMacro,
    );
    final parsed = Service.parseString(
      mingetPreviewText(text, libraryPreviewMacro, [5, 3, 2, 36]),
    );
    // Les deux existent : celle du service (5 paramètres) et celle du modèle (4).
    expect(parsed.macros['cadre-3d']!.arity, 5);
    expect(parsed.macros[libraryPreviewMacro]!.arity, 4);
  });

  testWidgets('le modèle s\'affiche malgré le minget du même nom', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('lib-cadre-3d')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('minget-error')), findsNothing);
    expect(find.byKey(const Key('preview-screen')), findsOneWidget);
    expect(find.byKey(const Key('library-differs')), findsOneWidget);
  });
}
