# Architecture de SamStone

Le moteur calcule les résultats. La présentation les montre, puis annonce sa fin.
Une IA appelle le même moteur sur une copie pour essayer un coup instantanément.

## Données

| Fichier | Fonction principale | Responsabilité |
| --- | --- | --- |
| `data/stones.json` | — | Définition complète de chaque carte, pouvoirs compris |
| `data/gods.json` | — | Dieux, familles, couleurs et descriptions |
| `data/npcs.json` | — | Adversaires, decks, dieux et profils d'IA |
| `StoneLoader` | `get_stone`, `has_stone`, `has_effect`, `get_god`, `get_npc` | Charge les catalogues, fournit des copies et des lectures sans copie |
| `ContentValidator` | `find_problems` | Liste les incohérences des catalogues ; `StoneLoader` les signale au démarrage |
| `PlayerData` | `load_save`, `save`, `set_player_deck` | Pseudo, dieu, deck et statistiques persistants |
| `PlayerSaveCodec` | `encode`, `decode` | Format et migration du profil sans accès disque |
| `PlayerSaveStorage` | `write`, `read` | Écriture sûre du profil sur le disque |
| `BattleContext` | `record_result` | Adversaire sélectionné, premier joueur et dernier résultat |
| `StoneCostRules` | `cost` | Règle du coût d'une carte |
| `StoneEffects` | — | Identifiants des pouvoirs du champ `effects` |
| `DeckRules` | `try_add`, `try_remove`, `try_replace` | Composition du deck |
| `UIFormat` | `cost` | Affichage des nombres dans l'interface |

Le fichier `user://savegame.json` reste compatible avec les profils antérieurs.
`PlayerSaveStorage` écrit d'abord le profil dans `savegame.json.tmp`, puis le
renomme : une coupure ne laisse jamais un profil à moitié écrit. Un fichier
illisible est renommé `savegame.json.unreadable` au lieu d'être écrasé, et un
remplacement interrompu est récupéré au chargement suivant.
`get_stone()` renvoie une copie modifiable. Les questions répétées pendant les
simulations (`has_stone`, `has_effect`, `stone_cost`) lisent l'index du catalogue
sans copie. Les coûts unitaires sont des constantes de `StoneCostRules`, reprises
par l'écran des règles. Moteur, interface et validation désignent les pouvoirs par
les constantes de `StoneEffects` ; `ContentValidator` signale tout pouvoir ou axe
de pile ou face inconnu dans `stones.json`.

## Résolution d'un coup

`GameState` contient le plateau, les mains et le hasard propre à la partie.
Chaque pierre posée possède une `BattleStone` mutable ; le catalogue reste intact.
Une case garde aussi l'auteur de sa pose (`placed_by`), que les captures ne changent pas.
`StoneSide` centralise les côtés, leurs directions et leurs opposés.
`PlacementRules.is_valid()` est la validation commune aux coups réels et simulés.

```text
CombatResolver.place_stone()
  ├─ PlacementRules.is_valid()
  ├─ création de BattleStone
  ├─ PlacementEffectResolver.resolve()
  │    ├─ RandomBladeEffect.resolve()
  │    └─ CoinFlipEffect.resolve()
  ├─ insertion sur le plateau et retrait de la main
  └─ SwarmSystem.recalculate() + transitions()   (rien à faire sans pierre Essaim)

CombatResolver.resolve_attacks()
  └─ AttackResolver.resolve()
       └─ plan pur : cibles, forces, réussites et arrêts des tirs

CombatResolver.finish_move()
  ├─ application des captures du plan
  ├─ PostAttackEffectResolver.resolve(plan d'attaque)
  │    ├─ WeaknessSystem.update_miasma()         aura continue, recalculée à chaque coup
  │    ├─ ShieldTheftSystem.resolve()             autres faces que celle qui a capturé
  │    ├─ WeaknessSystem.expire_for_player()
  │    └─ WeaknessSystem.apply_failed_attack()    pierres qui ont résisté à l'attaque
  └─ SwarmSystem.recalculate() + transitions()
```

`CombatResolver.apply_move()` enchaîne ces opérations immédiatement pour les IA.
`PostAttackEffectResolver` reçoit le plan complet : le Pillage lit ses captures,
l'Échec corrosif ses attaques ratées. Chaque transfert de Pillage indique ses
faces possibles (`candidate_sides`), que `PillageAnimation` fait clignoter.
`RulesEngine` fournit score, fin de partie et liste des coups disponibles.
`CombatBoard` est l'accès partagé aux instances des cases : une case occupée
porte toujours sa `BattleStone`, y compris dans les tests.
`BattleStone.markers_for_side()` décrit les symboles ; le moteur connaît leur type
et leur indice stable, tandis que l'interface calcule leurs positions.
L'ordre des types est `BattleStone.MARKER_KINDS` et la capacité d'une face
`MAX_MARKERS_PER_SIDE`. La vue passe par `markers_for_side()` et `marker_offset()`
sans recopier cet ordre ; `StoneSide.coin_faces()` donne les faces d'un pile ou face.

Les événements de pouvoirs sont construits dans `CombatEvents` avec des paramètres
typés. Leurs données restent des dictionnaires sérialisables, sans nœuds Godot
ni coordonnées écran. Les identifiants communs sont également définis ici.

## Tours et animations

`BoardSetupGenerator` tire avant le match la case bloquée et le premier joueur ;
l'écran `PreBattle` anime seulement ce tirage et le transmet par `BattleContext`.
`TurnManager.human_play()` et `ai_play()` vérifient le joueur actif puis déclenchent
le moteur. Les phases explicites sont `PLACING`, `PREPARING`, `SWARM`, `ATTACKING`,
`EFFECTS`, `WAITING_INPUT` et `GAME_OVER`.

```text
TurnManager
  └─ signal presentation_requested(CombatPresentation)
       └─ BoardController._on_presentation_requested()
            └─ BoardAnimationController.present()
                 ├─ BoardEffectGeometry : positions et trajectoires
                 ├─ animations spécialisées
                 └─ AnimationBatch : attend toutes les fins
                      └─ CombatPresentation.complete()
                           └─ TurnManager passe à la phase suivante
```

`TurnManager` n'attend aucun nombre de secondes et ne dépend d'aucun fichier UI.
Sans interface connectée, une étape se termine à la frame suivante.
Un redémarrage ou une fermeture annule les présentations en cours.

Les cartes du plateau affichent la `BattleStone` du moteur, déjà dans son état
final : chaque animation montre un aperçu de l'ancien état jusqu'à sa révélation.
Une étape PLACEMENT ou EFFECTS transmet dans `pending_swarm` le changement
d'Essaim révélé par l'étape SWARM suivante ; `BoardAnimationController` garde
son état « avant » pendant l'étape. Le Pillage lit donc les symboles volés sur
la carte affichée (`StoneCard.displayed_stone()`), avec les indices du moteur ;
`BoardEffectGeometry.pillage_transfers()` les convertit en positions.

Les réglages de `StoneCard` (aperçu, croissance d'un symbole, affaiblissement
affiché, propriétaire, sélection) ne redessinent la carte que si la valeur change.
Une animation peut donc les appeler à chaque image sans coût inutile.
`BoardView.refresh()` ne redessine que les cartes dont une valeur dessinée a
changé, et `HandView` retire seulement les cartes jouées.

Côté interface seulement, un garde-fou interrompt une étape dont l'animation dépasse
sa durée prévue (`CombatTimeline.step_duration`) de `WATCHDOG_MARGIN` secondes.
Il écrit un avertissement, nettoie les animations, puis termine l'étape : la
partie continue avec l'état déjà calculé. Le minuteur est un enfant interne du
contrôleur, arrêté à chaque fin d'étape et libéré avec la scène.
Les signaux `stone_placed`, `stone_preparing`, `attacks_started`, `effects_resolved`
et `swarm_changed` annoncent les faits ; ils ne contrôlent pas la fin des animations.

`BoardView` construit les cases, synchronise les cartes, reçoit les gestes et
fournit leur géométrie. Son enfant `Animations` contient `BoardAnimationController`.
La couche `SwarmLinks` reste responsable des lianes persistantes.

| Animation | Ce qu'elle montre |
| --- | --- |
| `RandomBladeAnimation` | Spirale puis placement des lames roses |
| `CoinFlipAnimation` | Pièce et échange éventuel des faces |
| `PillageAnimation` | Aspiration, repousse et répartition des boucliers |
| `AttackAnimation` | Projectiles, impacts, barrières et repousse |
| `WeaknessAnimation` | Poison, symboles brisés et réparation |
| `SwarmAnimation` | Impulsion de groupe, pousse et rupture |
| `SwarmLinkLayer` + `SwarmVineStyle` | Lianes persistantes et style partagé |

`CardRevealAnimation` partage seulement le cycle de vie et l'aperçu d'une carte
entre Fortune, pile ou face et Pillage. `CombatTimeline` regroupe les durées côté UI.
Aucune animation ne change le plateau logique ni ne relance le hasard.

## Écran de collection

`CollectionScreenController` coordonne les choix et enregistre les opérations.
`GodSelector`, `DeckPanel` et `CollectionGrid` possèdent chacun leur vue.
`CardGridLayout` crée les éléments visuels communs. Le tri est défini dans `CollectionGrid`
(`SortMode`, dans l'ordre des boutons du menu) : FAMILLE par défaut, puis coût,
rareté et nom, avec le nom pour départager les ex aequo.
Les cartes du deck n'apparaissent pas dans la collection. `CollectionGrid` les
garde construites mais masquées dans une `GridContainer`, qui referme les trous :
un changement de deck reconstruit ses emplacements et masque ou réaffiche seulement
les cartes concernées de la collection, sans recréer de carte.
Un changement de dieu ou de tri reconstruit la collection.

`CardActionDrawer`, `StoneInfoSheet` et `ReplacementPanel` gèrent leurs panneaux.
`TapGesture`, `TouchButton` et `TouchScrollContainer` conservent les gestes tactiles.

## Poser une carte en combat

Deux gestes posent une carte : toucher la carte puis la case, ou glisser la carte
jusqu'à la case. `HandView` signale chaque appui (`card_press_started`) ;
`BoardController` le transmet à `CardDragController` seulement pendant le tour du
joueur. `DragGesture` suit le doigt (par son index) ou la souris physique et ignore
les clics émulés ; au-delà de `UITheme.TOUCH_SLOP`, l'appui devient un glissement
et `TapGesture` l'annule, donc la carte n'est pas sélectionnée.

Pendant le glissement, une copie de la carte suit le pointeur (levée au-dessus du
doigt), la carte restée dans la main s'estompe, et `BoardView.nearest_cell()` éclaire
la case acceptée la plus proche de la copie, jusqu'à `DROP_RADIUS` écart de case.
`BoardController._can_drop()` décide des cases avec `PlacementRules.is_valid()` ;
relâcher demande `TurnManager.human_play()`, relâcher ailleurs annule sans sélection.

## IA

Une seule IA, `ProfileAI`, joue tous les adversaires. `AIProfile` lit son réglage
dans le champ `"ai"` de `npcs.json` ; `ContentValidator` en signale les erreurs.
`AITurnRunner.create_ai()` crée l'IA d'un profil.

| Niveau | `precision` | `anticipation` | Adversaires | Délai minimal |
| --- | --- | --- | --- | --- |
| 1 | 0 | non | Hiro, Mei | 0,6 s |
| 2 | 0,5 | non | Tetsuo, Yuki | 0,8 s |
| 3 | 1 | oui | Raiko, Kaguya | 1,2 s |

Avec la probabilité `precision`, l'IA joue le meilleur coup évalué, au hasard
entre les ex aequo. Sinon elle commet une erreur crédible : un coup tiré au sort
avec le poids `exp(−écart / T)`, où `T = (1 − p) / p` capture. À 0, elle joue au
hasard sans rien évaluer. Ce choix est tiré avant la réflexion, avec un hasard
propre à l'IA (`ProfileAI.rng`, fixé par les tests).

`MoveEvaluator` mesure un coup en captures, en le jouant avec
`CombatResolver.apply_move()` sur une copie de l'état. Un coup dont la simulation
consomme du hasard (Fortune, Pillage) est rejoué sur 4 tirages, avec des graines
propres à l'IA. Avec `anticipation` :

- la valeur retire la riposte attendue : pour chaque carte possible du joueur,
  ses meilleures captures immédiates depuis une case libre, puis la meilleure
  carte de sa main, en moyenne sur les mains possibles de sa taille
  (`OpponentModel.rank_weights`) ;
- à deux cases libres ou moins, un calcul exact pose chaque riposte possible
  jusqu'à la fin de la partie, avec la même moyenne sur les mains. Un coup
  aléatoire y est rejoué sur 2 tirages.

La riposte immédiate est découpée en tirs : une attaque est un plan pur où chaque
direction est indépendante. `MoveEvaluator` demande au résolveur, pour chaque case
libre, chaque tir différent (face, lames, lames bleues) une seule fois, avec une
pierre qui n'attaque que dans cette direction (`make_shot`), puis additionne les
tirs de chaque carte. Le coût dépend du nombre de tirs différents, qui plafonne,
et non du nombre de cartes. Les captures de chaque tir sont aussi calculées une
fois sur l'état reçu : pour un coup évalué, seuls les tirs dont la ligne traverse
une case changée (pose, captures, auras, défenses) sont redemandés au résolveur.
Sur le plateau 4×4, avec 40 cartes possibles, le niveau 3 réfléchit en moyenne
0,06 s sur PC (0,3 s au plus). Le calcul exact, lui, pose chaque carte possible :
il est limité à deux cases, où il reste court.

Avec `anticipation` (niveau 3), la valeur d'un coup gagne aussi 0,3 capture par
lame d'aura d'Essaim obtenue (`AURA_WEIGHT`) : l'aura reste et sert aux coups
suivants, ce qui pousse l'IA à relier ses pierres Essaim.

`OpponentModel` déduit les cartes possibles du dieu du joueur et des poses déjà
faites (`placed_by`) : `clone_for_ai()` cache la main humaine et le prochain tirage
réel, et l'IA ne lit jamais la vraie main. La riposte immédiate utilise des pierres
non posées, avec les deux issues d'un pile ou face (`CoinFlipEffect.apply_outcome`) ;
elle ignore les lames roses et l'aura d'Essaim que la carte recevrait. Le calcul
exact de fin de partie pose réellement les cartes.

`AIPlayer` définit le contrat : `start_search(état)` rend une `MoveSearch`, dont
`step(budget)` évalue les tirages un par un, puis `chosen_move()` donne le coup.
`AITurnRunner` l'avance de 4 ms par image dans `_process`, sans minuteur ni `await`,
et joue quand la réflexion est finie et le délai écoulé. Une partie relancée ou
une scène fermée abandonne la réflexion. `choose_move()` réfléchit d'un bloc pour
les tests.

## Ajouter un pouvoir

1. Définir ses données dans la carte de `stones.json`.
2. Placer son calcul dans `engine/effects/` selon son déclenchement.
3. L'appeler depuis `PlacementEffectResolver` ou `PostAttackEffectResolver`.
4. Décrire son résultat dans `CombatEvents` sans données d'affichage.
5. Lui associer une animation dans `BoardAnimationController` et un logo via `StoneSymbols`.
6. Ajouter les vérifications dans la suite de règles et la suite visuelle concernées.

L'IA joue ses coups avec le même résolveur : un nouveau pouvoir y est compté
sans code, et un pouvoir qui tire au hasard y est détecté. Seule la riposte
immédiate d'`OpponentModel` lit les cartes adverses sans les poser : elle ne voit
pas leurs pouvoirs de pose, à part le pile ou face.

Un nouveau système continu peut suivre `SwarmSystem`, avec un instantané et une
transition avant/après. `CombatResolver` garde uniquement l'ordre général des phases.
Le Miasme est le second système continu : `WeaknessSystem.update_miasma()` recalcule
après les captures de chaque coup le malus `BattleStone.miasma_weakness` et émet un
`WEAKEN` par pierre plus affaiblie ou un `WEAKNESS_EXPIRED` par pierre soulagée.
`BoardAnimationController` anime une traînée par source et fusionne les malus d'une
même cible. Les deux systèmes appliquent la règle des dieux de
`StoneLoader.is_power_active_for_god()` : une carte de famille n'agit que dans le
camp dont le dieu est le sien (`GameState.god_of()`).

## Vérification

Les scènes `GodSystemChecks.tscn` et `TouchInputChecks.tscn` sont les points d'entrée.
Les assertions et fixtures sont dans `tests/support/CombatTestSuite.gd`.
Les suites de règles, de séquençage, d'IA et d'interface sont réparties dans
`tests/combat/`, `tests/ai/` et `tests/ui/`. Les anciennes suites de placement et
de deck utilisent également ces assertions locales : aucune installation de GUT nécessaire.

`AnimatedMatchChecks` rejoue chaque coup en simulation et en présentation réelle
pour les six familles, puis compare le plateau, le hasard et tous les états de pouvoir.
`TurnSequenceChecks` vérifie aussi les fins retardées et l'annulation des présentations.

Les lanceurs chargent les suites à l'exécution et enregistrent `tests/support/TestLog.gd`
auprès de Godot. Une suite qui ne compile pas, une erreur ou un avertissement
inattendu, ou un dépassement du temps limite fait échouer l'exécution. Un test qui
provoque volontairement un message l'annonce avec `_expect_log()` ; si ce message
n'apparaît pas, c'est aussi un échec. Les échecs des vérifications sont écrits
avec `printerr`, pour ne pas être comptés une seconde fois comme erreurs Godot.
