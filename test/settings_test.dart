import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minserve_editor/src/assets.dart';
import 'package:minserve_editor/src/file_access.dart';
import 'package:minserve_editor/src/file_access_io.dart';
import 'package:minserve_editor/src/settings.dart';

import 'editor_page_test.dart' show FakeFiles, pumpEditor, codeText;

const _text = 'debut: a\npages:\n  a:\n    ecran: [efface]\n';
const _other = 'debut: b\npages:\n  b:\n    ecran: [efface]\n';
const _path = '/srv/x/jeu.yaml';
const _opened = OpenedFile('jeu.yaml', _text, path: _path);

String _title(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('file-name'))).data!;

Future<void> _edit(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('code')), '$_text# fin\n');
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('réglages', () {
    test('les récents : le dernier ouvert d\'abord, sans doublon, bornés', () {
      final s = AppSettings();
      s.addRecent('/a');
      s.addRecent('/b');
      s.addRecent('/a');
      expect(s.recent, ['/a', '/b']);
      for (var i = 0; i < 20; i++) {
        s.addRecent('/f$i');
      }
      expect(s.recent, hasLength(AppSettings.maxRecent));
      expect(s.recent.first, '/f19');
      s.removeRecent('/f19');
      expect(s.recent.first, '/f18');
      s.clearRecent();
      expect(s.recent, isEmpty);
    });

    test('ils se retrouvent d\'une fois sur l\'autre', () {
      final storage = MemorySettingsStorage();
      AppSettings(storage)
        ..addRecent('/a')
        ..addRecent('/b')
        ..setAssetsFolder('/a', '/mes/assets')
        ..setAssetsFolder('/b', '/autres')
        ..setAssetsFolder('/b', null);
      final again = AppSettings(storage);
      expect(again.recent, ['/b', '/a']);
      expect(again.assetsFolders, {'/a': '/mes/assets'});
    });

    test('un fichier de réglages abîmé : on repart de zéro', () {
      for (final bad in ['', 'pas du json', '[1]', '{"recent": 3}']) {
        final s = AppSettings(MemorySettingsStorage(bad));
        expect(s.recent, isEmpty, reason: bad);
      }
      final s = AppSettings(
        MemorySettingsStorage(
          '{"recent": ["/a", 3], "assetsFolders": {"/a": 1}}',
        ),
      );
      expect(s.recent, ['/a']);
      expect(s.assetsFolders, isEmpty);
    });

    test('le fichier de réglages sur le disque', () {
      final dir = Directory.systemTemp.createTempSync('minserve-settings-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/sous/dossier/settings.json');
      AppSettings(FileSettingsStorage(file)).addRecent('/a');
      expect(AppSettings(FileSettingsStorage(file)).recent, ['/a']);
      expect(dir.listSync(recursive: true).whereType<File>(), hasLength(1));
    });
  });

  group('fichiers récents', () {
    testWidgets('le menu rouvre un fichier', (tester) async {
      final files = FakeFiles(savesInPlace: true)
        ..disk['/srv/y/autre.yaml'] = _other;
      final settings = AppSettings()
        ..addRecent('/srv/y/autre.yaml')
        ..addRecent(_path);
      await pumpEditor(tester, files, file: _opened, settings: settings);
      await tester.tap(find.byKey(const Key('recent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('recent-/srv/y/autre.yaml')));
      await tester.pumpAndSettle();
      expect(_title(tester), 'autre.yaml');
      expect(codeText(tester), _other);
      expect(settings.recent.first, '/srv/y/autre.yaml');
    });

    testWidgets('un fichier disparu est retiré de la liste', (tester) async {
      final files = FakeFiles(savesInPlace: true);
      final settings = AppSettings()..addRecent('/srv/y/perdu.yaml');
      await pumpEditor(tester, files, file: _opened, settings: settings);
      await tester.tap(find.byKey(const Key('recent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('recent-/srv/y/perdu.yaml')));
      await tester.pumpAndSettle();
      expect(
        find.text('Fichier introuvable : /srv/y/perdu.yaml'),
        findsOneWidget,
      );
      expect(settings.recent, [_path]);
      expect(_title(tester), 'jeu.yaml');
    });

    testWidgets('ni menu dans le navigateur, ni liste vide', (tester) async {
      await pumpEditor(
        tester,
        FakeFiles(),
        settings: AppSettings()..addRecent('/a'),
      );
      expect(find.byKey(const Key('recent')), findsNothing);
      await pumpEditor(tester, FakeFiles(savesInPlace: true));
      expect(find.byKey(const Key('recent')), findsNothing);
    });

    testWidgets('« Vider la liste »', (tester) async {
      final settings = AppSettings()..addRecent('/a');
      await pumpEditor(
        tester,
        FakeFiles(savesInPlace: true),
        settings: settings,
      );
      await tester.tap(find.byKey(const Key('recent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('recent-clear')));
      await tester.pumpAndSettle();
      expect(settings.recent, isEmpty);
      expect(find.byKey(const Key('recent')), findsNothing);
    });

    testWidgets('enregistrer sous retient le nouveau fichier', (tester) async {
      final files = FakeFiles(savesInPlace: true)
        ..chosenPath = '/srv/z/neuf.yaml';
      final settings = AppSettings();
      await pumpEditor(tester, files, settings: settings);
      await tester.tap(find.byTooltip('Enregistrer'));
      await tester.pumpAndSettle();
      expect(settings.recent, ['/srv/z/neuf.yaml']);
    });
  });

  group('fichier modifié ailleurs', () {
    Future<FakeFiles> start(WidgetTester tester) async {
      final files = FakeFiles(savesInPlace: true)..disk[_path] = _text;
      await pumpEditor(tester, files, file: _opened);
      return files;
    }

    Future<void> changeOnDisk(
      WidgetTester tester,
      FakeFiles files,
      String text,
    ) async {
      files.disk[_path] = text;
      files.watchers[_path]!.add(null);
      await tester.pumpAndSettle();
    }

    testWidgets('sans modification en cours : rechargé, avec un message', (
      tester,
    ) async {
      final files = await start(tester);
      await changeOnDisk(tester, files, _other);
      expect(codeText(tester), _other);
      expect(_title(tester), 'jeu.yaml');
      expect(
        find.textContaining('a changé sur le disque : rechargé'),
        findsOneWidget,
      );
    });

    testWidgets('notre propre enregistrement ne dérange pas', (tester) async {
      final files = await start(tester);
      await _edit(tester);
      await tester.tap(find.byTooltip('Enregistrer'));
      await tester.pumpAndSettle();
      await changeOnDisk(tester, files, '$_text# fin\n');
      expect(find.byKey(const Key('keep-mine')), findsNothing);
      expect(find.textContaining('rechargé'), findsNothing);
      expect(codeText(tester), '$_text# fin\n');
    });

    testWidgets('modifications en cours : on demande, « garder » une fois', (
      tester,
    ) async {
      final files = await start(tester);
      await _edit(tester);
      await changeOnDisk(tester, files, _other);
      expect(find.text('Le fichier a changé sur le disque'), findsOneWidget);
      await tester.tap(find.byKey(const Key('keep-mine')));
      await tester.pumpAndSettle();
      expect(codeText(tester), '$_text# fin\n');
      expect(_title(tester), 'jeu.yaml •');
      // Le même texte sur le disque : pas de nouvelle question.
      files.watchers[_path]!.add(null);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('keep-mine')), findsNothing);
      // Un autre texte : on redemande, et « Recharger » prend la version du disque.
      await changeOnDisk(tester, files, '$_other# encore\n');
      expect(find.byKey(const Key('reload-disk')), findsOneWidget);
      await tester.tap(find.byKey(const Key('reload-disk')));
      await tester.pumpAndSettle();
      expect(codeText(tester), '$_other# encore\n');
      expect(_title(tester), 'jeu.yaml');
    });

    testWidgets('un fichier effacé : on ne fait rien', (tester) async {
      final files = await start(tester);
      files.disk.remove(_path);
      files.watchers[_path]!.add(null);
      await tester.pumpAndSettle();
      expect(codeText(tester), _text);
    });
  });

  group('dossier assets choisi', () {
    testWidgets('mémorisé pour le service, par défaut en un clic', (
      tester,
    ) async {
      final files = FakeFiles(savesInPlace: true)
        ..assets = MapAssets({
          'logo.vdt': Uint8List.fromList([65]),
        }, label: '/srv/x/assets')
        ..chosenFolder = '/mes/vdt';
      final settings = AppSettings();
      await pumpEditor(
        tester,
        files,
        file: OpenedFile(
          'jeu.yaml',
          'debut: a\npages:\n  a:\n    ecran:\n      - affiche: logo.vdt\n',
          path: _path,
        ),
        settings: settings,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('node-a')));
      await tester.pumpAndSettle();
      final tab = find.descendant(
        of: find.byKey(const Key('page-tabs')),
        matching: find.text('Écran'),
      );
      await tester.ensureVisible(tab);
      await tester.tap(tab);
      await tester.pumpAndSettle();
      expect(files.lastFolder, isNull);
      final pick = find.byKey(const Key('screen-a-0-affiche-pick'));
      await tester.ensureVisible(pick);
      await tester.tap(pick);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('asset-folder-reset')), findsNothing);
      await tester.tap(find.byKey(const Key('asset-folder')));
      await tester.pumpAndSettle();
      expect(settings.assetsFolders, {_path: '/mes/vdt'});
      expect(files.lastFolder, '/mes/vdt');
      expect(find.byKey(const Key('asset-folder-reset')), findsOneWidget);
      await tester.tap(find.byKey(const Key('asset-folder-reset')));
      await tester.pumpAndSettle();
      expect(settings.assetsFolders, isEmpty);
      expect(files.lastFolder, isNull);
      expect(find.byKey(const Key('asset-folder-reset')), findsNothing);
    });

    test('le bureau prend le dossier choisi à la place de assets/', () {
      final found = const DesktopFileAccess().assetsFor(
        '/srv/x/s.yaml',
        folder: '/mes/vdt',
      );
      expect(found?.label, '/mes/vdt');
      expect(
        const DesktopFileAccess().assetsFor('/srv/x/s.yaml')?.label,
        '/srv/x/assets',
      );
    });
  });

  test(
    'la surveillance du disque voit un enregistrement par renommage',
    () async {
      final dir = Directory.systemTemp.createTempSync('minserve-watch-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/s.yaml';
      File(path).writeAsStringSync('a\n');
      final stream = const DesktopFileAccess().changes(path)!;
      final seen = Completer<void>();
      final sub = stream.listen((_) {
        if (!seen.isCompleted) seen.complete();
      });
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await writeServiceFile(path, 'b\n');
      await seen.future.timeout(const Duration(seconds: 5));
      expect(File(path).readAsStringSync(), 'b\n');
    },
  );
}
