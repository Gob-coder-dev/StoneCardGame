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
| Godot 4.7 | 0.8.0 | Android, portrait 9:16 |

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

L'accueil propose deux modes de largeur égale : **CAMPAGNE**, qui ouvre les
rencontres contre l'IA, et **PVP**, qui ouvre un salon local. Deux téléphones
Android sur le même Wi-Fi peuvent créer et rejoindre une partie sans serveur
Internet, sans compte et sans service externe. Les deux modes partagent le même
plateau, le même moteur et les mêmes vues ; seul le driver du match change. Un
deck incomplet laisse le joueur sur l'accueil et ouvre une fenêtre modale
« DECK INCOMPLET ». Elle bloque les actions en arrière-plan, indique le nombre
de cartes manquantes et propose soit de fermer l'avertissement, soit d'ouvrir
directement la collection pour compléter le deck.

Le salon PVP propose quatre préparations — **Classique** (dieu et deck du
profil), **Aléatoire** (dieux et decks générés à chaque manche), **Miroir** (un
loadout dupliqué pour les deux camps) et **Sélection** (draft parallèle de 60 s
avec deux offres par camp, huit choix indépendants et un deck local actualisé)
— et trois formats de série : **FT1**, **FT2** (premier à 2 victoires) et
**FT3** (premier à 3). Une égalité ne marque aucun point et rejoue une manche.
L'hôte choisit le mode, la série et le palier de puissance ; toute modification
remet les deux joueurs à PAS PRÊT, et les règles se verrouillent après le double
PRÊT. Les cartes sont limitées par `power_tier = niveau de forme + décalage de
rareté`, avec une exception explicite possible dans le catalogue.

Le Classique FT1 démarre immédiatement après le double PRÊT. Le Classique
FT2/FT3 initialise la série puis lance la manche depuis le salon, avec les
mêmes identifiants sur les deux appareils. Aléatoire, Miroir et Sélection
ouvrent l'écran dédié **Préparation PVP** : le loadout local y est présenté avec
le dieu et ses huit cartes illustrées. En Sélection, deux offres adverses
compactes restent visibles en haut, deux offres locales sont centrées et le
deck local `VOTRE DECK — X / 8` se met à jour après chaque choix ; aucun choix
ni deck adverse n'est exposé. L'écran de résultat propose ensuite une action
principale adaptée au format (REVANCHE, PARTIE SUIVANTE ou NOUVELLE SÉRIE),
**RETOUR AU SALON** qui ramène chaque joueur individuellement en conservant la
connexion ENet (l'autre voit `EN PARTIE`), et **QUITTER** qui ferme la session
et revient au choix Créer/Rejoindre.

Les profils du salon et les loadouts de manche sont stockés séparément. Les
dieux et decks générés restent temporaires : ils peuvent survivre aux manches
qui doivent les conserver dans une même série, mais sont détruits au retour au
salon. Une partie Classique suivante reprend toujours le dieu et le deck
enregistrés de chaque joueur, sans modifier `PlayerData`.

La préparation des modes n'est plus liée au réseau. `GameModeRules`,
`SeriesRules`, `GameLoadout`, `LoadoutGenerator`, `DraftEngine` et
`ModePreparationService` forment le socle commun ; `CampaignModeSession`
orchestre localement le même Classique, Aléatoire, Miroir ou Sélection contre
l'IA, y compris FT1/FT2/FT3. `BattleContext.begin_mode()` constitue le point
d'entrée de la campagne et les drivers de combat lisent ses loadouts
temporaires. L'écran public de choix des règles de campagne reste volontairement
à ajouter plus tard : son ajout ne demandera ni duplication des règles ni
dépendance à ENet.

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
actuellement **275 PNG** : les 96 N1, les 81 N2, les 65 N3 et les 33 N4 sont
illustrés. Les Avortons des caves ont leurs quatre illustrations propres, avec
3, 6, 9 puis 12 individus. Toutes les lignées évolutives disposent désormais
d'une image propre pour chacun de leurs niveaux.
Les définitions de jeu
restent dans `data/stones.json` : modifier une image ne modifie donc ni les
statistiques ni les sauvegardes.

Au lancement, `CardArtCache` préchauffe en arrière-plan les illustrations du
dieu, du niveau et du deck actifs ; l'accueil affiche sa progression. La page
Cartes réutilise ensuite sa grille : un tri déplace les cartes existantes et un
changement de dieu conserve les 24 cartes neutres. Les six portraits de dieux
restent préparés pour la session, mais le jeu ne conserve jamais volontairement
les 275 illustrations de cartes dans son cache applicatif.

## Menus et lecture visuelle

La navigation inférieure donne accès à **Cartes**, **Jouer** et **Règles**. La
page Cartes comporte :

- les six dieux, représentés par leurs portraits ;
- trois decks sauvegardés automatiquement pour chaque dieu ;
- la collection, le tri, le remplacement d'une carte et les fiches détaillées ;
- le choix du niveau à équiper, sans bouton de sauvegarde séparé.

Les Rencontres se lisent en deux temps : une grille de grandes cases illustrées
(portrait, nom, famille et motif du dieu), puis un chemin serpentin de quinze
niveaux par adversaire. Chaque palier de cartes forme un chapitre et chaque
difficulté un rond ; un rond s'ouvre quand le précédent a été gagné. La
progression est déduite des victoires déjà enregistrées, sans nouveau champ de
sauvegarde. Le profil reprend la même règle : statistiques générales, puis un
chemin par dieu et pour Pr.Stone avec le nombre de niveaux terminés sur quinze.
Après une victoire, le résultat propose le niveau suivant du même chemin, une
revanche, un autre niveau, un autre dieu ou l'accueil ; après une défaite ou au
dernier rond, la sortie « Niveau suivant » disparaît.

L'interface adopte un thème d'arène machiavélique : fonds charbon, accents de
métal incandescent et halos néon violets ou carmin. Les formes restent discrètes
pour préserver la lisibilité des cartes et des règles. Les informations de
combat sont séparées visuellement afin de rester lisibles sur téléphone :

Le salon PVP garde la même arche de pierre et deux épées néon croisées à chaque
étape. Les écrans de résultat de campagne et de PVP partagent trois illustrations
selon le verdict : feux d'artifice aux nuances du dieu gagnant, crâne de cette
couleur en cas de défaite, ou deux épées aux couleurs des dieux en cas d'égalité.
Le détail de la direction artistique est dans
[IDENTITE_VISUELLE_MENUS.md](docs/IDENTITE_VISUELLE_MENUS.md).

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
  domain/                Règles pures : modes, séries, decks, coûts et pouvoirs
  application/           Orchestration des parcours sans dépendre des scènes
    pvp/                 Contexte, salon et adaptation des loadouts réseau
  engine/                GameState, tours, résolution des combats et effets
  network/               Transport et protocole ; projections PVP dans network/pvp
  ai/                    Évaluation des coups, ripostes et recherche de fin de partie
  ui/                    Menus, cartes, plateau, HUD et composants tactiles
    collection/          Sélection de dieu/deck, collection et panneaux de cartes
    combat/              Présentations, géométrie et animations de combat
    encounters/          Grille des dieux et chemin des niveaux
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

Les Rencontres proposent les six dieux et Pr.Stone, un adversaire sans dieu qui
utilise exclusivement des cartes neutres. Chacun se joue sur trois paliers de
cartes et cinq difficultés, présentés comme un chemin de quinze niveaux : un
niveau s'ouvre quand le précédent est gagné. Une victoire antérieure hors
séquence reste enregistrée mais ne valide le rond qu'une fois les précédents
gagnés. Pour les bots, les paliers tiennent compte de la
rareté sans modifier le niveau réel des formes : les épiques commencent au
palier 3 et les légendaires au palier 4. Le deck ne dépend que de l'adversaire et
du palier ; la difficulté règle la précision de l'IA (0, 0,25, 0,5, 0,75 ou 1)
et, au niveau le plus élevé, l'anticipation.

Pour le détail des responsabilités, des signaux et des fichiers, voir
[l'architecture complète](docs/ARCHITECTURE.md). Pour la palette et les choix de
mise en page, voir [l'identité visuelle des menus](docs/IDENTITE_VISUELLE_MENUS.md).
Le PVP local (rôles, ports, protocole, autorité de l'hôte, limites et dépannage)
est décrit dans [PVP_LOCAL.md](docs/PVP_LOCAL.md).
L’univers, les familles et les dieux sont décrits dans la
[direction artistique](docs/DIRECTION_ARTISTIQUE_MONSTRES.md).
L’[index de la documentation](docs/README.md) regroupe les références du projet,
dont le bestiaire et la direction artistique.

## Données et sauvegarde

Les données de contenu sont validées au démarrage :

- `data/stones.json` : lignées, formes, coûts, symboles et pouvoirs ;
- `data/gods.json` : dieux, familles, couleurs, descriptions et portraits ;
- `data/npcs.json` : six adversaires historiques, conservés pour les tests et
  les anciennes références ;
- `OpponentCatalog` : génère les 105 rencontres (six dieux et un bot neutre,
  trois paliers de cartes et cinq difficultés) sans dupliquer leurs decks.

Le profil local est enregistré dans `user://savegame.json`. Le format actuel est
la version 4 : il conserve le pseudo, les statistiques, les trois decks de chacun
des six dieux et le deck sélectionné pour chaque dieu. Les écritures passent par
un fichier temporaire pour éviter un profil partiellement écrit.

Les anciennes sauvegardes sont migrées automatiquement. Avant la première écriture
d'un ancien profil converti, la version d'origine est conservée dans
`user://savegame.json.before_monsters`.

Les IDs de contenu sont descriptifs et stables : une carte utilise par exemple
`avortons_des_caves_n2`, et les dieux utilisent `veskar`, `nerava`, `kharun`,
`ilyr`, `sylkha` et `enigma`. Les anciens IDs ne servent qu'à migrer les
sauvegardes ; ils ne doivent pas être employés dans du nouveau code ou de
nouveaux decks.

## Ouvrir le projet

1. Installer [Godot 4.7](https://godotengine.org/download/) ou une version plus
   récente compatible.
2. Dans Godot, choisir **Importer** puis sélectionner ce dossier.
3. Ouvrir le projet et lancer la scène principale `scenes/menus/MainMenu.tscn`.

Le projet utilise un canevas de référence de 1080 × 1920 avec étirement
`canvas_items` et l'aspect `expand` : les écrans plus hauts que le 9:16
reçoivent de l'espace supplémentaire au lieu de bandes noires. Les motifs
centrés gardent une échelle uniforme ; les salles BOARD et PVP ancrent en plus
leurs rails et arches à la largeur réelle pour rester plein cadre sur tablette.
Les compositions de combat et de préparation utilisent largeur et hauteur
disponibles : le Redmi de référence expose environ 1080 × 2400 au layout,
contre 1200 × 1920 pour la tablette.

## Tests

Les suites sont autonomes : aucune extension de test n'est nécessaire. Depuis la
racine du projet, avec `godot` disponible dans le `PATH` :

```sh
godot --headless --fixed-fps 60 --path . res://tests/GodSystemChecks.tscn
```

Cette suite couvre le catalogue, les sauvegardes, les règles de combat, les six
familles, l'IA, les animations, les menus, les régressions de rendu et le PVP
local (protocole, salon, modes et séries, génération des loadouts, draft,
confirmations et commandes validées par l'hôte).

```sh
godot --headless --fixed-fps 60 --path . res://tests/TouchInputChecks.tscn
```

Cette suite injecte de vrais événements tactiles et vérifie notamment le
défilement, les appuis, l'inertie, le multitouch, la fermeture des panneaux
modaux et la pose de cartes. Le résumé imprimé par chaque lanceur est la source
de vérité : le nombre de vérifications évolue avec les fonctionnalités et n'est
volontairement pas figé ici. Une livraison est valide uniquement lorsque les
deux commandes terminent avec le code `0`, sans échec ni erreur Godot.

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
