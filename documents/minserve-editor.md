# Minserve Editor : un éditeur graphique de `service.yaml`

Un éditeur / concepteur de `service.yaml` accessible depuis un navigateur.

Ce document est une **proposition** : rien n'est codé. Il décrit le but, l'architecture, les
décisions prises et un plan par étapes, sur le modèle de `minserve.md` dans le dépôt de
Minserve. Il vit dans le dépôt `minserve-editor`, qui sera publié sur GitHub ; la webapp sera
servie par GitHub Pages (§4.4).

## 1. But

Aujourd'hui un service s'écrit à la main en YAML (voir le manuel de Minserve,
`documents/MINSERVE-MANUAL-fr.md`).
L'exemple fait 1600 lignes : on y perd la vue d'ensemble (quelle page mène où ?) et on ne voit
le résultat qu'en se connectant avec Minterm. L'éditeur doit donc :

1. **montrer la hiérarchie des pages et les transitions** sous forme de graphe, et permettre
   de les modifier à la souris (créer une page, tirer un lien, renommer, supprimer) ;
2. **éditer une page** sans connaître la syntaxe : écran, saisie, règles, accès ;
3. dans un second temps, **afficher le rendu** des pages (ou d'un morceau de page) avec
   l'émulateur de Minterm, au fil de l'édition ;
4. enfin, créer et réutiliser des **mingets** : des morceaux d'écran paramétrés, comme des
   widgets (cadre 3D, ligne de menu, titre sur bandeau rouge…).

Le `service.yaml` reste **la** source de vérité : l'éditeur lit et écrit ce fichier, et un
fichier écrit à la main doit rester ouvrable sans rien perdre.

### Hors périmètre (au moins au début)

- Piloter ou déployer le serveur depuis l'éditeur. En particulier, **aucune connexion de
  l'éditeur à un serveur Minserve de production** : on importe et on exporte des fichiers.
- Éditer `minserve.yaml` (configuration du serveur), les comptes ou la base.
- Exécuter les programmes `exec` (BASTOS) : l'éditeur les représente par un nœud, sans les lancer.

## 2. Ce qui existe déjà et que l'on réutilise

| Existant | Rôle dans l'éditeur | Remarque |
| --- | --- | --- |
| `lib/src/service.dart` (Minserve) | Lecture, validation, expansion des macros et de `fois`. | Importe `dart:io` et `exec.dart` : **pas compilable pour le web tel quel** (voir §4). |
| `macros.dart`, `expressions.dart`, `videotex.dart` | Substitution, expressions, génération Videotex. | Dart pur : réutilisables tels quels. |
| `videotex_disassembler.dart` (`vdt2yaml`) | Importer un `.vdt` en instructions `ecran`. | Dart pur. |
| Macros (`macros:`) | **Ce sont déjà les mingets** : suites d'instructions nommées, avec paramètres. | Il manque la description des paramètres et l'aperçu (§7). |
| Émulateur de Minterm (Flutter) | Rendu fidèle d'un flux Videotex. | `min_emulator.dart` n'importe que `charcode` et `foundation` : bon. `min_model.dart` (série, WebSocket, fichiers) et `min_widget.dart` (audio, fenêtre) sont plus liés à l'application (§6). |
| `test/manual_test.dart` (Minserve) | Teste les exemples YAML du manuel. | Modèle pour tester la sérialisation de l'éditeur. |

## 3. Le point dur : ne pas casser le YAML écrit à la main

Un éditeur graphique qui régénère tout le fichier détruit les commentaires, l'ordre des clés,
les notations compactes (`{choix: "1", touche: envoi, suivant: page1}`), les macros et les
`fois`. Les commentaires de l'exemple font partie de sa valeur. Trois approches :

| Approche | Principe | Verdict |
| --- | --- | --- |
| A. Modèle objet + régénération | On parse en objets, on réécrit tout. | Perd commentaires et mise en forme. Refusée. |
| **B. Édition du YAML en place** | L'éditeur tient le texte et applique des modifications ciblées (`yaml_edit`, qui conserve commentaires et style). | **Recommandée.** Une action = une modification locale, le reste du fichier est intact. |
| C. Modèle propre à l'éditeur | Un format d'éditeur, exporté en YAML. | Deux formats à maintenir ; les fichiers existants ne s'ouvrent pas. Refusée. |

Conséquences de B :

- le **graphe est calculé** à partir du YAML (jamais stocké) ;
- une page qui utilise des constructions que l'éditeur ne sait pas représenter (expressions
  complexes, `fois` imbriqués…) s'ouvre en **mode YAML** (éditeur de texte avec coloration et
  erreurs), sans rien perdre ;
- l'éditeur de texte brut est donc toujours disponible : le graphique est un confort, pas une
  obligation. C'est aussi ce qui permet de livrer l'éditeur par étapes.

## 4. Architecture

```
┌──────────────────────── navigateur (Flutter web) ────────────────────────┐
│  Graphe des pages   Éditeur de page   Palette de mingets   Aperçu Minitel │
│            \             |                  |                  /          │
│             └────── Document (texte YAML + modifications) ─────┘          │
│                             |                                             │
│       minserve_core (Dart pur : lecture, validation, macros, rendu)       │
└───────────────────────────────────────────────────────────────────────────┘
        import / export de fichiers (aucune connexion à un serveur)
```

### 4.1 Paquets

Trois paquets, dans l'ordre où ils sont nécessaires :

1. **`minserve_core`** (Dart pur, sans `dart:io`) : extrait de Minserve. Contient la lecture et
   la validation d'un service, `macros`, `expressions`, `videotex`, et le calcul du flux
   Videotex d'une page. Le serveur en dépend, l'éditeur aussi : **une seule implémentation**
   de ce qu'est un service valide, jamais une deuxième copie dans l'éditeur.
2. **`minterm_view`** (Flutter) : l'émulateur et son widget d'affichage, **sans** série, sans
   fichiers, sans WebSocket, sans fenêtre. Minterm en dépend aussi.
3. **`minserve_editor`** (Flutter web) : l'application.

### 4.2 Dépôts

Trois dépôts, **décidé** : l'éditeur vit dans `minserve-editor` (celui-ci). Les deux paquets
qu'il utilise s'extraient dans les dépôts d'où ils viennent, qui en dépendent à leur tour :

| Dépôt | Contient | Modification |
| --- | --- | --- |
| `minserve` | `minserve_core` | Découpe de `lib/src` : le serveur importe le cœur. |
| `minterm` | `minterm_view` | Découpe de `lib/min` : l'application importe le paquet. |
| `minserve-editor` | l'application web | Nouveau. |

Pendant le développement, l'éditeur les prend **par chemin** (`path: ../minserve/...`) ; une
fois les dépôts publiés, par `git:` (URL, référence et sous-dossier du paquet) dans le
`pubspec.yaml`. Ce changement de dépendance doit être fait avant de publier la webapp, parce
que la compilation par GitHub Actions (§4.4) ne voit pas les dossiers voisins de ta machine.

Le gros travail préalable est l'**extraction de `minserve_core`** : `service.dart` mélange la lecture du YAML avec la politique `exec`
(dossiers autorisés, `dart:io`). Il faut séparer les deux sans changer le comportement ; les
1269 tests de Minserve servent de filet.

### 4.3 Où vit le fichier ?

L'éditeur est servi en ligne comme page statique ; le service, lui, est sur la machine de la
personne. **Décidé** : on commence par le mode le plus simple, qui marche dans tous les
navigateurs, et les autres viendront plus tard si le besoin se fait sentir.

1. **Ouvrir / enregistrer un fichier** (retenu) : sélecteur de fichier et téléchargement.
2. *Plus tard, facultatif.* **Dossier local** (API *File System Access* de Chrome / Edge) :
   l'éditeur lit et écrit `service.yaml` et ses `assets/` directement. Pas disponible dans
   Firefox ni Safari.
3. *Plus tard, facultatif.* **Brouillon dans le navigateur** (IndexedDB), pour ne pas perdre le
   travail en cours.

Le code d'accès au fichier doit rester derrière une petite interface (ouvrir, enregistrer),
pour que les modes 2 et 3 s'ajoutent sans toucher au reste. Avec le mode 1, l'API de dossier
local n'est plus la raison du HTTPS ; Pages le fournit de toute façon (§4.4).

Tout reste dans le navigateur : l'hébergement en ligne n'envoie **aucune donnée de service**
nulle part. C'est à garder comme règle et à dire dans l'interface.

### 4.4 Publication : GitHub Pages

Choix **retenu** : l'application est une page statique, servie par GitHub Pages, comme Minterm
(`https://abasty.github.io/minterm/`) ; l'éditeur sera à `https://abasty.github.io/minserve-editor/`.
C'est un bon choix ici : rien à administrer, du HTTPS,
et surtout aucun serveur qui verrait les services édités, ce qui garde la règle ci-dessus vraie
par construction.

Points d'attention :

- **Chemin de base** : l'application est sous `/minserve-editor/`, donc
  `flutter build web --base-href /minserve-editor/` (comme `deploy-minterm.sh`, avec `--csp`).
- **Déploiement** : deux façons. Le script `deploy-minterm.sh` de Minterm pousse la compilation
  sur la branche `gh-pages` depuis ta machine ; il s'adapte tel quel. Plus tard, une
  GitHub Action qui compile et publie à chaque étiquette de version. Dans les deux cas le
  dépôt doit être compilable **tout seul** (voir §4.2 pour les dépendances).
- **Dépôt public** pour Pages avec un compte gratuit : le code et ce document le seront aussi.
  À relire avant de publier (rien de privé dans les exemples de services, ni de nom de serveur
  ou de compte).
- **Aucune ressource tierce** : par défaut, une application Flutter web charge CanvasKit et ses
  polices depuis les serveurs de Google à chaque ouverture. On compile avec
  `--no-web-resources-cdn` (vérifié : `useLocalCanvasKit` vaut `true`), et on embarque la police
  de l'éditeur (DejaVu Sans Mono), car les polices du système ne sont pas accessibles depuis
  CanvasKit. C'est ce qui garde vraie la règle « rien n'est envoyé ailleurs ».
- **Pas d'en-têtes réglables** (Pages n'en permet pas) : pas d'isolation d'origine croisée, donc
  pas de WebAssembly multi-fil. Sans importance pour une application de ce genre ; à ne pas
  prévoir dans l'architecture.
- **Mises à jour** : les navigateurs gardent l'application en cache ; prévoir l'affichage du
  numéro de version dans l'interface, pour savoir ce que l'on utilise en cas de problème.
- **Licence** : MIT, comme Minserve (fichier `LICENSE`).

## 5. L'interface

### 5.1 Le graphe des pages

Un nœud par page, une flèche par transition. Les transitions viennent de :

| Source dans le YAML | Flèche |
| --- | --- |
| `debut` | entrée du graphe |
| règle `action.saisies[].suivant` | page → page, étiquetée par `choix` et `touche`, pointillée si `si` |
| `exec.suivant` | page → page, nœud « programme » |
| `raccourcis` | flèches **globales** (affichées à part, sinon le graphe devient illisible) |
| `guide`, `mdp_obligatoire` | idem, globales |
| `acces` (page réservée) | pastille « connecté » sur le nœud |

Fonctions : disposition automatique (hiérarchique depuis `debut`), déplacement manuel (la
position des nœuds est mémorisée dans un fichier à côté, `service.editor.json`, pour ne pas
polluer le YAML), zoom, recherche, repérage des **pages inaccessibles** et des **impasses**
(pages sans sortie, signalées comme le fait déjà le manuel), regroupement de pages (par
préfixe de nom ou à la main) pour les gros services.

Actions : double-clic = ouvrir la page ; tirer d'un nœud à un autre = ajouter une règle
(l'éditeur demande `choix` et `touche`) ; supprimer une flèche = supprimer la règle ;
renommer une page = **renommer partout** (`suivant`, `debut`, raccourcis…).

### 5.2 L'éditeur de page

Un panneau par partie de la page : **Écran**, **Saisie** (`entree`), **Règles** (`action`),
**Accès**, **Données**, **Programme** (`exec`). Chaque panneau a une vue formulaire et une vue
YAML, synchronisées.

L'écran est une liste d'instructions : on peut les réordonner, les insérer depuis une palette
(texte, position, couleur, rectangle, paragraphe, macro, `fois`…), et chaque instruction
connaît ses paramètres (le manuel §3 en est la liste).

### 5.3 Édition directe sur l'aperçu (étape 5)

Plus tard : sur l'aperçu Minitel (grille 40 × 25), cliquer une cellule règle `position`,
glisser un rectangle crée un `rectangle`, etc. C'est le gros morceau, et il n'est pas
nécessaire pour que l'éditeur serve.

## 6. L'aperçu avec l'émulateur de Minterm

### 6.1 Principe

Pas de serveur : l'éditeur calcule lui-même le flux Videotex de la page avec `minserve_core`
(les mêmes instructions, le même code que le serveur), et le donne à l'émulateur. Le rendu est
ainsi celui du vrai serveur, y compris le comportement de `position` (qui remet la couleur et
la taille à zéro), les attributs qui persistent au retour à la ligne, `repete`, etc.

```
page YAML ──► minserve_core ──► octets Videotex ──► MinEmulator ──► MinScreen (widget)
                    ▲
        variables et données de test (§6.3)
```

### 6.2 Ce qu'il faut extraire de Minterm

`min_emulator.dart` est quasiment autonome. Ce qu'il faut couper pour faire `minterm_view` :

- `min_model.dart` : mélange l'émulateur avec `file_picker`, `share_plus`, `path_provider`,
  la série (`serial_support`) et `web_socket_channel`. Il faut séparer le **modèle d'écran**
  (alimenté en octets) du **modèle de connexion** ;
- `min_widget.dart` : dépend de `audioplayers`, `provider` et `window_setup` (taille de
  fenêtre). Le son et la fenêtre passent derrière une interface facultative ;
- les shaders (`crt_barrel.frag`) restent facultatifs pour l'aperçu.

Ce travail profite à Minterm (l'application devient une coque autour du paquet). Il doit
garder verts les tests existants de Minterm (`min_emulator_*`, `min_widget_*`).

### 6.3 Les parties dynamiques

Une page n'est pas toujours statique : `${variable}`, `donnees` (messages, données
personnelles), `si`, expressions. Pour l'aperçu, l'éditeur propose un **jeu de données de
test** (variables, utilisateur connecté, quelques messages) modifiable dans un panneau. Les
`exec` ne sont pas lancés : l'aperçu montre l'`ecran` de la page, qui est affiché avant le
programme.

### 6.4 Aperçu d'un morceau

Même mécanique, sur une liste d'instructions seulement : une macro avec des arguments de test,
un bloc `fois`, une sélection d'instructions. C'est ce qui rend les mingets utilisables.

## 7. Les mingets

### 7.1 Idée

Un **minget** est une macro (`macros:`) enrichie de ce dont un éditeur a besoin :

```yaml
macros:
  option:
    description: "Une ligne de menu : lettre sur fond rouge puis libellé"
    parametres:
      - {nom: ligne,   type: entier, defaut: 10, min: 1, max: 24}
      - {nom: col,     type: entier, defaut: 3}
      - {nom: lettre,  type: texte,  defaut: "A"}
      - {nom: libelle, type: texte,  defaut: "Messagerie"}
    ecran:
      - ...
```

Aujourd'hui `macros:` est une liste d'instructions et le nombre de paramètres est déduit du
plus grand `$n` cité (voir le manuel de Minserve, §3.9). Il y a donc
deux manières de définir un minget, au choix de la personne :

| Forme | Pour qui |
| --- | --- |
| **Forme actuelle** (liste d'instructions) | Les services existants : ils restent valides et deviennent des mingets « sans métadonnées » (paramètres nommés `$1`, `$2`…). |
| **Forme étendue** (dictionnaire avec `parametres`, `description`, `ecran`) | Les mingets que l'éditeur crée. Les noms de paramètres permettent un formulaire d'appel. |

La forme étendue est une **évolution du serveur**, décidée (étape 8 du plan, à faire dans
`minserve` avant que l'éditeur en crée) : le serveur doit la comprendre, sinon un service créé par l'éditeur ne fonctionnerait pas sans lui. Le corps
continue d'utiliser `$1`, `$2`… ; le nom d'un paramètre n'est qu'une étiquette pour
l'interface (les noms dans le corps sont une évolution possible, déjà notée « Plus tard »
dans `minserve.md` de Minserve).

### 7.2 Usage dans l'éditeur

- une **palette** de mingets (ceux du service, plus une **bibliothèque** : cadre 3D, titre sur
  bandeau, ligne de menu, ligne de saisie…) avec leur aperçu ;
- *glisser* un minget sur la page l'insère (`- macro: [option, 12, 3, "A", "Messagerie"]`),
  avec un formulaire généré à partir des paramètres ;
- *Extraire en minget* : sélectionner des instructions, nommer les valeurs variables, l'éditeur
  crée la macro et remplace la sélection par l'appel (le travail que nous avons fait à la main
  pour `cadre-titre` et `cadre-menu`) ;
- *Mettre à jour tous les usages* quand la définition change, avec la liste des pages touchées.

### 7.3 Partager des mingets

Un minget qui sert à plusieurs services est un fichier. Aujourd'hui un service tient dans un
seul `service.yaml` : il n'y a pas d'inclusion. **Décidé** : on commence par la **copie** de la
définition dans chaque service (simple, aucune évolution du serveur). Une clé d'inclusion
pourra être ajoutée plus tard, à condition de ne rien casser : c'est pourquoi l'éditeur ne doit
jamais supposer qu'une macro est définie dans le fichier ouvert (il lit les définitions par une
fonction, pas en parcourant `macros:` directement), et la bibliothèque de mingets de l'éditeur
est un ensemble de définitions que l'on copie dans le service au moment de les utiliser.

## 8. Plan

Chaque étape est livrable et utile seule ; on s'arrête après chacune.

1. **Extraire `minserve_core`** de Minserve (sans `dart:io`), sans changer le comportement.
   Tests : les 1269 existants. Prérequis de tout le reste. *Mesure du risque* : voir ce qu'il
   faut couper dans `service.dart` avant de s'engager.
2. **Squelette de l'application web + éditeur YAML**, avec la **publication sur GitHub Pages**
   dès cette étape (§4.4) : on découvre tôt les problèmes de chemin de base et de cache.
   Contenu : ouvrir un `service.yaml`, le modifier
   dans un éditeur de texte avec erreurs de `minserve_core` en direct, l'enregistrer. Aucun
   graphique encore, mais déjà utile (la validation en ligne).
3. **Le graphe en lecture** : nœuds, flèches, pages inaccessibles et impasses, recherche. Aucune
   modification, donc aucun risque pour le YAML.
   *Faite.* Choix de réalisation : mise en page en colonnes de gauche à droite (distance au départ
   en transitions), les pages que le départ n'atteint pas formant des bandes en dessous ; une
   arête par couple de pages (plusieurs règles = plusieurs étiquettes) ; les étiquettes ne
   s'affichent que sur les flèches de la page sélectionnée, les autres sont atténuées ; les
   retours en arrière passent au-dessus et peuvent être masqués ; les liens globaux (raccourcis,
   GUIDE, mot de passe à changer) sont des pastilles au-dessus du graphe ; si le texte devient
   invalide, le graphe du dernier texte valide reste affiché, avec un bandeau.
4. **Le graphe en écriture** (via `yaml_edit`) : créer, renommer, supprimer une page, ajouter et
   supprimer une règle. Tests : « ouvrir, modifier, enregistrer » sur l'exemple, avec
   comparaison du texte (seules les lignes visées changent).
   *Faite.* `yaml_edit` vérifié sur l'exemple de 1650 lignes : il conserve commentaires et
   notation compacte `{…}`. Trois contournements, dans `lib/src/graph/service_edit.dart` :
   (1) renommer une page passe par le texte de la clé (`yaml_edit` ne renomme pas) ;
   (2) retirer une page ou une règle coupe les lignes dans le texte, avec les commentaires collés
   au-dessus (hors premier élément d'une liste), car `yaml_edit` emporte aussi le commentaire qui
   suit ; (3) donner une saisie à une page qui n'en a pas écrit les lignes à la suite de la page,
   car `yaml_edit` range les clés nouvelles par ordre alphabétique et écrit mal une table en ligne
   dans une table qu'il crée. Chaque modification vérifie le texte avant et après avec
   `Service.parseString` : refusée avec la raison du serveur si le résultat serait invalide.
   Une règle retirée est la dernière de sa page : la page perd aussi `entree` et `action` (le
   serveur n'accepte pas de saisie sans règle), après confirmation. Supprimer une page retire
   les règles qui y mènent, mais refuse tant qu'une valeur y renvoie (`debut`, `guide`,
   `exec.suivant`, `acces.sinon`…) : le message dit laquelle. Pas encore : tirer une flèche à la
   souris, changer la page de départ, éditer les transitions de programme (`exec.suivant`).
   Un historique unique (`lib/src/history.dart`, 200 étapes) défait et refait la frappe (regroupée
   par séries d'une seconde ou de même nombre de lignes) et les modifications du graphe ; il
   remplace celui du champ de texte, qui ne voyait pas le graphe.
5. **L'éditeur de page** en formulaires (saisie, règles, accès), avec repli en YAML.
   *Faite pour les règles, la saisie (`zonesaisie`) et l'accès* (`lib/src/graph/page_forms.dart`).
   Les formulaires sont des onglets du panneau de la page sélectionnée. **Chaque champ lit sa
   valeur dans le texte et ne réécrit que sa clé** (`setValue` / `removeValue` de
   `service_edit.dart`) : le reste de la page, les commentaires et les réglages que le formulaire
   ne montre pas ne bougent pas ; ils sont signalés par une puce « +n » qui renvoie au texte.
   Un champ n'écrit qu'à la fin de la saisie (Entrée ou perte du focus) ; si le serveur refuse la
   valeur, le texte reste inchangé, la raison s'affiche et le champ reprend sa valeur. Règles :
   saisie, touche, page suivante, ordre (les règles s'échangent ligne contre ligne), message
   d'erreur `defaut`. Saisie : ligne, colonne, longueur, curseur, casse, regex et son message, et
   touches de validation. Accès : comme le service / ouverte à tous / réservée aux connectés, avec
   `sinon`, `message` et `mdp_provisoire`. Pas encore : `zonemessage`, `donnees`, `exec` (un
   formulaire), conditions `si`, actions de compte et de message (`connexion`, `message`…).
6. **Extraire `minterm_view`** de Minterm, puis **l'aperçu** d'une page.
   *Faite.* **Minterm** (branche `feature/view`, un commit) : `packages/minterm_view/` contient
   l'émulateur `TMinitel`, les jeux de caractères (`assets/g0g2.png`, `g1.png`, déplacés) avec
   les caractères redéfinis (`MinitelFonts`), le peintre de l'écran (`MinitelPainter`, qui lit un
   `MinitelDisplay`) et un widget `MinitelView` sans clavier ni connexion ni son. L'application
   Minterm en dépend par chemin ; son peintre est une sous-classe mince (son, effet « CRT 80's »,
   réglages). Ses 105 tests donnent le même résultat qu'avant (2 échecs qui existaient déjà, sur
   le libellé « Cx/Fin » du clavier compact). **Minserve** : `renderPage` (cœur) est la seule
   définition de « ce qu'on envoie pour afficher une page » (écran, zone de saisie vide, curseur) ;
   l'interpréteur l'utilise, et les 1270 tests passent. **Éditeur** : onglet « Rendu » du panneau
   de la page (`lib/src/preview/page_preview.dart`) : l'écran Minitel de la page, tel que le
   serveur l'afficherait, mis à jour à chaque modification du texte. Limites de cette étape :
   pas de données (`donnees`), de variables ni de fichiers `affiche` (ils sont listés, mais pas
   montrés), pas de clignotement, pas d'édition sur l'aperçu (étapes 7 et 9).
   **Mode page** : un double clic sur une page du graphe (ou le bouton d'ouverture) l'ouvre en
   grand à la place du graphe — rendu en haut, propriétés (aperçu, règles, saisie, accès) en bas,
   séparés par une poignée ; « Graphe » ramène au graphe, centré sur la page.
7. **L'aperçu d'un morceau**, les données de test, l'édition de l'`ecran` en liste
   d'instructions avec aperçu.
   - **7a — Données de test des variables (faite)** : en mode page, le bouton « Données de test »
     ouvre un panneau à droite du rendu avec une valeur par variable `${nom}` citée dans la page,
     puis dans le reste du service, plus des variables ajoutées à la main. Le rendu en tient
     compte à chaque frappe. Les valeurs restent en mémoire (pas dans le `service.yaml`). Les
     `donnees` de la page ne sont pas chargées.
   - **7b — L'`ecran` en liste d'instructions (faite)** : onglet « Écran » du panneau
     de la page (`screen_form.dart`, fonctions `screenItems`, `insertScreenItem`, `replaceScreenItem`,
     `moveScreenItem`, `duplicateScreenItem`, `removeScreenItem` dans `service_edit.dart`). Une ligne par
     instruction : on l'écrit à la main (une seule ligne, validée par le serveur), on la monte, la
     descend, la copie, la supprime, ou on en insère une depuis un menu d'instructions avec valeurs par
     défaut. Les commentaires au-dessus d'une instruction la suivent. Les instructions sur plusieurs lignes
     (`si`, `fois`) sont montrées et se modifient dans le texte ; un écran écrit en ligne (`ecran: [efface]`)
     ne se réordonne pas ; le dernier retrait laisse `ecran: []` (la clé est obligatoire). **Formulaire par instruction (7b-2)** : chaque
     instruction connue montre ses paramètres en champs (entiers pour `ligne`, `col`, `largeur`...,
     palette de pastilles pour les huit couleurs (couleur et gris en diagonale, nom au survol), actif / inactif, visible / invisible, texte) ; un champ ne réécrit que
     sa clé (`setScreenParam`), une clé facultative se retire en la vidant, une clé obligatoire ne se
     vide pas, et le serveur refuse les valeurs hors limites. Un bouton « </> » bascule une ligne en
     texte libre ; `macro`, `octets`, `si` et `fois` restent en texte. Reste : les macros dans le menu
     d'ajout, `si` et `fois`.
   - **7c — L'aperçu d'un morceau (faite)** : dans l'onglet « Écran » du mode page, toucher une ligne
     la choisit, et un sélecteur en haut propose **Page** / **Jusqu'à n** (l'écran des instructions 1 à n) /
     **n seule**. Le morceau est rendu par le vrai code du serveur : l'éditeur fabrique un texte de service
     où l'`ecran` de la page ne garde que ces instructions (`screenSlice`), le fait lire par
     `Service.parseString` et le rend ; le texte réel n'est jamais touché. Un appel de macro (avec ses
     arguments), un bloc `fois` ou `si` se montrent donc comme n'importe quelle instruction. Un morceau que le
     serveur refuserait (par exemple un `si` coupé) s'explique sous l'écran. Une macro qu'aucune page
     n'appelle ne se montre pas encore : elle viendra avec les mingets (étape 8, formulaire d'appel avec
     arguments de test).
8. **Les mingets**, en cinq parties :
   - **8a — Forme étendue côté serveur (faite)** : `{description, parametres, ecran}`, contrôle des appels,
     arguments omis complétés par `defaut` ; `Service.macros` (voir §9).
   - **8b — Lister et prévisualiser (faite)** : le bouton « Mingets (n) » de la barre du graphe ouvre la liste
     des macros du service (`minget_panel.dart`). Choisir un minget le montre sur un écran Minitel avec des
     arguments d'essai (un champ par paramètre : entier, texte, interrupteur pour un booléen ; valeurs par défaut,
     bouton « Valeurs par défaut »). L'aperçu fabrique une page temporaire `__minget__` qui efface l'écran puis
     appelle la macro (`mingetPreviewText`), relue par le vrai serveur : un appel refusé s'explique à la place de
     l'écran. Pour une macro écrite en liste d'instructions, le type de chaque `$n` est deviné d'après le corps
     (`ligne: $1` : entier ; `ecrit: "$3"` ou `longueur($4)` : texte). « Dans le texte » va à la définition.
   - **8b-2 — Gérer les mingets (faite)** : dans le panneau, **renommer** (la clé et tous les appels, dans les
     pages, les blocs `si` et `fois`, `init` et le corps des autres macros : `renameMacro`, `macroUses`),
     **copier** (la définition recopiée sous un nouveau nom, `duplicateMacro`) et **supprimer**
     (`removeMacro` : refusée tant qu'une page ou une macro l'appelle, avec la liste des appelants ; la
     dernière macro retirée emporte la clé `macros`). Chaque opération est validée avant et après par le serveur
     et se défait avec Ctrl+Z.
   - **8c — Insérer un minget dans une page (faite)** : le sélecteur d'instruction liste aussi les macros du
     service (« macro nom — description » ; on tape `tra` pour `trait`). Un minget sans paramètre s'insère
     tout de suite ; sinon un formulaire d'appel (`macro_call.dart`) propose un champ par paramètre avec sa
     valeur par défaut, refuse d'avance ce que le serveur refuserait (type, bornes) et écrit
     `- macro: [nom, args...]` en **omettant les derniers arguments qui valent le défaut** (`macroCallText`).
     Un appel déjà écrit se montre dans l'onglet Écran avec son nom et un champ par paramètre (les omis avec leur
     valeur par défaut) ; modifier un champ réécrit l'appel, raccourci si possible.
   - **8d — Extraire en minget, voir les usages (faite)** : dans l'onglet Écran, le numéro de chaque
     instruction se coche (il devient une pastille pleine) ; pour une suite de lignes cochées, « Extraire en
     minget » ouvre une boîte (`extract_dialog.dart`) : nom, description, et la liste des valeurs qui peuvent
     varier (entiers et textes des instructions en ligne, texte d'un `ecrit` ; `extractableValues`), chacune avec
     une case et un nom de paramètre proposé d'après sa clé. `extractMinget` écrit la macro en forme étendue (le
     corps garde les lignes d'origine, chaque valeur choisie devient `$n`, sa valeur actuelle le `defaut`),
     la place à la suite des autres macros (ou avant `pages:`), remplace les instructions par
     `macro: [nom]` et vérifie que la page envoie les mêmes octets avant et après. Les blocs `si` et `fois`
     sont déplacés tels quels (leurs valeurs ne sont pas proposées). Dans le panneau Mingets, « Appelé par »
     liste les pages et les macros qui l'appellent (avec leur nombre) ; toucher une page l'ouvre sur l'onglet
     Écran, une macro la choisit. Comme le serveur développe les macros au chargement, modifier une définition
     met déjà tous ses appels à jour : aucune réécriture n'est nécessaire.
   - **8e — La bibliothèque de mingets (plan validé ; 8e-1 faite)** :
     - **8e-1, bibliothèque livrée avec l'éditeur (faite)** : `assets/library.yaml` (déclaré dans le
       `pubspec.yaml`), section `macros:` écrite comme dans un service, en forme étendue : copier-coller
       possible dans les deux sens. Contenu de départ : les six macros de `minserve/example/service.yaml`
       (`titre-centre`, `cadre-3d`, `option`, `titre-simple`, `regle`, `choix`), récrites avec des
       paramètres nommés, typés, avec défaut ; **à relire et corriger par l'auteur** (les défauts et les
       descriptions sont de moi). Règles du fichier : la clé de chaque macro seule sur sa ligne, des
       commentaires juste au-dessus (copiés avec la définition), des définitions autonomes. Dans le
       panneau Mingets, l'icône bibliothèque ouvre la liste des modèles (`library.dart` : `LibraryMinget`,
       `loadLibrary`), avec la même mise en page que les mingets du service : aperçu avec arguments d'essai
       (`withLibraryMacro` met le modèle dans une copie du service, qui ne sert qu'à l'aperçu), marque « dans
       le service » ou « différent ». « Ajouter au service » (`addLibraryMacro`) copie la définition, commentaires
       compris, à la suite des macros (ou dans une section `macros:` avant `pages:`) ; si le service a déjà un
       minget de même nom mais différent, un autre nom est demandé ; s'il est identique, rien n'est copié.
     - **Navigation du volet (faite après 8e-1, sur une remarque de l'auteur)** : une barre d'onglets fixe en
       haut du volet de droite, `Graphe | Page « x » ✕ | Mingets (n)`, remplace les boutons « ← Graphe » et le
       bouton Mingets de la barre d'outils. Les trois vues gardent leur état en changeant de vue (graphe :
       sélection et position ; page : instruction choisie, onglet ; mingets : choix et arguments d'essai,
       le panneau reste dans l'arbre sous un `IndexedStack`). L'onglet Page n'existe que si une page est
       ouverte (un seul à la fois ; ouvrir une autre page le remplace ; ✕ le ferme) ; toucher une autre page
       dans le graphe ne le change pas. « Ouvrir la page » est un vrai bouton (plus d'icône seule). L'onglet
       « Aperçu » de la page devient « Résumé » ; « Rendu » reste dans les détails du graphe. Mingets : une seule
       liste à deux sections, « Du service (n) » puis « Bibliothèque (m) » (marques : à ajouter, déjà dans le
       service, différent), le bascule service / bibliothèque disparaît ; un modèle choisi dit s'il est déjà dans le
       service et propose « Ajouter au service ». Les tests ouvrent une fenêtre de 900 px de haut (la barre ajoute
       44 px).
     - **8e-1b, à faire** : proposer les mingets de la bibliothèque dans le sélecteur d'instruction de l'onglet
       Écran (les ajouter au service au moment de les insérer, en une seule modification).
     - **8e-2, bibliothèque personnelle** : « Ajouter à ma bibliothèque » sur un minget du service ; stockage
       dans le navigateur (même format), plus « Exporter » / « Importer » un fichier `.yaml` de bibliothèque
       pour la partager ou la sauvegarder. Les modèles personnels s'affichent dans la même liste, avec une
       étiquette qui les distingue de ceux livrés.
9. **Édition directe sur l'aperçu** (§5.3).

Les étapes 6 à 8 peuvent s'intervertir selon l'envie : l'aperçu apporte beaucoup à peu de frais
une fois `minterm_view` extrait.

## 9. Décisions

**Prises**

- **Dépôt** : `minserve-editor`, à part (§4.2).
- **Hébergement** : GitHub Pages (§4.4).
- **Édition du YAML en place** (`yaml_edit`, §3, approche B). Vérifié sur le
  YAML de l'exemple à l'étape 4 : commentaires et notations compactes sont conservés ; trois
  cas se font par le texte (voir l'étape 4).
- **Mode de fichier** : ouvrir / enregistrer un fichier seul (§4.3). Dossier local et brouillon
  restent possibles plus tard.
- **Mingets** : forme étendue de `macros:`, côté serveur (§7.1), plutôt qu'un fichier à côté.
- **Partage de mingets** : copie dans chaque service ; une clé d'inclusion pourra venir plus
  tard (§7.3).
- **Dépendances** : par `git:`, sans publier sur pub.dev (§4.2). Les paquets extraits gardent
  `publish_to: none` ; chacun doit être dans un sous-dossier propre du dépôt, avec son
  `pubspec.yaml`, pour que `git: {url, path}` le trouve.
- **Licence** : MIT (§4.4).
- **Limites de l'éditeur** : il peut refuser de représenter graphiquement ce qu'il ne comprend
  pas, avec repli sur le YAML (§3).

**À prendre**

Plus rien d'ouvert à ce stade. La forme de la clé `parametres` des mingets est **tranchée** (étape 8a,
faite côté serveur) : liste de `{nom, type (entier|texte|booleen), defaut, min, max, description}`, le
n-ième étant `$n`, dans une macro écrite en dictionnaire `{description, parametres, ecran}`. Le serveur
contrôle les appels, complète les derniers arguments omis par leur `defaut`, et `Service.macros` expose les
définitions à l'éditeur.

## 10. Risques

| Risque | Parade |
| --- | --- |
| `service.dart` est très couplé à `dart:io` et à `exec` : l'extraction est longue. | Étape 1 isolée, tests existants comme filet, et on l'estime avant de promettre la suite. |
| `yaml_edit` ne conserve pas tout (style de flux, commentaires en fin de ligne). | Vérification précoce (§9) ; sinon éditer le texte à la main par plages de lignes. |
| Le graphe devient illisible sur de gros services. | Flèches globales à part, regroupement, filtre par page, vue « voisinage ». |
| Le rendu de l'aperçu diffère du serveur. | Même code (`minserve_core`) pour produire les octets : aucune réimplémentation. |
| Les dépendances par chemin empêchent de compiler sur GitHub. | Passer à `git:` avant la première publication (§4.2). |
| Flutter web : taille et temps de chargement ; clavier et sélecteurs de fichiers selon le navigateur. | Compiler tôt (`flutter build web`), tester Chrome et Firefox dès l'étape 2. |
| L'émulateur de Minterm évolue pendant l'extraction. | Faire l'étape 6 d'un seul tenant, avec les tests de Minterm. |

## 11. L'application Desktop (Linux)

Le même code Flutter compile en application Linux (`flutter build linux`, dossier `linux/`) ; ça marche
déjà. Le but est d'en faire une vraie application de bureau, sans diverger du code web : **une seule base
de code**, les différences vivent derrière de petites interfaces choisies au démarrage (`kIsWeb`), comme
`FileAccess` (§4.3). Le code propre au bureau (`dart:io`) va dans des fichiers à part, importés
conditionnellement, pour ne rien casser du build web.

### 11.1 Fichier du service (D1)

Aujourd'hui : « Ouvrir » (sélecteur) et « Enregistrer » (boîte « Enregistrer sous » à chaque fois, puisque
le web ne sait que télécharger). Sur Linux :

- une `DesktopFileAccess` qui **garde le chemin** du fichier ouvert : « Enregistrer » (Ctrl+S) réécrit le
  fichier en place, sans boîte ; « Enregistrer sous… » reste disponible ;
- écriture **atomique** (fichier temporaire puis renommage) pour ne jamais laisser un `service.yaml`
  tronqué ;
- **ouvrir en ligne de commande** (`minserve_editor service.yaml`, `main(List<String> args)`) et, plus
  tard, association de fichier (`.desktop`) ;
- **fichiers récents** et dernier service rouvert au lancement (petit fichier de réglages dans
  `~/.config/minserve-editor/`) ;
- **titre de la fenêtre** : nom du fichier et `•` si modifié ;
- **confirmation à la fermeture** si des modifications ne sont pas enregistrées (interception de la
  demande de fermeture de la fenêtre) ;
- **détecter une modification extérieure** (on édite aussi le fichier avec un autre éditeur ou on le
  change par git) : surveiller le fichier ; si le texte de l'éditeur n'a pas été modifié, recharger ; sinon
  proposer « recharger » ou « garder ma version » ; ne jamais écraser en silence.

Le mode « dossier local » du §4.3 (File System Access) devient sans objet sur Linux : c'est ce qu'on fait ici.

### 11.2 Les assets (D2)

Le dossier des assets est **choisi par la configuration du serveur** (`config.assets`), pas forcément à
côté du `service.yaml` : l'éditeur a son propre réglage, **`assets/` à côté du service par défaut**, modifiable
et mémorisé par service. Le serveur impose des règles que l'éditeur applique de la même façon (chemin
relatif avec `/`, rien hors du dossier liens symboliques résolus, 256 Ko au plus).

- brancher `AssetReader` de `renderPage` sur le dossier : l'aperçu montre enfin les `affiche` (il rend
  aujourd'hui des octets vides) ;
- **liste des assets** et choix d'un fichier dans le formulaire de l'instruction `affiche` (aujourd'hui un
  champ texte), avec aperçu du `.vdt` ;
- instruction `affiche` avec un chemin introuvable : signalé dans l'éditeur comme le fait le serveur au
  démarrage (`checkAssets`) ;
- **glisser-déposer** d'un fichier dans l'éditeur : copie dans `assets/`, avec refus d'écraser sans
  confirmation ;
- plus tard (TODO) : incorporer un `.vdt` au `service.yaml` (désassemblage en `ecran`, ou suite d'octets
  telle quelle).

Dans le navigateur, les assets restent à faire par « choisir / glisser » (TODO) : même code d'aperçu, source
différente derrière `AssetReader`.

### 11.3 Autres idées pour le bureau (à trier)

Classées de la plus utile à la plus lourde ; aucune n'est décidée.

1. **Données de test depuis le disque** : lire les vrais fichiers ou la base SQLite d'une page `donnees`
   pour l'aperçu, plutôt que des valeurs saisies. Tout exécutable (`exec`) resterait **désactivé par défaut**,
   à autoriser explicitement par service, avec la même politique `exec.allow` que le serveur.
2. **Contrôle du service avec le vrai serveur** : lancer la validation de `minserve` (`checkAssets`, règles
   `exec`, base SQLite) sur le fichier et afficher les erreurs dans l'éditeur ; plus fidèle que le seul
   `Service.parseString`.
3. **Lancer le service** : démarrer Minserve sur le fichier courant (processus enfant, port local) et
   l'essayer **dans Minterm ou dans le navigateur** ; arrêt et rechargement à l'enregistrement.
4. **Envoyer l'aperçu vers un vrai Minitel** par un port série (ce que fait déjà Minterm).
5. **Exporter une page ou un minget** en `.vdt`, ou en image, depuis l'aperçu.
6. **Dossier de travail** : ouvrir un dossier (service + assets + bibliothèque de mingets personnelle,
   §8 étape 8e-2, rangée dans `~/.config` plutôt que dans le navigateur).
7. **Git** : indiquer les fichiers modifiés, annuler vers la version commitée. À reconsidérer : l'éditeur
   de texte du dépôt fait déjà ça très bien.

À écarter pour l'instant : un « mode multi-fenêtres » et un gestionnaire d'extensions.

### 11.4 Étapes

1. **D0, mise en ordre (faite)** : `linux/` ajouté (exclu de l'analyse) ; entrée `web` rétablie dans
   `.metadata` ; titre de la fenêtre « Minserve Editor » et identifiant `io.github.abasty.minserve_editor`
   (à la place de `com.example`) ; `./build-linux.sh` (tests, `flutter build linux --release`, archive
   `build/minserve-editor-linux-x64.tar.gz` du dossier `bundle/`, 11 Mo, rien n'est publié) ; documenté
   dans le README. `deploy-editor.sh` (web) n'est pas touché. AppImage ou `.deb` : plus tard si besoin.
2. **D1, fichier en place (faite, sauf D1b)** : `FileAccess` gagne `savesInPlace` et `save(name, text, {path,
   saveAs})` qui rend le fichier enregistré (`OpenedFile` a un `path`) ; `FileAccessException` porte les
   erreurs à montrer (barre de message). Le navigateur garde `BrowserFileAccess` (téléchargement) ; le bureau
   a `DesktopFileAccess` (`file_access_io.dart`, importé par `file_access_platform.dart` avec
   `if (dart.library.io)` pour ne rien changer au build web) : sélecteurs du système (`file_picker`, qui
   s'appuie sur `zenity` ou `kdialog` sous Linux), lecture directe, écriture atomique (fichier voisin puis
   renommage, lien symbolique suivi). Dans l'éditeur : « Enregistrer » et Ctrl+S réécrivent en place (la
   première fois d'un nouveau service, le nom est demandé), « Enregistrer sous… » et Ctrl+Maj+S, bouton
   absent dans le navigateur ; `minserve_editor service.yaml` ouvre un fichier au départ (erreur de lecture
   : message ; un nom qui n'existe pas : nouveau service qui sera créé à l'enregistrement, avec un message) ;
   le titre de la fenêtre est « fichier • — Minserve Editor » (widget `Title`) ; à la fermeture de la fenêtre,
   le moteur Linux (qui traite lui-même `delete-event`) envoie `System.requestAppExit` au cadre
   d'application ; l'éditeur y répond avec `AppLifecycleListener.onExitRequested` (question s'il reste des
   modifications). Une première version avec un canal écrit dans `my_application.cc` ne marchait pas : le
   moteur prend la fermeture avant, ce code natif a été retiré. **Corrigé après essai de l'auteur** (la
   confirmation ne venait pas ; un fichier inexistant de la ligne de commande ne disait rien). Le
   sélecteur système et l'enregistrement en place ont été essayés par l'auteur sur un vrai service ; la
   fermeture corrigée est à réessayer.
   **D1b (faite)** : `lib/src/settings.dart` (`AppSettings`, `SettingsStorage`) garde dans
   `~/.config/minserve-editor/settings.json` (ou `$XDG_CONFIG_HOME`) les 10 derniers fichiers et le dossier
   assets de chaque service ; illisible ou non écrivable, il est ignoré sans bruit ; rien dans le
   navigateur. Un menu « Fichiers récents » (icône historique, bureau seulement, avec « Vider la liste »)
   rouvre un fichier (retiré de la liste s'il a disparu). Sans fichier demandé en ligne de commande,
   l'éditeur rouvre le dernier service s'il existe encore. L'éditeur surveille le dossier du fichier ouvert
   (`FileAccess.changes`, car « Enregistrer » remplace le fichier par un renommage) : après une pause de
   300 ms il relit le fichier ; si son texte est celui qu'on a enregistré ou déjà écarté, rien ; sinon, sans
   modification en cours il recharge avec un message, avec des modifications il demande « Garder ma
   version » ou « Recharger » (et ne redemande pas pour le même texte). Recharger efface l'historique
   défaire / refaire. **Non essayé à la main** : la surveillance réelle n'a été vérifiée que par un test
   avec un dossier temporaire.
3. **D2, assets** (§11.2), en trois temps :
   - **D2a, lire les assets pour l'aperçu (faite)** : `lib/src/assets.dart` (`AssetSource`, `AssetException`,
     `MapAssets`, `AssetsScope`) ; `FileAccess.assetsFor(chemin du service)` rend `DirectoryAssets` sur le
     bureau (`assets/` à côté du `service.yaml`, avec les règles du serveur : chemin relatif, rien hors du
     dossier liens symboliques résolus, fichier ordinaire, 256 Ko au plus) et `null` dans le navigateur ou
     pour un service pas encore enregistré. `renderPreview(..., source:)` lit les `affiche` ; un fichier
     illisible n'arrête pas l'aperçu, la note « Fichiers affiche non montrés (dossier …) » donne la raison de
     chacun. `AssetsScope` (dans `EditorPage`) évite de faire passer la source dans tout le graphe.
   - **D2b, liste et choix d'un fichier (faite)** : `AssetSource.list()` (tous les fichiers, sous-dossiers
     compris, sans ceux que `read` refuserait, 5000 au plus) ; dans l'onglet Écran, l'instruction `affiche`
     montre son champ « Fichier », un bouton « Choisir dans les assets » (`asset_dialog.dart` : liste
     filtrable, écran Videotex du fichier choisi avec bascule couleur / gris, taille) et, sous le champ,
     la taille du fichier ou la raison qui empêche de le lire (introuvable, hors du dossier, trop gros).
     Rien de tout cela dans le navigateur (pas de source d'assets).
   - **D2b-2, dossier assets au choix (faite avec D1b)** : dans la fenêtre « Choisir un fichier », « Dossier… »
     choisit un autre dossier que `assets/` à côté du service (la configuration du serveur peut le placer
     ailleurs), « Par défaut » y revient ; le choix est mémorisé par service (chemin du `service.yaml`).
     `AssetsSetup` (dans `AssetsScope`) porte ces deux actions.
   - **D2c, à faire** : glisser-déposer d'un fichier dans l'éditeur (copie dans `assets/`, sans écraser sans
     confirmation).
4. **D3, choix parmi §11.3**, selon l'envie.

Les étapes D se glissent entre les étapes 8 et 9 du §8 selon l'envie ; D1 et D2 n'ont aucune dépendance avec les
mingets. Tests : `DesktopFileAccess` se teste avec un dossier temporaire (pas d'interface graphique) ; le
reste réutilise les doubles `FakeFiles` existants.
