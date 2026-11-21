import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:minserve_core/minserve_core.dart';
import 'package:minserve_editor/src/graph/layout.dart';
import 'package:minserve_editor/src/graph/service_graph.dart';

ServiceGraph graphOf(String yaml) => ServiceGraph.of(Service.parseString(yaml));

const hub = '''
debut: sommaire
pages:
  sommaire:
    ecran: [efface]
    entree:
      zonesaisie: {ligne: 24, col: 1, longueur: 1}
      validation: [envoi, sommaire]
    action:
      saisies:
        - {choix: "1", touche: envoi, suivant: a}
        - {choix: "2", touche: envoi, suivant: b}
        - {choix: "9", touche: envoi, suivant: a}
        - {touche: sommaire, suivant: sommaire}
  a:
    ecran: [efface]
    entree:
      zonesaisie: {ligne: 24, col: 1, longueur: 1}
      validation: [envoi]
    action:
      saisies:
        - {touche: envoi, suivant: sommaire}
  b:
    ecran: [efface]
  orpheline:
    ecran: [efface]
    entree:
      zonesaisie: {ligne: 24, col: 1, longueur: 1}
      validation: [envoi]
    action:
      saisies:
        - {touche: envoi, suivant: a}
''';

void main() {
  test('une arête par couple de pages, avec une étiquette par règle', () {
    final g = graphOf(hub);
    final e = g.edges.singleWhere((e) => e.from == 'sommaire' && e.to == 'a');
    expect(e.labels, ['1 · ENVOI', '9 · ENVOI']);
    expect(e.kind, EdgeKind.rule);
    expect(e.conditional, isFalse);
    expect(g.edges.where((e) => e.from == 'sommaire').length, 3);
    expect(g.edges.singleWhere((e) => e.isLoop).labels, ['SOMMAIRE']);
  });

  test('impasses et pages inaccessibles', () {
    final g = graphOf(hub);
    expect(g.deadEnds, ['b']);
    expect(g.unreachable, ['orpheline']);
    expect(g.nodes['sommaire']!.isStart, isTrue);
    expect(g.nodes['a']!.hasInput, isTrue);
    expect(g.outgoing('a').single.to, 'sommaire');
    expect(g.incoming('a').length, 2);
  });

  test('une règle conditionnelle donne une arête conditionnelle', () {
    final g = graphOf('''
debut: a
pages:
  a:
    ecran: [efface]
    entree:
      zonesaisie: {ligne: 24, col: 1, longueur: 1}
      validation: [envoi]
    action:
      saisies:
        - {touche: envoi, suivant: b, si: {connecte: true}}
  b:
    ecran: [efface]
''');
    expect(g.edges.single.conditional, isTrue);
  });

  test('programmes, accès et liens globaux', () {
    final g = graphOf('''
debut: accueil
guide: aide
raccourcis:
  - {choix: "*", touche: sommaire, suivant: accueil}
pages:
  accueil:
    ecran: [efface]
    entree:
      zonesaisie: {ligne: 24, col: 1, longueur: 1}
      validation: [envoi, sommaire]
    action:
      saisies:
        - {choix: "1", touche: envoi, suivant: jeu}
  aide:
    ecran: [efface]
    entree:
      zonesaisie: {ligne: 24, col: 1, longueur: 1}
      validation: [retour]
    action:
      saisies:
        - {touche: retour, suivant: accueil}
  jeu:
    ecran: [efface]
    acces: {connecte: true, sinon: accueil}
    exec: {prog: jeu.sh, suivant: accueil}
  solo:
    ecran: [efface]
    acces: {connecte: false}
    exec: {prog: solo.sh}
''');
    expect(g.nodes['jeu']!.isProgram, isTrue);
    expect(g.nodes['jeu']!.requiresLogin, isTrue);
    expect(g.nodes['jeu']!.implicitLogin, isFalse);
    expect(
      g.edges.map((e) => (e.from, e.to, e.kind)),
      containsAll([
        ('accueil', 'jeu', EdgeKind.rule),
        ('jeu', 'accueil', EdgeKind.exec),
        ('jeu', 'accueil', EdgeKind.access),
      ]),
    );
    expect(g.globals.map((l) => (l.kind, l.to)), [
      (GlobalKind.shortcut, 'accueil'),
      (GlobalKind.guide, 'aide'),
    ]);
    // L'aide est atteinte par GUIDE, bien que rien n'y mène par une règle.
    expect(g.nodes['aide']!.unreachable, isFalse);
    expect(g.nodes['solo']!.unreachable, isTrue);
    expect(g.closing, ['solo']);
  });

  group('mise en page', () {
    test('colonnes = distance au départ, pas de chevauchement', () {
      final g = graphOf(hub);
      final l = layoutGraph(g);
      expect(l.layers['sommaire'], 0);
      expect(l.layers['a'], 1);
      expect(l.layers['b'], 1);
      // La page inaccessible forme sa propre bande, sous la première.
      expect(l.layers['orpheline'], 0);
      expect(l.rects['orpheline']!.top, greaterThan(l.rects['b']!.bottom));
      final rects = l.rects.values.toList();
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].overlaps(rects[j]), isFalse, reason: '$i / $j');
        }
        expect(Offset.zero & l.size, isNotNull);
        expect(rects[i].right, lessThanOrEqualTo(l.size.width));
        expect(rects[i].bottom, lessThanOrEqualTo(l.size.height));
      }
    });

    test('un retour vers une colonne précédente est reconnu', () {
      final g = graphOf(hub);
      final l = layoutGraph(g);
      final back = g.edges.singleWhere((e) => e.from == 'a');
      expect(l.isBack(back), isTrue);
      expect(l.isBack(g.edges.firstWhere((e) => e.to == 'b')), isFalse);
    });

    final example = File('../minserve/example/service.yaml');
    test(
      'le service d\'exemple se dispose sans chevauchement',
      skip: example.existsSync() ? null : 'dépôt minserve absent',
      () {
        final g = graphOf(example.readAsStringSync());
        final l = layoutGraph(g);
        expect(l.rects.length, g.nodes.length);
        final rects = l.rects.values.toList();
        for (var i = 0; i < rects.length; i++) {
          for (var j = i + 1; j < rects.length; j++) {
            expect(rects[i].overlaps(rects[j]), isFalse);
          }
        }
        // ignore: avoid_print
        print(
          'exemple : ${g.nodes.length} pages, ${g.edges.length} arêtes, '
          '${g.globals.length} liens globaux, impasses ${g.deadEnds}, '
          'inaccessibles ${g.unreachable}, taille ${l.size}',
        );
      },
    );
  });
}
