# minserve-editor

Un éditeur graphique de services [Minserve](https://github.com/abasty/minserve), en Dart et
Flutter, qui tourne dans un navigateur.

Un service Minserve est un fichier `service.yaml` : des pages, ce qu'elles affichent, ce que
l'on peut y saisir et où mène chaque saisie. Sur un service de taille réelle, on perd vite la
vue d'ensemble. L'éditeur est là pour la retrouver.

> **État : étape 3 du plan** (voir [documents/minserve-editor.md](documents/minserve-editor.md)).
> L'application ouvre un `service.yaml`, le modifie dans un éditeur de texte à numéros de ligne
> et le lit en direct avec le code du serveur (`minserve_core`). À côté, le **graphe des pages**
> (en lecture seule) : pages, transitions, impasses, pages inaccessibles, liens globaux,
> recherche, et « Aller au texte » depuis une page. On enregistre par un téléchargement.
> Le graphe ne modifie pas encore le YAML.

## Ce que l'éditeur doit faire

1. **Montrer le graphe des pages** et de leurs transitions, et le modifier à la souris : créer
   une page, tirer un lien, renommer, supprimer.
2. **Éditer une page** sans connaître la syntaxe : écran, saisie, règles, accès.
3. **Afficher le rendu** d'une page, ou d'un morceau de page, avec l'émulateur de
   [Minterm](https://github.com/abasty/minterm).
4. **Créer et réutiliser des « mingets »** : des morceaux d'écran paramétrés, comme des widgets
   (un cadre en relief, une ligne de menu, un titre sur bandeau rouge). Ce sont les macros de
   Minserve, avec des paramètres nommés et un aperçu.

## Principes

- **Le `service.yaml` reste la source de vérité.** L'éditeur modifie le texte en place, sans le
  régénérer : les commentaires, l'ordre des clés et la mise en forme d'un fichier écrit à la
  main sont conservés. Ce que l'éditeur ne sait pas représenter graphiquement s'ouvre en YAML.
- **Une seule définition de ce qu'est un service valide**, celle du serveur : l'éditeur
  réutilise le code de Minserve au lieu de le réécrire, et calcule le rendu avec le même code
  que le serveur.
- **Tout se passe dans le navigateur.** On ouvre un fichier, on l'édite, on l'enregistre. Rien
  n'est envoyé à un serveur, et l'éditeur ne se connecte à aucun serveur Minserve.

## Développer

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d chrome
```

Le paquet `minserve_core` est pris par chemin local : le dépôt
[minserve](https://github.com/abasty/minserve) doit se trouver à côté de celui-ci
(`../minserve/packages/minserve_core`). Avant de compiler ailleurs que sur cette machine
(GitHub Actions), il faudra le remplacer par une dépendance `git:` dans le `pubspec.yaml`.

## Publier

`./deploy-editor.sh` lance les tests, compile l'application et la pousse sur la branche
`gh-pages`, servie par GitHub Pages. La compilation utilise `--no-web-resources-cdn` : CanvasKit
et les polices sont servis avec l'application, rien n'est chargé depuis les serveurs de Google.
La police de l'éditeur (DejaVu Sans Mono, licence Bitstream Vera) est embarquée dans `assets/fonts/`.

## Documentation

- [documents/minserve-editor.md](documents/minserve-editor.md) : le but, l'architecture, les
  décisions prises, le plan en neuf étapes et les risques.

## Dépôts liés

| Dépôt | Rôle |
| --- | --- |
| [minserve](https://github.com/abasty/minserve) | Le serveur Minitel et le format de `service.yaml`. L'éditeur en réutilisera le cœur (lecture, validation, macros, Videotex), à extraire dans un paquet. |
| [minterm](https://github.com/abasty/minterm) | L'émulateur Minitel en Flutter. L'éditeur en réutilisera l'émulateur et son widget d'affichage, à extraire dans un paquet. |

## Publication

La webapp est servie par GitHub Pages, à l'adresse
`https://abasty.github.io/minserve-editor/` (voir « Publier »).

## Licence

[MIT](LICENSE).
