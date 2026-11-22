import 'package:flutter_test/flutter_test.dart';
import 'package:minserve_core/minserve_core.dart';
import 'package:minserve_editor/src/graph/service_edit.dart';

const _service = r'''
debut: a
macros:
  # le trait
  trait:
    - position: {ligne: $1, col: 1}
    - repete: {caractere: "-", nombre: 10}
  double:
    description: "Deux traits"
    parametres:
      - {nom: ligne, type: entier, defaut: 3}
    ecran:
      - macro: [trait, $1]
      - macro:
          - trait
          - 5
pages:
  a:
    ecran:
      - efface
      - macro: [trait, 2]   # un trait
      - si:
          connecte: true
          alors:
            - macro: ["trait", 4]
      - fois:
          nombre: 2
          ecran:
            - macro: [double]
    entree:
      zonesaisie: {ligne: 24, col: 1, longueur: 1}
      validation: [envoi]
    action:
      saisies:
        - {choix: "1", touche: envoi, suivant: b}
  b:
    ecran:
      - macro: [double, 9]
''';

void main() {
  test('les appels d\'une macro, partout', () {
    final uses = macroUses(_service, 'trait');
    expect({for (final u in uses) u.where}, {'macro double', 'page a'});
    expect(uses.length, 4);
    expect(macroUses(_service, 'double').map((u) => u.where).toSet(), {
      'page a',
      'page b',
    });
    expect(macroUses(_service, 'inconnue'), isEmpty);
  });

  test('renommer une macro : la clé et tous les appels', () {
    final t = renameMacro(_service, 'trait', 'ligne-haute');
    expect(t, contains('  ligne-haute:\n'));
    expect(t, contains('- macro: [ligne-haute, 2]   # un trait'));
    expect(t, contains('- macro: [ligne-haute, \$1]'));
    expect(t, contains('- macro: ["ligne-haute", 4]'.replaceAll('"', '')));
    expect(t, contains('          - ligne-haute\n'));
    // Le commentaire est conservé ; plus aucun appel à l'ancien nom.
    expect(t, contains('# le trait'));
    expect(macroUses(t, 'trait'), isEmpty);
    expect(() => Service.parseString(t), returnsNormally);
    expect(Service.parseString(t).macros.keys, ['ligne-haute', 'double']);
  });

  test(
    'renommer : refus d\'un nom pris, invalide, ou d\'une macro absente',
    () {
      expect(
        () => renameMacro(_service, 'trait', 'double'),
        throwsA(isA<EditException>()),
      );
      expect(
        () => renameMacro(_service, 'trait', 'a b'),
        throwsA(isA<EditException>()),
      );
      expect(
        () => renameMacro(_service, 'nope', 'x'),
        throwsA(isA<EditException>()),
      );
    },
  );

  test('supprimer : refusée si la macro est appelée, sinon retirée', () {
    expect(
      () => removeMacro(_service, 'trait'),
      throwsA(
        isA<EditException>().having(
          (e) => e.message,
          'message',
          contains('macro double'),
        ),
      ),
    );
    // Une macro sans appel : retirée avec son commentaire.
    const unused = r'''
debut: a
macros:
  # inutile
  seule:
    - efface
  autre:
    - efface
pages:
  a:
    ecran: [efface]
''';
    var t = removeMacro(unused, 'seule');
    expect(t, isNot(contains('seule')));
    expect(t, isNot(contains('inutile')));
    expect(t, contains('autre:'));
    // La dernière retirée emporte la clé macros.
    t = removeMacro(t, 'autre');
    expect(t, isNot(contains('macros')));
    expect(() => Service.parseString(t), returnsNormally);
  });

  test('dupliquer une macro', () {
    final t = duplicateMacro(_service, 'double', 'double-bis');
    final s = Service.parseString(t);
    expect(s.macros.keys, ['trait', 'double', 'double-bis']);
    expect(s.macros['double-bis']!.description, 'Deux traits');
    expect(s.macros['double-bis']!.arity, 1);
    // La copie suit l'original.
    expect(t.indexOf('double:') < t.indexOf('double-bis:'), isTrue);
    expect(t.indexOf('double-bis:') < t.indexOf('pages:'), isTrue);
    expect(
      () => duplicateMacro(_service, 'double', 'trait'),
      throwsA(isA<EditException>()),
    );
  });
}
