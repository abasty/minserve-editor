import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minserve_editor/src/file_access.dart';
import 'package:minserve_editor/src/file_access_io.dart';

import 'editor_page_test.dart' show FakeFiles, pumpEditor, codeText;

const _text = 'debut: a\npages:\n  a:\n    ecran: [efface]\n';

String _title(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('file-name'))).data!;

Future<void> _edit(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('code')), '$_text# fin\n');
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('éditeur de bureau', () {
    const opened = OpenedFile('jeu.yaml', _text, path: '/tmp/x/jeu.yaml');

    testWidgets('un fichier de départ : son nom, son texte', (tester) async {
      await pumpEditor(tester, FakeFiles(savesInPlace: true), file: opened);
      expect(_title(tester), 'jeu.yaml');
      expect(codeText(tester), _text);
    });

    testWidgets('enregistrer réécrit le fichier, sans rien demander', (
      tester,
    ) async {
      final files = FakeFiles(savesInPlace: true);
      await pumpEditor(tester, files, file: opened);
      await _edit(tester);
      expect(_title(tester), 'jeu.yaml •');
      await tester.tap(find.byTooltip('Enregistrer'));
      await tester.pumpAndSettle();
      expect(files.calls.single, (path: '/tmp/x/jeu.yaml', saveAs: false));
      expect(files.saved.single.$1, '/tmp/x/jeu.yaml');
      expect(_title(tester), 'jeu.yaml');
    });

    testWidgets('Ctrl+S enregistre', (tester) async {
      final files = FakeFiles(savesInPlace: true);
      await pumpEditor(tester, files, file: opened);
      await _edit(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(files.saved, hasLength(1));
      expect(_title(tester), 'jeu.yaml');
    });

    testWidgets('un nouveau service demande le nom une fois, puis se réécrit', (
      tester,
    ) async {
      final files = FakeFiles(savesInPlace: true)
        ..chosenPath = '/tmp/x/neuf.yaml';
      await pumpEditor(tester, files);
      await tester.tap(find.byTooltip('Enregistrer'));
      await tester.pumpAndSettle();
      expect(files.calls.first.path, isNull);
      expect(_title(tester), 'neuf.yaml');
      await _edit(tester);
      await tester.tap(find.byTooltip('Enregistrer'));
      await tester.pumpAndSettle();
      expect(files.calls.last, (path: '/tmp/x/neuf.yaml', saveAs: false));
    });

    testWidgets(
      '« Enregistrer sous » change de fichier ; annuler ne change rien',
      (tester) async {
        final files = FakeFiles(savesInPlace: true);
        await pumpEditor(tester, files, file: opened);
        await _edit(tester);
        // La boîte est annulée : le texte reste modifié.
        await tester.tap(find.byKey(const Key('save-as')));
        await tester.pumpAndSettle();
        expect(files.calls.single.saveAs, true);
        expect(files.saved, isEmpty);
        expect(_title(tester), 'jeu.yaml •');
        // Un autre fichier : il devient le fichier courant.
        files.chosenPath = '/tmp/x/copie.yaml';
        await tester.tap(find.byKey(const Key('save-as')));
        await tester.pumpAndSettle();
        expect(_title(tester), 'copie.yaml');
        await _edit(tester);
        await tester.tap(find.byTooltip('Enregistrer'));
        await tester.pumpAndSettle();
        expect(files.calls.last.path, '/tmp/x/copie.yaml');
      },
    );

    testWidgets('dans le navigateur : pas de « Enregistrer sous »', (
      tester,
    ) async {
      await pumpEditor(tester, FakeFiles());
      expect(find.byKey(const Key('save-as')), findsNothing);
    });

    testWidgets('une écriture qui échoue : message, texte toujours modifié', (
      tester,
    ) async {
      final files = FakeFiles(savesInPlace: true)
        ..failure = const FileAccessException('Enregistrement impossible : x');
      await pumpEditor(tester, files, file: opened);
      await _edit(tester);
      await tester.tap(find.byTooltip('Enregistrer'));
      await tester.pumpAndSettle();
      expect(find.text('Enregistrement impossible : x'), findsOneWidget);
      expect(_title(tester), 'jeu.yaml •');
    });

    testWidgets('un message de départ (fichier illisible) s\'affiche', (
      tester,
    ) async {
      await pumpEditor(
        tester,
        FakeFiles(savesInPlace: true),
        message: 'Lecture impossible : absent',
      );
      await tester.pump();
      expect(find.text('Lecture impossible : absent'), findsOneWidget);
    });

    testWidgets('la fermeture de la fenêtre demande confirmation', (
      tester,
    ) async {
      await pumpEditor(
        tester,
        FakeFiles(savesInPlace: true),
        file: opened,
        guardClose: true,
      );
      // Rien à perdre : on peut fermer tout de suite.
      expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
      expect(find.text('Modifications non enregistrées'), findsNothing);
      // Des modifications : une question, et « Annuler » garde la fenêtre.
      await _edit(tester);
      final answer = tester.binding.handleRequestAppExit();
      await tester.pumpAndSettle();
      expect(find.text('Modifications non enregistrées'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(await answer, AppExitResponse.cancel);
      // « Continuer » ferme.
      final again = tester.binding.handleRequestAppExit();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();
      expect(await again, AppExitResponse.exit);
    });

    testWidgets('sans garde (navigateur), la fermeture n\'est pas retenue', (
      tester,
    ) async {
      await pumpEditor(tester, FakeFiles(), file: opened);
      await _edit(tester);
      expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
    });
  });

  group('fichiers du bureau', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('minserve-editor-'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('écrire puis lire, sans fichier temporaire qui traîne', () async {
      final path = '${dir.path}/service.yaml';
      await writeServiceFile(path, 'a: é\n');
      await writeServiceFile(path, 'b: ü\n');
      final file = await readServiceFile(path);
      expect(file.text, 'b: ü\n');
      expect(file.name, 'service.yaml');
      expect(file.path, path);
      expect(dir.listSync().map((e) => e.path), [path]);
    });

    test('un lien symbolique reste un lien : sa cible change', () async {
      final target = File('${dir.path}/vrai.yaml')..writeAsStringSync('a\n');
      final link = Link('${dir.path}/lien.yaml')..createSync(target.path);
      await writeServiceFile(link.path, 'b\n');
      expect(FileSystemEntity.isLinkSync(link.path), true);
      expect(target.readAsStringSync(), 'b\n');
    });

    test('un dossier absent : une erreur lisible, rien d\'écrit', () async {
      await expectLater(
        writeServiceFile('${dir.path}/absent/x.yaml', 'a\n'),
        throwsA(
          isA<FileAccessException>().having(
            (e) => e.message,
            'message',
            startsWith('Enregistrement impossible'),
          ),
        ),
      );
      await expectLater(
        readServiceFile('${dir.path}/absent.yaml'),
        throwsA(
          isA<FileAccessException>().having(
            (e) => e.message,
            'message',
            startsWith('Lecture impossible'),
          ),
        ),
      );
    });

    test(
      'un fichier de la ligne de commande qui n\'existe pas : à créer',
      () async {
        final path = '${dir.path}/neuf.yaml';
        final file = await readStartupFile([path]);
        expect(file?.created, true);
        expect(file?.name, 'neuf.yaml');
        expect(file?.path, path);
        // Rien n'est créé avant l'enregistrement.
        expect(File(path).existsSync(), false);
        // Un dossier n'est pas un fichier : lecture impossible.
        await expectLater(
          readStartupFile([dir.path]),
          throwsA(isA<FileAccessException>()),
        );
      },
    );

    test('le fichier de la ligne de commande', () async {
      final path = '${dir.path}/s.yaml';
      File(path).writeAsStringSync('debut: a\n');
      expect(await readStartupFile([]), isNull);
      expect(await readStartupFile(['--verbose']), isNull);
      final file = await readStartupFile(['--verbose', path]);
      expect(file?.name, 's.yaml');
      expect(file?.text, 'debut: a\n');
    });
  });
}
