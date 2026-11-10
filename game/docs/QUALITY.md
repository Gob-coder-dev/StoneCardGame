# Qualité du code et livraison

Ce document fixe les critères de maintenance du jeu. Il complète
[`ARCHITECTURE.md`](ARCHITECTURE.md) sans dupliquer les règles fonctionnelles.

## Frontières

| Couche | Peut connaître | Ne doit pas connaître |
| --- | --- | --- |
| `domain/` | valeurs, catalogues en lecture, règles pures | scènes, transport, sauvegarde |
| `engine/` | domaine et état d'un combat | menus, campagne, sockets |
| `application/` | cas d'usage, domaine, ports de persistance/réseau | composition visuelle des scènes |
| `data/` | chargement, validation, migration, stockage | navigation et rendu |
| `network/` | protocole et transport | interface et profil persistant |
| `ui/` | projection des services et intentions du joueur | nouvelle règle métier |

Une façade de compatibilité doit annoncer explicitement sa destination, comme
`scripts/data/PvpMatchContext.gd`. Elle ne doit pas recevoir de nouvelle logique.

Le guidage interactif constitue une frontière explicite : `StoryService` et
`TutorialDirector` peuvent conserver des références faibles vers des ancres
`Control` afin de séquencer un tutoriel. Ils ne créent toutefois aucun contrôle,
ne composent aucune scène et délèguent entièrement le rendu à `ui/story/`.

## Fonctions et fichiers

- Une fonction porte une intention. Au-delà d'environ 60 lignes, vérifier si
  validation, transformation et effets de bord peuvent être nommés séparément.
- Une longueur supérieure reste acceptable pour une table de validation ou une
  construction de rapport pure si le découpage masquerait les invariants.
- Un contrôleur de scène coordonne plusieurs composants, mais ne recalcule pas
  leurs règles. Les calculs partagés exposent une projection unique, par exemple
  `PlayerData.card_upgrade_state()` pour les vues d'amélioration.
- La concision n'est pas un objectif isolé : deux lignes opaques ne remplacent
  pas dix lignes qui rendent un protocole ou une transaction vérifiable.

## Commentaires

Chaque script de production commence par sa mission et ses limites. Les
commentaires expliquent une contrainte, un invariant ou une raison ; ils ne
paraphrasent pas l'instruction suivante. Les migrations et façades historiques
indiquent pourquoi elles existent encore et leur condition de suppression.

Les guides de production artistique, dont `PROMPTS_FOOOCUS.md`, sont de la
documentation de contenu. Les consignes propres à un assistant ou à un poste de
travail restent hors du code et sont ignorées par Git.

## Performance

- Aucun chargement de fichier ou d'image ne doit être déclenché dans `_draw()`.
- Les `_process()` sont désactivés lorsqu'ils n'ont plus de travail.
- Les grandes listes réutilisent leurs vues ou chargent par secteurs.
- Une animation ne possède jamais une transaction : la sauvegarde précède sa
  présentation.
- Une optimisation doit viser une mesure ou supprimer un travail répété ; elle
  ne doit pas introduire un second cache sans cycle de vie explicite.

## Git

Les sources `.gd.uid`, les scènes, ressources, données et
`export_presets.cfg` sont versionnés. Les caches Godot, imports générés,
bytecodes Python, builds, APK, secrets de signature, journaux et métadonnées
locales d'outils sont exclus par le `.gitignore` racine.

## Validation avant livraison

Depuis la racine du dépôt :

```powershell
godot --headless --fixed-fps 60 --path game res://tests/GodSystemChecks.tscn
godot --headless --fixed-fps 60 --path game res://tests/TouchInputChecks.tscn
git diff --check
git status --short
```

Les deux suites doivent terminer avec le code `0`. Une vérification visuelle
reste obligatoire sur téléphone et tablette pour les proportions, gestes,
transitions et coûts de première ouverture.
