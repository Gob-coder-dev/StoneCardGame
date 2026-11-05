# Architecture de SamStone

Le moteur calcule les résultats. La présentation les montre, puis annonce sa fin.
Une IA appelle le même moteur sur une copie pour essayer un coup instantanément.

## Deux modes de match

Campagne et PVP local partagent la même scène `Board.tscn`, les mêmes vues et le
même moteur. `BoardController` ne choisit qu'un `MatchDriver` :

| Fichier | Entrées | Responsabilité |
| --- | --- | --- |
| `BoardController` | `_ready`, `_on_turn_started`, gestes | écoute le `TurnManager`, rafraîchit les vues, transmet les gestes au driver |
| `MatchDriver` | `setup`, `start`, `request_move`, `on_turn_started`, `on_turn_ended` | contrat commun : `local_side`, `can_submit()`, `records_campaign_stats`, `aborted`, `finished` |
| `CampaignMatchDriver` | `start` | adversaire du catalogue, deck du bot, `AITurnRunner`, statistiques de campagne |
| `LanMatchDriver` | `start`, `request_move` | commandes réseau validées par l'hôte, camp local, aucune statistique |
| `TurnManager` | `play`, `human_play`, `ai_play` | entrée générique `play(player, row, col, stone_id)` ; les deux wrappers restent pour la campagne |

`GameState` nomme ses camps `PLAYER_ONE` et `PLAYER_TWO` ; `PLAYER_HUMAN` et
`PLAYER_AI` restent des alias vers ces deux valeurs. `CombatResolver`,
`PlacementRules`, `BoardView`, `HandView` et `BattleHUD` gardent donc leur
contrat. La vue remappe seulement la coloration du plateau avec
`BoardView.local_owner`, pour que le camp local reste bleu sur les deux
téléphones. Le hasard du combat vient de `GameState.random_seed` et
`random_state` : l'hôte du PVP impose la graine, la campagne continue de tirer
la sienne.

## Réseau local

| Fichier | Responsabilité |
| --- | --- |
| `scripts/network/LanProtocol.gd` | version, types de messages, validation stricte et bornes ; aucun socket |
| `scripts/network/LanDiscovery.gd` | beacon UDP, écoute, dédoublonnage et expiration ; aucune boucle bloquante |
| `scripts/network/LanSession.gd` (autoload) | cycle ENet, états, signaux, RPC sur `/root/LanSession`, reset idempotent |
| `scripts/network/LanLobbyCoordinator.gd` | poignée de main, camps, PRÊT, configuration autoritaire du match |
| `scripts/network/LanMatchCoordinator.gd` | commandes, séquences, accusés, empreintes et désynchronisation |
| `scripts/network/LanAddressResolver.gd` | normalisation et classement purs des adresses locales |
| `scripts/data/PvpMatchContext.gd` (autoload) | données transitoires du match, sans écriture de profil |
| `scripts/ui/pvp/PvpLobbyFlow.gd` | cycle découverte, session et coordinateur du salon, sans dépendre de la scène |
| `scripts/ui/pvp/PvpLobbyController.gd` | présentation du salon, gestes et transition vers l'avant-combat |
| `scripts/network/LanTransportLink.gd` | façade de transport, remplacée par `FakeLanTransport` dans les tests |

Le détail du protocole, des ports, des permissions et des limites est dans
[PVP_LOCAL.md](PVP_LOCAL.md).
Les accords de lancement et de revanche ainsi que la confirmation d'un tour
sont bornés à 30 secondes. Ces délais applicatifs complètent la livraison fiable
d'ENet lorsqu'un pair reste connecté mais cesse de poursuivre le protocole.

## Données

| Fichier | Fonction principale | Responsabilité |
| --- | --- | --- |
| `data/stones.json` | — | Définition complète de chaque carte, pouvoirs compris |
| `data/gods.json` | — | Dieux, familles, couleurs et descriptions |
| `data/npcs.json` | — | Six adversaires historiques, leurs decks et profils d'IA |
| `OpponentCatalog` | `build`, `build_neutral`, `deck_for`, `neutral_deck_for`, `levels_for`, `source_id_of`, `sources` | Génère les adversaires dieu ou neutre × palier × difficulté, leurs chemins ordonnés et les sept sources complètes |
| `EncounterPath` | `states`, `current_index`, `next_level`, `completed_count` | États verrouillé, disponible et terminé d'un chemin, et successeur immédiat, sans interface ni sauvegarde |
| `BotCardTierRules` | `effective_level` | Classe les cartes des bots selon le niveau de forme et le plancher de rareté, sans changer leur niveau de jeu |
| `StoneLoader` | `get_stone`, `has_stone`, `has_effect`, `stone_affinity`, `stone_rarity`, `get_neutral_lineages`, `get_god`, `get_npc` | Charge les catalogues, fournit des copies et des lectures sans copie |
| `ContentValidator` | `find_problems` | Liste les incohérences des catalogues ; `StoneLoader` les signale au démarrage |
| `PlayerData` | `get_active_deck`, `get_deck`, `get_selected_deck`, `set_player_deck`, `set_player_god`, `set_selected_deck`, `load_save`, `save` | Profil et trois decks persistants par dieu |
| `PlayerSaveCodec` | `encode`, `decode` | Format et migration du profil sans accès disque |
| `DeckCatalogueMigration` | `requires_conversion`, `convert` | Remplace les anciennes cartes par des formes compatibles, distinctes et dans le budget |
| `CardArtCache` | `activate_god`, `texture`, `progress_for_god` | Préchauffe les illustrations utiles hors du thread principal et borne les références conservées |
| `PlayerSaveStorage` | `write`, `read` | Écriture sûre du profil sur le disque |
| `BattleContext` | `select_opponent`, `current_opponent`, `prepare_result`, `persist_result` | Adversaire sélectionné, premier joueur, résultat et état de sa persistance |
| `StoneCostRules` | `cost` | Règle du coût d'une carte |
| `StoneEffects` | — | Identifiants et valeurs des pouvoirs (corrosion, renfort et plafond d'Essaim) |
| `StoneEvolutionRules` | `max_level`, `preview_level`, `is_valid_level` | Limites par rareté et saturation des seuls aperçus |
| `DeckRules` | `try_add`, `try_remove`, `try_replace` | Composition du deck et nombre d'emplacements par dieu (`DECKS_PER_GOD`) |
| `UIFormat` | `cost` | Affichage des nombres dans l'interface |

Le fichier `user://savegame.json` reste compatible avec les profils antérieurs.
`PlayerSaveStorage` écrit d'abord le profil dans `savegame.json.tmp`, puis le
renomme : une coupure ne laisse jamais un profil à moitié écrit. Un fichier
illisible est renommé `savegame.json.unreadable` au lieu d'être écrasé, et un
remplacement interrompu est récupéré au chargement suivant.

Le format version 4 contient `decks_by_god` (trois tableaux d'identifiants de formes par dieu),
`selected_deck_by_god` (indices de 0 à 2), `player_god_id`, `player_name` et
`stats`. Il ne conserve plus de copie séparée du deck actif. `PlayerSaveCodec`
migre les profils sans version et la version 1 : l'ancien `player_deck` devient
l'emplacement 1 du dieu équipé, ou du dieu déduit des cartes si nécessaire.
Chaque emplacement est nettoyé dans sa propre famille ; les autres emplacements
commencent vides. Un chargement seul ne réécrit pas le fichier.

`PvpMatchContext` ne contient que des données de match (participants, camps,
profils, decks, graine, cases bloquées, premier joueur, dernier résultat) : il
ne touche jamais `PlayerData`, donc un match PVP ne modifie ni les statistiques
de campagne ni `per_npc`.

`PlayerData` possède les banques et renvoie des copies via ses lectures. Les
modifications du deck, du dieu et du numéro sélectionné sont validées et
enregistrées immédiatement ; en cas d'erreur disque, elles restaurent l'état
précédent et renvoient `false`. Une sélection de dieu retrouve sa propre banque
et son dernier numéro, sans filtrer le deck précédent. Un deck incomplet est
valide pour la sauvegarde, mais pas pour le combat. `MainMenu` et
`BoardController` lisent `get_active_deck()` ; le moteur reçoit uniquement la
composition sélectionnée et ne connaît pas les emplacements sauvegardés.
Le résultat d'une campagne suit la même garantie : `BattleContext` prépare les
valeurs puis ne marque la progression comme enregistrée qu'après le succès de
`PlayerData.record_game()`. En cas d'erreur disque, le résultat affiche la cause,
propose un nouvel essai et n'ouvre pas prématurément le niveau suivant.

`get_stone()` renvoie une copie modifiable. Les questions répétées pendant les
simulations (`has_stone`, `has_effect`, `stone_cost`) lisent l'index du catalogue
sans copie. Les coûts unitaires sont des constantes de `StoneCostRules`, reprises
par l'écran des règles. Moteur, interface et validation désignent les pouvoirs par
les constantes de `StoneEffects`, y compris les valeurs numériques affichées
dans les légendes : celles-ci ne chargent pas les systèmes du moteur.
`ContentValidator` signale tout pouvoir ou axe
de pile ou face inconnu dans `stones.json`.

### Lignées et formes

`stones.json` contient 96 lignées de monstres et 275 formes, sans ancien tableau
`stones`. Le tableau `lineages` décrit les lignées : identité commune et tableau
`levels` de définitions explicites. Les quatre raretés modernes imposent 4/3/2/1
formes. Chaque forme peut fournir ses statistiques, son nom, son texte et son
image `asset` ; famille et rareté sont communes. Les nombres de symboles doivent
être entiers et respecter la capacité de chaque face.

Les PNG de production sont dans `assets/cards/<famille>/<forme>.png`. Le champ
`asset` commun d'une lignée fournit son illustration N1 aux niveaux sans image
spécifique ; un `asset` défini sur une forme a priorité. Les 96 lignées disposent
d'une illustration N1 ; les formes de niveau supérieur peuvent progressivement
recevoir leur propre image. Réaffecter une illustration modifie seulement les
références `asset` et les PNG correspondants, sans changer l'index des formes,
les statistiques ou les sauvegardes. Les originaux et les imports restent pour
l'instant à leur résolution complète, en compression sans perte et sans limite
de taille ; leur réduction est une optimisation d'assets distincte.

`StoneCard._load_texture_if_any()` demande la ressource à `CardArtCache` au
changement de définition, sans bloquer le thread principal. La carte reçoit le
signal `texture_ready` et se redessine lorsque l'image arrive. `_illustration_rect()`
calcule le rectangle proportionnel et centré ; `_draw()` affiche la texture sur
fond sombre puis les badges et le nom. Aucun fichier n'est chargé pendant le
dessin et le moteur n'accède jamais aux textures. Le même composant couvre
collection, fiche, main et plateau.

`StoneLoader` valide puis indexe les définitions complètes une fois au chargement.
`get_stone(form_id)` reste le contrat commun au moteur et aux vues.
`stone_lineage`, `stone_level`, `lineage_max_level`, `variant_id` et `variant_ids`
fournissent des lectures de l'index ; `get_lineages_for_god` fournit une entrée
par monstre pour la collection. Une forme demandée hors limites est refusée ;
seul `preview_variant` sature le niveau demandé. Le dictionnaire facultatif
`legacy_ids` décrit les correspondances explicites d'anciens identifiants.
Les identifiants décrivent maintenant le contenu : `avortons_des_caves` désigne
une lignée, `avortons_des_caves_n2` sa deuxième forme. Les 406 identifiants de
cartes historiques ne sont plus indexés comme cartes jouables ;
`resolve_saved_id` les résout seulement pour les sauvegardes. Les mêmes règles
s'appliquent aux IDs de dieux et de PNJ via `resolve_saved_god_id` et
`resolve_saved_npc_id`. Les champs historiques `catalogue_ref` et `kind` ont
été retirés : ils étaient redondants et aucun système de jeu ne les lisait.

La version 4 lit les profils antérieurs. `PlayerSaveCodec` confie les tableaux
contenant des alias à `DeckCatalogueMigration`. Cette conversion déterministe
cherche des formes proches de la correspondance déclarée, protège les lignées
actuelles et réserve un budget pour les cartes restantes. Elle utilise
`DeckRules` pour les ajouts effectifs. Les identifiants internes des six dieux
et des six adversaires historiques restent stables pour préserver banques et
statistiques.

`PlayerData.load_save` conserve en mémoire le JSON d'origine à convertir, sans
écriture. À la première sauvegarde, `PlayerSaveStorage` l'enregistre dans
`savegame.json.before_monsters` avant le profil version 4. Une copie existante
est conservée ; si sa création échoue, la modification est annulée. Les tests
utilisent un chemin distinct et isolent aussi cette copie en attente.

Les decks restent des tableaux d'identifiants de formes. `DeckRules.lineage_index`
centralise la recherche d'une lignée ; les validations et les opérations de
remplacement interdisent deux formes du même monstre. `try_set_level` réutilise
le remplacement et son calcul de budget. `CombatResolver`, `BattleStone` et
`TurnManager` reçoivent directement les statistiques de la forme et n'appliquent
aucun multiplicateur de niveau pendant le combat.

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
`CombatBoard.has_active_power(state, cell, effect)` centralise l'activation des
pouvoirs continus : propriétaire, pierre, effet présent et affinité compatible
avec le dieu du camp. Une pierre neutre agit dans tous les camps. Le catalogue
ne fournit que `stone_affinity(id)` ; cette activation ne s'applique pas aux
symboles physiques (boucliers et lames longues).
`BattleStone.markers_for_side()` décrit les symboles ; le moteur connaît leur type
et leur indice stable, tandis que l'interface calcule leurs positions.
L'ordre des types est `BattleStone.MARKER_KINDS` et la capacité d'une face
`MAX_MARKERS_PER_SIDE`. La vue passe par `markers_for_side()` et `marker_offset()`
sans recopier cet ordre ; `StoneSide.coin_faces()` donne les faces d'un pile ou face.

Les événements de pouvoirs sont construits dans `CombatEvents` avec des paramètres
typés. Leurs données restent des dictionnaires sérialisables, sans nœuds Godot
ni coordonnées écran. Les identifiants communs sont également définis ici.

## Tours et animations

`BoardSetupGenerator` fournit le tirage des cases bloquées et du premier joueur.
`PreBattle` révèle ce dernier et le transmet par `BattleContext` ; le terrain
est tiré au démarrage du combat.
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
La case porte aussi l'information de camp : `BoardView` choisit son fond et son
contour bleu ou rouge depuis la palette de `UITheme`. Lors d'une capture,
`BoardAnimationController` appelle `reveal_cell_owner()` au moment de l'impact ;
cette anticipation est uniquement visuelle et ne modifie jamais `GameState`.
`BlockedCellOverlay` dessine la grande croix et les entailles des cases interdites
avec une géométrie proportionnelle, sans taille de police fixe.
La couche `SwarmLinks` reste responsable des lianes persistantes.
`BoardEffectGeometry.weakness_groups()` fusionne les malus d'une même cible du
premier état avant au dernier état après, puis fournit les cartes et trajectoires
regroupées par source. Le contrôleur se contente de lancer une animation par
groupe ; deux sources ne pilotent jamais deux aperçus rivaux d'une même cible.

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
`GodSelector`, `NumberedSelector`, `DeckPanel` et `CollectionGrid` possèdent
chacun leur vue. `NumberedSelector` partage les boutons tactiles des decks et
des niveaux ; il émet `value_selected` et ignore les règles et la sauvegarde.
`GodSelector` présente l'identité équipée à côté de ses trois decks, puis crée
les six choix dans une grille 3 × 2. Il ne modifie pas `PlayerData` : il émet
seulement `god_selected`, que le contrôleur valide et enregistre comme auparavant.
Le contrôleur appelle `PlayerData.set_selected_deck()`, puis actualise le deck
et les cartes masquées dans la collection, sans recréer celle-ci. Changer de
contexte referme les panneaux de carte et annule tout remplacement en attente.
L'interface reste silencieuse en cas de succès et affiche les erreurs d'écriture.

Le niveau global de collection, le niveau consulté dans `StoneInfoSheet` et
la forme sauvegardée dans le deck sont trois états distincts. Le contrôleur
achemine le tiroir et `StoneInfoSheet.use_requested` vers `_request_use`, puis
vers `DeckRules` et `PlayerData`. La fiche n'écrit jamais le profil. Sa carte
est réutilisée entre niveaux ; son contenu peut défiler et son bouton Utiliser
reste accessible. Les erreurs de budget ou d'écriture sont affichées dans le
panneau ouvert. Le remplacement conserve l'identifiant précis choisi, sans
relire le filtre global.

`CollectionGrid.set_preview_level` actualise une carte par lignée et réordonne
les mêmes nœuds selon le coût courant. Le tri déplace également ces nœuds sans
les reconstruire ; un changement de dieu conserve les vingt-quatre lignées
neutres et recycle les douze emplacements de famille. Une lignée équipée est
entièrement masquée. `CardArtCache` préchauffe hors du thread principal les
illustrations du dieu, du niveau et du deck actifs. Il garde les six portraits
de dieux pour la session, mais relâche ses références fortes aux anciens groupes
de cartes afin de ne pas mettre les 275 images en mémoire. `StoneCard` affiche
la texture dès son arrivée et reste utilisable avec son repli neutre pendant le
chargement. Il affiche aussi un petit repère de niveau pour les lignées évolutives
et utilise leur champ `asset` existant. Une image absente affiche seulement un
indicateur neutre : aucune illustration procédurale de l'ancienne version n'est
conservée dans le composant de carte.
Son large cadre minéral, sombre et désaturé, indique la famille. Un liseré
intérieur distinct indique la rareté par sa couleur et sa géométrie (simple,
reflet, double ou ornée). L'état sélectionné reste un halo extérieur et ne
recouvre donc aucune de ces informations. La propriété `_owner` subsiste pour
les aperçus de combat, mais n'est plus dessinée sur le cadre de la carte.
`CardGridLayout` crée les éléments visuels communs. Le tri est défini dans `CollectionGrid`
(`SortMode`, dans l'ordre des boutons du menu) : FAMILLE par défaut (cartes du
dieu puis neutres, chaque groupe par coût croissant), puis coût, rareté et nom,
avec le nom pour départager les ex aequo.
Les cartes du deck n'apparaissent pas dans la collection. `CollectionGrid` les
garde construites mais masquées dans une `GridContainer`, qui referme les trous :
un changement de deck reconstruit ses emplacements et masque ou réaffiche seulement
les cartes concernées de la collection, sans recréer de carte.
Un changement de tri réordonne les wrappers existants. Un changement de dieu
conserve les vingt-quatre wrappers neutres et recycle les douze autres.

`UITheme.DECK_COLUMNS` fixe les colonnes de la main, du deck et du remplacement.
La main calcule ses rangées sur le deck complet, puis garde sa hauteur pendant
le combat. `CARD_HAND`, `CARD_DECK` et `CARD_REPLACEMENT` restent des tailles
indépendantes ; les valeurs initiales des scènes reflètent la disposition actuelle.

`CardActionDrawer`, `StoneInfoSheet` et `ReplacementPanel` gèrent leurs panneaux.
`TapGesture`, `TouchButton` et `TouchScrollContainer` conservent les gestes tactiles.

L'habillage du refuge est commun aux écrans : `UITheme` fournit la palette et
les fabriques de styles, `RefugeTheme` construit le thème global depuis ces
constantes. `MenuBackground` dessine les fonds sans recevoir d'entrée et
remplace l'ancien `ParchmentBackground`. Les variations de boutons sont
déclarées dans le thème, sans modifier leurs contrôleurs tactiles.
`data/gods.json` fournit le champ `asset` des portraits livrés dans `assets/gods/` ;
l'accueil, le sélecteur, l'avant-combat et le HUD les utilisent. `GodPortrait`
est la vue commune du sélecteur et du combat : il charge l'image, conserve ses
proportions et applique le cadre de famille. L'accueil conserve son grand
`TextureRect`. Chaque écran reste responsable des textes, tailles et interactions
autour du portrait. Voir
[l'identité visuelle des menus](IDENTITE_VISUELLE_MENUS.md).

## Rencontres

`GameRoutes` centralise les chemins des scènes de la boucle principale et
diagnostique un changement impossible. Les contrôleurs conservent la décision
de navigation propre à leur écran, mais ne recopient plus les chemins `res://`.

`EncounterSelectController` affiche une case par dieu, plus Pr.Stone, puis ouvre
le chemin de la source choisie. `EncounterPathController` présente les quinze
niveaux de cette source — trois paliers de cartes et cinq difficultés — et
lance le combat. `OpponentCatalog.levels_for()` est le seul endroit qui ordonne
ces niveaux ; `EncounterPath` en déduit les états verrouillé, disponible et
terminé à partir de `PlayerData.is_npc_beaten()`. Une victoire débloque le
niveau suivant ; une victoire antérieure hors séquence reste enregistrée dans le
profil mais ne valide pas un rond isolé, elle compte dès que les niveaux
précédents ont été gagnés. Aucun champ de sauvegarde n'est ajouté, et les ronds
terminés comme le rond ouvert restent sélectionnables. `OpponentCatalog` génère
à la demande les 105 rencontres.

Les decks des dieux restent majoritairement composés de leur
famille ; Pr.Stone n'utilise que des lignées neutres. La difficulté ne modifie
pas le deck et fournit le profil d'IA ainsi que l'identifiant stable
`bot_<adversaire>_<palier>_<difficulté>`.

`BotCardTierRules` donne aux bots un niveau de puissance distinct du niveau de
forme utilisé par le moteur : commun et rare commencent au palier 1, épique au
palier 3 et légendaire au palier 4. Le niveau effectif est le maximum du niveau
de forme et de ce plancher. La collection, l'évolution, les coûts et le combat
continuent donc d'utiliser les données originales des cartes. Les règles de
`DeckRules` restent réservées aux decks des joueurs ; `StoneLoader` fournit à la
fabrique les lignées neutres et la rareté des formes.

`BattleContext.select_opponent()` conserve la rencontre ; `current_opponent()`
retombe sur `StoneLoader.get_npc()` pour les adversaires historiques de
`npcs.json`. `PreBattle`, `BoardController` et l'écran de résultat lisent la même
source. `BattleContext.selected_source_id` retient le chemin ouvert, ce qui
permet à `PreBattle` et au résultat d'y revenir ; `source_id_of()` déduit la
source d'un adversaire généré. Depuis le résultat, `Niveau suivant` prépare
directement le rond suivant du même chemin, `Rejouer` relance le même duel,
`Choisir un autre niveau` rouvre le serpentin, `Choisir un autre dieu` revient
à la grille et `Accueil` au menu principal ; le bouton du suivant disparaît
après une défaite, au dernier rond ou tant que le résultat n'a pas été écrit sur
le disque. Le bot sans dieu conserve un `god_id` vide et est présenté explicitement
comme tel, sans ajouter de dieu jouable à `gods.json`. Le profil affiche un
chemin par dieu et pour Pr.Stone avec le nombre de niveaux terminés sur quinze ;
ce décompte suit la même règle linéaire que le serpentin, pas les anciennes
victoires agrégées par palier.

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

Une seule IA, `ProfileAI`, joue tous les adversaires. `AIProfile` reçoit le
profil construit par `OpponentCatalog` (ou celui de `npcs.json` pour les
adversaires historiques) ; `ContentValidator` et `OpponentCatalog.problems()`
en signalent les erreurs. `AITurnRunner.create_ai()` crée l'IA d'un profil.

`OpponentCatalog` combine six dieux et un bot neutre, trois paliers de cartes et
cinq difficultés. Le deck est déterministe pour un couple adversaire × palier :
les cinq difficultés affrontent les mêmes cartes. L'identifiant
`bot_<adversaire>_<palier>_<difficulté>` sert de clé aux statistiques.

| Difficulté | `precision` | `anticipation` | Délai minimal |
| --- | --- | --- | --- |
| Très facile | 0 | non | 0,6 s |
| Facile | 0,25 | non | 0,7 s |
| Moyen | 0,5 | non | 0,8 s |
| Difficile | 0,75 | non | 0,9 s |
| Très difficile | 1 | oui | 1,2 s |

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
  (`OpponentModel.expected_from_variants`) ;
- à deux cases libres ou moins, `EndgameSearch.evaluate()` pose chaque riposte possible
  jusqu'à la fin de la partie, avec la même moyenne sur les mains. Un coup
  aléatoire y est rejoué sur 2 tirages.

La riposte immédiate est découpée en tirs : une attaque est un plan pur où chaque
direction est indépendante. `RiposteModel` demande au résolveur, pour chaque case
libre, chaque tir différent (face, lames, lames bleues) une seule fois, avec une
pierre qui n'attaque que dans cette direction (`make_shot`), puis additionne les
tirs de chaque carte. Le coût dépend du nombre de tirs différents, qui plafonne,
et non du nombre de cartes. Les captures de chaque tir sont aussi calculées une
fois sur l'état reçu : pour un coup évalué, seuls les tirs dont la ligne traverse
une case changée (pose, captures, auras, défenses) sont redemandés au résolveur.
Ces données restent propres à une recherche, sans cache global. Les tests
comparent directement `RiposteModel` à un recalcul complet.

La main cachée est modélisée par des lignées équiprobables sans remise, puis un
niveau équiprobable au sein de chaque lignée. Une lignée posée est entièrement
exclue, même après capture. `OpponentModel.expected_from_variants` calcule la
distribution du meilleur résultat via un polynôme de degré limité à la taille
de main, sans énumérer les mains. Le cas à une forme par lignée garde
`rank_weights`. `RiposteModel` et `EndgameSearch` partagent ce calcul ; une
simulation de riposte retire aussi les autres formes de la lignée jouée.
Il s'agit d'une hypothèse de composition, indépendante du véritable deck humain.

Les performances de l'IA dépendent du catalogue, du plateau, du profil et de la
machine. Toute modification de l'évaluation, des pouvoirs ou du nombre de cases
doit donc être mesurée sur ordinateur et sur téléphone ; les valeurs historiques
ne sont pas des objectifs de performance ni des garanties.

`EndgameSearch` est un service sans état : il reçoit la simulation et la taille
de la main cachée. L'exploration des placements restants est complète, mais la
main reste supposée et le hasard échantillonné. La borne de coupure conservée
dans le tour de l'IA ne coupe aucune branche avec le seuil actuel de deux cases.
Relever ce seuil demanderait de nouveaux tests et de nouvelles mesures.

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
`step(budget)` prépare le modèle de riposte par petites unités puis évalue les
tirages un par un ; `chosen_move()` donne ensuite le coup. `AITurnRunner` lui
accorde environ 4 ms par image dans `_process`, sans minuteur ni `await`,
et joue quand la réflexion est finie et le délai écoulé. Une partie relancée ou
une scène fermée abandonne la réflexion. `choose_move()` réfléchit d'un bloc pour
les tests.
Le budget couvre la préparation des cartes, des lignes, des signatures et des
captures de base. Il est vérifié entre deux unités : une unité individuelle peut
donc légèrement le dépasser. Les mesures doivent inclure le total et le plus long
appel à `step()`.

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
`BoardEffectGeometry` fusionne les malus par cible et prépare les groupes par
source ; `BoardAnimationController` lance leurs traînées. Les deux systèmes
continus appliquent la règle unique de `CombatBoard.has_active_power()` : une carte de famille n'agit que dans le
camp dont le dieu est le sien (`GameState.god_of()`).

## Vérification

Les scènes `GodSystemChecks.tscn` et `TouchInputChecks.tscn` sont les points d'entrée.
Les assertions et fixtures sont dans `tests/support/CombatTestSuite.gd`.
`PlayerProfileFixture` redirige les écritures des tests d'interface vers un
fichier dédié, puis restaure le profil en mémoire et le chemin initial.
`PlayerDataChecks` vérifie aussi les banques, leur migration, les modifications
automatiques, le rechargement et le retour à l'état précédent en cas d'erreur.
Les suites de règles, de séquençage, d'IA et d'interface sont réparties dans
`tests/combat/`, `tests/ai/` et `tests/ui/`. Les anciennes suites de placement et
de deck utilisent également ces assertions locales : aucune installation de GUT nécessaire.

`AnimatedMatchChecks` rejoue chaque coup en simulation et en présentation réelle
pour les six familles, puis compare le plateau, le hasard et tous les états de pouvoir.
Les dieux sont équipés dans les deux camps, et des ouvertures dédiées garantissent
que les comparaisons Déclin et Essaim déclenchent réellement leurs auras.
`TurnSequenceChecks` vérifie aussi les fins retardées et l'annulation des présentations.

Au dernier contrôle automatisé, `GodSystemChecks` compte 514 réussites,
sans échec et sans erreur Godot ; `TouchInputChecks` réussit ses
80 vérifications tactiles.

Les lanceurs chargent les suites à l'exécution et enregistrent `tests/support/TestLog.gd`
auprès de Godot. Une suite qui ne compile pas, une erreur ou un avertissement
inattendu, ou un dépassement du temps limite fait échouer l'exécution. Un test qui
provoque volontairement un message l'annonce avec `_expect_log()` ; si ce message
n'apparaît pas, c'est aussi un échec. Les échecs des vérifications sont écrits
avec `printerr`, pour ne pas être comptés une seconde fois comme erreurs Godot.
