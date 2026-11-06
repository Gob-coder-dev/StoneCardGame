## Validation du protocole PVP local : formes acceptées, formes refusées,
## enveloppe JSON et annonce de découverte.
extends "res://tests/support/CombatTestSuite.gd"

const ProfileFixture := preload("res://tests/support/PlayerProfileFixture.gd")


func run() -> void:
	_test_identity()
	_test_hello()
	_test_lobby_state()
	_test_match_start()
	_test_series_messages()
	_test_moves()
	_test_turn_proofs()
	_test_end_and_desync()
	_test_start_request()
	_test_malformed_payloads()
	_test_beacon()


func _hello(player_name: String = "Joueur") -> Dictionary:
	var hello := LanProtocol.identity_fields()
	hello.merge({
		"name": player_name,
		"god_id": "veskar",
		"deck": ProfileFixture.DECK.duplicate(),
	})
	return hello


func _participants() -> Array:
	return [
		{"peer_id": 1, "side": GameState.PLAYER_ONE, "name": "Hote", "god_id": "veskar",
			"deck": ProfileFixture.DECK.duplicate()},
		{"peer_id": 2, "side": GameState.PLAYER_TWO, "name": "Client", "god_id": "veskar",
			"deck": ProfileFixture.DECK.duplicate()},
	]


func _config() -> Dictionary:
	return {
		"match_id": "match-1",
		"seed": 123456,
		"blocked_cells": [[0, 1], [2, 3]],
		"starting_player": GameState.PLAYER_TWO,
		"participants": _participants(),
	}


func _test_identity() -> void:
	var fingerprint := LanProtocol.catalogue_fingerprint()
	_check(fingerprint.length() == LanProtocol.FINGERPRINT_LENGTH,
		"l'empreinte du catalogue est un SHA-256 complet")
	_check(LanProtocol.app_version() == str(ProjectSettings.get_setting("application/config/version")),
		"le protocole annonce la version réelle de l'application")
	_check(LanProtocol.compatibility_problem(LanProtocol.identity_fields()) == "",
		"deux installations identiques se déclarent compatibles")
	var wrong_app := LanProtocol.identity_fields()
	wrong_app["app_version"] = "0.0.0-test"
	_check(LanProtocol.compatibility_problem(wrong_app) != "",
		"une version d'application différente est refusée")
	var wrong_catalogue := LanProtocol.identity_fields()
	wrong_catalogue["catalogue"] = "0".repeat(LanProtocol.FINGERPRINT_LENGTH)
	_check(LanProtocol.compatibility_problem(wrong_catalogue) != "",
		"un catalogue différent est refusé")
	var wrong_protocol := LanProtocol.identity_fields()
	wrong_protocol["protocol_version"] = LanProtocol.VERSION + 1
	_check(LanProtocol.compatibility_problem(wrong_protocol) != "",
		"une version de protocole différente est refusée")


func _test_hello() -> void:
	var hello := _hello()
	_check(LanProtocol.validate(LanProtocol.KIND_HELLO, hello)["ok"],
		"une poignée de main complète est acceptée")
	var text := LanProtocol.encode(LanProtocol.KIND_HELLO, hello)
	var decoded := LanProtocol.decode(text)
	_check(text != "" and decoded["ok"] and decoded["kind"] == LanProtocol.KIND_HELLO
		and decoded["payload"]["name"] == "Joueur",
		"la poignée de main survit à l'aller-retour JSON")
	var ack := LanProtocol.identity_fields()
	ack.merge({"name": "Hote", "god_id": "nerava", "you_are": GameState.PLAYER_TWO})
	_check(LanProtocol.validate(LanProtocol.KIND_HELLO_ACK, ack)["ok"],
		"un accusé de poignée de main valide est accepté")
	var wrong_side := ack.duplicate(true)
	wrong_side["you_are"] = GameState.PLAYER_ONE
	_check(not LanProtocol.validate(LanProtocol.KIND_HELLO_ACK, wrong_side)["ok"],
		"l'accusé doit attribuer PLAYER_TWO au client")
	_check(LanProtocol.validate(LanProtocol.KIND_HELLO_REJECT,
		{"reason": "Partie complète."})["ok"],
		"un refus motivé est un message valide")


func _test_lobby_state() -> void:
	var summary := {"name": "Hote", "god_id": "veskar", "deck_valid": true, "ready": false}
	var payload := {"host": summary, "client": summary.duplicate(), "status": "connected"}
	_check(LanProtocol.validate(LanProtocol.KIND_LOBBY_STATE, payload)["ok"],
		"l'état du salon est valide avec deux résumés et un statut")
	var broken := payload.duplicate(true)
	broken["client"] = {"name": "Client", "god_id": "veskar", "deck_valid": true}
	_check(not LanProtocol.validate(LanProtocol.KIND_LOBBY_STATE, broken)["ok"],
		"un résumé de salon incomplet est refusé")
	_check(LanProtocol.validate(LanProtocol.KIND_READY, {"ready": true})["ok"],
		"le message PRÊT accepte un booléen strict")
	_check(not LanProtocol.validate(LanProtocol.KIND_READY, {"ready": 1})["ok"],
		"le message PRÊT refuse un entier à la place d'un booléen")


func _test_match_start() -> void:
	var config := _config()
	_check(LanProtocol.validate(LanProtocol.KIND_MATCH_START, config)["ok"],
		"une configuration de match complète est valide")
	var text := LanProtocol.encode(LanProtocol.KIND_MATCH_START, config)
	var decoded := LanProtocol.decode(text)
	_check(decoded["ok"] and int(decoded["payload"]["seed"]) == 123456
		and (decoded["payload"]["blocked_cells"] as Array).size() == 2,
		"la configuration du match survit à l'aller-retour JSON")
	var three := config.duplicate(true)
	var third: Array = (three["participants"] as Array).duplicate(true)
	third.append({"peer_id": 3, "side": GameState.PLAYER_ONE, "name": "Triche",
		"god_id": "veskar", "deck": ProfileFixture.DECK.duplicate()})
	three["participants"] = third
	_check(not LanProtocol.validate(LanProtocol.KIND_MATCH_START, three)["ok"],
		"un troisième participant est refusé par le protocole")
	var same_side := config.duplicate(true)
	var duplicated: Array = (same_side["participants"] as Array).duplicate(true)
	duplicated[1]["side"] = GameState.PLAYER_ONE
	same_side["participants"] = duplicated
	_check(not LanProtocol.validate(LanProtocol.KIND_MATCH_START, same_side)["ok"],
		"deux participants dans le même camp sont refusés")
	var bad_cells := config.duplicate(true)
	bad_cells["blocked_cells"] = [[4, 4]]
	_check(not LanProtocol.validate(LanProtocol.KIND_MATCH_START, bad_cells)["ok"],
		"une case bloquée hors du plateau est refusée")
	var bad_cell_type := config.duplicate(true)
	bad_cell_type["blocked_cells"] = [[0, 0], [0, 0]]
	_check(not LanProtocol.validate(LanProtocol.KIND_MATCH_START, bad_cell_type)["ok"],
		"deux cases bloquées identiques sont refusées")
	var bad_first := config.duplicate(true)
	bad_first["starting_player"] = 3
	_check(not LanProtocol.validate(LanProtocol.KIND_MATCH_START, bad_first)["ok"],
		"un premier joueur hors des deux camps est refusé")
	var empty_seed := config.duplicate(true)
	empty_seed["seed"] = "graine"
	_check(not LanProtocol.validate(LanProtocol.KIND_MATCH_START, empty_seed)["ok"],
		"une graine non entière est refusée")


func _test_series_messages() -> void:
	var rules := {"mode": "draft", "series": "ft2", "power_tier": 3, "rules_revision": 4}
	_check(LanProtocol.validate(LanProtocol.KIND_RULES_UPDATE, rules)["ok"],
		"protocole : une mise à jour de règles complète est acceptée")
	var bad_rules := rules.duplicate()
	bad_rules["mode"] = "inconnu"
	_check(not LanProtocol.validate(LanProtocol.KIND_RULES_UPDATE, bad_rules)["ok"],
		"protocole : un mode de règles inconnu est refusé")
	_check(LanProtocol.validate(LanProtocol.KIND_RULES_LOCK, {"rules_revision": 4})["ok"],
		"protocole : le verrouillage porte la révision")
	_check(LanProtocol.validate(LanProtocol.KIND_READY,
		{"ready": true, "rules_revision": 4})["ok"],
		"protocole : le PRÊT peut référencer la révision des règles")

	var ids := {
		"series_id": "series-1", "preparation_id": "prep-1",
		"rules_revision": 4, "round_index": 1,
	}
	var prepare := ids.duplicate()
	prepare.merge({"mode": "draft", "series": "ft2", "power_tier": 3,
		"deadline_unix_ms": 123456})
	_check(LanProtocol.validate(LanProtocol.KIND_PREPARE_START, prepare)["ok"],
		"protocole : le début de préparation est validé")
	var no_deadline := prepare.duplicate()
	no_deadline.erase("deadline_unix_ms")
	_check(not LanProtocol.validate(LanProtocol.KIND_PREPARE_START, no_deadline)["ok"],
		"protocole : une préparation sans échéance est refusée")

	var loadout := ids.duplicate()
	loadout.merge({"god_id": "veskar", "deck": ProfileFixture.DECK.duplicate(),
		"total_quarters": DeckRules.deck_quarters(ProfileFixture.DECK)})
	_check(LanProtocol.validate(LanProtocol.KIND_LOADOUT_REVEAL, loadout)["ok"],
		"protocole : un loadout local complet est accepté")
	var too_expensive := loadout.duplicate()
	too_expensive["total_quarters"] = DeckRules.DECK_BUDGET * StoneCostRules.COST_SCALE + 1
	_check(not LanProtocol.validate(LanProtocol.KIND_LOADOUT_REVEAL, too_expensive)["ok"],
		"protocole : un total de loadout hors budget est refusé")
	var ready_loadout := ids.duplicate()
	ready_loadout.merge({"side": GameState.PLAYER_ONE, "ready": true})
	_check(LanProtocol.validate(LanProtocol.KIND_LOADOUT_READY, ready_loadout)["ok"],
		"protocole : la confirmation de loadout est typée")
	_check(LanProtocol.validate(LanProtocol.KIND_LOADOUT_CONFIRM, ids)["ok"],
		"protocole : la confirmation ne porte que les identifiants")

	var offers := ids.duplicate()
	offers.merge({
		"step_one": 0, "step_two": 0, "complete_one": false, "complete_two": false,
		"viewer_side": GameState.PLAYER_ONE, "offers_step": 0,
		"offers_one": [ProfileFixture.DECK[0], ProfileFixture.DECK[1]],
		"offers_two": [ProfileFixture.DECK[2], ProfileFixture.DECK[3]],
		"deadline_unix_ms": 123456,
	})
	_check(LanProtocol.validate(LanProtocol.KIND_DRAFT_OFFERS, offers)["ok"],
		"protocole : quatre propositions projetées sont acceptées")
	var three_offers := offers.duplicate(true)
	three_offers["offers_one"] = [ProfileFixture.DECK[0], ProfileFixture.DECK[1], ProfileFixture.DECK[2]]
	_check(not LanProtocol.validate(LanProtocol.KIND_DRAFT_OFFERS, three_offers)["ok"],
		"protocole : trois propositions dans une paire sont refusées")
	var wrong_projection := offers.duplicate(true)
	wrong_projection["offers_step"] = 1
	_check(not LanProtocol.validate(LanProtocol.KIND_DRAFT_OFFERS, wrong_projection)["ok"],
		"protocole : une projection sur une autre étape que le destinataire est refusée")
	var wrong_viewer := offers.duplicate(true)
	wrong_viewer["viewer_side"] = 9
	_check(not LanProtocol.validate(LanProtocol.KIND_DRAFT_OFFERS, wrong_viewer)["ok"],
		"protocole : le destinataire des offres doit être un camp valide")
	var choice := ids.duplicate()
	choice.merge({"own_step": 0, "stone_id": ProfileFixture.DECK[0]})
	_check(LanProtocol.validate(LanProtocol.KIND_DRAFT_CHOICE, choice)["ok"],
		"protocole : un choix de draft valide est accepté")
	var duplicate_choice := choice.duplicate()
	duplicate_choice["extra"] = true
	_check(not LanProtocol.validate(LanProtocol.KIND_DRAFT_CHOICE, duplicate_choice)["ok"],
		"protocole : un champ inconnu dans le choix est refusé")
	var progress := ids.duplicate()
	progress.merge({"own_step": 1, "own_deck": [ProfileFixture.DECK[0]],
		"own_complete": false})
	_check(LanProtocol.validate(LanProtocol.KIND_DRAFT_PROGRESS, progress)["ok"],
		"protocole : l'accusé privé de deck est validé")
	var bad_progress := progress.duplicate(true)
	bad_progress["own_deck"] = []
	_check(not LanProtocol.validate(LanProtocol.KIND_DRAFT_PROGRESS, bad_progress)["ok"],
		"protocole : un deck local incohérent avec l'étape est refusé")
	_check(LanProtocol.VERSION == 5,
		"le protocole de draft projeté par destinataire est en version 5")
	_check(LanProtocol.validate(LanProtocol.KIND_PVP_PRESENCE,
		{"presence": LanPvpPresence.LOBBY})["ok"],
		"protocole : une présence de salon est valide")
	_check(not LanProtocol.validate(LanProtocol.KIND_PVP_PRESENCE,
		{"presence": "inconnue"})["ok"],
		"protocole : une présence inconnue est refusée")

	var result := ids.duplicate()
	result.merge({
		"winner": GameState.PLAYER_ONE, "score_one": 10, "score_two": 4,
		"wins_one": 1, "wins_two": 0, "ties": 0, "finished": false,
		"series_winner": GameState.PLAYER_NONE, "next_round_index": 2,
	})
	_check(LanProtocol.validate(LanProtocol.KIND_ROUND_RESULT, result)["ok"],
		"protocole : un résultat de manche complet est accepté")
	var bad_result := result.duplicate()
	bad_result["winner"] = 9
	_check(not LanProtocol.validate(LanProtocol.KIND_ROUND_RESULT, bad_result)["ok"],
		"protocole : un vainqueur de manche inconnu est refusé")

	var series := {
		"series_id": "series-1", "mode": "draft", "series": "ft2",
		"rules_revision": 4, "power_tier": 3, "wins_one": 1, "wins_two": 0,
		"wins_needed": 2, "max_rounds": 3, "round_index": 2, "ties": 0,
		"finished": false, "winner": GameState.PLAYER_NONE, "seed": 42,
		"keeps_loadouts": false,
	}
	_check(LanProtocol.validate(LanProtocol.KIND_SERIES_STATE, series)["ok"],
		"protocole : l'état de série est validé")
	var bad_series := series.duplicate()
	bad_series["wins_needed"] = 9
	_check(not LanProtocol.validate(LanProtocol.KIND_SERIES_STATE, bad_series)["ok"],
		"protocole : un objectif de série impossible est refusé")

	var round_config := _config().duplicate(true)
	round_config.merge({
		"series_id": "series-1", "rules_revision": 4, "preparation_id": "prep-1",
		"round_index": 1, "mode": "draft", "series": "ft2", "power_tier": 3,
	})
	_check(LanProtocol.validate(LanProtocol.KIND_ROUND_START, round_config)["ok"],
		"protocole : un lancement de manche étendu est accepté")
	var legacy_round := _config().duplicate(true)
	_check(not LanProtocol.validate(LanProtocol.KIND_ROUND_START, legacy_round)["ok"],
		"protocole : un lancement de manche sans identifiants de série est refusé")
	_check(LanProtocol.validate(LanProtocol.KIND_MATCH_START, legacy_round)["ok"],
		"protocole : l'ancien match_start reste accepté pour le mode classique")


func _test_start_request() -> void:
	var request := {"match_id": "match-1"}
	_check(LanProtocol.validate(LanProtocol.KIND_START_REQUEST, request)["ok"],
		"une demande de lancement ne porte que l'identifiant du match")
	_check(not LanProtocol.validate(LanProtocol.KIND_START_REQUEST,
		{"match_id": "match-1", "side": GameState.PLAYER_TWO})["ok"],
		"une demande de lancement avec un champ inconnu est refusée")
	_check(not LanProtocol.validate(LanProtocol.KIND_START_REQUEST, {})["ok"],
		"une demande de lancement sans match est refusée")


func _test_moves() -> void:
	var intent := {"match_id": "match-1", "player": GameState.PLAYER_ONE,
		"row": 0, "col": 1, "stone_id": "de_boiteux_n1"}
	_check(LanProtocol.validate(LanProtocol.KIND_MOVE_INTENT, intent)["ok"],
		"une intention de coup minimale est valide")
	var accepted := intent.duplicate(true)
	accepted["sequence"] = 1
	_check(LanProtocol.validate(LanProtocol.KIND_MOVE_ACCEPTED, accepted)["ok"],
		"une commande acceptée avec séquence est valide")
	var zero_sequence := accepted.duplicate(true)
	zero_sequence["sequence"] = 0
	_check(not LanProtocol.validate(LanProtocol.KIND_MOVE_ACCEPTED, zero_sequence)["ok"],
		"une séquence acceptée doit commencer à 1")
	var bad_row := intent.duplicate(true)
	bad_row["row"] = 4
	_check(not LanProtocol.validate(LanProtocol.KIND_MOVE_INTENT, bad_row)["ok"],
		"une ligne hors plateau est refusée")
	var bad_col := intent.duplicate(true)
	bad_col["col"] = -1
	_check(not LanProtocol.validate(LanProtocol.KIND_MOVE_INTENT, bad_col)["ok"],
		"une colonne négative est refusée")
	var bad_stone := intent.duplicate(true)
	bad_stone["stone_id"] = ""
	_check(not LanProtocol.validate(LanProtocol.KIND_MOVE_INTENT, bad_stone)["ok"],
		"une carte vide est refusée")
	var long_stone := intent.duplicate(true)
	long_stone["stone_id"] = "x".repeat(LanProtocol.MAX_STONE_ID_LENGTH + 1)
	_check(not LanProtocol.validate(LanProtocol.KIND_MOVE_INTENT, long_stone)["ok"],
		"une carte trop longue est refusée")
	var wrong_side := intent.duplicate(true)
	wrong_side["player"] = 7
	_check(not LanProtocol.validate(LanProtocol.KIND_MOVE_INTENT, wrong_side)["ok"],
		"un camp inconnu est refusé")
	var extra := intent.duplicate(true)
	extra["bonus"] = 10
	_check(not LanProtocol.validate(LanProtocol.KIND_MOVE_INTENT, extra)["ok"],
		"une clé inconnue est refusée")
	_check(LanProtocol.validate(LanProtocol.KIND_MOVE_REJECTED,
		{"match_id": "match-1", "sequence": 0, "reason": "Coup invalide."})["ok"],
		"un refus de coup est valide")


func _test_turn_proofs() -> void:
	var fingerprint := LanProtocol.catalogue_fingerprint()
	var ack := {"match_id": "match-1", "sequence": 1, "fingerprint": fingerprint}
	_check(LanProtocol.validate(LanProtocol.KIND_TURN_ACK, ack)["ok"],
		"un accusé de fin de tour est valide")
	_check(LanProtocol.validate(LanProtocol.KIND_TURN_CONFIRMED, ack)["ok"],
		"une confirmation de tour est valide")
	var short := ack.duplicate(true)
	short["fingerprint"] = "abc"
	_check(not LanProtocol.validate(LanProtocol.KIND_TURN_ACK, short)["ok"],
		"une empreinte d'état tronquée est refusée")
	var negative := ack.duplicate(true)
	negative["sequence"] = -1
	_check(not LanProtocol.validate(LanProtocol.KIND_TURN_ACK, negative)["ok"],
		"une séquence négative est refusée")


func _test_end_and_desync() -> void:
	_check(LanProtocol.validate(LanProtocol.KIND_MATCH_END,
		{"match_id": "match-1", "winner": GameState.PLAYER_TWO, "score_one": 3, "score_two": 9})["ok"],
		"une fin de partie valide est acceptée")
	_check(not LanProtocol.validate(LanProtocol.KIND_MATCH_END,
		{"match_id": "match-1", "winner": 9, "score_one": 3, "score_two": 9})["ok"],
		"un vainqueur hors des deux camps est refusé")
	_check(not LanProtocol.validate(LanProtocol.KIND_MATCH_END,
		{"match_id": "match-1", "winner": 1, "score_one": 99, "score_two": 9})["ok"],
		"un score impossible est refusé")
	_check(LanProtocol.validate(LanProtocol.KIND_DESYNC,
		{"match_id": "match-1", "sequence": 4, "reason": "États différents."})["ok"],
		"un message de désynchronisation est valide")


func _test_malformed_payloads() -> void:
	_check(not LanProtocol.validate("inconnu", {})["ok"],
		"un type de message inconnu est refusé")
	_check(not LanProtocol.decode("")["ok"], "un message vide est refusé")
	_check(not LanProtocol.decode("pas du json")["ok"], "un message illisible est refusé")
	_check(not LanProtocol.decode("x".repeat(LanProtocol.MAX_MESSAGE_CHARS + 1))["ok"],
		"un message trop long est refusé")
	var foreign := JSON.stringify({"v": LanProtocol.VERSION + 1, "kind": LanProtocol.KIND_BYE,
		"payload": {}})
	_check(not LanProtocol.decode(foreign)["ok"],
		"une enveloppe d'une autre version est refusée")
	var object_payload := JSON.stringify({"v": LanProtocol.VERSION,
		"kind": LanProtocol.KIND_READY, "payload": {"ready": {"script": "res://x.gd"}}})
	_check(not LanProtocol.decode(object_payload)["ok"],
		"une charge utile contenant un objet est refusée")
	var too_many_cards := _hello()
	too_many_cards["deck"] = ProfileFixture.DECK.duplicate() + [ProfileFixture.DECK[0]]
	_check(not LanProtocol.validate(LanProtocol.KIND_HELLO, too_many_cards)["ok"],
		"un deck de neuf cartes est refusé")
	var short_name := _hello("A")
	_check(not LanProtocol.validate(LanProtocol.KIND_HELLO, short_name)["ok"],
		"un pseudo d'un caractère est refusé")
	var long_name := _hello("x".repeat(LanProtocol.MAX_NAME_LENGTH + 1))
	_check(not LanProtocol.validate(LanProtocol.KIND_HELLO, long_name)["ok"],
		"un pseudo trop long est refusé")
	var unknown_god := _hello()
	unknown_god["god_id"] = "ancien_dieu"
	_check(not LanProtocol.validate(LanProtocol.KIND_HELLO, unknown_god)["ok"],
		"un dieu inconnu est refusé")
	var numeric_deck := _hello()
	numeric_deck["deck"] = [1, 2, 3]
	_check(not LanProtocol.validate(LanProtocol.KIND_HELLO, numeric_deck)["ok"],
		"un deck qui ne contient pas des identifiants texte est refusé")
	_check(not LanProtocol.validate(LanProtocol.KIND_BYE, {"x": 1})["ok"],
		"un message de départ avec des clés inconnues est refusé")


func _test_beacon() -> void:
	var beacon := LanProtocol.make_beacon("Hote", LanProtocol.GAME_PORT, 1)
	_check(LanProtocol.validate_beacon(beacon)["ok"], "une annonce de partie est valide")
	var wrong_marker := beacon.duplicate(true)
	wrong_marker["beacon"] = "autre_jeu"
	_check(not LanProtocol.validate_beacon(wrong_marker)["ok"],
		"une annonce d'un autre jeu est ignorée")
	var bad_port := beacon.duplicate(true)
	bad_port["port"] = 70000
	_check(not LanProtocol.validate_beacon(bad_port)["ok"], "un port d'annonce invalide est refusé")
	var bad_players := beacon.duplicate(true)
	bad_players["players"] = 3
	_check(not LanProtocol.validate_beacon(bad_players)["ok"],
		"une annonce de plus de deux joueurs est refusée")
	var future := beacon.duplicate(true)
	future["protocol_version"] = LanProtocol.VERSION + 1
	_check(not LanProtocol.validate_beacon(future)["ok"],
		"une annonce d'une autre version n'est pas proposée au joueur")
