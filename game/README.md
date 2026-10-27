# SamStone — jeu Godot

Ce dossier est le projet Godot autonome du monorepo SamStone. Les commandes de
ce document sont à exécuter depuis `game/`, sauf lorsqu'elles utilisent
explicitement `--path game`. Voir aussi le [README racine](../README.md).

Jeu de cartes stratégique mobile créé avec Godot. Deux joueurs s'affrontent sur
un plateau de 4 × 4 cases en posant des pierres-monstres : les lames de chaque
face capturent les cartes adverses, tandis que le dieu choisi donne accès à une
famille de pouvoirs et à son propre style de jeu.

L'univers actuel est un bestiaire d'horreur : monstres organiques, machines
vivantes, créatures coloniales et entités du hasard. Le projet cible Android,
mais se lance également sur ordinateur avec Godot.

| Moteur | Version du projet | Cible principale |
| --- | --- | --- |
| Godot 4.7 | 0.6.0 | Android, portrait 9:16 |

## Aperçu du jeu

- Plateau de **4 × 4** cases, avec 0 à 2 cases aléatoirement condamnées.
- Un deck contient **8 pierres**, pour un budget maximal de **80 points**.
- Chaque face ne peut contenir que **4 symboles** au total : lames, lames
  spéciales et boucliers utilisent les mêmes emplacements.
- Une capture réussit seulement si l'attaque est strictement supérieure à la
  défense de la face adverse. Une égalité ne capture pas.
- Le premier joueur est tiré au sort ; le gagnant contrôle le plus de pierres
  lorsque toutes les cases jouables sont remplies.

Une pierre se pose par toucher successif (carte, puis case) ou par glisser-déposer.
Les gestes tactiles sont prévus pour laisser défiler les écrans lorsqu'ils ne
deviennent pas un appui volontaire.

## Dieux et familles

Le joueur choisit un dieu. Son deck peut inclure les 24 lignées neutres et les
12 lignées exclusives de sa famille.

| Dieu | Famille | Identité de jeu |
| --- | --- | --- |
| Véskar, le Manipulateur | Les Aléators | Lames roses aléatoires à demi-coût et pile ou face qui échange des faces. |
| Nérava, la Mère des Fièvres | Les Flétris | Miasme continu sur les voisines ennemies et Échec corrosif après une résistance. |
| Kharûn, la Muraille | Les Remparts | Demi-boucliers qui augmentent la défense sans augmenter l'attaque. |
| Ilyr, le Guetteur Éternel | Les Veilleurs | Lames bleues qui attaquent à distance et traversent les alliés. |
| Sylkha, la Mère-Ruche | L'Essaim | Liaisons organiques entre alliés et bonus de lames d'aura partagés. |
| Énigma, la Machine Première | Les Assimilateurs | Les symboles vaincus deviennent des boucliers répartis sur l'attaquant. |

Les effets continus de famille, comme le Miasme et l'Essaim, ne restent actifs
que lorsqu'une carte appartient au camp dont le dieu correspond à sa famille.

## Cartes, raretés et évolutions

Le catalogue contient **96 lignées** et **275 formes** jouables :

| Rareté | Lignées | Formes | Niveaux maximum |
| --- | ---: | ---: | ---: |
| Commune | 33 | 132 | 4 |
| Rare | 32 | 96 | 3 |
| Épique | 16 | 32 | 2 |
| Légendaire | 15 | 15 | 1 |

Chaque lignée ne peut figurer qu'une fois dans un même deck, quel que soit le
niveau sélectionné. Le filtre de collection permet d'apercevoir un niveau donné,
et la fiche **Infos** permet de consulter les formes puis d'équiper précisément
celle choisie.

Les illustrations sont stockées dans `assets/cards/`. Le projet embarque
actuellement **246 PNG** : les 96 N1, les 81 N2 et les 65 N3 sont illustrés,
ainsi que 4 N4. Les 29 N4 restants héritent encore du dessin de leur lignée.
Les définitions de jeu
restent dans `data/stones.json` : modifier une image ne modifie donc ni les
statistiques ni les sauvegardes.

## Menus et lecture visuelle

La navigation inférieure donne accès à **Cartes**, **Jouer** et **Règles**. La
page Cartes comporte :

- les six dieux, représentés par leurs portraits ;
- trois decks sauvegardés automatiquement pour chaque dieu ;
- la collection, le tri, le remplacement d'une carte et les fiches détaillées ;
- le choix du niveau à équiper, sans bouton de sauvegarde séparé.

L'interface adopte le style du *cabinet des monstres* : ardoise sombre, texte
ivoire, accents ambrés et portraits horrifiques. Les informations de combat sont
séparées visuellement afin de rester lisibles sur téléphone :

| Élément | Information portée |
| --- | --- |
| Cadre minéral sombre de la carte | Famille du dieu |
| Contour extérieur simple | Rareté |
| Logo en haut à droite | Pouvoir de la carte |
| Case du plateau | Propriétaire : bleu pour le joueur, rouge pour l'adversaire |
| Grande croix ivoire | Case condamnée, non jouable |

Lors d'une capture, la case change de camp au moment de l'impact. La carte garde
donc toujours son cadre de rareté et de famille, même après plusieurs captures.

## Architecture

Le projet sépare volontairement les règles, la présentation et les données :

```text
data/                    Catalogue des cartes, dieux et adversaires
scripts/
  data/                  Chargement du catalogue, profil et migration des sauvegardes
  domain/                Deck, coûts, évolution, côtés et constantes de pouvoirs
  engine/                GameState, tours, résolution des combats et effets
  ai/                    Évaluation des coups, ripostes et recherche de fin de partie
  ui/                    Menus, cartes, plateau, HUD et composants tactiles
    collection/          Sélection de dieu/deck, collection et panneaux de cartes
    combat/              Présentations, géométrie et animations de combat
scenes/                  Scènes Godot des menus, du combat et des composants
assets/                  Illustrations, portraits, icônes et thème
tests/                   Suites de règles, IA, interface et interactions tactiles
```

Le flux principal est le suivant :

1. `CombatResolver` calcule le placement, les attaques, captures et effets.
2. `TurnManager` organise les phases du tour et attend les présentations.
3. `BoardController` relaie les événements vers la vue.
4. `BoardView` et `BoardAnimationController` affichent le résultat sans modifier
   les règles ni relancer le hasard.

L'IA utilise le même moteur sur des copies de l'état : elle ne lit ni la main
réelle du joueur ni le prochain tirage aléatoire.

Les Rencontres combinent un dieu, un palier de cartes (niveau 1, niveau 2,
niveaux 3) et une difficulté. Le deck ne dépend que du dieu et du palier ;
la difficulté règle la précision de l'IA (0, 0,25, 0,5, 0,75 ou 1) et, au
niveau le plus élevé, l'anticipation.

Pour le détail des responsabilités, des signaux et des fichiers, voir
[l'architecture complète](docs/ARCHITECTURE.md). Pour la palette et les choix de
mise en page, voir [l'identité visuelle des menus](docs/IDENTITE_VISUELLE_MENUS.md).
La bible des monstres, des dieux et des évolutions est dans la
[direction artistique](docs/DIRECTION_ARTISTIQUE_MONSTRES.md).

## Données et sauvegarde

Les données de contenu sont validées au démarrage :

- `data/stones.json` : lignées, formes, coûts, symboles et pouvoirs ;
- `data/gods.json` : dieux, familles, couleurs, descriptions et portraits ;
- `data/npcs.json` : six adversaires historiques, conservés pour les tests et
  les anciennes références ;
- `OpponentCatalog` : génère les quatre-vingt-dix rencontres (six dieux, trois
  paliers de cartes et cinq difficultés) sans dupliquer leurs decks.

Le profil local est enregistré dans `user://savegame.json`. Le format actuel est
la version 4 : il conserve le pseudo, les statistiques, les trois decks de chacun
des six dieux et le deck sélectionné pour chaque dieu. Les écritures passent par
un fichier temporaire pour éviter un profil partiellement écrit.

Les anciennes sauvegardes sont migrées automatiquement. Avant la première écriture
d'un ancien profil converti, la version d'origine est conservée dans
`user://savegame.json.before_monsters`.

## Ouvrir le projet

1. Installer [Godot 4.7](https://godotengine.org/download/) ou une version plus
   récente compatible.
2. Dans Godot, choisir **Importer** puis sélectionner ce dossier.
3. Ouvrir le projet et lancer la scène principale `scenes/menus/MainMenu.tscn`.

Le projet utilise un canevas de référence de 1080 × 1920 avec étirement
`canvas_items` et l'aspect `expand` : les écrans plus hauts que le 9:16
reçoivent de l'espace supplémentaire au lieu de bandes noires, sans déformer
l'interface portrait.

## Tests

Les suites sont autonomes : aucune extension de test n'est nécessaire. Depuis la
racine du projet, avec `godot` disponible dans le `PATH` :

```sh
godot --headless --fixed-fps 60 --path . res://tests/GodSystemChecks.tscn
```

Cette suite couvre le catalogue, les sauvegardes, les règles de combat, les six
familles, l'IA, les animations, les menus et les régressions de rendu.

```sh
godot --headless --fixed-fps 60 --path . res://tests/TouchInputChecks.tscn
```

Cette suite injecte de vrais événements tactiles et vérifie notamment le
défilement, les appuis, l'inertie, le multitouch, la fermeture des panneaux
modaux et la pose de cartes. Au dernier contrôle, les suites terminent
respectivement par :

```text
GOD_SYSTEM_CHECKS: 446 passed, 0 failed, 0 Godot errors
TACTILE : 76 vérifications, 0 échec(s), 0 erreur(s) Godot.
```

Les tests automatisés ne remplacent pas une vérification visuelle sur téléphone
après export : les animations, le confort des gestes et la lisibilité doivent
aussi être testés sur l'écran cible.

## Export Android

1. Installer le JDK 17 et le SDK Android.
2. Dans Godot, ouvrir **Projet → Export → Android**.
3. Configurer un keystore de signature pour une distribution, ou utiliser le
   keystore de débogage pour les essais locaux.
4. Exporter l'APK depuis le préréglage Android.

Les fichiers de build, APK, clés et exports sont volontairement exclus de Git.
