# Audio — sons et musiques de SamStone

## Vue d'ensemble

- **4 musiques** : `main_theme`, `map`, `battle`, `ritual`.
- **26 effets sonores affectés** à un déclencheur du jeu.
- **1 fichier en réserve** : conservé dans `sources/alternates/`, non branché.
- **Aucun effet sonore manquant** dans la banque actuelle.
- **Tous les sons affectés sont branchés** via l'autoload `Audio` ; les écrans
  n'appellent jamais `AudioServer` directement.

Les chemins ci-dessous sont les chemins Godot définitifs et sont recopiés une
seule fois, dans `AudioCatalog.gd`. Les noms de fichiers sont conservés tels
quels : un renommage doit être répercuté dans le catalogue.

## Les quatre musiques

| Fichier | Usage | Boucle |
| --- | --- | :-: |
| `res://data/audio/music/main_theme.ogg` | Menus : accueil, boutique, decks/collection, quêtes, règles, statistiques, salon PVP, résultats | oui |
| `res://data/audio/music/map.ogg` | Campagne : carte, préparation, avant-combat | oui |
| `res://data/audio/music/battle.ogg` | Plateau de combat, en campagne comme en PVP | oui |
| `res://data/audio/music/ritual.wav` | Écran de Rituel uniquement | oui |

Il n'y a pas d'autre musique : pas de piste par dieu, par chapitre, par mode PVP
ni par écran de résultat. `ritual.wav` est le seul fichier non-OGG ; il pourra
être converti plus tard, sans changer son rôle.

## Arborescence

```text
data/audio/
├── README.md
├── music/                  les 4 musiques, à plat
├── sources/
│   ├── Witchcraft_wav/     WAV d'origine Witchcraft, non chargés par le jeu
│   └── alternates/         sons non affectés ou variantes en réserve
└── sfx/
    ├── ui/                 sélection et validation d'interface
    ├── economy/            validation d'achat
    ├── combat/             pose, attaque, capture et pouvoirs
    ├── coin_flip/          pile ou face de partie et pouvoirs Aléators
    ├── ritual/             flammes, révélation et sortie de carte de Rituel
    └── result/             manche, partie, série et égalité
```

Les anciens dossiers vides (`campaign`, `collection`, `feedback`, `pvp`,
`quests`, `story`) ont été supprimés : ils ne correspondaient à aucun fichier
réel. Les `.gitkeep` inutiles ont également été retirés.

## Effets sonores

### `sfx/ui/` — 2 fichiers

| Fichier | Déclencheur |
| --- | --- |
| `res://data/audio/sfx/ui/button.mp3` | **Toutes les sélections du joueur.** Dès qu'il touche quelque chose : bouton, carte, case du plateau, onglet, nœud de campagne, choix de dieu ou de deck, ouverture/fermeture de panneau. |
| `res://data/audio/sfx/ui/button_2.mp3` | **Validation d'une action qui n'est pas un achat.** Confirmation d'amélioration de carte, validation de deck, récolte de quête, lancement de combat, etc. Les boutons qui se répètent pour confirmer utilisent ce son. |

### `sfx/economy/` — 1 fichier

| Fichier | Déclencheur |
| --- | --- |
| `res://data/audio/sfx/economy/purchase.wav` | **Validation d'un achat.** Tous les boutons qui confirment une dépense : offre de boutique, déblocage de dieu, achat de Rituel. |

### `sfx/combat/` — 10 fichiers

| Fichier | Déclencheur |
| --- | --- |
| `res://data/audio/sfx/combat/stone_place_1.wav` | **Pose de carte du joueur local.** Quand le joueur pose une pierre, par toucher carte → case ou par glisser-déposer. |
| `res://data/audio/sfx/combat/stone_place_2.wav` | **Pose de carte de l'adversaire.** Quand l'IA ou le joueur distant pose une pierre. |
| `res://data/audio/sfx/combat/attack.wav` | **Départ d'une attaque.** Quand une carte attaque, avant la résolution des captures. |
| `res://data/audio/sfx/combat/attack_miss.wav` | **Attaque bloquée.** Attaque qui ne capture pas : mur, défense égale ou supérieure à l'attaque. |
| `res://data/audio/sfx/combat/captured.wav` | **Carte capturée.** Chaque carte qui change de camp, quel que soit le camp qui capture. |
| `res://data/audio/sfx/combat/weakness.wav` | **Activation du pouvoir des Flétris.** Miasme appliqué à une voisine ou Échec corrosif appliqué après une attaque résistée. |
| `res://data/audio/sfx/combat/repair.wav` | **Fin d'affaiblissement.** Quand une carte n'est plus affaiblie par un Flétri : expiration du Miasme ou de l'Échec corrosif. |
| `res://data/audio/sfx/combat/random_blade.wav` | **Pouvoir des lames aléatoires.** Révélation et placement des lames roses tirées au sort par un Aléator. |
| `res://data/audio/sfx/combat/swarm.wav` | **Activation des lianes d'Essaim.** Formation ou évolution du réseau de lianes entre les cartes Essaim alliées. |
| `res://data/audio/sfx/combat/pillage.wav` | **Vol de symboles des Assimilateurs.** Quand une carte assimilatrice vole des symboles (picks) à une carte vaincue et les répartit en boucliers. |

### `sfx/coin_flip/` — 4 fichiers

| Fichier | Déclencheur |
| --- | --- |
| `res://data/audio/sfx/coin_flip/coin_flip.wav` | **Animation de pile ou face d'une carte Aléator.** Se joue pendant le lancer de la pièce, avant que le résultat soit révélé. |
| `res://data/audio/sfx/coin_flip/coin_flip_start_battle.wav` | **Pile ou face du début de partie.** Tirage qui décide qui commence, sur l'écran d'avant-combat. |
| `res://data/audio/sfx/coin_flip/coin_flip_validate.mp3` | **Pile ou face favorable.** Issue positive du pouvoir d'un Aléator : les faces sont échangées. |
| `res://data/audio/sfx/coin_flip/coin_flip_wrong.wav` | **Pile ou face défavorable.** Issue négative : les faces restent inchangées. |

### `sfx/ritual/` — 4 fichiers

| Fichier | Déclencheur |
| --- | --- |
| `res://data/audio/sfx/ritual/big_flame.wav` | **Grande flamme du début de Rituel.** Au moment où le joueur touche le sceau et déclenche l'embrasement plein écran. |
| `res://data/audio/sfx/ritual/little_flame.wav` | **Petites flammes au milieu du Rituel.** Entre deux récompenses, quand une flamme secondaire accompagne le passage à la carte suivante. |
| `res://data/audio/sfx/ritual/reveal.wav` | **Révélation de la carte de Rituel.** Quand la carte de récompense apparaît, au retournement de la face scellée. |
| `res://data/audio/sfx/ritual/woosh.mp3` | **Sortie de carte de Rituel.** Au moment où la carte de récompense quitte l'écran pour passer à la suivante. |

### `sfx/result/` — 5 fichiers

| Fichier | Déclencheur |
| --- | --- |
| `res://data/audio/sfx/result/round_won.mp3` | **Manche gagnée en FT2/FT3.** La série n'est pas encore terminée. |
| `res://data/audio/sfx/result/round_defeat.mp3` | **Manche perdue en FT2/FT3.** La série n'est pas encore terminée. |
| `res://data/audio/sfx/result/victory.mp3` | **Partie ou série gagnée.** Victoire finale : FT1 remporté, ou série FT2/FT3 terminée en faveur du joueur. |
| `res://data/audio/sfx/result/defeat.mp3` | **Partie ou série perdue.** Défaite finale : FT1 perdu, ou série FT2/FT3 terminée en faveur de l'adversaire. |
| `res://data/audio/sfx/result/draw.mp3` | **Égalité.** Fin de manche ou de partie sans vainqueur. En FT2/FT3, l'égalité ne termine pas la série et une nouvelle manche est jouée. |

> En FT1, la manche et la partie sont la même chose : c'est `victory`,
> `defeat` ou `draw` qui joue. En FT2/FT3, l'écran de résultat choisit
> `round_won` / `round_defeat` tant que la série continue, puis `victory` /
> `defeat` quand elle est terminée.

## Fichier en réserve

Ce fichier n'est affecté à aucun déclencheur pour l'instant. Il reste dans
`sources/alternates/` et ne doit pas être supprimé sans décision.

| Fichier | Raison |
| --- | --- |
| `res://data/audio/sources/alternates/attack_miss.mp3` | Variante MP3 de `attack_miss.wav`. Le WAV est la version de référence ; la variante est conservée pour comparaison. |

## Ce que le jeu ne fait pas

Ces précisions évitent d'inventer des sons qui n'ont aucun déclencheur réel.

- **Pas de pioche.** La main affiche le deck complet (5 pierres pour le
  tutoriel, 8 ensuite). Poser une pierre la retire de la main ; il n'y a ni
  pioche, ni défausse, ni main qui se remplit au fil des tours.
- **Pas de mélange en combat.** Le deck est construit dans la Collection avant
  la partie. Aucun shuffle, aucun deck épuisé, aucune carte à piocher.
- **Pas de chronomètre de tour.** Seuls les drafts de préparation affichent un
  compte à rebours ; aucun son de tic-tac n'est nécessaire pour le plateau.
- **La main ne se recharge pas.** Une pierre jouée reste jouée jusqu'à la fin de
  la manche.
- **Pas de son dédié pour chaque écran.** `button` couvre toutes les sélections,
  y compris la sélection d'une carte en pleine partie. `button_2` couvre les
  validations et `purchase` les achats. Il n'y a pas de son séparé pour le
  retour, les onglets, l'ouverture d'un panneau ou une erreur.
- **Pas de son par dieu, chapitre ou mode.** Les pouvoirs qui ont un son sont
  ceux listés plus haut : Flétris, lames aléatoires, Essaim, Assimilateurs et
  pile ou face. Les autres actions n'ont pas de son dédié pour l'instant.

## État technique de la banque

La banque est hétérogène. Godot l'importe sans problème, mais une normalisation
sera nécessaire si on veut un comportement parfaitement homogène :

- la plupart des WAV de combat et de Rituel sont en **44,1 kHz / 16 bits / stéréo** ;
- `random_blade.wav` est en **48 kHz / 16 bits / stéréo** ;
- `stone_place_1.wav` et `stone_place_2.wav` sont en **96 kHz / 24 bits / mono** ;
- `coin_flip.wav` est en **48 kHz / 24 bits / stéréo** ;
- `coin_flip_start_battle.wav` est en **44,1 kHz / 16 bits / stéréo** ;
- `big_flame.wav` et `little_flame.wav` sont en **44,1 kHz / 16 bits / stéréo** ;
- `reveal.wav` est en **44,1 kHz / 16 bits / stéréo** ;
- les MP3 sont en **256 ou 320 kbps**, à 44,1 ou 48 kHz.

Godot importe tous ces formats et le jeu fonctionne tel quel. Une conversion
vers 44,1 kHz / 16 bits reste recommandée avant une normalisation définitive si
on veut alléger les fichiers et uniformiser les temps de chargement, mais elle
n'est pas bloquante.

## Architecture audio

Deux fichiers seulement portent la technique :

- `res://scripts/application/audio/AudioCatalog.gd` : catalogue de données.
  Il contient les identifiants, les chemins des 26 SFX et des 4 musiques, les
  clés de métadonnées et la correspondance écran → musique. Aucun autre fichier
  ne recopie un chemin audio.
- `res://scripts/application/audio/AudioService.gd` : autoload `Audio`. Il
  possède les bus, le pool de lectures courtes, le lecteur de musique, le
  lecteur de jingle et le branchement automatique des boutons.

Le reste du jeu ne fait que trois choses : `Audio.play_sfx(AudioCatalog.SFX_…)`
pour un effet court, `Audio.play_jingle(AudioCatalog.SFX_…)` pour un son de
résultat, ou poser une métadonnée sur un `BaseButton`. Un écran ne choisit
jamais sa musique : le service suit la scène courante.

### Bus et mixage

`res://default_bus_layout.tres` déclare `Master`, `Music` et `SFX`. Le lecteur
de musique envoie sur `Music`, le pool d'effets et le lecteur de jingle sur
`SFX`. Chaque bus peut être réglé séparément sans toucher au code : `Music` est
volontairement plus bas que `SFX` (`-13 dB` contre `0 dB`) pour rester en fond
sonore.

### Effets sonores

- Pool de 10 `AudioStreamPlayer` : un lecteur libre est toujours préféré, puis
  un tourniquet évite de sacrifier toujours le même quand les dix jouent.
  Deux captures simultanées ne se coupent donc pas.
- Les flux sont chargés une fois puis gardés en cache.
- Un identifiant inconnu ou un fichier absent produit un avertissement Godot
  explicite, jamais un crash.

### Musique

- Un seul lecteur : le changement de piste est une coupure franche. L'ancienne
  musique s'arrête et la nouvelle démarre au début, sans fondu ni
  chevauchement. Deux scènes qui partagent la même musique ne la redémarrent
  pas.
- Les quatre musiques bouclent. Le bouclage est activé à l'import (OGG
  `loop=true` ; WAV en mode `Forward` avec une fin de boucle explicite en
  échantillons) et le service le réaffirme au chargement. Pour un WAV, l'import
  utilise `edit/loop_mode=2` : l'énumération de l'importeur commence à
  `Detect From WAV`, contrairement à celle d'`AudioStreamWAV`.
- La piste est choisie à partir du nom de fichier de la scène courante
  (`AudioCatalog.SCENE_MUSIC`) : `main_theme` par défaut pour un écran inconnu.

| Musique | Scènes |
| --- | --- |
| `main_theme` | `MainMenu`, `ShopScreen`, `CollectionScreen`, `HowToPlay`, `Stats`, `Quests`, `PvpLobby`, `PvpPreparation`, `Result`, `PvpResult` |
| `map` | `EncounterSelect`, `EncounterPath`, `CampaignMap`, `CampaignPreparation`, `PreBattle` |
| `battle` | `Board` |
| `ritual` | `RitualOpening` |

### Jingles de résultat

Les cinq sons de `sfx/result/` sont des morceaux complets, pas de simples
effets. Ils ne doivent jamais se superposer à la musique :

- `Audio.play_jingle(id)` arrête la musique, joue le jingle seul, puis relance
  la musique de l'écran quand il se termine.
- Quitter l'écran avant la fin coupe le jingle et démarre la musique du nouvel
  écran. Rien ne continue à jouer par-dessus la navigation.
- `Audio.play_sfx` redirige automatiquement ces cinq identifiants vers
  `play_jingle`, pour qu'un appel distrait ne puisse pas recréer le
  chevauchement.

### Boutons

Tout `BaseButton` ajouté à l'arbre reçoit automatiquement `button` sur
`pressed`, y compris les boutons créés à la volée par les contrôleurs. Deux
métadonnées permettent de déroger à ce défaut :

- `Audio.set_button_sfx(bouton, AudioCatalog.SFX_BUTTON_2)` pour une validation
  ou `SFX_PURCHASE` pour une dépense ;
- `Audio.set_button_silent(bouton)` quand le geste déclenche déjà son propre son.

## Points d'accroche branchés

| Son | Code réel |
| --- | --- |
| `button` | Branchement automatique des `BaseButton`. Appels explicites pour les gestes qui ne sont pas des boutons : `BoardController._on_card_selected`, `_on_card_drag_started`, `CollectionScreenController._open_card_actions`, `LoadoutCardGrid._on_card_pressed`, `DialogueOverlay._advance`. Une case du plateau ne joue que le son de pose, jamais le clic générique. |
| `button_2` | `UpgradePriceButton`, `CardActionDrawer.primary_button`, `PreBattleController.start_button`, `CampaignPreparationController.confirm_button`, `PvpPreparationController.confirm_button`, `PvpLobbyController.ready_button`, récolte de quête, `CampaignLevelDialog.launch_button` / `replay_button`, `EncounterPathController.fight_button`, `RitualOpeningController.finish_button`. |
| `purchase` | `ShopPurchaseModal.confirm_button` et les boutons d'offre directe de `ShopScreenController`. |
| `stone_place_1` / `stone_place_2` | `BoardController._on_stone_placed`, en comparant `owner` au camp local. |
| `attack` | `BoardAnimationController.animate_attacks`, au départ de l'animation. |
| `attack_miss` | `BoardAnimationController._on_attack_hit` quand `success == false`. |
| `captured` | `BoardAnimationController.animate_capture`, avec garde contre un second signal pour la même carte. |
| `weakness` | `BoardAnimationController.animate_effects`, événements `WEAKEN` / `TEMPORARY_WEAKEN`. |
| `repair` | `BoardAnimationController.animate_effects`, réparations visibles. |
| `random_blade` | `BoardAnimationController.animate_preparation`, événement `RANDOM_BLADE`. |
| `coin_flip` | `CoinFlipAnimation.play`, au début du lancer. |
| `coin_flip_validate` / `coin_flip_wrong` | `CoinFlipAnimation._update_preview`, à `COIN_REVEAL` : `flipped == true` pour `validate`, `false` pour `wrong`. |
| `swarm` | `BoardAnimationController.animate_swarm`, événement `SWARM_CHANGE`. |
| `pillage` | `BoardAnimationController.animate_effects`, événement `SHIELD_THEFT`. |
| `big_flame` | `RitualOpeningController._on_sigil_pressed`, avec `flames.ignite_full()`. |
| `little_flame` | `RitualOpeningController._advance`, avec `flames.ignite_minor()`. |
| `reveal` | `RitualOpeningController._reveal_current`, pendant le retournement. |
| `woosh` | `RitualOpeningController._advance`, pendant la sortie de carte. |
| `coin_flip_start_battle` | `PreBattleController._animate_coin_flip`. |
| `round_won` / `round_defeat` | `ResultController._play_result_sound` et `PvpResultController._play_result_sound` quand la série continue, via `Audio.play_jingle`. |
| `victory` / `defeat` / `draw` | Mêmes méthodes quand la partie ou la série est terminée, ou en FT1, via `Audio.play_jingle`. |

## Règles d'extension

- **Ne pas renommer** un fichier de la banque sans mettre à jour
  `AudioCatalog.gd`. Le service ne connaît que ce catalogue.
- Ajouter un son se fait en trois endroits : le fichier, l'identifiant et son
  chemin dans `AudioCatalog`, puis l'appel `Audio.play_sfx` au déclencheur.
- Pour `stone_place_1` / `stone_place_2`, toujours raisonner en **camp local** :
  sur chaque appareil, la pose du joueur local utilise `stone_place_1` et celle
  de l'adversaire utilise `stone_place_2`.
- Pour les résultats, lire l'état de la série avant de choisir le son : une
  manche intermédiaire ne doit pas jouer `victory` / `defeat`. Ces cinq sons
  passent toujours par `Audio.play_jingle`, jamais par le pool d'effets courts.
- Un bouton dont le geste a déjà un son propre doit être déclaré silencieux
  plutôt que de laisser le clic générique se superposer.

## Checklist de livraison

- [x] Les fichiers sont rangés dans les dossiers définitifs.
- [x] Les anciens dossiers vides et les `.gitkeep` inutiles sont supprimés.
- [x] Le README décrit chaque son et son déclencheur réel.
- [x] Les bus `Music` et `SFX` existent dans `default_bus_layout.tres`.
- [x] L'`AudioService` et le pool de SFX sont branchés.
- [x] Chaque point d'accroche ci-dessus est branché dans le code.
- [x] Les quatre musiques bouclent et changent avec la scène.
- [x] Les suites `GodSystemChecks` et `TouchInputChecks` passent avec l'audio.
- [ ] La normalisation des formats est faite si elle est retenue.
- [ ] Le fichier en réserve `attack_miss.mp3` est tranché : intégré, remplacé ou supprimé.
