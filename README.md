# minserve-editor

Un éditeur graphique de services [Minserve](https://github.com/abasty/minserve), en Dart et
Flutter, qui tourne dans un navigateur.

Un service Minserve est un fichier `service.yaml` : des pages, ce qu'elles affichent, ce que
l'on peut y saisir et où mène chaque saisie. Sur un service de taille réelle, on perd vite la
vue d'ensemble. L'éditeur est là pour la retrouver.

> **État : étape 6 du plan** (voir [documents/minserve-editor.md](documents/minserve-editor.md)).
> L'application ouvre un `service.yaml`, le modifie dans un éditeur de texte à numéros de ligne
> et le lit en direct avec le code du serveur (`minserve_core`). À côté, le **graphe des pages** :
> pages, transitions, impasses, pages inaccessibles, liens globaux, recherche, et « Aller au
> texte » depuis une page. Le graphe **modifie le texte** : créer, renommer et supprimer une
> page, ajouter et retirer une transition (les autres lignes, commentaires compris, restent
> telles quelles). **Rendu** de la page sur un écran Minitel (émulateur de Minterm), mis à jour à chaque modification ; un **double clic** sur une page (ou le bouton « Ouvrir ») l’ouvre en grand à la place du graphe : rendu en haut, propriétés en bas. L'onglet **Écran** liste les instructions de la page, chacune avec ses champs (ligne, colonne, couleurs...) : ajouter depuis un menu, monter, descendre, copier, supprimer, ou écrire en texte. Le bouton **Mingets** liste les macros du service et montre chacune avec des arguments d'essai. On les insère dans une page depuis le sélecteur d'instruction, avec un formulaire d'appel. Des instructions cochées s'**extraient en minget** (les valeurs variables deviennent des paramètres). Choisir une instruction montre l'écran **jusqu'à elle** ou **elle seule** (macro, `fois`, `si` compris). Un panneau de **données de test** donne des valeurs aux variables `${nom}` pour voir la page remplie. **Formulaires de page** (règles, saisie, accès) : chaque champ ne réécrit que sa clé. Les volets (texte / graphe, graphe / panneau de page) se **redimensionnent en tirant leur poignée**. **Défaire / refaire** (boutons ou Ctrl+Z, Ctrl+Y) valent pour la frappe comme
> pour le graphe. On enregistre par un téléchargement.

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

## Application Linux

Le même code compile en application de bureau (plan : `documents/minserve-editor.md` §11).
`./build-linux.sh` lance les tests, compile (`flutter build linux --release`) et range le dossier
`bundle` dans `build/minserve-editor-linux-x64.tar.gz` : décompresser, puis lancer `minserve-editor/minserve_editor`
(l'exécutable, `data/` et `lib/` restent ensemble). Il faut GTK 3 sur la machine, et `zenity` ou `kdialog`
pour les boîtes d'ouverture et d'enregistrement ; rien n'est publié. Sur le bureau, « Enregistrer » (Ctrl+S)
réécrit le fichier ouvert, « Enregistrer sous… » (Ctrl+Maj+S) en choisit un autre, et
`minserve_editor service.yaml` ouvre un fichier au départ.

## Documentation

- [documents/minserve-editor.md](documents/minserve-editor.md) : le but, l'architecture, les
  décisions prises, le plan en neuf étapes et les risques.

## Dépôts liés

| Dépôt | Rôle |
| --- | --- |
| [minserve](https://github.com/abasty/minserve) | Le serveur Minitel et le format de `service.yaml`. L'éditeur réutilise son cœur (`packages/minserve_core` : lecture, validation, macros, Videotex, rendu d'une page). |
| [minterm](https://github.com/abasty/minterm) | L'émulateur Minitel en Flutter. L'éditeur réutilise l'émulateur et l'affichage de l'écran (`packages/minterm_view`). |

## Publication

La webapp est servie par GitHub Pages, à l'adresse
`https://abasty.github.io/minserve-editor/` (voir « Publier »).

## Licence

[MIT](LICENSE).
