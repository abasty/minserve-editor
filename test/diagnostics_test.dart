import 'package:flutter_test/flutter_test.dart';
import 'package:minserve_editor/src/diagnostics.dart';
import 'package:minserve_editor/src/editor_page.dart';

void main() {
  test('le texte d\'un nouveau service est valide', () {
    final d = diagnose(newServiceText);
    expect(d.isValid, isTrue);
    expect(d.service!.start, 'accueil');
    expect(d.service!.pages.keys, ['accueil']);
  });

  test('une erreur de YAML est localisée', () {
    final d = diagnose('debut: a\npages:\n  a:\n    ecran: [efface\n');
    expect(d.isValid, isFalse);
    expect(d.line, isNotNull);
    expect(d.message, startsWith('YAML invalide'));
  });

  test('une erreur de service est localisée comme par le serveur', () {
    final d = diagnose('''
debut: accueil
pages:
  accueil:
    ecran:
      - ecrit: "Bonjour"
      - truc: 1
''');
    expect(d.isValid, isFalse);
    expect(d.line, 6);
  });

  test('les macros et fois du serveur sont comprises', () {
    final d = diagnose('''
debut: a
macros:
  titre:
    - ecrit: \$1
pages:
  a:
    ecran:
      - macro: [titre, "Salut"]
      - fois: {nombre: 3, ecran: [{ecrit: "x"}]}
''');
    expect(d.isValid, isTrue, reason: d.message);
  });
}
