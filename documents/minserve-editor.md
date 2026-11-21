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
5. **L'éditeur de page** en formulaires (saisie, règles, accès), avec repli en YAML.
6. **Extraire `minterm_view`** de Minterm, puis **l'aperçu** d'une page.
7. **L'aperçu d'un morceau**, les données de test, l'édition de l'`ecran` en liste
   d'instructions avec aperçu.
8. **Les mingets** : forme étendue côté serveur, palette, formulaire d'appel, extraction,
   bibliothèque.
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

Plus rien d'ouvert à ce stade. Une question technique se tranche au fil des étapes : la forme
exacte de la clé `parametres` des mingets (étape 8).

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
