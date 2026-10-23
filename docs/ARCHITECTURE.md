# Architecture de SamStone

Le moteur calcule les résultats. La présentation les montre, puis annonce sa fin.
Une IA appelle le même moteur sur une copie pour essayer un coup instantanément.

## Données

| Fichier | Fonction principale | Responsabilité |
| --- | --- | --- |
| `data/stones.json` | — | Définition complète de chaque carte, pouvoirs compris |
| `data/gods.json` | — | Dieux, familles, couleurs et descriptions |
| `data/npcs.json` | — | Adversaires, decks, dieux et stratégies IA |
| `StoneLoader` | `get_stone`, `get_god`, `get_npc` | Charge les catalogues et fournit des copies |
| `ContentValidator` | `validate` | Vérifie leur cohérence au démarrage |
| `PlayerData` | `load_save`, `save`, `set_player_deck` | Pseudo, dieu, deck et statistiques persistants |
| `PlayerSaveCodec` | `encode`, `decode` | Format et migration du profil sans accès disque |
| `BattleContext` | `record_result` | Adversaire sélectionné, premier joueur et dernier résultat |
| `StoneCostRules` | `cost` | Règle du coût d'une carte |
| `DeckRules` | `try_add`, `try_remove`, `try_replace` | Composition du deck |
| `UIFormat` | `cost` | Affichage des nombres dans l'interface |

Le fichier `user://savegame.json` reste compatible avec les profils antérieurs.
`StoneLoader.stone_cost()` et `format_cost()` sont de petits accès pratiques
conservés pour le composant `StoneCard`, dont les dessins seront remplacés plus tard.
Ils délèguent les calculs à `StoneCostRules` et `UIFormat`.

## Résolution d'un coup

`GameState` contient le plateau, les mains et le hasard propre à la partie.
Chaque pierre posée possède une `BattleStone` mutable ; le catalogue reste intact.
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
  └─ SwarmSystem.recalculate() + transitions()

CombatResolver.resolve_attacks()
  └─ AttackResolver.resolve()
       └─ plan pur : cibles, forces, réussites et arrêts des tirs

CombatResolver.finish_move()
  ├─ application des captures du plan
  ├─ PostAttackEffectResolver.resolve()
  │    ├─ WeaknessSystem.apply_miasma()
  │    ├─ ShieldTheftSystem.resolve()
  │    ├─ WeaknessSystem.expire_for_player()
  │    └─ WeaknessSystem.apply_failed_attack()
  └─ SwarmSystem.recalculate() + transitions()
```

`CombatResolver.apply_move()` enchaîne ces opérations immédiatement pour les IA.
`RulesEngine` fournit score, fin de partie et liste des coups disponibles.
`CombatBoard` est un accès partagé aux instances des cases, y compris les fixtures anciennes.
`BattleStone.markers_for_side()` décrit les symboles ; le moteur connaît leur type
et leur indice stable, tandis que l'interface calcule leurs positions.

Les événements de pouvoirs sont construits dans `CombatEvents` avec des paramètres
typés. Leurs données restent des dictionnaires sérialisables, sans nœuds Godot
ni coordonnées écran. Les identifiants communs sont également définis ici.

## Tours et animations

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
`CardGridLayout` crée les éléments visuels communs. Le tri est défini dans `CollectionGrid`.
Un changement de deck actualise ses emplacements et la sélection des cartes existantes.
Un changement de dieu ou de tri reconstruit la collection.

`CardActionDrawer`, `StoneInfoSheet` et `ReplacementPanel` gèrent leurs panneaux.
`TapGesture`, `TouchButton` et `TouchScrollContainer` conservent les gestes tactiles.

## IA

`AITurnRunner` attend son délai, demande un coup à `AIPlayer.choose_move()`, puis
le transmet à `TurnManager`. `clone_for_ai()` cache la main humaine et le prochain tirage réel.
`RandomAI` tire un coup, `GreedyAI` maximise les captures estimées, `ScoreAI` compare
le score après simulation. `ScoreAI` reprend la stratégie de l'ancien `MinimaxAI` :
celui-ci s'arrêtait dès la branche humaine et n'explorait pas trois tours.
Le nom et le code décrivent désormais cette profondeur réelle d'un seul coup.

## Ajouter un pouvoir

1. Définir ses données dans la carte de `stones.json`.
2. Placer son calcul dans `engine/effects/` selon son déclenchement.
3. L'appeler depuis `PlacementEffectResolver` ou `PostAttackEffectResolver`.
4. Décrire son résultat dans `CombatEvents` sans données d'affichage.
5. Lui associer une animation dans `BoardAnimationController` et un logo via `StoneSymbols`.
6. Ajouter les vérifications dans la suite de règles et la suite visuelle concernées.

Un nouveau système continu peut suivre `SwarmSystem`, avec un instantané et une
transition avant/après. `CombatResolver` garde uniquement l'ordre général des phases.

## Vérification

Les scènes `GodSystemChecks.tscn` et `TouchInputChecks.tscn` sont les points d'entrée.
Les assertions et fixtures sont dans `tests/support/CombatTestSuite.gd`.
Les suites de règles, de séquençage, d'IA et d'interface sont réparties dans
`tests/combat/`, `tests/ai/` et `tests/ui/`. Les anciennes suites de placement et
de deck utilisent également ces assertions locales : aucune installation de GUT nécessaire.

`AnimatedMatchChecks` rejoue chaque coup en simulation et en présentation réelle
pour les six familles, puis compare le plateau, le hasard et tous les états de pouvoir.
`TurnSequenceChecks` vérifie aussi les fins retardées et l'annulation des présentations.
