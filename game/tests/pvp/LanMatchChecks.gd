## Match PVP local : commandes validées par l'hôte, séquences monotones,
## empreintes d'état, désynchronisation et absence d'écriture des statistiques.
## Aucun Wi-Fi : le transport est simulé et le moteur réel est utilisé.
extends "res://tests/support/CombatTestSuite.gd"

const Fake := preload("res://tests/support/FakeLanTransport.gd")
const Coordinator := preload("res://scripts/network/LanMatchCoordinator.gd")
const Driver := preload("res://scripts/ui/match/LanMatchDriver.gd")
const Fingerprint := preload("res://scripts/engine/StateFingerprint.gd")
const ProfileFixture := preload("res://tests/support/PlayerProfileFixture.gd")

const MATCH_ID := "match-1"


func run() -> void:
	_test_host_command()
	_test_client_command()
	_test_out_of_turn()
	_test_invalid_moves()
	_test_duplicate_command()
	_test_sequence_guard()
	_test_confirmations()
	_test_desynchronisation()
	_test_disconnect()
	_test_liveness_timeout()
	_test_results()
	_test_start_handshake()
	_test_rematch()
	_test_determinism()
	await _test_driver_keeps_stats()


func _deck() -> Array:
	return ProfileFixture.DECK.duplicate()


func _state(first_player: int = GameState.PLAYER_ONE, seed: int = 4242) -> GameState:
	var state := GameState.new()
	state.setup_hands(_deck(), _deck())
	state.set_random_seed(seed)
	state.human_god_id = "veskar"
	state.ai_god_id = "veskar"
	state.current_player = first_player
	return state


## Consigne les événements des deux coordinateurs et applique les commandes
## acceptées. Aucune lambda ici : une lambda capturant le dictionnaire de test
## créerait un cycle de références avec les signaux qu'il possède.
class Recorder extends RefCounted:
	const CombatResolverModel := preload("res://scripts/engine/CombatResolver.gd")

	var state: GameState
	var host_applied: Array = []
	var client_applied: Array = []
	var host_confirmed: Array = []
	var client_confirmed: Array = []
	var host_desync: Array = []
	var client_desync: Array = []
	var host_aborted: Array = []
	var client_aborted: Array = []
	var client_finished: Array = []
	var host_pending: Array = []
	var client_pending: Array = []
	var host_ready: Array = []
	var client_ready: Array = []
	var rematch_serial := 0

	const ProfileFixture := preload("res://tests/support/PlayerProfileFixture.gd")

	## Configuration de revanche : un nouveau match et une nouvelle graine,
	## comme le fait l'écran de résultat de l'hôte.
	func build_rematch() -> Dictionary:
		rematch_serial += 1
		return {
			"match_id": "rematch-%d" % rematch_serial,
			"seed": 9000 + rematch_serial,
			"blocked_cells": [],
			"starting_player": GameState.PLAYER_TWO,
			"participants": [
				{"peer_id": 1, "side": GameState.PLAYER_ONE, "name": "Hote",
					"god_id": "veskar", "deck": ProfileFixture.DECK.duplicate()},
				{"peer_id": 2, "side": GameState.PLAYER_TWO, "name": "Client",
					"god_id": "veskar", "deck": ProfileFixture.DECK.duplicate()},
			],
		}

	func on_host_pending() -> void:
		host_pending.append(true)

	func on_client_pending() -> void:
		client_pending.append(true)

	func on_host_ready(config: Dictionary) -> void:
		host_ready.append(config.duplicate(true))

	func on_client_ready(config: Dictionary) -> void:
		client_ready.append(config.duplicate(true))

	func _init(shared_state: GameState) -> void:
		state = shared_state

	## Même validation que la production : joueur actif et PlacementRules.
	func validator(player: int, row: int, col: int, stone_id: String) -> bool:
		return player == state.current_player \
			and PlacementRules.is_valid(state, row, col, stone_id, player)

	## Applique la commande acceptée puis passe la main, comme le TurnManager.
	func apply(command: Dictionary, target: Array) -> void:
		target.append(command)
		CombatResolverModel.apply_move(state, int(command["row"]), int(command["col"]),
			str(command["stone_id"]), int(command["player"]))
		state.current_player = GameState.PLAYER_TWO \
			if int(command["player"]) == GameState.PLAYER_ONE else GameState.PLAYER_ONE

	func on_host_applied(command: Dictionary) -> void:
		apply(command, host_applied)

	func on_client_applied(command: Dictionary) -> void:
		apply(command, client_applied)

	func on_host_confirmed(sequence: int) -> void:
		host_confirmed.append(sequence)

	func on_client_confirmed(sequence: int) -> void:
		client_confirmed.append(sequence)

	func on_host_desync(reason: String) -> void:
		host_desync.append(reason)

	func on_client_desync(reason: String) -> void:
		client_desync.append(reason)

	func on_host_aborted(message: String) -> void:
		host_aborted.append(message)

	func on_client_aborted(message: String) -> void:
		client_aborted.append(message)

	func on_client_finished(winner: int, one: int, two: int) -> void:
		client_finished.append([winner, one, two])


## Deux coordinateurs reliés par un transport mémoire, sur un seul état simulé.
func _pair(first_player: int = GameState.PLAYER_ONE) -> Dictionary:
	var state := _state(first_player)
	var recorder := Recorder.new(state)
	var host_transport := Fake.new()
	host_transport.local_id = LanProtocol.SERVER_ID
	var client_transport := Fake.new()
	client_transport.local_id = 2
	host_transport.remote = client_transport
	client_transport.remote = host_transport

	var host: LanMatchCoordinator = Coordinator.new()
	var client: LanMatchCoordinator = Coordinator.new()
	host.attach(host_transport, MATCH_ID, true, GameState.PLAYER_ONE, 2)
	client.attach(client_transport, MATCH_ID, false, GameState.PLAYER_TWO)
	host.set_move_validator(recorder.validator)
	host.command_accepted.connect(recorder.on_host_applied)
	client.command_accepted.connect(recorder.on_client_applied)
	host.turn_confirmed.connect(recorder.on_host_confirmed)
	client.turn_confirmed.connect(recorder.on_client_confirmed)
	host.desync.connect(recorder.on_host_desync)
	client.desync.connect(recorder.on_client_desync)
	host.aborted.connect(recorder.on_host_aborted)
	client.aborted.connect(recorder.on_client_aborted)
	client.match_finished.connect(recorder.on_client_finished)
	host.start_pending.connect(recorder.on_host_pending)
	client.start_pending.connect(recorder.on_client_pending)
	host.match_ready.connect(recorder.on_host_ready)
	client.match_ready.connect(recorder.on_client_ready)
	host.begin(first_player)
	client.begin(first_player)
	## Les tableaux sont partagés avec le consignateur : les tests les lisent
	## directement sans dépendre d'une copie.
	return {
		"state": state,
		"recorder": recorder,
		"host_transport": host_transport,
		"client_transport": client_transport,
		"host": host,
		"client": client,
		"host_applied": recorder.host_applied,
		"client_applied": recorder.client_applied,
		"host_confirmed": recorder.host_confirmed,
		"client_confirmed": recorder.client_confirmed,
		"host_desync": recorder.host_desync,
		"client_desync": recorder.client_desync,
		"host_aborted": recorder.host_aborted,
		"client_aborted": recorder.client_aborted,
		"client_finished": recorder.client_finished,
	}


func _free_cell(state: GameState) -> Vector2i:
	for index in range(state.board.size()):
		var cell: Dictionary = state.board[index]
		if cell["cell_type"] != GameState.CELL_BLOCKED and cell["owner"] == GameState.PLAYER_NONE:
			return Vector2i(index / GameState.BOARD_SIZE, index % GameState.BOARD_SIZE)
	return Vector2i(-1, -1)


func _hand_card(state: GameState, player: int) -> String:
	return str(state.hand_of(player)[0])


func _confirm(pair: Dictionary, fingerprint: String = "") -> void:
	var host: LanMatchCoordinator = pair["host"]
	var client: LanMatchCoordinator = pair["client"]
	var sequence := host.sequence()
	var value := fingerprint if fingerprint != "" else Fingerprint.of(pair["state"])
	host.report_local_state(value, sequence)
	client.report_local_state(value, sequence)


func _test_host_command() -> void:
	var pair := _pair()
	var host: LanMatchCoordinator = pair["host"]
	var client: LanMatchCoordinator = pair["client"]
	var state: GameState = pair["state"]
	var cell := _free_cell(state)
	_check(host.request_move(cell.x, cell.y, _hand_card(state, GameState.PLAYER_ONE)),
		"l'hôte joue son coup autoritaire")
	_check(host.sequence() == 1 and client.sequence() == 1,
		"la séquence acceptée vaut 1 des deux côtés")
	var accepted := (pair["host_transport"] as Fake).sent_of(LanProtocol.KIND_MOVE_ACCEPTED)
	_check(accepted.size() == 1 and int(accepted[0]["payload"]["sequence"]) == 1
		and int(accepted[0]["payload"]["player"]) == GameState.PLAYER_ONE,
		"l'hôte diffuse la commande acceptée avec une séquence monotone")
	_check((pair["client_applied"] as Array).size() == 1,
		"le client applique la commande reçue")
	_check(not host.can_submit() and not client.can_submit(),
		"aucun joueur ne peut rejouer avant la confirmation du tour")


func _test_client_command() -> void:
	var pair := _pair()
	var host: LanMatchCoordinator = pair["host"]
	var client: LanMatchCoordinator = pair["client"]
	var state: GameState = pair["state"]
	host.request_move(_free_cell(state).x, _free_cell(state).y,
		_hand_card(state, GameState.PLAYER_ONE))
	_confirm(pair)
	_check(host.can_submit() and client.can_submit(),
		"les deux appareils rouvrent le tour après confirmation")
	var cell := _free_cell(state)
	_check(client.request_move(cell.x, cell.y, _hand_card(state, GameState.PLAYER_TWO)),
		"le client envoie une intention de coup")
	var intents := (pair["client_transport"] as Fake).sent_of(LanProtocol.KIND_MOVE_INTENT)
	_check(intents.size() == 1 and int(intents[0]["payload"]["player"]) == GameState.PLAYER_TWO,
		"l'intention du client ne porte aucune séquence : l'hôte la décide")
	_check(host.sequence() == 2 and client.sequence() == 2,
		"le coup du client reçoit la séquence suivante des deux côtés")
	_check((pair["client_applied"] as Array).size() == 2,
		"le client applique aussi le coup qu'il a proposé")


func _test_out_of_turn() -> void:
	var pair := _pair()
	var state: GameState = pair["state"]
	# Le client tente de jouer alors que c'est au tour de l'hôte.
	pair["client_transport"].push(2, LanProtocol.KIND_MOVE_INTENT, {
		"match_id": MATCH_ID,
		"player": GameState.PLAYER_TWO,
		"row": 0,
		"col": 0,
		"stone_id": _hand_card(state, GameState.PLAYER_TWO),
	})
	var host: LanMatchCoordinator = pair["host"]
	_check(host.sequence() == 0 and (pair["client_applied"] as Array).is_empty(),
		"un coup hors tour ne modifie pas l'état autoritaire")
	var rejects := (pair["host_transport"] as Fake).sent_of(LanProtocol.KIND_MOVE_REJECTED)
	_check(rejects.size() == 1 and int(rejects[0]["to"]) == 2,
		"l'hôte renvoie une erreur contrôlée au client hors tour")


func _test_invalid_moves() -> void:
	var pair := _pair(GameState.PLAYER_TWO)
	var state: GameState = pair["state"]
	var card := _hand_card(state, GameState.PLAYER_TWO)
	pair["client_transport"].push(2, LanProtocol.KIND_MOVE_INTENT, {
		"match_id": MATCH_ID, "player": GameState.PLAYER_TWO,
		"row": 9, "col": 0, "stone_id": card,
	})
	var host: LanMatchCoordinator = pair["host"]
	_check(host.sequence() == 0, "des coordonnées invalides ne changent pas la partie")
	var missing_card_pair := _pair(GameState.PLAYER_TWO)
	missing_card_pair["client_transport"].push(2, LanProtocol.KIND_MOVE_INTENT, {
		"match_id": MATCH_ID, "player": GameState.PLAYER_TWO,
		"row": 0, "col": 0, "stone_id": "carte_absente_n1",
	})
	var missing_host: LanMatchCoordinator = missing_card_pair["host"]
	_check(missing_host.sequence() == 0,
		"une carte absente de la main ne peut pas être posée")
	var wrong_match := _pair(GameState.PLAYER_TWO)
	wrong_match["client_transport"].push(2, LanProtocol.KIND_MOVE_INTENT, {
		"match_id": "un-autre-match", "player": GameState.PLAYER_TWO,
		"row": 0, "col": 0,
		"stone_id": _hand_card(wrong_match["state"], GameState.PLAYER_TWO),
	})
	var wrong_host: LanMatchCoordinator = wrong_match["host"]
	_check(wrong_host.sequence() == 0, "un coup d'un autre match est ignoré")
	_check((pair["host_transport"] as Fake).sent_of(LanProtocol.KIND_MOVE_REJECTED).size() == 1,
		"chaque commande invalide reçoit un refus explicite")


func _test_duplicate_command() -> void:
	var pair := _pair(GameState.PLAYER_TWO)
	var state: GameState = pair["state"]
	var intent := {
		"match_id": MATCH_ID,
		"player": GameState.PLAYER_TWO,
		"row": _free_cell(state).x,
		"col": _free_cell(state).y,
		"stone_id": _hand_card(state, GameState.PLAYER_TWO),
	}
	pair["client_transport"].push(2, LanProtocol.KIND_MOVE_INTENT, intent)
	var host: LanMatchCoordinator = pair["host"]
	var client: LanMatchCoordinator = pair["client"]
	_check(host.sequence() == 1 and client.sequence() == 1,
		"le premier envoi est accepté une fois")
	var rejects_before := (pair["host_transport"] as Fake).sent_of(
		LanProtocol.KIND_MOVE_REJECTED).size()
	pair["client_transport"].push(2, LanProtocol.KIND_MOVE_INTENT, intent)
	_check(host.sequence() == 1, "un doublon ne crée pas de seconde commande")
	_check((pair["host_transport"] as Fake).sent_of(
		LanProtocol.KIND_MOVE_REJECTED).size() == rejects_before,
		"un doublon est refusé silencieusement, sans erreur envoyée au client")


func _test_sequence_guard() -> void:
	var pair := _pair()
	var client: LanMatchCoordinator = pair["client"]
	# `push` sur le transport de l'hôte : le paquet arrive au client, émis par l'hôte.
	pair["host_transport"].push(LanProtocol.SERVER_ID, LanProtocol.KIND_MOVE_ACCEPTED, {
		"match_id": MATCH_ID,
		"sequence": 5,
		"player": GameState.PLAYER_ONE,
		"row": 0,
		"col": 0,
		"stone_id": "de_boiteux_n1",
	})
	_check((pair["client_desync"] as Array).size() == 1 and not client.can_submit(),
		"une séquence sautée arrête le client au lieu de diverger")


func _test_confirmations() -> void:
	var pair := _pair()
	var state: GameState = pair["state"]
	var host: LanMatchCoordinator = pair["host"]
	host.request_move(_free_cell(state).x, _free_cell(state).y,
		_hand_card(state, GameState.PLAYER_ONE))
	_confirm(pair)
	_check(pair["host_confirmed"] == [1] and pair["client_confirmed"] == [1],
		"des empreintes identiques confirment le tour des deux côtés")
	var confirmations := (pair["host_transport"] as Fake).sent_of(
		LanProtocol.KIND_TURN_CONFIRMED)
	_check(confirmations.size() == 1 and int(confirmations[0]["payload"]["sequence"]) == 1,
		"l'hôte diffuse la confirmation du tour")


func _test_desynchronisation() -> void:
	var pair := _pair()
	var state: GameState = pair["state"]
	var host: LanMatchCoordinator = pair["host"]
	var client: LanMatchCoordinator = pair["client"]
	host.request_move(_free_cell(state).x, _free_cell(state).y,
		_hand_card(state, GameState.PLAYER_ONE))
	var left := "a".repeat(LanProtocol.FINGERPRINT_LENGTH)
	var right := "b".repeat(LanProtocol.FINGERPRINT_LENGTH)
	host.report_local_state(left, host.sequence())
	client.report_local_state(right, client.sequence())
	_check((pair["host_desync"] as Array).size() == 1,
		"l'hôte détecte deux empreintes différentes")
	_check((pair["client_desync"] as Array).size() == 1,
		"le client est prévenu de la désynchronisation")
	_check(not host.can_submit() and not client.can_submit(),
		"la partie fermée n'accepte plus aucun coup")


func _test_disconnect() -> void:
	var pair := _pair()
	pair["client_transport"].peer_left.emit(LanProtocol.SERVER_ID)
	_check((pair["client_aborted"] as Array).size() == 1
		and str(pair["client_aborted"][0]).contains("quitté"),
		"le client est averti quand l'hôte quitte")
	var other := _pair()
	other["host_transport"].peer_left.emit(2)
	_check((other["host_aborted"] as Array).size() == 1,
		"l'hôte est averti quand le client quitte")


func _test_liveness_timeout() -> void:
	var transport := Fake.new()
	transport.local_id = LanProtocol.SERVER_ID
	var coordinator := Coordinator.new()
	coordinator.attach(transport, MATCH_ID, true, GameState.PLAYER_ONE, 2)
	var driver: LanMatchDriver = Driver.new()
	driver._coordinator = coordinator
	coordinator.aborted.connect(driver._on_aborted)
	var messages: Array = []
	driver.aborted.connect(func(message: String): messages.append(message))
	driver._on_confirmation_timeout()
	_check(messages.size() == 1 and str(messages[0]).contains("confirme")
		and LanProtocol.TURN_CONFIRM_TIMEOUT_SECONDS > 0.0
		and LanProtocol.START_AGREEMENT_TIMEOUT_SECONDS > 0.0,
		"un pair silencieux interrompt le match au lieu de bloquer le tour indéfiniment")
	driver.shutdown()
	# Ce driver isolé n'entre volontairement pas dans l'arbre : il doit donc
	# être libéré immédiatement, contrairement aux fixtures ajoutées par add_child().
	driver.free()


func _test_results() -> void:
	var pair := _pair()
	var host: LanMatchCoordinator = pair["host"]
	var client: LanMatchCoordinator = pair["client"]
	client.finish_match(GameState.PLAYER_TWO, 2, 9)
	_check((pair["client_finished"] as Array).is_empty(),
		"le client ne peut pas décider du résultat")
	host.finish_match(GameState.PLAYER_TWO, 2, 9)
	_check(pair["client_finished"] == [[GameState.PLAYER_TWO, 2, 9]],
		"le résultat diffusé par l'hôte arrive au client")


## La revanche se négocie après la fin : chaque appareil la demande, l'hôte
## seul produit la nouvelle configuration et les deux l'adoptent ensemble.
func _test_rematch() -> void:
	var pair := _pair()
	var host: LanMatchCoordinator = pair["host"]
	var client: LanMatchCoordinator = pair["client"]
	var recorder = pair["recorder"]
	host.finish_match(GameState.PLAYER_ONE, 7, 2)
	host.enable_start()
	client.enable_start()
	host.set_start_builder(recorder.build_rematch)
	_check(client.request_start(), "le client peut demander une revanche après le résultat")
	_check((recorder.host_ready as Array).is_empty(),
		"la revanche ne démarre pas tant que l'hôte ne la demande pas")
	_check((recorder.host_pending as Array).size() == 1,
		"l'hôte est prévenu de la demande adverse")
	_check(client.request_start(), "une demande déjà faite reste acceptée")
	_check((pair["client_transport"] as Fake).sent_of(
		LanProtocol.KIND_START_REQUEST).size() == 1,
		"le client n'envoie qu'une demande de lancement")
	_check(host.request_start(), "l'hôte accepte la revanche demandée")
	_check((pair["host_transport"] as Fake).sent_of(
		LanProtocol.KIND_MATCH_START).size() == 1,
		"l'hôte diffuse une seule nouvelle configuration de match")
	_check((recorder.host_ready as Array).size() == 1
		and (recorder.client_ready as Array).size() == 1,
		"les deux appareils reçoivent la nouvelle configuration de revanche")
	var config: Dictionary = recorder.host_ready[0]
	_check(LanProtocol.validate(LanProtocol.KIND_MATCH_START, config)["ok"]
		and str(config.get("match_id", "")) == "rematch-1"
		and int(config.get("seed", 0)) == 9001,
		"la revanche repart sur un nouveau match et une nouvelle graine")
	_check(host.match_id() == "rematch-1" and client.match_id() == "rematch-1",
		"les deux coordinateurs adoptent le nouvel identifiant de match")
	_check(not host.can_submit() and not client.can_submit(),
		"la revanche attend le premier tour au lieu d'ouvrir le plateau seule")


## Le premier match suit la même règle que la revanche : après le pile ou face,
## chacun touche COMMENCER et l'hôte seul donne le départ aux deux appareils.
func _test_start_handshake() -> void:
	var pair := _pair()
	var host: LanMatchCoordinator = pair["host"]
	var client: LanMatchCoordinator = pair["client"]
	var recorder = pair["recorder"]
	var config: Dictionary = recorder.build_rematch()
	host.enable_start(config)
	client.enable_start(config)
	_check(client.request_start(), "le client annonce qu'il est prêt avant le premier coup")
	_check((recorder.host_ready as Array).is_empty()
		and (recorder.client_ready as Array).is_empty(),
		"un seul COMMENCER n'ouvre pas le plateau")
	_check((recorder.host_pending as Array).size() == 1,
		"l'hôte voit que l'adversaire a touché COMMENCER")
	_check(host.request_start(), "l'hôte donne le départ quand les deux sont prêts")
	_check((recorder.host_ready as Array).size() == 1
		and (recorder.client_ready as Array).size() == 1,
		"les deux téléphones reçoivent le même signal de départ")
	_check(str((recorder.client_ready as Array)[0].get("match_id", "")) == "rematch-1"
		and client.match_id() == "rematch-1",
		"le client ouvre le plateau avec la configuration validée par l'hôte")
	_check(not client.request_start(), "un second COMMENCER ne relance pas le match")


func _test_determinism() -> void:
	var first := _state(GameState.PLAYER_ONE, 987654)
	var second := _state(GameState.PLAYER_ONE, 987654)
	var other := _state(GameState.PLAYER_ONE, 987654)
	for index in range(6):
		var player := GameState.PLAYER_ONE if index % 2 == 0 else GameState.PLAYER_TWO
		var row := 0
		var col := index / 2
		var card := _hand_card(first, player)
		CombatResolverModel.apply_move(first, row, col, card, player)
		CombatResolverModel.apply_move(second, row, col, str(second.hand_of(player)[0]), player)
		first.current_player = GameState.PLAYER_TWO if player == GameState.PLAYER_ONE \
			else GameState.PLAYER_ONE
		second.current_player = first.current_player
	_check(first.empty_playable_cells == second.empty_playable_cells
		and first.random_state == second.random_state
		and first.next_instance_id == second.next_instance_id,
		"même graine et mêmes coups avancent le plateau et le hasard de la même façon")
	_check(Fingerprint.of(first) == Fingerprint.of(second),
		"même graine et mêmes coups produisent la même empreinte d'état")
	_check(Fingerprint.of(first).length() == LanProtocol.FINGERPRINT_LENGTH,
		"l'empreinte tient dans le format du protocole")
	CombatResolverModel.apply_move(other, 1, 0, _hand_card(other, GameState.PLAYER_ONE),
		GameState.PLAYER_ONE)
	_check(Fingerprint.of(first) != Fingerprint.of(other),
		"un coup différent produit une empreinte différente")
	_check(Fingerprint.of(null) == "".sha256_text(),
		"une empreinte sans état reste stable et ne plante pas")


## La preuve la plus importante : un match PVP ne touche jamais aux statistiques.
func _test_driver_keeps_stats() -> void:
	var stats := PlayerData.stats.duplicate(true)
	var games_played := int(PlayerData.stats.get("games_played", 0))
	var per_npc := (PlayerData.stats.get("per_npc", {}) as Dictionary).size()
	var manager := TurnManager.new()
	add_child(manager)
	var config := {
		"match_id": "match-stats",
		"seed": 777,
		"blocked_cells": [],
		"starting_player": GameState.PLAYER_ONE,
		"participants": [
			{"peer_id": 1, "side": GameState.PLAYER_ONE, "name": "Hote", "god_id": "veskar",
				"deck": _deck()},
			{"peer_id": 2, "side": GameState.PLAYER_TWO, "name": "Client", "god_id": "veskar",
				"deck": _deck()},
		],
	}
	PvpMatchContext.begin(config, GameState.PLAYER_ONE, LanProtocol.SERVER_ID,
		config["participants"][0], config["participants"][1])
	var driver: LanMatchDriver = Driver.new()
	add_child(driver)
	driver.setup(manager)
	_check(driver.start(), "le driver PVP démarre une partie depuis le contexte")
	var state := manager.get_state()
	_check(state.random_seed == 777,
		"le combat PVP utilise la graine choisie par l'hôte")
	_check(not driver.records_campaign_stats,
		"le driver PVP n'enregistre aucune statistique de campagne")
	var cell := _free_cell(state)
	_check(driver.request_move(cell.x, cell.y, _hand_card(state, GameState.PLAYER_ONE)),
		"un coup PVP passe par la même validation que la campagne")
	for _frame in range(20):
		await get_tree().process_frame
	_check(manager.get_state().empty_playable_cells == GameState.total_cells() - 1,
		"le coup PVP est résolu par le même moteur")
	_check(PlayerData.stats == stats
		and int(PlayerData.stats.get("games_played", 0)) == games_played
		and (PlayerData.stats.get("per_npc", {}) as Dictionary).size() == per_npc,
		"un match PVP ne modifie pas les statistiques de campagne ni per_npc")
	driver.shutdown()
	LanSession.reset()
	PvpMatchContext.clear()
	driver.queue_free()
	manager.queue_free()
	await get_tree().process_frame
