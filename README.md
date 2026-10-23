# SamStone — 石の戦い

Jeu de cartes stratégique inspiré de Skystones (Skylanders Giants).
Style : samouraï / yokai, univers japonais.
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
  domain/              DeckRules, StoneCostRules, StoneSide et StoneEffects
  engine/              État, tours, validation et résolution générale
    combat/            Attaques, événements et ticket de présentation
    effects/           Pose, Fortune, Déclin, Pillage et Essaim
  ai/                  IA à profils, évaluation des coups et AITurnRunner
  ui/                  Écrans, plateau, main et StoneCard
    collection/        Sélecteur de dieu, deck, grille et panneaux
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
au doigt et à la souris. Elle ne sauvegarde aucun
changement de deck ou de statistiques.

Chaque suite se termine par un résumé, par exemple
`GOD_SYSTEM_CHECKS: 280 passed, 0 failed, 0 Godot errors` ou
`TACTILE : 50 vérifications, 0 échec(s), 0 erreur(s) Godot.`, et renvoie le code
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

- Plateau 3×3 avec 0 ou 1 case bloquée (aléatoire)
- Chaque joueur équipe un dieu puis choisit 5 pierres parmi les cartes neutres
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
- Le Miasme de Déclin affaiblit les voisines après les tentatives de capture ;
  l'Échec corrosif affaiblit seulement les pierres adverses qui ont résisté à
  l'attaque, jusqu'à la fin du prochain coup du lanceur
- Les auras de Déclin révèlent le malus à l'impact et brisent visuellement les
  lames neutralisées, tandis que les boucliers restent intacts
- Essaim entretient une aura de groupe et Pillage remplit avec de nouveaux
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
Le panneau supérieur permet de choisir l'un des six dieux ; la collection est
alors filtrée et les cartes incompatibles sont retirées du deck avec un message.
Toucher une pierre ouvre ses informations et son action. Si le deck est plein,
le jeu demande quelle pierre remplacer et affiche le calcul du budget pour
chaque possibilité. Toute modification valide est enregistrée automatiquement.

---

## Les 25 pierres (par rareté)

| Rareté    | Pierres |
|-----------|---------|
| Common    | Ashigaru, Yumi Archer, Naginata Monk, Kappa, Tanuki, Shinobi |
| Uncommon  | Samurai Red, Kitsune, Oni Mineur, Rōnin, Yamabushi, Tengu, Kunoichi, Rikishi |
| Rare      | Samurai Blue, Jōrōgumo, Raijin, Tatsu, Fūjin, Grand Oni |
| Epic      | Yasha, Ryūjin, Susanoo, Amaterasu |
| Legendary | Izanagi (4/4/4/4) |

## Dieux, familles et budget

Les six styles jouables sont Inari/Fortune, Izanami/Déclin,
Hachiman/Rempart, Tsukuyomi/Horizon, Ōkuninushi/Essaim et Susanoo/Pillage.
Chaque famille possède trois pierres exclusives ; sept pierres restent neutres.

Les cartes Fortune utilisent un seul pouvoir : Kappa révèle deux lames
aléatoires (badge ×2), Tanuki lance un pile ou face horizontal et Ronin un
pile ou face vertical. La pièce s'affiche au-dessus de la carte : ✓ échange
les faces prévues, ✕ conserve leur disposition. Les boucliers sont représentés
par des demi-cercles, avec une base plate contre la pierre.

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
coûtent chacun 0,5 point, une lame longue 1,5 point, et les pouvoirs continus ont
un supplément déclaré sur la carte dans `stones.json`. Un deck de cinq pierres
ne peut pas dépasser `DECK_BUDGET = 50` points. Les demi-points sont conservés par
les règles et affichés sans arrondi dans les menus.

## Les 6 NPCs

Chaque adversaire possède désormais un dieu et un deck cohérent avec sa famille.
Les decks des adversaires ne sont pas soumis au plafond de 50 points du joueur :
Yuki, Raiko et Kaguya le dépassent. Au chargement, `ContentValidator` vérifie
seulement leur taille, leur famille et leur profil d'IA.

| NPC | Difficulté | IA | Dieu / famille |
|-----|-----------|-----|----------------|
| Hiro le Novice | Facile | Niveau 1 | Hachiman / Rempart |
| Mei la Kunoichi | Facile | Niveau 1 | Izanami / Déclin |
| Tetsuo le Rōnin | Moyen | Niveau 2 | Inari / Fortune |
| Yuki la Prêtresse | Moyen | Niveau 2 | Ōkuninushi / Essaim |
| Raiko le Maître du Tonnerre | Difficile | Niveau 3 | Tsukuyomi / Horizon |
| Kaguya la Sans-Nom | Difficile | Niveau 3 | Susanoo / Pillage |

Une seule IA joue tous les adversaires, réglée par le champ `"ai"` de `npcs.json` :

- niveau 1, `{"precision": 0.0, "anticipation": false}` : joue au hasard ;
- niveau 2, `{"precision": 0.5, "anticipation": false}` : une fois sur deux, le
  coup qui capture le plus ; sinon une erreur crédible, tirée au sort en
  favorisant les coups qui rapportent ;
- niveau 3, `{"precision": 1.0, "anticipation": true}` : retire de chaque coup la
  riposte attendue du joueur, puis calcule exactement les trois derniers coups.

L'IA ne voit ni la main du joueur ni le prochain tirage réel : elle suppose les
cartes de son dieu et les neutres, moins celles déjà posées. D'autres niveaux se
créent en changeant ces deux valeurs, sans code.
