import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:minserve_core/minserve_core.dart';
import 'package:minserve_editor/src/graph/service_edit.dart';

const base = '''
# Mon service
debut: accueil
guide: aide
raccourcis:
  - {touche: sommaire, suivant: accueil}
pages:
  # La page d'accueil.
  accueil:
    ecran: [efface]   # écran vide
    entree:
      zonesaisie: {ligne: 24, col: 1, longueur: 1}
      validation: [envoi, sommaire]
    action:
      saisies:
        - {choix: "1", touche: envoi, suivant: liste}
        # Le fichier.
        - {choix: "2", touche: envoi, suivant: fichier}
  # La liste.
  liste:
    ecran: [efface]
    entree:
      zonesaisie: {ligne: 24, col: 1, longueur: 1}
      validation: [envoi, retour]
    action:
      saisies:
        - {touche: retour, suivant: accueil}
        - {choix: "1", touche: envoi, suivant: liste}
  fichier:
    ecran: [efface]
  aide:
    ecran: [efface]
    entree:
      zonesaisie: {ligne: 24, col: 1, longueur: 1}
      validation: [retour]
    action:
      saisies:
        - {touche: retour, suivant: accueil}
''';

/// Les lignes qui diffèrent entre [a] et [b] : (supprimées, ajoutées).
(List<String>, List<String>) changes(String a, String b) {
  final x = a.split('\n'), y = b.split('\n');
  var pre = 0;
  while (pre < x.length && pre < y.length && x[pre] == y[pre]) {
    pre++;
  }
  var suf = 0;
  while (suf < x.length - pre &&
      suf < y.length - pre &&
      x[x.length - 1 - suf] == y[y.length - 1 - suf]) {
    suf++;
  }
  return (x.sublist(pre, x.length - suf), y.sublist(pre, y.length - suf));
}

Service parse(String text) => Service.parseString(text);

void main() {
  test('ajouter une page ne touche qu\'à la fin', () {
    final out = addPage(base, 'nouvelle');
    final (removed, added) = changes(base, out);
    expect(removed, isEmpty);
    expect(added.first, '  nouvelle:');
    expect(parse(out).pages.containsKey('nouvelle'), isTrue);
  });

  test('un mauvais nom de page est refusé', () {
    expect(() => addPage(base, 'a b'), throwsA(isA<EditException>()));
    expect(() => addPage(base, 'liste'), throwsA(isA<EditException>()));
    expect(() => addPage(base, ''), throwsA(isA<EditException>()));
  });

  test('renommer change la clé et toutes les références, rien d\'autre', () {
    final out = renamePage(base, 'accueil', 'home');
    final (removed, added) = changes(base, out);
    // debut, raccourcis, la clé de la page, 2 règles de retour (liste, aide).
    expect(removed.length, greaterThanOrEqualTo(5));
    expect(removed.length, added.length);
    expect(out, contains('debut: home'));
    expect(out, contains('  home:\n'));
    expect(out, contains('# La page d\'accueil.'));
    expect(out, contains('# écran vide'));
    final service = parse(out);
    expect(service.start, 'home');
    expect(service.pages.containsKey('accueil'), isFalse);
    expect(service.pages['liste']!.action!.choices.first.next, 'home');
    // Le reste est identique : même nombre de lignes, mêmes commentaires.
    expect(out.split('\n').length, base.split('\n').length);
  });

  test('renommer vers un nom pris ou invalide est refusé', () {
    expect(
      () => renamePage(base, 'accueil', 'liste'),
      throwsA(isA<EditException>()),
    );
    expect(
      () => renamePage(base, 'accueil', 'é è'),
      throwsA(isA<EditException>()),
    );
    expect(
      () => renamePage(base, 'zzz', 'autre'),
      throwsA(isA<EditException>()),
    );
  });

  test('référence : dit où une page est utilisée', () {
    final refs = pageReferences(base, 'accueil');
    expect(refs.map((r) => r.where), [
      'debut',
      'raccourcis, règle 1',
      'page liste, règle 1',
      'page aide, règle 1',
    ]);
    expect(refs.first.removable, isFalse);
    expect(refs.last.removable, isTrue);
  });

  test('supprimer une page retire aussi les règles qui y mènent', () {
    final out = removePage(base, 'fichier');
    final service = parse(out);
    expect(service.pages.containsKey('fichier'), isFalse);
    expect(service.pages['accueil']!.action!.choices.length, 1);
    // Le commentaire collé à la règle retirée part avec elle.
    expect(out, isNot(contains('# Le fichier.')));
    expect(out, contains('# La liste.'));
  });

  test('supprimer une page retire les commentaires collés au-dessus', () {
    // « liste » n'est plus utilisée ailleurs que par des règles.
    final out = removePage(base, 'liste');
    expect(out, isNot(contains('# La liste.')));
    expect(out, isNot(contains('liste')));
    expect(out, contains('# La page d\'accueil.'));
    expect(parse(out).pages.length, 3);
  });

  test('supprimer une page encore utilisée par une valeur est refusé', () {
    expect(
      () => removePage(base, 'accueil'),
      throwsA(
        isA<EditException>().having(
          (e) => e.message,
          'message',
          contains('debut'),
        ),
      ),
    );
    expect(() => removePage(base, 'aide'), throwsA(isA<EditException>()));
  });

  test('ajouter une règle à une page qui en a', () {
    final out = addRule(base, 'accueil', 'aide', key: 'envoi', choice: '3');
    final (removed, added) = changes(base, out);
    expect(removed, isEmpty);
    expect(added, ['        - {choix: "3", touche: envoi, suivant: aide}']);
    expect(parse(out).pages['accueil']!.action!.choices.length, 3);
  });

  test('ajouter une règle avec une touche qui n\'est pas dans validation', () {
    final out = addRule(base, 'accueil', 'aide', key: 'suite');
    expect(out, contains('validation: [envoi, sommaire, suite]'));
    expect(
      parse(out).pages['accueil']!.action!.choices.last.key,
      FunctionKey.suite,
    );
  });

  test('ajouter une règle à une page sans saisie lui en donne une', () {
    final out = addRule(base, 'fichier', 'accueil', key: 'retour');
    final fichier = parse(out).pages['fichier']!;
    expect(fichier.input, isNotNull);
    expect(fichier.action!.choices.single.next, 'accueil');
    final (removed, added) = changes(base, out);
    expect(removed, isEmpty);
    expect(added.length, greaterThan(4));
  });

  test('une page qui lance un programme ne reçoit pas de règle', () {
    final withExec = base.replaceFirst(
      '  fichier:\n    ecran: [efface]\n',
      '  fichier:\n    ecran: [efface]\n'
          '    exec: {prog: jeu.sh, suivant: accueil}\n',
    );
    expect(
      () => addRule(withExec, 'fichier', 'accueil', key: 'retour'),
      throwsA(isA<EditException>()),
    );
    expect(
      () => addRule(base, 'accueil', 'liste', key: 'inconnue'),
      throwsA(isA<EditException>()),
    );
  });

  test('retirer une règle', () {
    final out = removeRule(base, 'liste', 1, 'liste');
    final (removed, added) = changes(base, out);
    expect(removed, ['        - {choix: "1", touche: envoi, suivant: liste}']);
    expect(added, isEmpty);
    expect(parse(out).pages['liste']!.action!.choices.length, 1);
  });

  test('retirer la dernière règle d\'une page lui retire sa saisie', () {
    expect(isOnlyRule(base, 'accueil'), isFalse);
    expect(isOnlyRule(base, 'aide'), isTrue);
    final one = removeRule(base, 'liste', 1, 'liste');
    expect(isOnlyRule(one, 'liste'), isTrue);
    final out = removeRule(one, 'liste', 0, 'accueil');
    final liste = parse(out).pages['liste']!;
    expect(liste.input, isNull);
    expect(liste.action, isNull);
    expect(changes(one, out).$2, isEmpty);
    // La page d'aide doit garder sa saisie : le serveur refuse.
    expect(
      () => removeRule(base, 'aide', 0, 'accueil'),
      throwsA(isA<EditException>()),
    );
  });

  test('supprimer la dernière page cible d\'une page lui retire sa saisie', () {
    final two = base.replaceFirst('suivant: fichier}', 'suivant: liste}');
    expect(pagesLosingInput(base, 'fichier'), isEmpty);
    // Dans « base », seule la règle de aide mène à accueil, mais pas seule.
    expect(pagesLosingInput(base, 'liste'), isEmpty);
    final out = removePage(two, 'fichier');
    expect(parse(out).pages.containsKey('fichier'), isFalse);
  });

  test('retirer une règle emporte son commentaire', () {
    final out = removeRule(base, 'accueil', 1, 'fichier');
    expect(out, isNot(contains('# Le fichier.')));
  });

  test('retirer une règle qui a changé est refusé', () {
    expect(
      () => removeRule(base, 'liste', 1, 'accueil'),
      throwsA(isA<EditException>()),
    );
    expect(
      () => removeRule(base, 'liste', 7, 'liste'),
      throwsA(isA<EditException>()),
    );
  });

  test('un texte invalide n\'est pas modifié', () {
    expect(
      () => addPage('debut: x\npages: {}', 'a'),
      throwsA(isA<EditException>()),
    );
  });

  final example = File('../minserve/example/service.yaml');
  test('sur le service d\'exemple : seules les lignes concernées changent', () {
    final text = example.readAsStringSync();
    final lines = text.split('\n').length;

    final added = addPage(text, 'essai');
    expect(changes(text, added).$1, isEmpty);
    expect(added.split('\n').length, lines + 4);

    final renamed = renamePage(text, 'babillard', 'forum');
    final (gone, came) = changes(text, renamed);
    expect(gone.length, came.length);
    expect(renamed.split('\n').length, lines);
    expect(renamed, contains('  forum:'));
    expect(parse(renamed).pages.containsKey('forum'), isTrue);

    // sommaire -> fichier est la première règle de sommaire.
    final rule = removeRule(text, 'sommaire', 0, 'fichier');
    expect(changes(text, rule).$1.length, 1);

    final withRule = addRule(text, 'sommaire', 'fichier', choice: '5');
    expect(withRule, isNotNull);
  }, skip: !example.existsSync());
}
