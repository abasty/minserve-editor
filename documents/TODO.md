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
- [ ] Autres : commentaire/décommentation de lignes (Ctrl+/), annuler/refaire fiable, repli des pages, mini-carte ou liste des pages (plan du document), correspondance des guillemets et crochets.
- [ ] À trancher : continuer à écrire notre propre champ de texte (`code_editor.dart`, ligne de hauteur fixe) ou adopter un paquet d'édition de code. Contrainte : pas de ressource tierce chargée à l'exécution (voir doc §4.4).
