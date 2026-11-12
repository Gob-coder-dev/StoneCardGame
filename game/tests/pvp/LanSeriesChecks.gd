## Série PVP locale : draft parallèle, confidentialité, timeout et lancement
## Classique FT2/FT3. Aucun socket réel.
extends "res://tests/support/CombatTestSuite.gd"

const Fake := preload("res://tests/support/FakeLanTransport.gd")
const SeriesCoordinator := preload("res://scripts/network/LanSeriesCoordinator.gd")
const DraftModel := preload("res://scripts/domain/DraftEngine.gd")
const RulesModel := preload("res://scripts/domain/MatchRules.gd")
const ProfileFixture := preload("res://tests/support/PlayerProfileFixture.gd")


class Recorder extends RefCounted:
	var rounds_host: Array = []
	var rounds_client: Array = []
	var errors_host: Array = []
	var errors_client: Array = []

	func on_host_round(config: Dictionary) -> void:
		rounds_host.append(config)

	func on_client_round(config: Dictionary) -> void:
		rounds_client.append(config)

	func on_host_error(message: String) -> void:
		errors_host.append(message)

	func on_client_error(message: String) -> void:
		errors_client.append(message)


func _profiles(mode: String) -> Dictionary:
	var host_deck: Array = ProfileFixture.DECK.duplicate() if mode == RulesModel.MODE_CLASSIC else []
	# Le deck de campagne fourni par la fixture appartient à véskar : les deux
	# camps Classique doivent donc utiliser le même dieu pour être valides.
	var client_god := "veskar" if mode == RulesModel.MODE_CLASSIC else "nerava"
	return {
		"host": {"name": "Hote", "god_id": "veskar", "deck": host_deck},
		"client": {"name": "Client", "god_id": client_god, "deck": host_deck.duplicate()},
	}


func _rules(mode: String, series: String, tier: int = 4) -> Dictionary:
	var rules := RulesModel.default_config()
	rules["mode"] = mode
	rules["series"] = series
	rules["power_tier"] = tier
	rules["locked"] = true
	return rules


func _pair(mode: String, series: String, tier: int = 4) -> Dictionary:
	var profiles := _profiles(mode)
	var host_transport := Fake.new()
	host_transport.local_id = 1
	var client_transport := Fake.new()
	client_transport.local_id = 2
	host_transport.remote = client_transport
	client_transport.remote = host_transport
	var recorder := Recorder.new()
	var host := SeriesCoordinator.new()
	var client := SeriesCoordinator.new()
	var rules := _rules(mode, series, tier)
	host.attach(host_transport, true, GameState.PLAYER_ONE, 2,
		profiles["host"], profiles["client"], rules, 424242)
	client.attach(client_transport, false, GameState.PLAYER_TWO, 0,
		profiles["client"], profiles["host"], rules)
	host.round_ready.connect(recorder.on_host_round)
	client.round_ready.connect(recorder.on_client_round)
	host.failed.connect(recorder.on_host_error)
	client.failed.connect(recorder.on_client_error)
	host.host_start_series()
	return {
		"host": host, "client": client, "host_transport": host_transport,
		"client_transport": client_transport, "recorder": recorder,
		"rounds_host": recorder.rounds_host, "rounds_client": recorder.rounds_client,
		"errors_host": recorder.errors_host, "errors_client": recorder.errors_client,
	}


func run() -> void:
	_test_parallel_draft_host_first()
	_test_parallel_draft_client_first()
	_test_draft_offers_project_viewer_step()
	_test_client_receives_live_draft_deadline()
	_test_draft_timeout_with_one_finished()
	_test_draft_determinism_and_privacy()
	_test_classic_ft2_initializes_both_clients()
	_test_classic_ft3_initializes_both_clients()
	_test_classic_ignores_power_tier()
	_test_random_and_mirror_still_work()
	_test_invalid_draft_messages()


func _choose_all(flow: LanSeriesCoordinator) -> bool:
	for step in range(DeckRules.DECK_SIZE):
		var state := flow.public_state()
		var offers: Array = state["draft"]["own_offers"]
		if step == DeckRules.DECK_SIZE - 1 and offers.size() != 2:
			return false
		if not flow.choose_local(str(offers[0])):
			return false
	return true


func _test_client_receives_live_draft_deadline() -> void:
	var pair := _pair(RulesModel.MODE_DRAFT, RulesModel.SERIES_FT1)
	var host: LanSeriesCoordinator = pair["host"]
	var client: LanSeriesCoordinator = pair["client"]
	var host_remaining := host.remaining_seconds()
	var client_remaining := client.remaining_seconds()
	_check(host_remaining > 0.0 and client_remaining > 0.0,
		"timer draft : l'hôte et le client reçoivent une échéance active")
	_check(absf(host_remaining - client_remaining) < 1.0,
		"timer draft : le client calcule le même temps restant que l'hôte")
	host.close()
	client.close()


func _test_parallel_draft_host_first() -> void:
	var pair := _pair(RulesModel.MODE_DRAFT, RulesModel.SERIES_FT1)
	var host: LanSeriesCoordinator = pair["host"]
	var client: LanSeriesCoordinator = pair["client"]
	_check(_choose_all(host), "draft parallèle : l'hôte effectue ses huit choix sans le client")
	var host_state := host.public_state()
	var client_state := client.public_state()
	_check(bool(host_state.get("own_draft_complete", false))
		and (host_state["own_loadout"] as Dictionary).get("deck", []).size() == 8,
		"draft parallèle : le premier deck terminé obtient immédiatement son loadout")
	_check(str(host_state["phase"]) == RulesModel.PHASE_PREPARING,
		"draft parallèle : le premier deck ne termine pas globalement la préparation")
	_check(int(client_state["draft"]["own_step"]) == 0
		and (client_state["draft"]["own_offers"] as Array).size() == 2
		and bool(client_state["draft"]["complete_one"]),
		"draft parallèle : le client resté à zéro conserve ses offres")
	_check(host.confirm_local(), "draft parallèle : le premier joueur peut se déclarer PRÊT")
	_check(bool(host.public_state()["own_ready"]) and (pair["rounds_host"] as Array).is_empty(),
		"draft parallèle : PRÊT seul ne lance pas la manche")
	_check(_choose_all(client), "draft parallèle : le client termine ensuite ses huit choix")
	var client_state_after := client.public_state()
	_check((client_state_after["own_loadout"] as Dictionary).get("deck", []).size() == 8
		and bool(client_state_after.get("own_draft_complete", false)),
		"draft parallèle : le second deck est construit sans blocage")
	var host_loadout: Dictionary = host.public_state()["own_loadout"]
	var client_loadout: Dictionary = client.public_state()["own_loadout"]
	_check(int(host_loadout["total_quarters"]) == int(client_loadout["total_quarters"]),
		"draft parallèle : les deux decks ont exactement le même total")
	_check(_lineages_unique((host_loadout["deck"] as Array), host._draft.generator)
		and _lineages_unique((client_loadout["deck"] as Array), host._draft.generator),
		"draft parallèle : toutes les lignées restent uniques")
	_check(client.confirm_local(), "draft parallèle : le second PRÊT est accepté")
	_check((pair["rounds_host"] as Array).size() == 1
		and (pair["rounds_client"] as Array).size() == 1,
		"draft parallèle : la manche démarre seulement après les deux PRÊT")
	_check(pair["rounds_host"][0] == pair["rounds_client"][0],
		"draft parallèle : les deux appareils reçoivent la même configuration")
	_check(not client.public_state().has("opponent_deck")
		and not (client.public_state()["draft"] as Dictionary).has("opponent_deck")
		and not (client.public_state()["draft"] as Dictionary).has("own_choice"),
		"draft parallèle : aucun deck ni choix adverse n'est exposé")
	_check((pair["errors_host"] as Array).is_empty() and (pair["errors_client"] as Array).is_empty(),
		"draft parallèle : aucune erreur réseau")
	host.close()
	client.close()


func _test_parallel_draft_client_first() -> void:
	var pair := _pair(RulesModel.MODE_DRAFT, RulesModel.SERIES_FT1)
	var host: LanSeriesCoordinator = pair["host"]
	var client: LanSeriesCoordinator = pair["client"]
	_check(_choose_all(client), "draft inversé : le client effectue ses huit choix en premier")
	_check((client.public_state()["own_loadout"] as Dictionary).get("deck", []).size() == 8
		and int(host.public_state()["draft"]["own_step"]) == 0,
		"draft inversé : le client obtient son deck sans avancer l'hôte")
	_check(client.confirm_local(), "draft inversé : le client peut se déclarer PRÊT")
	_check(_choose_all(host), "draft inversé : l'hôte termine ensuite ses huit choix")
	_check(int(host.public_state()["draft"]["own_step"]) == 8
		and (host.public_state()["own_loadout"] as Dictionary).get("deck", []).size() == 8,
		"draft inversé : la dernière carte de l'hôte reste sélectionnable")
	_check(host.confirm_local(), "draft inversé : l'hôte confirme après le client")
	_check((pair["rounds_host"] as Array).size() == 1
		and (pair["rounds_client"] as Array).size() == 1,
		"draft inversé : la manche démarre sur les deux appareils")
	host.close()
	client.close()


func _test_draft_offers_project_viewer_step() -> void:
	var pair := _pair(RulesModel.MODE_DRAFT, RulesModel.SERIES_FT1)
	var host: LanSeriesCoordinator = pair["host"]
	var client: LanSeriesCoordinator = pair["client"]
	# Le client avance seul : l'hôte reste à l'étape 0 et doit pourtant voir la
	# paire du client prévue pour l'étape 0, pas sa paire courante (étape 5).
	for index in range(5):
		var client_offers: Array = client.public_state()["draft"]["own_offers"]
		_check(client.choose_local(str(client_offers[0])),
			"projection réseau : le client avance indépendamment")
	var host_view: Dictionary = host.public_state()["draft"]
	var client_view: Dictionary = client.public_state()["draft"]
	_check(int(host_view["own_step"]) == 0 and int(host_view["opponent_step"]) == 5,
		"projection réseau : l'hôte voit 0 / 5 sans avancer")
	_check(host_view["offers_two"] == host._draft.offers_for_step(GameState.PLAYER_TWO, 0)
		and host_view["offers_two"] != host._draft.offers_for(GameState.PLAYER_TWO),
		"projection réseau : l'hôte voit la paire adverse de son étape 0")
	_check(client_view["offers_one"] == host._draft.offers_for_step(GameState.PLAYER_ONE, 5)
		and int(client_view["offers_step"]) == 5,
		"projection réseau : le client voit la paire de l'hôte à sa propre étape 5")
	# L'hôte avance à son tour : le client doit recevoir la paire de l'hôte
	# projetée sur l'étape 5 du client, et non la paire courante de l'hôte (1).
	var host_offers: Array = host.public_state()["draft"]["own_offers"]
	_check(host.choose_local(str(host_offers[0])),
		"projection réseau : l'hôte avance après le client")
	client_view = client.public_state()["draft"]
	_check(int(client_view["own_step"]) == 5 and int(client_view["opponent_step"]) == 1,
		"projection réseau : le client voit 5 / 1")
	_check(client_view["offers_one"] == host._draft.offers_for_step(GameState.PLAYER_ONE, 5)
		and client_view["offers_one"] != host._draft.offers_for(GameState.PLAYER_ONE),
		"projection réseau : le client voit la paire de l'hôte à son étape 5")
	host_view = host.public_state()["draft"]
	_check(host_view["offers_two"] == host._draft.offers_for_step(GameState.PLAYER_TWO, 1),
		"projection réseau : l'hôte voit la paire du client à sa nouvelle étape 1")
	_check(not host_view.has("opponent_deck") and not client_view.has("opponent_deck"),
		"projection réseau : aucune projection n'expose le deck adverse")
	_check((pair["errors_host"] as Array).is_empty() and (pair["errors_client"] as Array).is_empty(),
		"projection réseau : aucune erreur de validation")
	host.close()
	client.close()


func _test_draft_timeout_with_one_finished() -> void:
	var pair := _pair(RulesModel.MODE_DRAFT, RulesModel.SERIES_FT1)
	var host: LanSeriesCoordinator = pair["host"]
	var client: LanSeriesCoordinator = pair["client"]
	_check(_choose_all(host), "timeout : l'hôte termine son deck avant l'expiration")
	_check(host.confirm_local(), "timeout : l'hôte est PRÊT avant l'expiration")
	host.poll(DraftModel.DEFAULT_DURATION_SECONDS + 1.0)
	var client_state := client.public_state()
	_check((client_state["own_loadout"] as Dictionary).get("deck", []).size() == 8
		and bool(client_state.get("own_draft_complete", false)),
		"timeout : le deck incomplet du client est complété indépendamment")
	_check(bool(host.public_state()["own_ready"]),
		"timeout : le joueur déjà prêt n'est pas réinitialisé")
	_check(client.confirm_local() and (pair["rounds_host"] as Array).size() == 1,
		"timeout : la manche démarre après le PRÊT du joueur complété")
	host.close()
	client.close()


func _test_draft_determinism_and_privacy() -> void:
	var first := DraftModel.new()
	var second := DraftModel.new()
	var a := first.start(424242, "veskar", "nerava", 4)
	var b := second.start(424242, "veskar", "nerava", 4)
	_check(bool(a.get("ok", false)) and bool(b.get("ok", false)),
		"déterminisme : un plan de huit paires existe pour veskar contre nerava")
	if bool(a.get("ok", false)) and bool(b.get("ok", false)):
		_check(first.all_offers() == second.all_offers(),
			"déterminisme : la même graine produit exactement les mêmes offres")
		_check(first.public_state(GameState.PLAYER_ONE).get("own_deck", []).is_empty()
			and not first.public_state(GameState.PLAYER_ONE).has("opponent_deck"),
			"confidentialité : la vue d'un camp ne contient jamais le deck adverse")


func _test_classic_ft2_initializes_both_clients() -> void:
	var pair := _pair(RulesModel.MODE_CLASSIC, RulesModel.SERIES_FT2)
	_assert_classic_round(pair, RulesModel.SERIES_FT2)
	(pair["host"] as LanSeriesCoordinator).close()
	(pair["client"] as LanSeriesCoordinator).close()


func _test_classic_ft3_initializes_both_clients() -> void:
	var pair := _pair(RulesModel.MODE_CLASSIC, RulesModel.SERIES_FT3)
	_assert_classic_round(pair, RulesModel.SERIES_FT3)
	(pair["host"] as LanSeriesCoordinator).close()
	(pair["client"] as LanSeriesCoordinator).close()


func _test_classic_ignores_power_tier() -> void:
	var pair := _pair(RulesModel.MODE_CLASSIC, RulesModel.SERIES_FT1,
		RulesModel.MIN_POWER_TIER)
	_check((pair["rounds_host"] as Array).size() == 1
		and (pair["rounds_client"] as Array).size() == 1
		and (pair["errors_host"] as Array).is_empty(),
		"classique : le palier masqué ne filtre jamais le deck enregistré")
	(pair["host"] as LanSeriesCoordinator).close()
	(pair["client"] as LanSeriesCoordinator).close()


func _assert_classic_round(pair: Dictionary, series: String) -> void:
	var host: LanSeriesCoordinator = pair["host"]
	var client: LanSeriesCoordinator = pair["client"]
	_check((pair["rounds_host"] as Array).size() == 1
		and (pair["rounds_client"] as Array).size() == 1,
		"classique %s : l'hôte et le client reçoivent une configuration de manche" % series)
	if (pair["rounds_host"] as Array).is_empty() or (pair["rounds_client"] as Array).is_empty():
		return
	var host_config: Dictionary = pair["rounds_host"][0]
	var client_config: Dictionary = pair["rounds_client"][0]
	_check(host_config == client_config, "classique %s : les deux configurations sont identiques" % series)
	_check(str(host_config.get("series_id", "")) != ""
		and str(host_config.get("preparation_id", "")) != ""
		and str(host_config.get("match_id", "")) != "",
		"classique %s : series_id, preparation_id et match_id sont initialisés" % series)
	_check(host.phase() == RulesModel.PHASE_IN_MATCH
		and client.phase() == RulesModel.PHASE_IN_MATCH,
		"classique %s : les deux appareils quittent RULES_READY pour IN_MATCH" % series)
	_check((pair["errors_host"] as Array).is_empty() and (pair["errors_client"] as Array).is_empty(),
		"classique %s : aucune erreur d'identifiants" % series)


func _test_random_and_mirror_still_work() -> void:
	for mode in [RulesModel.MODE_RANDOM, RulesModel.MODE_MIRROR]:
		for tier in [1, 4]:
			var pair := _pair(mode, RulesModel.SERIES_FT1, tier)
			var host: LanSeriesCoordinator = pair["host"]
			var client: LanSeriesCoordinator = pair["client"]
			var host_loadout: Dictionary = host.public_state()["own_loadout"]
			var client_loadout: Dictionary = client.public_state()["own_loadout"]
			_check((host_loadout.get("deck", []) as Array).size() == 8
				and (client_loadout.get("deck", []) as Array).size() == 8,
				"%s palier %d : les deux decks sont générés" % [
					RulesModel.mode_label(mode), tier])
			_check(int(host_loadout.get("total_quarters", -1))
				== int(client_loadout.get("total_quarters", -2)),
				"%s palier %d : les deux decks ont exactement le même total" % [
					RulesModel.mode_label(mode), tier])
			_check(host.confirm_local() and client.confirm_local(),
				"%s palier %d : les deux confirmations restent acceptées" % [
					RulesModel.mode_label(mode), tier])
			_check((pair["rounds_host"] as Array).size() == 1
				and (pair["rounds_client"] as Array).size() == 1,
				"%s palier %d : une manche démarre sur les deux appareils" % [
					RulesModel.mode_label(mode), tier])
			host.close()
			client.close()


func _test_invalid_draft_messages() -> void:
	var pair := _pair(RulesModel.MODE_DRAFT, RulesModel.SERIES_FT1)
	var host: LanSeriesCoordinator = pair["host"]
	var client_transport: Fake = pair["client_transport"]
	var before := str(host.public_state()["draft"]["own_offers"])
	var stale := {
		"series_id": host.series_id(),
		"preparation_id": "ancienne-preparation",
		"rules_revision": 0,
		"round_index": 1,
		"own_step": 0,
		"stone_id": "de_boiteux_n1",
	}
	client_transport.push(2, LanProtocol.KIND_DRAFT_CHOICE, stale)
	_check(str(host.public_state()["draft"]["own_offers"]) == before,
		"draft : un choix d'une ancienne préparation est ignoré")
	_check((pair["errors_host"] as Array).is_empty(),
		"draft : un ancien message ne provoque pas d'erreur Godot")
	host.close()
	(pair["client"] as LanSeriesCoordinator).close()


func _lineages_unique(deck: Array, generator: LoadoutGenerator) -> bool:
	var seen := {}
	for stone_id in deck:
		var lineage := generator.lineage_of(str(stone_id))
		if lineage == "" or seen.has(lineage):
			return false
		seen[lineage] = true
	return true
