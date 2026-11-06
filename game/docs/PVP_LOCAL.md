# PVP local — deux téléphones, un Wi-Fi, aucun serveur

Le mode PVP local fait s'affronter deux appareils Android sur le même réseau
Wi-Fi (ou sur un point d'accès créé par l'un des deux téléphones). Un appareil
est l'hôte autoritaire, l'autre est le client. Aucun compte, aucun service
Internet et aucun relais externe ne sont nécessaires.

La campagne est inchangée : elle utilise le même `Board.tscn`, les mêmes vues,
le même `CombatResolver`, le même `TurnManager` et la même IA.

## Hôte et client

| Rôle | Camp | Autorité |
| --- | --- | --- |
| Hôte | `PLAYER_ONE` | valide les poignées de main, les coups et le résultat |
| Client | `PLAYER_TWO` | propose ses coups, ne décide de rien |

`LanSession` (autoload) porte le cycle réseau et les RPC. Les messages arrivent
toujours sur `/root/LanSession`, dont le chemin est identique sur les deux
appareils. ENet est créé avec **un seul client autorisé** :
`create_server(port, LanProtocol.MAX_PARTICIPANTS - 1)`.

## Modes, séries et paliers

Le salon choisit quatre modes de préparation et trois formats de série.
L'hôte seul peut les modifier ; le client voit les mêmes valeurs, sans pouvoir
les changer.

| Mode | Loadout de chaque manche |
| --- | --- |
| Classique | dieu et deck actifs des deux profils |
| Aléatoire | deux dieux et deux decks générés, au même total exact |
| Miroir | un seul loadout généré, dupliqué en profondeur pour les deux camps |
| Sélection | draft parallèle de 60 s : deux offres jouables par camp, deck local de 8 cartes actualisé à chaque choix |

`FT1`, `FT2` et `FT3` demandent le premier à 1, 2 ou 3 victoires, avec au plus
1, 3 ou 5 manches hors égalités. Une égalité ne marque aucun point et ouvre une
nouvelle manche. Le mode Classique en FT1 conserve le démarrage immédiat. En
Classique FT2/FT3, l'hôte initialise la série puis envoie `prepare_start` et
`round_start` sans quitter le salon. Aléatoire, Miroir et Sélection ouvrent
l'écran dédié de préparation.

Chaque option porte une révision monotone. Modifier le mode, la série ou le
palier incrémente la révision et remet les deux joueurs à PAS PRÊT ; le PRÊT
référence la révision courante. Quand les deux sont prêts, l'hôte verrouille
les règles (`rules_lock`) et elles ne changent plus avant le retour au salon.

Le palier est affiché et appliqué uniquement en Aléatoire, Miroir et Sélection.
Le mode Classique utilise toujours le deck enregistré complet, sans filtrage de
palier. Pour les trois modes concernés, `power_tier = niveau de forme +
décalage de rareté` (commune 0, rare 1, épique 2, légendaire 3), avec un champ
explicite `power_tier` prioritaire. Une limite N n'autorise que les cartes dont
le palier effectif est inférieur ou égal à N.

En Aléatoire, le générateur ne considère que les couples de dieux qui possèdent
au moins un total de huit cartes atteignable en commun. Il choisit ensuite de
façon déterministe depuis la graine un total parmi la moitié supérieure des
totaux communs, puis construit les deux decks à ce total exact. Les 80 points
sont donc une limite maximale, jamais une cible obligatoire : au palier 1, une
partie peut légitimement produire deux decks moins chers mais strictement égaux.
Miroir applique la même sélection de total avant de dupliquer le loadout.

Sélection commence au palier 2. Son plan public fixe huit paires indépendantes
par joueur et doit garantir huit lignées uniques quelle que soit la carte prise,
soit seize lignées disponibles par dieu. Le catalogue du palier 1 n'en contient
que treize ; l'interface désactive donc ce choix au lieu de générer un draft
impossible ou de modifier les offres selon les décisions secrètes.

## Ports

| Usage | Protocole | Port |
| --- | --- | --- |
| Découverte (beacon JSON) | UDP | `45454` (`LanProtocol.DISCOVERY_PORT`) |
| Match et salon | UDP / ENet | `45555` (`LanProtocol.GAME_PORT`) |

Les deux ports sont distincts : le broadcast de découverte ne traverse jamais la
session ENet.

## Découverte

`LanDiscovery` :

- l'hôte diffuse toutes les `1.0 s` une annonce JSON de marque `samstone`
  (pseudo, port de jeu, nombre de joueurs, version) vers `255.255.255.255:45454` ;
- le client écoute sur le même port, dédoublonne par clé `ip:port`, conserve au
  plus `8` parties et oublie une annonce non revue depuis `3.5 s` ;
- `poll(delta)` est appelé à chaque image : aucune boucle bloquante, aucun
  thread ;
- chaque image traite au plus `16` paquets, pour qu'un pair ne puisse pas
  monopoliser la frame ;
- `stop()` ferme explicitement le socket.

Si le broadcast est refusé (routeur, permission, mode restreint), le salon
affiche un message clair et **conserve la saisie manuelle de l'adresse IP**
affichée par l'hôte.

## Interface du salon

`PvpLobby.tscn` ne montre qu'un écran à la fois, dans le même cadre :

1. **Choix du mode** : deux cartes, `CRÉER UNE PARTIE` et `REJOINDRE UNE
   PARTIE`. Aucun statut, aucune adresse, aucune mention de la campagne.
2. **Rejoindre** : la liste des salons trouvés se met à jour toute seule ;
   sous la liste, un champ accepte `192.168.1.98` ou `192.168.1.98:45555`
   (le port est retiré, celui du jeu est fixe) pour les réseaux où le
   broadcast est bloqué. Pendant une tentative, une fenêtre modale garde la
   recherche visible en arrière-plan, indique l'hôte et l'adresse visés, puis
   permet d'annuler. En cas d'échec ou de délai dépassé, elle affiche le motif,
   l'adresse essayée et propose de réessayer la même cible ou de revenir à la
   recherche. ANNULER et le retour Android ferment la tentative et relancent
   l'écoute. Aucun bouton ACTUALISER : `RELANCER` relève seulement un socket
   mort après une coupure Wi-Fi.
3. **Salle d'attente** : l'hôte y lit `VOTRE ADRESSE`, et un appui la copie
   dans le presse-papiers. Les deux cartes joueur affichent le pseudo, le dieu
   dans sa couleur et un badge `PRÊT` (vert) ou `PAS PRÊT` (rouge) ; l'état du
   deck n'est jamais affiché, puisqu'il est forcément valide pour arriver ici.
   Le bouton PRÊT passe à `PRÊT ✓` puis `DÉMARRAGE…`. Quand l'adversaire est
   encore dans une préparation, un combat ou un résultat, sa carte affiche
   `EN PARTIE` : l'autre joueur ne peut alors ni se déclarer prêt ni modifier
   les règles. À son retour, les deux repassent à PAS PRÊT et les règles se
   déverrouillent. Sous l'adresse, le panneau **RÈGLES DE LA SÉRIE** montre le
   mode et le format ; la ligne du palier apparaît seulement pour Aléatoire,
   Miroir et Sélection. Les listes et leurs fenêtres utilisent le thème néon
   commun au lieu du rendu natif de Godot.
   L'hôte les modifie ; le client les voit grisés avec la mention « Seul
   l'hôte peut modifier ces options ».

`RETOUR` depuis une recherche ou une salle ferme la session et revient au
choix du mode ; depuis le choix du mode, il sort du PVP.

L'adresse proposée est classée : `192.168.x`, puis `172.16–31.x`, puis `10.x`,
avec les adresses loopback, lien-local et IPv6 écartées. Godot n'exposant pas
le nom des interfaces, ce classement évite de proposer une adresse de VPN ou
d'opérateur, qui n'est pas joignable depuis l'autre téléphone, alors que la
découverte annonce bien l'adresse du Wi-Fi. C'est `poll()` qui émet le beacon :
la découverte tourne donc dans tous les modes, y compris pendant que l'hôte
attend un adversaire.

## Poignée de main

1. Le client se connecte en ENet, puis envoie `hello` avec
   `protocol_version`, `app_version`, l'empreinte du catalogue
   (`catalogue`), son pseudo, son `god_id` et son deck.
2. L'hôte vérifie le format, la taille des chaînes, les bornes du deck
   (`DeckRules.is_deck_valid(deck, god_id)`), la compatibilité de version et
   l'absence d'un troisième appareil.
3. L'hôte répond `hello_ack` (`you_are: PLAYER_TWO`) ou `hello_reject` avec un
   motif court : version, catalogue, deck invalide, partie complète.
4. Chaque joueur envoie `ready` avec `rules_revision`. Une révision périmée
   est refusée ; toute modification réelle remet les deux à PAS PRÊT.
5. Quand les deux sont prêts et valides, l'hôte verrouille les règles et
   diffuse `rules_lock`. En Classique FT1, il génère aussitôt `match_start` :
   `match_id`, `seed`, `blocked_cells`, `starting_player`, `participants`
   (peer, camp, pseudo, dieu, deck). Pour les autres combinaisons, il crée la
   série et envoie `prepare_start` avec les identifiants, le mode, le format,
   le palier et l'échéance du draft. En Classique FT2/FT3, il enchaîne
   immédiatement `round_start` sans ouvrir de scène de préparation : le client
   reste dans le salon jusqu'à ce message.
6. Aléatoire, Miroir et Sélection quittent `PvpLobby` et ouvrent
   `PvpPreparation.tscn`. Aléatoire et Miroir envoient à chaque camp un
   `loadout_reveal` contenant **son seul** dieu et son seul deck. Sélection
   envoie à chaque camp un `draft_offers` avec **deux paires indexées sur son
   étape locale** : ses propres offres et celles que l'adversaire aurait à la
   même étape. Les paires adverses ne sont donc jamais celles de la
   progression réelle de l'autre camp. Le compteur `opponent_step` reste la
   progression réelle, sans exposer les cartes choisies. Puis vient le loadout
   final de chaque camp. Les deux joueurs avancent indépendamment
   (`step_one`/`step_two`, `deck_one`/`deck_two`,
   `complete_one`/`complete_two`) : l'un peut faire ses huit choix avant
   l'autre, et le premier deck terminé reçoit immédiatement son loadout. Le
   plan de huit paires est précalculé par l'hôte ; chaque offre locale a le
   même coût, les lignées restent uniques et les deux decks finissent au même
   total. `draft_progress` ne transmet qu'à son propriétaire l'étape, la
   complétion et le deck en construction ; les choix restent privés. Le deck
   local est actualisé après chaque choix accepté.
7. Chaque camp confirme : `loadout_confirm` pour le client, `loadout_ready`
   pour l'hôte. Le premier camp terminé peut se déclarer `PRÊT` sans fermer le
   draft adverse ; sa dernière carte reste toujours sélectionnable. L'hôte
   lance `round_start` quand les deux ont confirmé ; ce message porte la
   graine, le terrain, le premier joueur, les deux loadouts et les identifiants
   de série. À l'échéance de 60 s, l'hôte complète chaque deck incomplet sans
   effacer les choix déjà faits. `PvpPreparation` ouvre alors `PreBattle`, et
   le match ne démarre qu'après validation complète des deux côtés.
8. Le salon ouvre l'écran de pile ou face (branche PVP de `PreBattle.tscn`) :
   il révèle le premier joueur **déjà tiré par l'hôte**, sans consommer de
   nouveau hasard. Chaque appareil doit ensuite toucher `COMMENCER` : le
   premier qui appuie voit « En attente de l'adversaire… », et l'hôte diffuse
   `match_start` (même configuration, même `match_id`) quand les deux ont
   appuyé. Un seul téléphone ne peut donc pas ouvrir le plateau tout seul.
9. Le plateau s'ouvre avec ses cases bloquées déjà marquées. Seul le joueur
   actif peut le toucher : le tour suivant n'est réactivé qu'à la réception de
   `turn_confirmed` (`MatchDriver.interaction_changed`).

Un refus de troisième appareil n'interrompt jamais le salon en cours.

## Fin de manche, série et revanche

Un match terminé n'affiche plus un simple message dans le salon : le plateau
passe à `PvpResult.tscn`, qui garde la session ENet ouverte. En série, l'écran
montre le score des manches et le format ; l'hôte y enregistre le verdict
autoritaire. Une égalité ne donne aucun point et ouvre une nouvelle manche.

- **Partie suivante** (série non terminée) : `PARTIE SUIVANTE` envoie
  `start_request` avec l'identifiant de série. Les deux appareils doivent le
  demander ; l'hôte prépare alors une manche neuve (nouveaux decks en
  Aléatoire, nouveau draft en Sélection, loadouts conservés en Miroir et
  Classique), et les deux repassent par les confirmations.
- **Série terminée** : le premier à 2 (FT2) ou 3 (FT3) victoires gagne ;
  l'action principale devient `NOUVELLE SÉRIE` (ou `REVANCHE` en FT1). Une
  nouvelle série conserve les règles et les profils mais reçoit un nouvel
  identifiant ; elle repasse par `PvpPreparation` lorsque le mode l'exige.
- Chaque appareil voit son propre verdict (`VICTOIRE !`, `DÉFAITE...` ou
  `ÉGALITÉ`) et son score à gauche, comme sur le plateau. En FT1, aucun score
  de série, aucun objectif ni numéro de manche n'est affiché.
- `REVANCHE` en FT1 et `PARTIE SUIVANTE` en FT2/FT3 non terminé demandent
  l'accord des deux appareils. Le client envoie `start_request` avec
  l'identifiant de la série ; l'hôte attend les deux demandes avant de créer
  la manche ou la partie suivante. Les loadouts Classique et Miroir sont
  conservés ; Aléatoire régénère et Sélection relance un draft.
- Le nouvel identifiant, la graine, les cases bloquées et le premier joueur
  sont tirés par l'hôte, comme au premier match ; les pseudos, dieux et decks
  sont conservés.
- Les deux appareils repassent par le pile ou face PVP, puis par un plateau
  neuf. Le premier qui demande voit « En attente de l'adversaire… ».
- `RETOUR AU SALON` abandonne la partie ou la série mais **conserve la
  connexion ENet**, l'hôte, le client et les profils. Chaque camp annonce
  seulement sa présence `LOBBY` : le joueur qui agit revient seul, l'autre
  reste où il est et ne reçoit aucun ordre de navigation. Tant que le pair
  n'est pas revenu, sa carte affiche `EN PARTIE`, `PRÊT` reste désactivé et
  les règles sont verrouillées. Quand les deux sont au salon, l'hôte nettoie
  l'ancienne série, le draft, les loadouts et le score ; les deux repassent à
  PAS PRÊT et les règles se déverrouillent. Les profils du salon sont des
  snapshots distincts des participants de manche : un dieu ou un deck généré
  n'est jamais réinjecté dans le salon. Une partie Classique lancée ensuite
  reprend obligatoirement les dieux et decks enregistrés. Aucun ancien état ne
  subsiste.
- `QUITTER` ferme réellement le coordinateur et `LanSession`, puis ramène au
  choix Créer/Rejoindre du PVP. C'est une méthode distincte du retour
  individuel. Le bouton retour Android suit ce comportement de sortie, y
  compris pendant un draft.

Le protocole passe en version `5`. `draft_offers` porte `viewer_side` et
`offers_step` : l'hôte refuse une projection qui ne correspond pas à l'étape
réelle du destinataire. Aux messages de salon s'ajoutent
`rules_update`, `rules_lock`, `prepare_start`, `loadout_reveal`,
`loadout_ready`, `loadout_confirm`, `draft_offers`, `draft_choice`,
`draft_progress`, `draft_finished`, `round_start`, `round_result`,
`series_state` et `pvp_presence`. `ready` et `lobby_state` portent la
révision des règles ; `match_start` reste accepté pour le Classique FT1 et la
revanche. Un seul accord ne suffit jamais : l'hôte attend les deux camps avant
de donner le départ, et le client n'ouvre son plateau que sur `match_start`.
Les présences explicites sont `LOBBY`, `PREPARATION`, `PRE_BATTLE`, `IN_MATCH` et `RESULT`. Chaque message ne transporte que ce statut ; il ne déclenche jamais la navigation du pair.

## Commandes de coup

Un coup est une intention minimale :

```json
{
  "match_id": "…",
  "player": 2,
  "row": 0,
  "col": 1,
  "stone_id": "avortons_des_caves_n2"
}
```

L'intention ne contient **pas** de séquence : seul l'hôte la numérote.

1. Le joueur local envoie `move_intent` quand c'est son tour.
2. L'hôte vérifie l'expéditeur (`multiplayer.get_remote_sender_id()` via le
   transport), le `match_id`, le camp, le joueur actif, la phase, les
   coordonnées, la présence de la carte dans la main et
   `PlacementRules.is_valid(...)`.
3. Un doublon est refusé **silencieusement** ; une commande invalide reçoit
   `move_rejected`.
4. L'hôte diffuse `move_accepted` avec une séquence strictement croissante.
5. Les deux moteurs appliquent la même commande, avec la même graine.
6. Après résolution et présentation, chaque appareil envoie `turn_ack`
   (`sequence`, `fingerprint`).
7. L'hôte compare les deux empreintes, puis diffuse `turn_confirmed`.
   Le tour suivant ne s'ouvre qu'à ce moment-là.
8. Si les empreintes diffèrent, `desync` arrête la partie et le salon affiche
   l'erreur.

Une commande acceptée dont la séquence ne suit pas exactement l'état local est
traitée comme une désynchronisation : le client s'arrête au lieu de diverger.
Une attente de confirmation de tour est bornée à 30 secondes. Le même délai
s'applique aux accords COMMENCER et REVANCHE : un pair toujours connecté mais
qui ne poursuit plus le protocole ne peut pas bloquer l'autre indéfiniment.

## Autorité de l'hôte

Le client ne peut jamais choisir :

- son camp ;
- le mode, le format de série ou le palier ;
- les dieux et decks générés, les offres du draft ou les choix de l'adversaire ;
- le premier joueur ;
- les cases bloquées ;
- la validité d'un coup ;
- les loadouts retenus, la manche suivante ou le résultat.

Pendant une préparation, le client ne peut envoyer qu'un choix parmi ses deux
propositions (`draft_choice`) et sa confirmation de loadout
(`loadout_confirm`). Toute carte hors offre, tout choix en double et toute
confirmation d'une ancienne préparation sont ignorés.

`match_end` n'est émis que par l'hôte. Un client qui tente `finish_match()` est
ignoré. La configuration `match_start` reçue est refusée si ses participants
n'attribuent pas `PLAYER_TWO` au pair local, ou si les deux camps désignent le
même `peer_id`.

## Déterminisme et graine

- La graine vient de l'hôte (`seed`) et entre dans `GameState.random_seed`.
- `GameState.random_state` avance uniquement par `draw_random_index()` : le
  hasard du combat est donc rejouable, sans `randi()` local.
- Le combat ne lit aucun état graphique : `BoardView`, `HandView` et
  `BattleHUD` ne font qu'afficher le résultat du moteur.
- Le premier joueur et les cases bloquées arrivent dans `match_start`.

## Empreintes d'état

`StateFingerprint.of(state)` produit un SHA-256 d'une représentation canonique :
version de schéma, joueur courant, cases jouables restantes, compteur
d'instances, scores, dieux, mains, `random_seed`/`random_state`, puis chaque case
avec son type, son propriétaire, son `placed_by`, son `stone_id` et les faces de
sa pierre dans l'ordre fixe de `StoneSide.ALL`. Aucun ordre de dictionnaire
implicite n'intervient, et deux états identiques donnent la même empreinte.

## Ce que le PVP ne fait pas

- **Mode de confiance locale, pas anti-triche.** Pour que les deux moteurs
  calculent la même chose, `match_start` réplique le deck et le dieu des deux
  joueurs. Un client modifié pourrait donc les lire. Celui qui triche est aussi
  celui qui casse son propre déterminisme : la désynchronisation est détectée.
- Aucune migration d'hôte : si l'hôte quitte le salon, le client revient à la
  recherche avec un message et ne peut plus se déclarer prêt ; pendant un match,
  la partie s'arrête et le client revient au salon avec un message.
- Aucun résultat PVP n'est écrit dans les statistiques de campagne ni dans
  `per_npc` (`LanMatchDriver.records_campaign_stats == false`).
- Pendant le draft, les deux offres adverses de **l'étape locale** sont
  visibles mais non interactives ; leur choix, leur deck en construction et
  leur loadout restent privés. Seuls l'étape réelle, la complétion et le
  compteur de cartes choisies transitent. Au lancement de la manche, les deux
  decks sont répliqués pour que les moteurs restent déterministes.
- Aucun relais, aucun serveur de matchmaking : les deux appareils doivent
  pouvoir se joindre en UDP sur le même sous-réseau.
- Aucun support iOS dans cette version (voir plus bas).

## Permissions Android

`export_presets.cfg` active exactement :

- `permissions/internet=true` pour ENet et l'UDP ;
- `permissions/change_wifi_multicast_state=true` pour le broadcast de
  découverte.

Aucune permission de localisation n'est demandée : elle n'est pas nécessaire à
la découverte UDP utilisée ici. Les autres permissions du préréglage restent
minimales.

## iOS : adaptations non faites

Le mode PVP local est livré pour Android uniquement. Porter la découverte sur
iOS demanderait au minimum :

- une description `NSLocalNetworkUsageDescription` et la déclaration des types
  Bonjour, ou l'entitlement `com.apple.developer.networking.multicast` ;
- une découverte compatible avec les restrictions iOS sur le broadcast UDP
  (souvent via `NWBrowser`/Bonjour plutôt que `255.255.255.255`) ;
- une vérification du comportement en arrière-plan et du redémarrage du
  socket après verrouillage de l'écran ;
- des essais sur appareils réels, la permission réseau local étant demandée à
  l'utilisateur.

ENet lui-même est portable ; c'est la découverte et les autorisations qui
demandent ce travail.

## Tests automatisés

| Suite | Portée |
| --- | --- |
| `tests/pvp/LanProtocolChecks.gd` | tous les types de messages, payloads mal formés, clés inconnues, bornes, deck, pseudo, dieu, demande de lancement, annonces de découverte |
| `tests/pvp/GameModeChecks.gd` | paliers de puissance, générateurs Aléatoire/Miroir, draft Sélection, égalités et séries FT1/FT2/FT3, révisions et verrouillage du salon |
| `tests/pvp/LanLobbyChecks.gd` | poignée de main, camps, deck invalide, versions incompatibles, troisième joueur, ordre des PRÊT, configuration refusée, départ du pair, contexte de match |
| `tests/pvp/LanSeriesChecks.gd` | préparation Aléatoire et Miroir, copie profonde, draft parallèle, confidentialité, timeout, Classique FT2/FT3, manche suivante, score de série, messages périmés |
| `tests/pvp/PvpPreparationChecks.gd` | navigation salon → préparation → avant-combat, portrait et huit cartes illustrées, draft tactile, deck local en temps réel, dispositions 1080×2400 et 1200×1920 sans scroll, retour individuel, présence, trois actions de résultat et retour connecté |
| `tests/pvp/LanMatchChecks.gd` | coups hôte et client, hors tour, coordonnées, carte absente, mauvais match, doublon, séquence sautée, confirmations, désynchronisation, déconnexions, résultat, revanche négociée, déterminisme, statistiques intactes |
| `tests/TouchInputChecks.tscn` | gestes tactiles des menus, du salon PVP, du résultat et du plateau |
| `tests/support/FakeLanTransport.gd` | transport mémoire : aucun socket, aucun Wi-Fi |

Les suites sont enregistrées dans `tests/run_god_system_checks.gd`. Leur nombre
de vérifications n'est pas figé dans ce document : la sortie des lanceurs et
leur code de retour font foi. Les deux commandes doivent terminer avec le code
`0`, sans échec ni erreur Godot.

## Dépannage

| Symptôme | Cause probable | Solution |
| --- | --- | --- |
| Aucune partie détectée | broadcast bloqué, appareils sur deux réseaux, isolation des clients | recopier l'adresse copiée dans la salle d'attente, ou désactiver l'isolation AP |
| Le salon s'ouvre mais l'adversaire ne voit rien | pare-feu local, ports `45454`/`45555` bloqués | autoriser Godot/l'APK sur le réseau privé |
| « Réseau local indisponible » | Wi-Fi coupé ou aucune adresse IPv4 | reconnecter le Wi-Fi, vérifier que les deux téléphones sont sur le même SSID |
| « Version incompatible » | APK ou catalogue différents | installer la même version sur les deux appareils |
| « Partie complète » | un troisième appareil tente d'entrer | normal : un seul client est accepté |
| « Désynchronisation détectée » | états divergents (appareil modifié, coup non déterministe) | relancer une partie ; si cela se reproduit, noter les coups joués |
| Retour au salon avec un message | l'hôte ou le client a quitté | recréer une partie |

## Procédure de test sur deux téléphones

1. Installer la même version sur les deux appareils.
2. Les connecter au même Wi-Fi (ou au point d'accès de l'un des deux).
3. Accueil → PVP sur les deux.
4. Appareil A : CRÉER UNE PARTIE. La salle d'attente affiche « VOTRE
   ADRESSE » ; un appui la copie dans le presse-papiers.
5. Appareil B : REJOINDRE UNE PARTIE ; vérifier que le salon de A apparaît
   seul dans la liste, sinon coller l'adresse dans le champ de la même page.
6. Vérifier les deux cartes joueur (pseudo, dieu coloré, badge PRÊT/PAS PRÊT).
   L'hôte choisit le mode, le format de série et le palier ; vérifier que le
   client les voit sans pouvoir les modifier et que chaque changement remet
   les deux badges à PAS PRÊT.
7. Toucher PRÊT des deux côtés : en Classique FT1 la partie démarre
   immédiatement. En Classique FT2/FT3, vérifier que les deux restent au salon
   jusqu'à la configuration de manche. En Aléatoire/Miroir, vérifier le loadout
   local illustré. En Sélection, vérifier deux offres adverses compactes, deux
   offres locales centrées, le deck local `VOTRE DECK — X / 8` actualisé après
   chaque choix et le compte à rebours de 60 s. Faire les huit choix d'un seul
   côté : son deck se termine et `PRÊT` devient disponible sans bloquer
   l'autre. Vérifier qu'aucun choix ni deck adverse n'est révélé.
8. Jouer les manches jusqu'au format choisi. Vérifier qu'une égalité ne marque
   aucun point, qu'une nouvelle manche régénère les decks en Aléatoire et
   propose un nouveau draft en Sélection, et que l'écran de résultat affiche
   le score de série.
9. Jouer une partie complète, puis la refaire avec l'hôte qui commence et avec
   le client qui commence.
10. Jouer un pouvoir utilisant du hasard des deux côtés : les deux écrans
    doivent rester synchronisés.
11. Tester le retour Android depuis l'accueil, le salon et le combat.
12. Quitter le salon depuis l'hôte, puis depuis le client.
13. Quitter pendant le combat depuis l'hôte, puis depuis le client.
14. Installer deux versions différentes et vérifier le refus explicite.
15. Couper le broadcast (routeur ou permission) et vérifier le repli par IP.
16. Tenter de créer une partie PVP avec un deck incomplet : l'avertissement
    reste sur le salon, aucune socket n'est ouverte.
17. Activer l'isolation des clients sur le routeur et vérifier le message
    d'échec compréhensible.
18. Terminer une manche : vérifier le verdict, le score local à gauche et
    l'écran de fin sur les deux téléphones. Demander la manche suivante des
    deux côtés, puis vérifier qu'une seule demande ne prépare rien.
19. Terminer une série FT2 ou FT3 : vérifier le vainqueur et le score de
    série. Utiliser RETOUR AU SALON sur un seul appareil : lui seul revient au
    salon, l'autre reste sur son écran, sa carte affiche EN PARTIE, `PRÊT`
    reste désactivé et les règles sont verrouillées. Revenir avec le second :
    vérifier le nettoyage de l'ancienne série et du draft, les deux badges
    PAS PRÊT et les règles de nouveau modifiables. Vérifier que l'hôte est
    resté hôte et que la connexion ENet n'a pas été recréée. Refaire ce test
    après Aléatoire, Miroir et Sélection, choisir ensuite Classique et vérifier
    que les deux dieux et les deux decks sont ceux des profils d'origine.
20. Depuis l'écran de fin, utiliser QUITTER : la connexion ENet doit se fermer
    et les deux appareils revenir au choix Créer/Rejoindre. Vérifier aussi le
    retour Android pendant un draft : aucun choix ni loadout ne doit rester.
21. Après le pile ou face, vérifier qu'un seul COMMENCER ne lance rien, puis
    que les deux téléphones ouvrent le plateau ensemble quand les deux l'ont
    touché.
