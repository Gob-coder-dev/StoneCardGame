## Régressions des modes partagés hors réseau : modèles génériques, préparation
## locale de campagne, draft IA et conservation des loadouts selon le format.
extends "res://tests/support/CombatTestSuite.gd"

const ProfileFixture := preload("res://tests/support/PlayerProfileFixture.gd")
const SessionModel := preload("res://scripts/application/CampaignModeSession.gd")


func run() -> void:
	_test_generic_loadout()
	_test_classic_series()
	_test_random_series()
	_test_local_draft()


func _profile(god_id: String = "veskar") -> Dictionary:
	return {"name": god_id, "god_id": god_id, "deck": ProfileFixture.DECK.duplicate()}


func _config(mode: String, format: String = SeriesRules.SERIES_FT1,
		tier: int = GameModeRules.MAX_POWER_TIER) -> Dictionary:
	return {"mode": mode, "series": format, "power_tier": tier}


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
