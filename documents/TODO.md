# TODO — idées à planifier

Idées hors du plan en 9 étapes de `minserve-editor.md` §8. Pas d'ordre ni d'engagement.

## Vues du graphe

- [ ] **Vue 3D interactive** (carte mentale) : pages en nœuds dans l'espace, rotation, zoom, survol des transitions. À essayer d'abord en lecture seule, à partir du même `ServiceGraph`.
- [ ] **Déplacer les pages à la main** dans la vue 2D (glisser un nœud) et **éloigner ou rapprocher** des groupes de pages.
- [ ] **Mémoriser les positions** choisies. Où ? Hors du `service.yaml` serveur (qui ne doit pas les connaître) : fichier à côté, ou section ignorée par le serveur. À trancher.
- [ ] Alterner mise en page automatique et positions manuelles (bouton « Réorganiser »).
- [ ] Autres vues possibles : arbre depuis la page de départ, matrice pages × pages, regroupement par fonction (messagerie, jeux…).

## Éditeur de texte

- [ ] **Plus agréable à lire** : coloration syntaxique du YAML (clés, chaînes, commentaires, nombres), couleurs cohérentes avec le thème clair et sombre.
- [ ] **Indentation automatique** : conserver l'indentation à Entrée, Tab et Maj+Tab pour (dés)indenter une sélection, deux espaces (jamais de tabulation).
- [ ] **Complétion** : clés connues du format (`ecran`, `entree`, `action`…), noms de pages dans `suivant`, `debut`, raccourcis ; macros définies.
- [ ] **Recherche et remplacement** dans le texte (Ctrl+F, Ctrl+H), avec saut au résultat suivant.
- [ ] Autres : commentaire/décommentation de lignes (Ctrl+/), repli des pages, mini-carte ou liste des pages (plan du document), correspondance des guillemets et crochets.
- [ ] À trancher : continuer à écrire notre propre champ de texte (`code_editor.dart`, ligne de hauteur fixe) ou adopter un paquet d'édition de code. Contrainte : pas de ressource tierce chargée à l'exécution (voir doc §4.4).

## Édition du graphe (suite de l'étape 4)

- [ ] **Tirer une flèche** d'une page à l'autre à la souris pour créer une transition (aujourd'hui : bouton « Ajouter une transition »).
- [ ] **Changer la page de départ** (`debut`) depuis le graphe.
- [ ] **Transitions de programme et d'accès** (`exec.suivant`, `acces.sinon`) modifiables depuis le graphe ; aujourd'hui seulement les règles de `action`.
- [ ] Changer la cible ou la touche d'une règle existante (aujourd'hui : la retirer et en ajouter une).

## Rendu

- [ ] **Clignotement** des caractères dans l'aperçu (aujourd'hui, ils sont affichés fixes).
- [ ] **Fichiers `affiche`** : les montrer (choisir le dossier `assets` du service, ou les glisser dans l'éditeur).
- [ ] **Données de test** (variables, messages, compteurs) pour voir la page remplie (étape 7).
- [ ] **Incorporer un fichier `.vdt` au `service.yaml`** (une fois les assets accessibles) : soit en liste d'instructions `ecran` (désassembleur du cœur, comme `tool/vdt2yaml.dart`), soit en gardant sa **suite d'octets telle quelle**, sans décompilation ; éventuellement sous forme de macro. Confirmation avant de remplacer l'`affiche`.
- [ ] **Texte limité à la page** : en mode page, ne montrer dans l'éditeur de texte que le YAML de la page ouverte (avec un lien « Tout le texte »). À décider selon l'usage.
- [ ] La lettre `F` en haut à droite (ligne 00) est celle d'un terminal non connecté : peut-être la masquer dans l'aperçu.
- [ ] Remplacer les dépendances `path:` (`minserve_core`, `minterm_view`) par `git:` avant de publier par GitHub Actions.
