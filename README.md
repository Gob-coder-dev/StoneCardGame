# SamStone

Jeu de cartes stratégique inspiré de Skystones (Skylanders Giants).
Univers : bestiaire d'horreur, 96 lignées illustrées au niveau 1.
Plateforme cible : Android (APK)
Moteur : Godot 4 + GDScript

---

## Structure du projet

Le guide [Architecture](docs/ARCHITECTURE.md) décrit chaque fichier, ses fonctions
principales, les communications et les emplacements pour ajouter un pouvoir.
Le fichier local `CLAUDE.md`, lorsqu'il est présent, contient les consignes de
travail pour Claude. Ce fichier et les archives historiques sont exclus de Git.

Le moteur applique les règles dans `CombatResolver` et les systèmes de pouvoirs.
`TurnManager` organise les tours et attend la fin effective de chaque présentation.
`BoardController` transmet les demandes à `BoardAnimationController` ; `BoardView`
affiche le plateau. `PlayerData` sauvegarde le profil, tandis que `BattleContext`
conserve uniquement les informations temporaires du combat.

```text
data/                  Définitions complètes : cartes, dieux et adversaires
scripts/
  data/                Catalogue, validation, profil sauvegardé et BattleContext
  domain/              DeckRules, StoneEvolutionRules, coûts, faces et pouvoirs
  engine/              État, tours, validation et résolution générale
    combat/            Attaques, événements et ticket de présentation
    effects/           Pose, Fortune, Déclin, Pillage et Essaim
  ai/                  IA à profils, évaluation des coups et AITurnRunner
  ui/                  Écrans, plateau, main et StoneCard
    collection/        Sélecteurs de dieu et de deck, grille et panneaux
    combat/            Présentation, géométrie et animations
      animations/      Fortune, pièce et Pillage
    input/             Gestes et défilement tactiles
scenes/                Menus, combat et composants
tests/
  combat/              Règles, profils, séquences et parties animées
  ai/                  Choix des IA et simulations
  ui/                  Menus et animations
  support/             Fixtures et assertions communes
```

---

## Pour ouvrir le projet

Les menus utilisent le **cabinet des monstres** : fonds de refuge, panneaux
en ardoise, texte ivoire, boutons ambrés et portraits des six dieux. La palette
est centralisée dans `UITheme` et le thème est construit par `RefugeTheme`.
Sur une carte, le minerai sombre indique la famille et le liseré intérieur
indique la rareté par sa couleur comme par sa forme. En combat, le cadre de la
case — bleu ou rouge — indique le camp ; une grande croix ivoire signale les
cases interdites. Une capture recolore sa case au moment exact de l'impact.
Voir [l'identité visuelle des menus](docs/IDENTITE_VISUELLE_MENUS.md).

1. Télécharger **Godot 4.7** (ou plus récent) sur https://godotengine.org
2. Lancer Godot → "Import" → sélectionner ce dossier `samstone/`
3. Le projet s'ouvre directement

---

## Pour lancer les tests

Les deux suites sont autonomes, sans extension GUT à installer. Exécuter les
commandes depuis la racine du projet, avec Godot disponible dans le `PATH`.

La suite de règles et d'intégration couvre le deck, les sauvegardes, les six
familles, les attaques, le hasard reproductible et caché à l'IA, les effets,
l'IA et ses profils, les menus et le séquencement des animations. Elle compare aussi
des parties animées avec les simulations instantanées pour chaque famille.

```sh
godot --headless --fixed-fps 60 --path . res://tests/GodSystemChecks.tscn
```

La suite tactile vérifie les interactions avec de vrais événements Godot :

```sh
godot --headless --fixed-fps 60 --path . res://tests/TouchInputChecks.tscn
```

Cette suite injecte les événements par `Input`, avec l'émulation et le routage
GUI de Godot. Elle couvre le défilement sur le texte, les cartes et les boutons,
l'annulation des appuis, l'inertie, le multitouch, les fenêtres, la souris,
le clavier et la pose d'une carte pendant un combat, par appuis ou par glissement
au doigt et à la souris, ainsi que les boutons des trois decks. Les tests de
profil et d'interface écrivent dans des fichiers temporaires dédiés, puis les
suppriment ; la sauvegarde personnelle du joueur reste intacte.

Chaque suite se termine par un résumé, par exemple
`GOD_SYSTEM_CHECKS: 433 passed, 0 failed, 0 Godot errors` ou
`TACTILE : 63 vérifications, 0 échec(s), 0 erreur(s) Godot.`, et renvoie le code
de sortie 1 en cas de problème. Sont comptés comme problèmes : une vérification
ratée, une suite qui ne compile pas, une erreur ou un avertissement Godot non
annoncé par le test, et un dépassement du temps limite (300 s et 120 s de jeu).
Les avertissements annoncés, comme le garde-fou des animations, restent visibles
dans le journal. Une erreur de compilation d'un lanceur lui-même n'affiche aucun
résumé : un résumé absent est donc aussi un échec.

Les suites détaillées sont réparties dans `tests/combat/`, `tests/ai/` et
`tests/ui/` ; leurs fixtures, assertions et le journal `TestLog` sont dans
`tests/support/`. Une vérification headless ne remplace pas un contrôle visuel
des animations.

Sur téléphone, vérifier également les mêmes gestes après réexport de l'APK.
L'émulation souris depuis le tactile reste activée : Godot 4.7 l'utilise pour
le défilement natif. Les interactions personnalisées ignorent les doublons
émulés, et `TouchButton` supprime leur survol visuel tout en conservant les
appuis natifs, le clavier et la souris physique.

---

## Pour exporter en APK Android

1. Installer le JDK 17 et le SDK Android (via Android Studio ou sdkmanager)
2. Dans Godot : Projet → Export → Android
3. Configurer le keystore (pour Play Store) ou utiliser le debug keystore
4. Export → Export Project → choisir .apk

---

## Règles du jeu

- Plateau 4×4 avec 0, 1 ou 2 cases bloquées (aléatoires)
- Chaque joueur équipe un dieu puis choisit 8 pierres parmi les cartes neutres
  et celles de la famille de ce dieu
- Les joueurs posent à tour de rôle (tirage pile/face pour le premier)
- Pour poser une carte : la toucher puis toucher une case, ou la glisser jusqu'à
  la case ; pendant le glissement, la case où elle sera posée s'éclaire
- Chaque face possède au maximum 4 emplacements communs aux lames normales,
  lames spéciales et boucliers
- Quand une pierre est posée, elle capture les pierres adverses adjacentes
  si ses lames sont STRICTEMENT supérieures au côté face-à-face
- Égalité de lames = pas de capture
- Les logos en haut à droite annoncent les pouvoirs ; les lames roses de Fortune
  sont révélées à la pose, les boucliers défendent et les grandes lames bleues
  peuvent attaquer à distance
- Le Miasme de Déclin est une aura continue : chaque pierre adverse voisine
  perd 1 force par pierre Miasme voisine, y compris une carte posée plus tard
  (elle attaque d'abord, puis subit le malus) ; l'aura s'éteint si la pierre
  Miasme passe chez un autre dieu. L'Échec corrosif retire 2 de force aux seules
  pierres adverses qui ont résisté à l'attaque, jusqu'à la fin du prochain coup
  du lanceur
- Règle des dieux : les pouvoirs continus (Essaim, Miasme) d'une carte de
  famille n'agissent que dans le camp dont le dieu est le sien
- Les auras de Déclin révèlent le malus à l'impact et brisent visuellement les
  lames neutralisées, tandis que les boucliers restent intacts
- Essaim entretient une aura de groupe (+2 lames par autre membre, jusqu'à +4)
  et Pillage remplit avec de nouveaux
  boucliers les emplacements libres des faces autres que celle qui a capturé
- Les changements d'Essaim propagent une impulsion entre les cartes puis font
  pousser ou rétracter exactement les lames calculées par le moteur
- Les lianes vertes croisées restent visibles sur toute la largeur des bords tant
  que les cartes appartiennent au même groupe et sont coupées dès qu'une capture
  sépare ce réseau
- La partie se termine quand le plateau est plein
- Victoire = celui qui contrôle le plus de pierres

## Navigation et deck

Les trois écrans principaux sont accessibles depuis la barre inférieure :
**Cartes**, **Jouer** et **Règles**. L'accueil affiche le pseudo local et ouvre la
page Profil & Stats, où ce pseudo peut être modifié (2 à 16 caractères).

Dans l'écran Cartes, le deck et la collection appartiennent au même défilement.
La collection montre seulement les cartes absentes du deck : une carte retirée
du deck y revient à sa place. Elle est triée par FAMILLE par défaut (les cartes
du dieu, puis les neutres, chaque groupe du moins cher au plus cher), ou par
coût, rareté ou nom ;
les ex aequo sont toujours rangés par nom.
Le panneau supérieur permet de choisir l'un des six dieux. Chacun possède trois
decks indépendants, sélectionnés par les boutons **1, 2, 3** sous le choix du dieu.
Changer de dieu retrouve son dernier emplacement sélectionné et sa collection,
sans modifier les decks des autres dieux. Une même carte peut figurer dans
plusieurs decks. Seules les cartes du deck actuellement sélectionné sont
masquées dans la collection.
Toucher une pierre ouvre ses informations et son action. Si le deck est plein,
le jeu demande quelle pierre remplacer et affiche le calcul du budget pour
chaque possibilité. Toute modification valide est enregistrée automatiquement,
sans bouton de sauvegarde ni message de succès. Les boutons numérotés n'affichent
aucun indicateur de remplissage. Un deck vide ou incomplet reste enregistré,
mais le combat exige huit pierres et un coût de 80 points au maximum.

L'accueil et le combat utilisent le deck sélectionné. Les cartes des dix-huit
emplacements, le dieu actif et le numéro choisi pour chaque dieu sont conservés
dans `user://savegame.json`. Le format version 4 conserve les identifiants de
formes et les niveaux choisis. Il migre toujours l'ancien deck vers
l'emplacement 1 de son dieu ; pseudo et statistiques sont conservés, les autres
emplacements démarrent vides. En cas d'échec d'écriture, la modification est
annulée et un message d'erreur apparaît.

## Lignées et évolutions

Le catalogue comprend **96 lignées et 275 formes** : 24 neutres et 12 pour chacun
des six dieux. Les cartes japonaises et les huit prototypes ont été remplacés par
le [catalogue de monstres](docs/CATALOGUE_CARTES_PROPOSITION.md), qui détaille les
statistiques de chaque niveau et les pistes visuelles.

Les communes ont quatre niveaux, les rares trois, les épiques deux et les
légendaires un seul. Toutes les formes sont disponibles ; aucun système
d'expérience ou de déblocage n'est ajouté.

Les illustrations de niveau 1 des **96 lignées sur 96** sont reliées au catalogue.
Onze lignées prioritaires disposent de toutes leurs formes illustrées : voir le
[comparatif des évolutions](docs/designs/bestiaire-pixel-art-01/reconstruction-lignees/index.html).
Les **81 lignées évolutives sur 81** disposent aussi d'un N2 propre : voir le
[comparatif N1/N2](docs/designs/bestiaire-pixel-art-01/evolutions-n2/index.html).
Le bestiaire contient 203 PNG de cartes (96 N1, 81 N2, 22 N3 et 4 N4).
Le [comparatif N1/N2/N3](docs/designs/bestiaire-pixel-art-01/evolutions-n3/index.html)
présente les 22 N3 intégrés sur 65. Treize dessins de ce lot ont été retenus ;
quatre essais trop proches du N2 sont à reprendre. La limite de génération
interrompt le lot avec 43 dessins restants, dont les prompts sont conservés.
Les quatre premiers essais N2 trop proches du N1 ont été remplacés.
Les PNG retenus se trouvent dans
`assets/cards/`, rangés par famille et nommés d'après l'identifiant de la forme.
La [galerie](docs/designs/bestiaire-pixel-art-01/index.html) utilise ces mêmes
fichiers : une retouche de l'image est visible dans le jeu et dans la galerie.

Le champ `asset` d'une lignée fournit l'image commune à ses niveaux, en attendant
leurs illustrations évolutives. Une entrée de `levels` peut définir son propre
`asset` pour remplacer cette image. Les couvertures N1 et N2 sont complètes ;
les 72 illustrations N3/N4 restantes sont suivies dans la galerie. Le choix de l'image ne change
aucune statistique ni sauvegarde.

`StoneCard` affiche le PNG entier, centré sur fond sombre et sans déformation,
dans la collection, les fiches, la main et le plateau. Les PNG gardent leur
résolution ; les retouches de luminosité sont tracées dans le manifeste et
préservent leur alpha. Les fichiers `.png.import` utilisent la compression
sans perte, aucune limite de taille et des mipmaps pour l'affichage réduit.
Ces options suivent la [documentation d'import des images Godot](https://docs.godotengine.org/en/latest/tutorials/assets_pipeline/importing_images.html).

Le bouton **Afficher : niveau 1 à 4** change seulement l'aperçu de la collection.
Le niveau affiché sature au maximum de chaque lignée. La collection conserve
une seule entrée par monstre ; ses nœuds sont actualisés et réordonnés selon le
coût de la forme affichée.

Dans **Infos**, les boutons numérotés consultent les formes existantes et
**Utiliser** équipe exactement celle montrée. Si la lignée est déjà équipée,
son niveau change au même emplacement. Un deck accepte une seule forme de chaque
lignée. Un deck complet ouvre le remplacement avec la forme choisie ; budget et
écriture disque restent vérifiés avant toute modification effective.

La direction visuelle future est décrite dans
[Direction artistique — Bestiaire d'horreur](docs/DIRECTION_ARTISTIQUE_MONSTRES.md).

---

## Migration du catalogue

Les 131 anciens identifiants servent uniquement à convertir les sauvegardes,
via `legacy_ids` dans `stones.json`. Ils ne sont plus jouables. La conversion
conserve les emplacements, le dieu, le pseudo et les statistiques. Elle choisit
des formes compatibles et des lignées distinctes, en ajustant si nécessaire le
niveau ou la lignée pour respecter les huit cartes et les 80 points.
Les identifiants techniques des dieux et des adversaires restent stables.

Le chargement ne réécrit pas le profil. Avant la première modification d'un
profil contenant ces cartes, son JSON d'origine est conservé dans
`user://savegame.json.before_monsters`. Cette copie n'est jamais remplacée par
les sauvegardes suivantes. Un échec de création de cette copie empêche la
réécriture du profil.

## Dieux, familles et budget

Les six styles sont Véskar/Fortune (Les Aléators), Nérava/Déclin (Les Flétris),
Kharûn/Rempart (Les Remparts), Ilyr/Horizon (Les Veilleurs), Sylkha/Essaim
(L'Essaim) et Énigma/Pillage (Les Assimilateurs). Chaque dieu voit 36 lignées :
ses 12 exclusives et les 24 neutres, soit 105 formes possibles.

Une carte Fortune utilise un seul pouvoir : des lames roses aléatoires
(badge ×N), un pile ou face horizontal ou un pile ou face vertical.
La pièce s'affiche au-dessus de la carte : ✓ échange les faces prévues,
✕ conserve leur disposition. Les boucliers sont représentés par des
demi-cercles, avec une base plate contre la pierre.

Après une capture Pillage, les symboles de la face vaincue se détachent et sont
aspirés dans un entonnoir d'énergie. Ils repoussent ensuite sur la carte
capturée. Sur l'attaquant, un noyau central alimente quatre conduits : de faux
chemins s'allument rapidement parmi les faces possibles, puis les chemins
sélectionnés restent dorés et acheminent les demi-boucliers vers leurs
emplacements définitifs. La face qui a capturé ne reçoit aucun bouclier : son
conduit reste éteint. `ShieldTheftSystem` tire chaque destination et indique dans
l'événement les faces possibles ; la vue ne relance aucun tirage. `TurnManager` verrouille le coup
jusqu'au signal de fin de la présentation, y compris avant la fin de partie.
Les aperçus animés de `StoneCard` sont des copies et ne modifient jamais le modèle
de combat. `StoneSymbols` dessine les mêmes pictogrammes sur les cartes et dans
les règles.

Les attaques sont décrites par `CombatResolver.resolve_attacks` avant tout
effet de Miasme ou de Pillage. Chaque direction contient ses cibles successives,
les comparaisons de force et le point d'arrêt du tir. Sans ennemi atteignable,
aucune animation n'est créée. Les lames bleues traversent chaque ennemi capturé,
puis s'arrêtent sur une résistance ou une case bloquée ; leur force distante
reste constante et seules elles s'activent pour une cible éloignée.
`CombatTimeline` centralise les durées visuelles ; `TurnManager` attend les fins
effectives via `CombatPresentation`.
Les animations révèlent le plan calculé et n'altèrent ni le plateau ni le hasard.

Le coût part de la somme des lames normales. Une lame aléatoire et un bouclier
coûtent chacun 0,5 point, une lame longue 1,25 point, et le pouvoir de famille
ajoute le supplément `power_cost` déclaré sur la carte dans `stones.json`
(depuis l'équilibrage 4×4 : 1 pour Pillage, 0,5 pour Essaim et Rempart, 0 pour
Déclin ; Fortune et Horizon paient déjà leurs lames roses et bleues). Un deck de huit pierres
ne peut pas dépasser `DECK_BUDGET = 80` points. Les quarts de point sont conservés par
les règles et affichés sans arrondi dans les menus.

## Les 6 NPCs

Chaque adversaire possède désormais un dieu et un deck cohérent avec sa famille.
Les six decks proposés contiennent huit lignées distinctes, respectent leur
famille et restent dans le budget de 80 points. Le validateur de contenu
contrôle leur taille, leur famille et leur profil d'IA ; les tests contrôlent
également leur budget et l'absence de doublons.

| NPC | Difficulté | IA | Dieu / famille |
|-----|-----------|-----|----------------|
| Le Disciple de la Muraille | Facile | Niveau 1 | Kharûn / Rempart |
| La Porteuse de fièvre | Facile | Niveau 1 | Nérava / Déclin |
| Le Croupier ricanant | Moyen | Niveau 2 | Véskar / Fortune |
| La Tisseuse de racines | Moyen | Niveau 2 | Sylkha / Essaim |
| Le Guetteur du Lointain | Difficile | Niveau 3 | Ilyr / Horizon |
| Le Maître des carcasses | Difficile | Niveau 3 | Énigma / Pillage |

Une seule IA joue tous les adversaires, réglée par le champ `"ai"` de `npcs.json` :

- niveau 1, `{"precision": 0.0, "anticipation": false}` : joue au hasard ;
- niveau 2, `{"precision": 0.5, "anticipation": false}` : une fois sur deux, le
  coup qui capture le plus ; sinon une erreur crédible, tirée au sort en
  favorisant les coups qui rapportent ;
- niveau 3, `{"precision": 1.0, "anticipation": true}` : retire de chaque coup la
  riposte attendue du joueur, puis explore les placements des deux derniers coups.

`MoveEvaluator` coordonne la simulation et sa valeur ; `RiposteModel` prépare
les tirs adverses et réutilise ceux qui n'ont pas changé ; `EndgameSearch`
explore la fin de partie. La main adverse reste supposée et le hasard est
échantillonné, même lorsque les placements restants sont tous explorés.

L'IA ne voit ni la main du joueur ni le prochain tirage réel : elle suppose les
cartes de son dieu et les neutres, moins celles déjà posées. D'autres niveaux se
créent en changeant ces deux valeurs, sans code.
