import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minserve_core/minserve_core.dart';
import 'package:minserve_editor/src/assets.dart';
import 'package:minserve_editor/src/file_access_io.dart';
import 'package:minserve_editor/src/preview/page_preview.dart';
import 'package:minterm_view/minterm_view.dart';

import 'editor_page_test.dart' show FakeFiles, pumpEditor, codeText;
import 'page_preview_test.dart' show line;

const _service = '''
debut: a
pages:
  a:
    ecran:
      - efface
      - affiche: logo.vdt
      - affiche: dessous/autre.vdt
''';

/// Positionne en ligne 3, colonne 1 (US 0x43 0x41) et écrit « XYZ ».
final _logo = Uint8List.fromList([0x1F, 0x43, 0x41, 0x58, 0x59, 0x5A]);

void main() {
  test('l\'aperçu lit les fichiers affiche dans les assets', () {
    final service = Service.parseString(_service);
    final data = renderPreview(
      service,
      service.pages['a']!,
      source: MapAssets({'logo.vdt': _logo}),
    );
    expect(line(data.minitel, 3, length: 3), 'XYZ');
    // L'autre fichier manque : la raison est donnée, le reste s'affiche.
    expect(data.missing, ['dessous/autre.vdt']);
    expect(
      data.problems['dessous/autre.vdt'],
      'fichier introuvable dans assets : dessous/autre.vdt',
    );
    expect(data.error, isNull);
  });

  test('sans assets : rien n\'est lu, tout est « manquant »', () {
    final service = Service.parseString(_service);
    final data = renderPreview(service, service.pages['a']!);
    expect(data.missing, ['logo.vdt', 'dessous/autre.vdt']);
    expect(data.problems, isEmpty);
  });

  test('un fichier trop gros', () {
    final big = Uint8List(maxAssetSize + 1);
    expect(
      () => MapAssets({'x': big}).read('x'),
      throwsA(isA<AssetException>()),
    );
  });

  testWidgets('l\'éditeur montre l\'affiche du dossier du service ouvert', (
    tester,
  ) async {
    final files = FakeFiles(savesInPlace: true)
      ..assets = MapAssets({'logo.vdt': _logo}, label: '/srv/assets');
    await pumpEditor(tester, files);
    await tester.enterText(find.byKey(const Key('code')), _service);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('node-a')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('node-a')));
    await tester.pumpAndSettle();
    final text = tester.widget<Text>(find.byKey(const Key('preview-missing')));
    expect(text.data, contains('/srv/assets'));
    expect(text.data, contains('dessous/autre.vdt'));
    expect(text.data, isNot(contains('logo.vdt')));
  });

  testWidgets(
    'le formulaire affiche : état du fichier et choix dans la liste',
    (tester) async {
      final files = FakeFiles(savesInPlace: true)
        ..assets = MapAssets({
          'logo.vdt': _logo,
          'jeux/pirate.vdt': Uint8List.fromList([0x1F, 0x43, 0x41, 0x4F]),
        });
      await pumpEditor(tester, files);
      await tester.enterText(find.byKey(const Key('code')), _service);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('node-a')));
      await tester.pump();
      final tab = find.descendant(
        of: find.byKey(const Key('page-tabs')),
        matching: find.text('Écran'),
      );
      await tester.ensureVisible(tab);
      await tester.tap(tab);
      await tester.pumpAndSettle();
      String status(int i) => tester
          .widget<Text>(find.byKey(Key('screen-a-$i-affiche-status')))
          .data!;
      expect(status(1), '6 octets');
      expect(status(2), 'fichier introuvable dans assets : dessous/autre.vdt');
      // Le choix : la liste, un filtre, l'écran du fichier, puis « Choisir ».
      final pick = find.byKey(const Key('screen-a-2-affiche-pick'));
      await tester.ensureVisible(pick);
      await tester.tap(pick);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('asset-logo.vdt')), findsOneWidget);
      expect(find.byKey(const Key('asset-jeux/pirate.vdt')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('asset-filter')), 'pir');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('asset-logo.vdt')), findsNothing);
      await tester.tap(find.byKey(const Key('asset-jeux/pirate.vdt')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('asset-preview')), findsOneWidget);
      // Niveaux de gris par défaut ; la palette passe en couleur.
      expect(
        tester.widget<MinitelView>(find.byType(MinitelView)).colors,
        MinGrey,
      );
      await tester.tap(find.byKey(const Key('asset-colors')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MinitelView>(find.byType(MinitelView)).colors,
        MinColors,
      );
      await tester.tap(find.byKey(const Key('dialog-ok')));
      await tester.pumpAndSettle();
      expect(codeText(tester), contains('affiche: "jeux/pirate.vdt"'));
      expect(status(2), '4 octets');
    },
  );

  testWidgets('sans assets (navigateur) : pas de bouton, pas d\'état', (
    tester,
  ) async {
    await pumpEditor(tester, FakeFiles());
    await tester.enterText(find.byKey(const Key('code')), _service);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('node-a')));
    await tester.pump();
    final tab = find.descendant(
      of: find.byKey(const Key('page-tabs')),
      matching: find.text('Écran'),
    );
    await tester.ensureVisible(tab);
    await tester.tap(tab);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('screen-a-1-affiche')), findsOneWidget);
    expect(find.byKey(const Key('screen-a-1-affiche-pick')), findsNothing);
    expect(find.byKey(const Key('screen-a-1-affiche-status')), findsNothing);
  });

  group('dossier du disque', () {
    late Directory dir;
    late DirectoryAssets assets;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('minserve-assets-');
      Directory('${dir.path}/service/assets/dessous')
          .createSync(recursive: true);
      File('${dir.path}/service/assets/logo.vdt').writeAsBytesSync(_logo);
      File('${dir.path}/service/assets/dessous/autre.vdt')
          .writeAsBytesSync([65]);
      File('${dir.path}/secret.vdt').writeAsBytesSync([1]);
      assets = DirectoryAssets(Directory('${dir.path}/service/assets'));
    });
    tearDown(() => dir.deleteSync(recursive: true));

    String reason(String path) {
      try {
        assets.read(path);
      } on AssetException catch (e) {
        return e.message;
      }
      return 'lu';
    }

    test('lit un fichier, y compris dans un sous-dossier', () {
      expect(assets.read('logo.vdt'), _logo);
      expect(assets.read('dessous/autre.vdt'), [65]);
    });

    test('mêmes refus que le serveur', () {
      expect(
        reason('absent.vdt'),
        'fichier introuvable dans assets : absent.vdt',
      );
      expect(reason('../../secret.vdt'), startsWith('fichier hors du dossier'));
      expect(reason('/etc/passwd'), startsWith('fichier hors du dossier'));
      expect(reason('dessous'), 'pas un fichier : dessous');
      Link('${dir.path}/service/assets/lien.vdt')
          .createSync('${dir.path}/secret.vdt');
      expect(reason('lien.vdt'), startsWith('fichier hors du dossier'));
      File('${dir.path}/service/assets/gros.vdt')
          .writeAsBytesSync(Uint8List(maxAssetSize + 1));
      expect(reason('gros.vdt'), startsWith('fichier trop gros'));
    });

    test('la liste : tous les fichiers, sans ceux qui sortent du dossier', () {
      Link('${dir.path}/service/assets/lien.vdt')
          .createSync('${dir.path}/secret.vdt');
      expect(assets.list(), ['dessous/autre.vdt', 'logo.vdt']);
      expect(DirectoryAssets(Directory('${dir.path}/rien')).list(), isEmpty);
    });

    test('un dossier assets absent : on le dit', () {
      final none = DirectoryAssets(Directory('${dir.path}/rien'));
      expect(
        () => none.read('logo.vdt'),
        throwsA(
          isA<AssetException>().having(
            (e) => e.message,
            'message',
            startsWith('dossier assets introuvable'),
          ),
        ),
      );
    });

    test('le bureau cherche assets/ à côté du service', () {
      final found = const DesktopFileAccess().assetsFor(
        '${dir.path}/service/s.yaml',
      );
      expect(found?.label, '${dir.path}/service/assets');
      expect(const DesktopFileAccess().assetsFor(null), isNull);
    });
  });
}
