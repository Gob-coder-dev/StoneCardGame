## Salon PVP local : poignée de main, attribution des camps, deck invalide,
## versions incompatibles, troisième joueur et passage en match.
## Aucun socket réel : le transport est simulé.
extends "res://tests/support/CombatTestSuite.gd"

const Fake := preload("res://tests/support/FakeLanTransport.gd")
const Lobby := preload("res://scripts/network/LanLobbyCoordinator.gd")
const ProfileFixture := preload("res://tests/support/PlayerProfileFixture.gd")


func run() -> void:
	_test_full_handshake()
	_test_invalid_deck()
	_test_version_mismatch()
	_test_third_player()
	_test_ready_order()
	_test_bad_config_on_client()
	_test_peer_left()
	_test_local_deck_required()
	_test_context_mapping()


func _deck() -> Array:
	return ProfileFixture.DECK.duplicate()


## Consigne les événements des deux salons. Aucune lambda : capturer le
## dictionnaire de test créerait un cycle avec les signaux qu'il possède.
class Recorder extends RefCounted:
	var errors_host: Array = []
	var errors_client: Array = []
	var started_host: Array = []
	var started_client: Array = []

	func on_host_failed(message: String) -> void:
		errors_host.append(message)

	func on_client_failed(message: String) -> void:
		errors_client.append(message)

	func on_host_started(config: Dictionary) -> void:
		started_host.append(config)

	func on_client_started(config: Dictionary) -> void:
		started_client.append(config)


func _pair(host_deck: Array = [], client_deck: Array = []) -> Dictionary:
	var host_deck_value: Array = host_deck if not host_deck.is_empty() else _deck()
	var client_deck_value: Array = client_deck if not client_deck.is_empty() else _deck()
	var recorder := Recorder.new()
	var host_transport := Fake.new()
	host_transport.local_id = LanProtocol.SERVER_ID
	var client_transport := Fake.new()
	client_transport.local_id = 2
	host_transport.remote = client_transport
	client_transport.remote = host_transport
	var host := Lobby.new()
	var client := Lobby.new()
	host.attach(host_transport, true, 2)
	client.attach(client_transport, false)
	host.set_local_profile("Hote", "veskar", host_deck_value)
	client.set_local_profile("Client", "veskar", client_deck_value)
	host.failed.connect(recorder.on_host_failed)
	client.failed.connect(recorder.on_client_failed)
	host.match_started.connect(recorder.on_host_started)
	client.match_started.connect(recorder.on_client_started)
	return {
		"host_transport": host_transport,
		"client_transport": client_transport,
		"host": host,
		"client": client,
		"recorder": recorder,
		"errors_host": recorder.errors_host,
		"errors_client": recorder.errors_client,
		"started_host": recorder.started_host,
		"started_client": recorder.started_client,
	}


## Connexion ENet puis poignée de main applicative.
func _connect(pair: Dictionary) -> void:
	pair["host_transport"].peer_joined.emit(2)
	pair["client_transport"].connected_to_host.emit()


func _test_full_handshake() -> void:
	var pair := _pair()
	_connect(pair)
	var acks: Array = pair["host_transport"].sent_of(LanProtocol.KIND_HELLO_ACK)
	_check(acks.size() == 1 and int(acks[0]["payload"]["you_are"]) == GameState.PLAYER_TWO,
		"l'hôte accuse la poignée de main et donne PLAYER_TWO au client")
	_check(pair["client"].host_summary()["name"] == "Hote"
		and pair["host"].client_summary()["name"] == "Client",
		"chaque salon connaît le pseudo de son pair")
	_check(int(pair["host"].state()["local_side"]) == GameState.PLAYER_ONE
		and int(pair["client"].state()["local_side"]) == GameState.PLAYER_TWO,
		"l'hôte est PLAYER_ONE et le client PLAYER_TWO")
	_check(pair["host_transport"].sent_of(LanProtocol.KIND_LOBBY_STATE).size() >= 1,
		"l'hôte diffuse l'état du salon après validation")
	_check(pair["host"].press_ready() and pair["host_transport"].sent_of(
		LanProtocol.KIND_MATCH_START).is_empty(),
		"le prêt de l'hôte seul ne démarre pas la partie")
	_check(pair["client"].press_ready(), "le client peut se déclarer prêt")
	_check(pair["started_host"].size() == 1 and pair["started_client"].size() == 1,
		"la partie démarre quand les deux joueurs sont prêts")
	var config: Dictionary = pair["started_host"][0]
	_check(str(config["match_id"]) != "" and int(config["seed"]) != 0,
		"l'hôte génère un identifiant et une graine de match")
	var participants: Array = config["participants"]
	_check(participants.size() == 2
		and int(participants[0]["side"]) == GameState.PLAYER_ONE
		and int(participants[0]["peer_id"]) == LanProtocol.SERVER_ID
		and int(participants[1]["side"]) == GameState.PLAYER_TWO
		and int(participants[1]["peer_id"]) == 2,
		"les deux participants et leurs camps sont figés par l'hôte")
	_check((config["blocked_cells"] as Array).size() <= LanProtocol.MAX_BLOCKED_CELLS
		and int(config["starting_player"]) != 0,
		"les cases bloquées et le premier joueur viennent de l'hôte")
	_check(config == pair["started_client"][0],
		"le client reçoit exactement la configuration validée")


func _test_invalid_deck() -> void:
	var pair := _pair([], ProfileFixture.DECK.slice(0, 5))
	_connect(pair)
	var rejects: Array = pair["host_transport"].sent_of(LanProtocol.KIND_HELLO_REJECT)
	_check(rejects.size() == 1 and str(rejects[0]["payload"]["reason"]).contains("Deck"),
		"un deck incomplet est refusé explicitement")
	_check(pair["errors_client"].size() == 1 and str(pair["errors_client"][0]).contains("Deck"),
		"le client affiche le motif du refus")
	_check(pair["client"].press_ready() == false,
		"un deck refusé ne peut pas se déclarer prêt")


func _test_version_mismatch() -> void:
	var cases := [
		{"field": "app_version", "value": "0.0.0-elsewhere", "label": "application"},
		{"field": "catalogue", "value": "0".repeat(LanProtocol.FINGERPRINT_LENGTH),
			"label": "catalogue"},
		{"field": "protocol_version", "value": LanProtocol.VERSION + 1, "label": "protocole"},
	]
	for entry in cases:
		var pair := _pair()
		pair["host_transport"].peer_joined.emit(2)
		var hello := LanProtocol.identity_fields()
		hello.merge({"name": "Client", "god_id": "veskar", "deck": _deck()})
		hello[entry["field"]] = entry["value"]
		pair["client_transport"].push(2, LanProtocol.KIND_HELLO, hello)
		var rejects: Array = pair["host_transport"].sent_of(LanProtocol.KIND_HELLO_REJECT)
		_check(rejects.size() == 1,
			"une version de %s incompatible est refusée" % entry["label"])
		_check(pair["host_transport"].sent_of(LanProtocol.KIND_MATCH_START).is_empty(),
			"aucune partie ne démarre avec un %s incompatible" % entry["label"])


func _test_third_player() -> void:
	var pair := _pair()
	_connect(pair)
	var hello := LanProtocol.identity_fields()
	hello.merge({"name": "Triche", "god_id": "veskar", "deck": _deck()})
	pair["client_transport"].push(3, LanProtocol.KIND_HELLO, hello)
	var rejects: Array = pair["host_transport"].sent_of(LanProtocol.KIND_HELLO_REJECT)
	_check(rejects.size() == 1 and int(rejects[0]["to"]) == 3
		and str(rejects[0]["payload"]["reason"]) == Lobby.FULL_MESSAGE,
		"un troisième appareil est refusé avec un motif explicite")
	_check(pair["host"].state()["status"] != Lobby.STATUS_ERROR,
		"refuser un intrus ne casse pas le salon en cours")


func _test_ready_order() -> void:
	var pair := _pair()
	_connect(pair)
	_check(pair["client"].press_ready(), "le client peut être prêt avant l'hôte")
	_check(pair["started_host"].is_empty(),
		"le client ne peut pas démarrer la partie tout seul")
	_check(pair["host"].press_ready() and pair["started_host"].size() == 1,
		"l'hôte démarre seulement une fois les deux prêts")


func _test_bad_config_on_client() -> void:
	var pair := _pair()
	_connect(pair)
	var config := {
		"match_id": "match-x",
		"seed": 42,
		"blocked_cells": [],
		"starting_player": GameState.PLAYER_ONE,
		"participants": [
			{"peer_id": 1, "side": GameState.PLAYER_ONE, "name": "Hote", "god_id": "veskar",
				"deck": _deck()},
			{"peer_id": 9, "side": GameState.PLAYER_TWO, "name": "Client", "god_id": "veskar",
				"deck": _deck()},
		],
	}
	pair["host_transport"].push(LanProtocol.SERVER_ID, LanProtocol.KIND_MATCH_START, config)
	_check(pair["started_client"].is_empty() and not pair["errors_client"].is_empty(),
		"une configuration qui n'attribue pas le client est refusée")
	var wrong_side := config.duplicate(true)
	(wrong_side["participants"] as Array)[1]["side"] = GameState.PLAYER_ONE
	(wrong_side["participants"] as Array)[0]["side"] = GameState.PLAYER_TWO
	pair["host_transport"].push(LanProtocol.SERVER_ID, LanProtocol.KIND_MATCH_START, wrong_side)
	_check(pair["started_client"].is_empty(),
		"un client ne peut pas se voir attribuer un autre camp")

	var invalid_host_pair := _pair()
	_connect(invalid_host_pair)
	var invalid_host := config.duplicate(true)
	(invalid_host["participants"] as Array)[0]["deck"] = _deck().slice(0, 5)
	(invalid_host["participants"] as Array)[1]["peer_id"] = 2
	invalid_host_pair["host_transport"].push(
		LanProtocol.SERVER_ID, LanProtocol.KIND_MATCH_START, invalid_host)
	_check(invalid_host_pair["started_client"].is_empty()
		and not invalid_host_pair["errors_client"].is_empty()
		and str(invalid_host_pair["errors_client"][0]).contains("Deck"),
		"le client valide aussi le deck de l'hôte avant de quitter le salon")


func _test_peer_left() -> void:
	var pair := _pair()
	_connect(pair)
	pair["host_transport"].peer_left.emit(2)
	_check(pair["errors_host"].size() == 1 and str(pair["errors_host"][0]).contains("quitté"),
		"le départ du client est signalé à l'hôte")
	_check(str(pair["host"].state()["status"]) == Lobby.STATUS_HOSTING,
		"l'hôte reste prêt à accueillir un autre adversaire")


func _test_local_deck_required() -> void:
	var host := Lobby.new()
	var transport := Fake.new()
	transport.local_id = LanProtocol.SERVER_ID
	host.attach(transport, true, 2)
	host.set_local_profile("Hote", "veskar", [])
	# Un adversaire est connecté : seul le deck local peut bloquer le prêt.
	transport.peer_joined.emit(2)
	var errors: Array = []
	host.failed.connect(func(message: String): errors.append(message))
	_check(not host.press_ready() and errors.size() == 1,
		"un deck local incomplet interdit de se déclarer prêt")
	_check(not bool(host.state()["can_ready"]),
		"le bouton PRÊT reste inactif tant que le deck local est invalide")


func _test_context_mapping() -> void:
	var context := preload("res://scripts/data/PvpMatchContext.gd").new()
	var participants := [
		{"peer_id": 1, "side": GameState.PLAYER_ONE, "name": "Hote", "god_id": "veskar",
			"deck": _deck()},
		{"peer_id": 2, "side": GameState.PLAYER_TWO, "name": "Client", "god_id": "veskar",
			"deck": _deck()},
	]
	var config := {
		"match_id": "match-mapping",
		"seed": 99,
		"blocked_cells": [[1, 1]],
		"starting_player": GameState.PLAYER_TWO,
		"participants": participants,
	}
	context.begin(config, GameState.PLAYER_TWO, 2, participants[1], participants[0])
	_check(context.is_active() and context.side_of_peer(1) == GameState.PLAYER_ONE
		and context.side_of_peer(2) == GameState.PLAYER_TWO,
		"le contexte associe chaque peer_id à son camp")
	_check(context.local_side == GameState.PLAYER_TWO
		and context.remote_side() == GameState.PLAYER_ONE,
		"le contexte connaît le camp local et le camp distant")
	_check(context.local_name == "Client" and context.remote_name == "Hote"
		and context.seed == 99 and context.starting_player == GameState.PLAYER_TWO,
		"le contexte conserve profils, graine et premier joueur")
	_check(context.deck_of_side(GameState.PLAYER_ONE) == _deck(),
		"le contexte expose le deck de chaque camp au moteur")
	context.clear()
	_check(not context.is_active() and context.participants.is_empty(),
		"le contexte se vide sans laisser de données de match")
	context.free()
