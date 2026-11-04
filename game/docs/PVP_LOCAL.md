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
   Le bouton PRÊT passe à `PRÊT ✓` puis `DÉMARRAGE…`.

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
4. Chaque joueur envoie `ready`.
5. Quand les deux sont prêts et valides, l'hôte génère et diffuse
   `match_start` : `match_id`, `seed`, `blocked_cells`, `starting_player`,
   `participants` (peer, camp, pseudo, dieu, deck).
6. Le match ne démarre qu'après validation complète de ce message des deux
   côtés.
7. Le salon ouvre l'écran de pile ou face (branche PVP de `PreBattle.tscn`) :
   il révèle le premier joueur **déjà tiré par l'hôte**, sans consommer de
   nouveau hasard. Chaque appareil doit ensuite toucher `COMMENCER` : le
   premier qui appuie voit « En attente de l'adversaire… », et l'hôte diffuse
   `match_start` (même configuration, même `match_id`) quand les deux ont
   appuyé. Un seul téléphone ne peut donc pas ouvrir le plateau tout seul.
8. Le plateau s'ouvre avec ses cases bloquées déjà marquées. Seul le joueur
   actif peut le toucher : le tour suivant n'est réactivé qu'à la réception de
   `turn_confirmed` (`MatchDriver.interaction_changed`).

Un refus de troisième appareil n'interrompt jamais le salon en cours.

## Fin de match et revanche

Un match terminé n'affiche plus un simple message dans le salon : le plateau
passe à `PvpResult.tscn`, qui garde la session ENet ouverte.

- Chaque appareil voit son propre verdict (`VICTOIRE !`, `DÉFAITE...` ou
  `ÉGALITÉ`) et son score à gauche, comme sur le plateau.
- `REVANCHE` demande une nouvelle partie ; le client envoie `start_request`
  avec l'identifiant du match terminé. L'hôte attend d'avoir reçu cette
  demande **et** d'avoir demandé la sienne avant de diffuser un nouveau
  `match_start`. C'est exactement la poignée de main du `COMMENCER`
  d'avant-combat, avec une configuration neuve au lieu de celle du match.
- Le nouvel identifiant, la graine, les cases bloquées et le premier joueur
  sont tirés par l'hôte, comme au premier match ; les pseudos, dieux et decks
  sont conservés.
- Les deux appareils repassent par le pile ou face PVP, puis par un plateau
  neuf. Le premier qui demande voit « En attente de l'adversaire… ».
- `QUITTER` ferme la session et ramène au salon. Si l'adversaire quitte, la
  revanche est désactivée avec un message.

Le protocole passe en version `2` : le type `start_request` s'ajoute aux
messages existants, et `match_start` sert au premier match comme à la revanche.
Un seul accord ne suffit jamais : l'hôte attend les deux avant de donner le
départ, et le client n'ouvre son plateau que sur `match_start`.

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

## Autorité de l'hôte

Le client ne peut jamais choisir :

- son camp ;
- le premier joueur ;
- les cases bloquées ;
- la validité d'un coup ;
- le résultat.

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
- Aucun deck adverse n'est affiché dans l'interface.
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
| `tests/pvp/LanLobbyChecks.gd` | poignée de main, camps, deck invalide, versions incompatibles, troisième joueur, ordre des PRÊT, configuration refusée, départ du pair, contexte de match |
| `tests/pvp/LanMatchChecks.gd` | coups hôte et client, hors tour, coordonnées, carte absente, mauvais match, doublon, séquence sautée, confirmations, désynchronisation, déconnexions, résultat, revanche négociée, déterminisme, statistiques intactes |
| `tests/support/FakeLanTransport.gd` | transport mémoire : aucun socket, aucun Wi-Fi |

Les suites sont enregistrées dans `tests/run_god_system_checks.gd`. Dernières
mesures réelles :

```text
GOD_SYSTEM_CHECKS: 716 passed, 0 failed, 0 Godot errors
TACTILE : 86 vérifications, 0 échec(s), 0 erreur(s) Godot.
```

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
6. Vérifier les deux cartes joueur (pseudo, dieu coloré, badge PRÊT/PAS PRÊT),
   toucher PRÊT des deux côtés : la partie doit démarrer en même temps.
7. Jouer une partie complète, puis la refaire avec l'hôte qui commence et avec
   le client qui commence.
8. Jouer un pouvoir utilisant du hasard des deux côtés : les deux écrans
   doivent rester synchronisés.
9. Tester le retour Android depuis l'accueil, le salon et le combat.
10. Quitter le salon depuis l'hôte, puis depuis le client.
11. Quitter pendant le combat depuis l'hôte, puis depuis le client.
12. Installer deux versions différentes et vérifier le refus explicite.
13. Couper le broadcast (routeur ou permission) et vérifier le repli par IP.
14. Tenter de créer une partie PVP avec un deck incomplet : l'avertissement
    reste sur le salon, aucune socket n'est ouverte.
15. Activer l'isolation des clients sur le routeur et vérifier le message
    d'échec compréhensible.
16. Terminer une partie : vérifier le verdict, le score local à gauche et
    l'écran de fin sur les deux téléphones, puis demander REVANCHE des deux
    côtés.
17. Quitter depuis l'écran de fin avec QUITTER, puis vérifier que l'adversaire
    voit la revanche se désactiver avec un message.
18. Après le pile ou face, vérifier qu'un seul COMMENCER ne lance rien, puis
    que les deux téléphones ouvrent le plateau ensemble quand les deux l'ont
    touché.
