## Régressions des modes partagés hors réseau : modèles génériques, préparation
## locale de campagne, draft IA et conservation des loadouts selon le format.
extends "res://tests/support/CombatTestSuite.gd"

const ProfileFixture := preload("res://tests/support/PlayerProfileFixture.gd")
const SessionModel := preload("res://scripts/application/CampaignModeSession.gd")


func run() -> void:
	_test_generic_loadout()
	_test_classic_series()
	_test_random_series()
	_test_constrained_modes()
	_test_local_draft()


func _profile(god_id: String = "veskar") -> Dictionary:
	return {"name": god_id, "god_id": god_id, "deck": ProfileFixture.DECK.duplicate()}


func _config(mode: String, format: String = SeriesRules.SERIES_FT1,
		tier: int = GameModeRules.MAX_POWER_TIER,
		constraints: Dictionary = {}) -> Dictionary:
	var result := {"mode": mode, "series": format, "power_tier": tier}
	result.merge(constraints, true)
	return result


func _test_generic_loadout() -> void:
	var loadout := GameLoadout.create("veskar", ProfileFixture.DECK, 42)
	var data := loadout.to_dict()
	_check(loadout.is_valid() and data.get("god_id") == "veskar",
		"modes partagés : le loadout générique contient un dieu et un deck valides")
	_check(not data.has("series_id") and not data.has("preparation_id")
		and not data.has("rules_revision"),
		"modes partagés : le loadout générique ne contient aucune métadonnée PVP")
	_check(MatchRules.MODE_RANDOM == GameModeRules.MODE_RANDOM
		and MatchRules.SERIES_FT2 == SeriesRules.SERIES_FT2,
		"modes partagés : la façade historique délègue aux règles spécialisées")


func _test_classic_series() -> void:
	var session := SessionModel.new()
	var configured := session.configure(_config(GameModeRules.MODE_CLASSIC,
		SeriesRules.SERIES_FT2), _profile(), _profile(), 100)
	_check(bool(configured.get("ok", false)) and session.loadout_one() != null,
		"campagne : une série Classique prépare ses deux loadouts sans réseau")
	var first_deck := session.loadout_one().deck
	_check(session.confirm_local(), "campagne : la préparation locale se confirme sans pair distant")
	var round := session.record_round(GameState.PLAYER_ONE, 9, 4)
	_check(bool(round.get("ok", false)) and not session.series().finished,
		"campagne : une première victoire FT2 ouvre une manche suivante")
	var next := session.prepare_round()
	_check(bool(next.get("ok", false)) and bool(next.get("reused", false))
		and session.loadout_one().deck == first_deck,
		"campagne : Classique conserve le deck entre les manches")
	session.record_round(GameState.PLAYER_ONE, 8, 5)
	_check(session.series().finished and session.series().winner == GameState.PLAYER_ONE,
		"campagne : la série locale se termine au seuil FT2")


func _test_random_series() -> void:
	var session := SessionModel.new()
	var configured := session.configure(_config(GameModeRules.MODE_RANDOM,
		SeriesRules.SERIES_FT2, 1), _profile(), _profile(), 200)
	_check(bool(configured.get("ok", false)) and session.loadout_one().is_valid()
		and session.loadout_two().is_valid(),
		"campagne : Aléatoire palier 1 génère deux loadouts locaux valides")
	var first_one := session.loadout_one().to_dict()
	var first_two := session.loadout_two().to_dict()
	session.record_round(GameState.PLAYER_TWO, 3, 9)
	var next := session.prepare_round()
	var changed := session.loadout_one().to_dict() != first_one \
		or session.loadout_two().to_dict() != first_two
	_check(bool(next.get("ok", false)) and not bool(next.get("reused", true)) and changed,
		"campagne : Aléatoire régénère les loadouts à la manche suivante")


func _test_constrained_modes() -> void:
	var random_session := SessionModel.new()
	var random_config := _config(GameModeRules.MODE_RANDOM, SeriesRules.SERIES_FT2, 3, {
		"generator_god_id": "veskar",
		"generator_min_god_cards": DeckRules.DECK_SIZE,
	})
	var random_ready := random_session.configure(random_config, _profile(), _profile(), 400)
	var random_one := random_session.loadout_one()
	var random_two := random_session.loadout_two()
	_check(bool(random_ready.get("ok", false)) and random_one != null and random_two != null
		and random_one.god_id == "veskar" and random_two.god_id == "veskar"
		and _affinity_count(random_one.deck, "veskar") == DeckRules.DECK_SIZE
		and _affinity_count(random_two.deck, "veskar") == DeckRules.DECK_SIZE,
		"campagne : un Aléatoire contraint peut imposer Véskar et deux decks purs")
	_check(random_one.total_quarters == random_two.total_quarters,
		"campagne : les decks purs contraints gardent le même total")

	var ilyr_deck := [
		"longuepine_n4", "pique_en_haut_n4", "fauche_fond_n4",
		"bouche_arbalete_n4", "veilleur_bifurque_n1", "perce_voute_n1",
		"dard_de_traverse_n2", "avortons_des_caves_n1",
	]
	var mirror_session := SessionModel.new()
	var mirror_config := _config(GameModeRules.MODE_MIRROR, SeriesRules.SERIES_FT2, 4, {
		"generator_god_id": "ilyr",
		"generator_min_god_cards": 7,
		"mirror_fixed_deck": ilyr_deck,
	})
	var mirror_ready := mirror_session.configure(mirror_config, _profile(), _profile(), 500)
	var mirror_one := mirror_session.loadout_one()
	var mirror_two := mirror_session.loadout_two()
	_check(bool(mirror_ready.get("ok", false)) and mirror_one != null and mirror_two != null
		and mirror_one.god_id == "ilyr" and mirror_two.god_id == "ilyr"
		and mirror_one.deck == ilyr_deck and mirror_two.deck == ilyr_deck,
		"campagne : un Miroir contraint peut imposer un deck Ilyr exact")


func _affinity_count(deck: Array, god_id: String) -> int:
	var count := 0
	for raw_id in deck:
		if StoneLoader.stone_affinity(str(raw_id)) == god_id:
			count += 1
	return count


func _test_local_draft() -> void:
	var session := SessionModel.new()
	var configured := session.configure(_config(GameModeRules.MODE_DRAFT),
		_profile("veskar"), _profile("nerava"), 300)
	_check(bool(configured.get("ok", false)) and bool(configured.get("requires_draft", false)),
		"campagne : Sélection démarre un draft local sans transport réseau")
	var guard := 0
	while session.loadout_one() == null and guard < DeckRules.DECK_SIZE:
		var state := session.public_state()
		var offers: Array = (state.get("draft", {}) as Dictionary).get("own_offers", [])
		if offers.is_empty() or not session.choose_player(str(offers[0])):
			break
		guard += 1
	_check(guard == DeckRules.DECK_SIZE and session.loadout_one() != null
		and session.loadout_two() != null,
		"campagne : huit choix du joueur et huit décisions IA produisent deux decks")
	_check(session.loadout_one().is_valid() and session.loadout_two().is_valid()
		and session.loadout_one().total_quarters == session.loadout_two().total_quarters,
		"campagne : les decks de Sélection sont légaux et de même total")
