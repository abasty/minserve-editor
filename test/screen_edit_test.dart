import 'package:flutter_test/flutter_test.dart';
import 'package:minserve_editor/src/graph/page_lines.dart';
import 'package:minserve_core/minserve_core.dart';
import 'package:minserve_editor/src/graph/service_edit.dart';

const _service = '''
debut: accueil
pages:
  accueil:
    ecran:
      - efface
      # le titre
      - position: {ligne: 3, col: 5}
      - ecrit: "Bonjour"
      - si:
          connecte: true
          alors:
            - ecrit: "oui"
      - affiche: logo.vdt
    entree:
      zonesaisie: {ligne: 24, col: 1, longueur: 3}
      validation: [envoi]
    action:
      saisies:
        - {choix: "1", touche: envoi, suivant: accueil, variable: pseudo}
  vide:
    ecran: []
    entree:
      zonesaisie: {ligne: 24, col: 1, longueur: 3}
      validation: [envoi]
    action:
      saisies:
        - {choix: "1", touche: envoi, suivant: accueil}
''';

List<String> names(String text, [String page = 'accueil']) => [
  for (final i in screenItems(text, page)) i.name,
];

void main() {
  test('lire les instructions', () {
    final items = screenItems(_service, 'accueil');
    expect(names(_service), ['efface', 'position', 'ecrit', 'si', 'affiche']);
    expect(items[1].text, 'position: {ligne: 3, col: 5}');
    expect(items[3].multiline, isTrue);
    expect(items[2].multiline, isFalse);
    expect(screenItems(_service, 'vide'), isEmpty);
  });

  test('ajouter au milieu, à la fin, et dans un écran vide', () {
    var t = insertScreenItem(_service, 'accueil', 2, 'couleur: {texte: jaune}');
    expect(names(t), [
      'efface',
      'position',
      'couleur',
      'ecrit',
      'si',
      'affiche',
    ]);
    t = insertScreenItem(t, 'accueil', 6, 'heure');
    expect(names(t).last, 'heure');
    expect(t, contains('      - couleur: {texte: jaune}\n      - ecrit'));
    t = insertScreenItem(t, 'vide', 0, 'efface');
    expect(names(t, 'vide'), ['efface']);
    expect(() => Service.parseString(t), returnsNormally);
  });

  test('retirer : le dernier laisse un écran vide', () {
    var t = removeScreenItem(_service, 'accueil', 2);
    expect(names(t), ['efface', 'position', 'si', 'affiche']);
    t = removeScreenItem(t, 'accueil', 2); // le bloc si
    expect(names(t), ['efface', 'position', 'affiche']);
    expect(t, isNot(contains('alors')));
    t = removeScreenItem(t, 'accueil', 0);
    t = removeScreenItem(t, 'accueil', 0);
    t = removeScreenItem(t, 'accueil', 0);
    expect(names(t), isEmpty);
    expect(t, contains('ecran: []'));
    expect(() => Service.parseString(t), returnsNormally);
  });

  test('remplacer une instruction', () {
    final t = replaceScreenItem(
      _service,
      'accueil',
      1,
      'position: {ligne: 10, col: 2}',
    );
    expect(screenItems(t, 'accueil')[1].text, 'position: {ligne: 10, col: 2}');
    expect(t, contains('# le titre'));
  });

  test('remplacer : refus du texte qui n\'est pas une instruction', () {
    expect(
      () => replaceScreenItem(_service, 'accueil', 1, 'a: 1\nb: 2'),
      throwsA(isA<EditException>()),
    );
    expect(
      () => replaceScreenItem(_service, 'accueil', 1, 'a: 1, b: 2'),
      throwsA(isA<EditException>()),
    );
    // Une instruction inconnue : refusée par le service.
    expect(
      () => replaceScreenItem(_service, 'accueil', 1, 'inconnue: 3'),
      throwsA(isA<EditException>()),
    );
    // Le bloc si ne se remplace pas ici.
    expect(
      () => replaceScreenItem(_service, 'accueil', 3, 'efface'),
      throwsA(isA<EditException>()),
    );
  });

  test('dupliquer, y compris un bloc', () {
    var t = duplicateScreenItem(_service, 'accueil', 3);
    expect(names(t), ['efface', 'position', 'ecrit', 'si', 'si', 'affiche']);
    t = duplicateScreenItem(t, 'accueil', 0);
    expect(names(t).take(2), ['efface', 'efface']);
  });

  test('déplacer : les commentaires suivent l\'instruction', () {
    var t = moveScreenItem(_service, 'accueil', 1, -1);
    expect(names(t).take(2), ['position', 'efface']);
    // Le commentaire « le titre » était au-dessus de position.
    expect(
      t.indexOf('# le titre') < t.indexOf('position:') &&
          t.indexOf('position:') < t.indexOf('- efface'),
      isTrue,
    );
    t = moveScreenItem(
      _service,
      'accueil',
      2,
      1,
    ); // ecrit passe sous le bloc si
    expect(names(t), ['efface', 'position', 'si', 'ecrit', 'affiche']);
    expect(
      () => moveScreenItem(_service, 'accueil', 0, -1),
      throwsA(isA<EditException>()),
    );
    expect(
      () => moveScreenItem(_service, 'accueil', 4, 1),
      throwsA(isA<EditException>()),
    );
  });

  test('une ligne vide après une instruction ne la rend pas multiligne', () {
    final t = _service.replaceFirst(
      '      - ecrit: "Bonjour"\n',
      '      - ecrit: "Bonjour"\n\n',
    );
    final items = screenItems(t, 'accueil');
    expect(items[2].text, 'ecrit: "Bonjour"');
    expect(items[2].multiline, isFalse);
    // Le bloc si compte ses vraies lignes : si, connecte, alors, ecrit.
    expect(items[3].text.split('\n').length, 4);
    final r = replaceScreenItem(t, 'accueil', 2, 'ecrit: "Salut"');
    expect(r, contains('- ecrit: "Salut"\n\n'));
  });

  test('écrire et retirer un paramètre', () {
    var t = setScreenParam(_service, 'accueil', 1, 'position', 'ligne', 10);
    expect(t, contains('- position: {ligne: 10, col: 5}'));
    // Un texte qui n'est pas un entier est refusé par le serveur.
    expect(
      () => setScreenParam(t, 'accueil', 1, 'position', 'col', 'x'),
      throwsA(isA<EditException>()),
    );
    // Une clé nouvelle va à la fin ; la retirer laisse une table propre.
    t = replaceScreenItem(t, 'accueil', 0, 'couleur: {texte: blanc}');
    t = setScreenParam(t, 'accueil', 0, 'couleur', 'fond', 'rouge');
    expect(t, contains('- couleur: {texte: blanc, fond: rouge}'));
    t = setScreenParam(t, 'accueil', 0, 'couleur', 'texte', null);
    expect(t, contains('- couleur: {fond: rouge}'));
    // Une table vide, ou une valeur refusée par le serveur, est refusée.
    expect(
      () => setScreenParam(t, 'accueil', 0, 'couleur', 'fond', null),
      throwsA(isA<EditException>()),
    );
    expect(
      () => setScreenParam(t, 'accueil', 1, 'position', 'ligne', 99),
      throwsA(isA<EditException>()),
    );
    // Un bloc ou une forme qui n'est pas une table en ligne : refus.
    expect(
      () => setScreenParam(t, 'accueil', 3, 'si', 'x', 1),
      throwsA(isA<EditException>()),
    );
  });

  test('un morceau de l\'écran, pour l\'aperçu', () {
    final slice = screenSlice(_service, 'accueil', 1, 2);
    final service = Service.parseString(slice);
    expect(service.pages['accueil']!.screen.length, 2);
    // Un bloc si entier, avec ses sous-instructions.
    final block = Service.parseString(screenSlice(_service, 'accueil', 3, 3));
    expect(block.pages['accueil']!.screen.length, 1);
    // Le vrai texte n'a pas changé, et les bornes sont vérifiées.
    expect(names(_service).length, 5);
    expect(
      () => screenSlice(_service, 'accueil', 2, 9),
      throwsA(isA<EditException>()),
    );
  });

  test('l\'aperçu d\'un appel de macro et d\'un fois', () {
    const text = r'''
debut: a
macros:
  trait:
    - position: {ligne: $1, col: 1}
    - repete: {caractere: "-", nombre: 10}
pages:
  a:
    ecran:
      - efface
      - macro: [trait, 5]
      - fois:
          nombre: 3
          ecran:
            - ecrit: "x"
''';
    for (final i in [1, 2]) {
      final slice = Service.parseString(screenSlice(text, 'a', i, i));
      expect(slice.pages['a']!.screen, isNotEmpty);
    }
    expect(
      Service.parseString(screenSlice(text, 'a', 1, 1))
          .pages['a']!
          .screen
          .length,
      2,
    );
    expect(
      Service.parseString(screenSlice(text, 'a', 2, 2))
          .pages['a']!
          .screen
          .length,
      3,
    );
  });

  test('un minget se montre sur une page temporaire', () {
    const text = r'''
debut: a
macros:
  trait:
    parametres:
      - {nom: ligne, type: entier, defaut: 5, min: 1, max: 24}
      - {nom: texte, type: texte, defaut: "x"}
    ecran:
      - position: {ligne: $1, col: 1}
      - ecrit: $2
pages:
  a:
    ecran: [efface]
''';
    expect(macroLines(text), {'trait': 3});
    final preview = mingetPreviewText(text, 'trait', [7, 'salut']);
    final service = Service.parseString(preview);
    expect(service.pages.keys, ['a', mingetPage]);
    expect(service.pages[mingetPage]!.screen.length, 3);
    // Un appel refusé par le serveur l'est aussi ici.
    expect(
      () => Service.parseString(mingetPreviewText(text, 'trait', [99, 'x'])),
      throwsA(isA<ServiceException>()),
    );
    // Le texte d'origine n'est pas modifié.
    expect(text, isNot(contains(mingetPage)));
  });
}
