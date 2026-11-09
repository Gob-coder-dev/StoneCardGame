## Intégration réelle des nœuds de campagne avec les règles partagées :
## Classique fixe/généré/profil, Aléatoire, Miroir, Sélection et séries.
extends "res://tests/support/CombatTestSuite.gd"

const ContentLoader := preload("res://scripts/data/campaign/CampaignContentLoader.gd")
const GraphModel := preload("res://scripts/domain/campaign/CampaignGraph.gd")
const ProgressModel := preload("res://scripts/domain/campaign/CampaignProgress.gd")
const StoreModel := preload("res://scripts/data/campaign/CampaignProgressStore.gd")
const ServiceModel := preload("res://scripts/application/campaign/CampaignService.gd")
const Codec := preload("res://scripts/data/PlayerSaveCodec.gd")
const ProfileFixture := preload("res://tests/support/PlayerProfileFixture.gd")
const PATH := "user://campaign_encounter_checks.json"
const BAD_PATH := "user://campaign_encounter_missing_dir/progress.json"

var _service: CampaignService = null
var _graph: CampaignGraph = null
var _fixture: ProfileFixture = null


func run() -> void:
	_cleanup()
	_fixture = ProfileFixture.new()
	var content := ContentLoader.read()
	if not bool(content.get("ok", false)):
		_check(false, "rencontres : le contenu de campagne est valide")
		_fixture.restore()
		return
	_graph = GraphModel.build(content["definition"])
	var progress := ProgressModel.new()
	for node in _graph.nodes():
		progress.mark_completed(node.id)
	_service = ServiceModel.new(_graph, progress, StoreModel.new(PATH), [])
	CampaignContext.set_service_for_tests(_service)
	var profile_before: Dictionary = PlayerData.get_profile()
	_test_tutorial()
	_test_intro_mirrors()
	_test_classic_fixed()
	_test_early_curve()
	_test_random_mode()
	_test_mirror_mode()
	_test_draft_mode()
	_test_special_minis()
	_test_profile_mirror()
	_test_failed_preparation_is_transactional()
	_test_failed_attempt_save_is_transactional()
	_check(PlayerData.get_profile() == profile_before,
		"rencontres : aucun dieu ni deck généré n'est écrit dans le profil permanent")
	BattleContext.clear_campaign_node()
	CampaignContext.reset_for_tests()
	_check(not FileAccess.file_exists(PlayerData._save_path + ".campaign"),
		"rencontres : la campagne ne détourne pas le fichier de profil")
	_fixture.restore()
	_cleanup()


func _cleanup() -> void:
	for path in [PATH, PATH + ".tmp", PATH + ".unreadable", BAD_PATH,
			BAD_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _enter(node_id: String) -> Dictionary:
	var result := CampaignContext.enter_node(node_id)
	_check(bool(result.get("ok", false)), "rencontres : le nœud '%s' se prépare" % node_id)
	if not bool(result.get("ok", false)):
		printerr("  ", result.get("reason", ""))
	return result


func _test_tutorial() -> void:
	var previous_profile := PlayerData.get_profile()
	PlayerData._apply_profile(Codec.starter_profile())
	var result := _enter("tuto_01")
	var npc := BattleContext.current_opponent()
	_check(not bool(result.get("needs_series_session", true))
		and not BattleContext.has_mode_session(),
		"rencontres : le tutoriel reste un combat Classique FT1 sans session")
	_check(str(npc.get("god_id", "")) == "" and str(npc.get("name", "")).contains("Pr.Stone"),
		"rencontres : le premier niveau affronte Pr.Stone sans dieu")
	_check((npc.get("deck", []) as Array) == _graph.node("tuto_01").fixed_deck()
		and (npc.get("deck", []) as Array).size() == DeckRules.DECK_SIZE,
		"rencontres : le tutoriel utilise son deck fixe de huit cartes")
	_check(int(npc.get("bracket_label", "").right(1)) == 1
		and float(npc.get("ai", {}).get("precision", 1.0)) == 0.0,
		"rencontres : le tutoriel est palier 1 et précision 0")
	var setup: Dictionary = npc.get("match_setup", {})
	_check(int(setup.get("board_size", 0)) == 3
		and int(setup.get("player_hand_size", 0)) == 5
		and int(setup.get("opponent_hand_size", 0)) == 4
		and int(setup.get("forced_first_player", 0)) == GameState.PLAYER_HUMAN,
		"rencontres : le profil neuf lance le tutoriel 3 × 3, cinq cartes contre quatre, en premier")
	BattleContext.clear_campaign_node()
	PlayerData._apply_profile(previous_profile)


func _test_intro_mirrors() -> void:
	var expected := {
		"init_veskar": "veskar", "init_nerava": "nerava", "init_kharun": "kharun",
		"init_ilyr": "ilyr", "init_sylkha": "sylkha", "init_enigma": "enigma",
	}
	for node_id in expected:
		var result := _enter(node_id)
		_check(bool(result.get("needs_series_session", false))
			and BattleContext.confirm_mode_preparation()
			and BattleContext.has_prepared_loadouts(),
			"rencontres : l'initiation '%s' prépare son Miroir local" % node_id)
		var one := BattleContext.player_loadout
		var two := BattleContext.opponent_loadout
		var opponent := BattleContext.current_opponent()
		var god_id := str(expected[node_id])
		var all_common_n1 := one != null and one.deck.size() == DeckRules.DECK_SIZE
		if one != null:
			for stone_id in one.deck:
				all_common_n1 = all_common_n1 \
					and StoneLoader.stone_rarity(str(stone_id)) == "common" \
					and StoneLoader.stone_level(str(stone_id)) == 1
		_check(one != null and two != null and one.god_id == god_id
			and two.god_id == god_id and one.deck == two.deck
			and _affinity_count(one.deck, god_id) == 4
			and _affinity_count(one.deck, "neutral") == 4 and all_common_n1
			and BattleContext.forced_first_player == GameState.PLAYER_HUMAN,
			"rencontres : '%s' impose le dieu, un deck commun N1 en 4/4 et le joueur commence" % node_id)
		_check(str(opponent.get("name", "")) == str(opponent.get("combatant_name", ""))
			and not str(opponent.get("name", "")).contains("—")
			and str(opponent.get("encounter_name", "")) != "",
			"rencontres : '%s' sépare le nom court du titre narratif" % node_id)
		BattleContext.clear_campaign_node()


func _test_classic_fixed() -> void:
	_enter("veskar_01")
	var npc := BattleContext.current_opponent()
	var node := _graph.node("veskar_01")
	_check(str(npc.get("god_id", "")) == "veskar"
		and (npc.get("deck", []) as Array) == node.fixed_deck(),
		"rencontres : Classique fixe reprend exactement le dieu et le deck du nœud")
	_check(not BattleContext.has_mode_session(),
		"rencontres : un Classique FT1 n'ouvre pas de session inutile")
	BattleContext.clear_campaign_node()


func _test_early_curve() -> void:
	for node_id in ["veskar_01", "nerava_01", "kharun_01", "ilyr_01", "sylkha_01"]:
		var node := _graph.node(node_id)
		var tier_one := 0
		var tier_two := 0
		for stone_id in node.fixed_deck():
			var tier := CardPowerTierRules.effective_tier(StoneLoader.get_stone(str(stone_id)))
			tier_one += 1 if tier == 1 else 0
			tier_two += 1 if tier == 2 else 0
		_check(node.max_power_tier() == 2 and tier_one == 6 and tier_two == 2
			and float(node.ai_profile().get("precision", 1.0)) <= 0.18,
			"rencontres : '%s' amorce le Carrefour avec six cartes palier 1 et deux palier 2" % node_id)


func _test_random_mode() -> void:
	var result := _enter("veskar_02")
	_check(bool(result.get("needs_series_session", false))
		and BattleContext.has_mode_session(),
		"rencontres : Aléatoire FT2 démarre une session locale")
	_check(BattleContext.confirm_mode_preparation() and BattleContext.has_prepared_loadouts(),
		"rencontres : les loadouts Aléatoire sont confirmés sans réseau")
	_check(BattleContext.player_loadout.is_valid() and BattleContext.opponent_loadout.is_valid()
		and BattleContext.player_loadout.total_quarters
			== BattleContext.opponent_loadout.total_quarters,
		"rencontres : Aléatoire fournit deux decks légaux de même total")
	BattleContext.clear_campaign_node()


func _test_mirror_mode() -> void:
	_enter("mirror_01")
	_check(BattleContext.confirm_mode_preparation() and BattleContext.has_prepared_loadouts(),
		"rencontres : Miroir prépare ses loadouts localement")
	_check(BattleContext.player_loadout.god_id == BattleContext.opponent_loadout.god_id
		and BattleContext.player_loadout.deck == BattleContext.opponent_loadout.deck,
		"rencontres : Miroir copie exactement le dieu et le deck pour les deux camps")
	BattleContext.clear_campaign_node()


func _test_draft_mode() -> void:
	var result := _enter("convergence_01")
	_check(bool(result.get("needs_preparation", false)) and BattleContext.has_mode_session(),
		"rencontres : Sélection ouvre une préparation de draft")
	for index in range(DeckRules.DECK_SIZE):
		var state := BattleContext.mode_state()
		var offers: Array = (state.get("draft", {}) as Dictionary).get("own_offers", [])
		if offers.is_empty():
			break
		if not BattleContext.choose_draft_card(str(offers[0])):
			break
	var state_after := BattleContext.mode_state()
	_check(bool((state_after.get("draft", {}) as Dictionary).get("complete", false)),
		"rencontres : huit choix locaux terminent le draft contre l'IA")
	_check(BattleContext.confirm_mode_preparation() and BattleContext.has_prepared_loadouts(),
		"rencontres : les decks du draft sont installés dans la session")
	_check(BattleContext.player_loadout.deck.size() == DeckRules.DECK_SIZE
		and BattleContext.opponent_loadout.deck.size() == DeckRules.DECK_SIZE
		and BattleContext.player_loadout.total_quarters
			== BattleContext.opponent_loadout.total_quarters,
		"rencontres : Sélection produit deux decks complets de même total")
	BattleContext.clear_campaign_node()


func _test_special_minis() -> void:
	var veskar := _enter("r03_mini")
	_check(bool(veskar.get("needs_series_session", false)),
		"rencontres : Véskar conserve une série FT2")
	_check(BattleContext.confirm_mode_preparation() and BattleContext.has_prepared_loadouts(),
		"rencontres : Véskar prépare ses decks locaux")
	var veskar_one := BattleContext.player_loadout
	var veskar_two := BattleContext.opponent_loadout
	_check(veskar_one.god_id == "veskar" and veskar_two.god_id == "veskar"
		and _affinity_count(veskar_one.deck, "veskar") == DeckRules.DECK_SIZE
		and _affinity_count(veskar_two.deck, "veskar") == DeckRules.DECK_SIZE,
		"rencontres : Véskar génère deux decks 100 % Aléators")
	_check(veskar_one.total_quarters == veskar_two.total_quarters,
		"rencontres : les decks purs de Véskar gardent un total identique")
	BattleContext.clear_campaign_node()

	var ilyr := _enter("r09_mini1")
	_check(bool(ilyr.get("needs_series_session", false)),
		"rencontres : Ilyr conserve une série FT2")
	_check(BattleContext.confirm_mode_preparation() and BattleContext.has_prepared_loadouts(),
		"rencontres : Ilyr prépare son Miroir local")
	var mirror_one := BattleContext.player_loadout
	var mirror_two := BattleContext.opponent_loadout
	var ilyr_node := _graph.node("r09_mini1")
	_check(mirror_one.god_id == "ilyr" and mirror_two.god_id == "ilyr"
		and mirror_one.deck == mirror_two.deck
		and mirror_one.deck == ilyr_node.mirror_fixed_deck(),
		"rencontres : Ilyr copie exactement son deck miroir fixe")
	_check(_affinity_count(mirror_one.deck, "ilyr") == 7,
		"rencontres : le deck miroir d'Ilyr contient sept Veilleurs sur huit cartes")
	BattleContext.clear_campaign_node()

	for index in range(1, 5):
		var path_id := "r09_mini1_path_%d" % index
		_enter(path_id)
		_check(BattleContext.confirm_mode_preparation()
			and _affinity_count(BattleContext.player_loadout.deck, "ilyr") >= 7,
			"rencontres : l'approche '%s' génère au moins sept cartes Ilyr" % path_id)
		BattleContext.clear_campaign_node()

	var fixed_checks := [
		["mini_optional_01", "nerava", 2, 0.80, false],
		["r04_mini", "sylkha", 2, 0.85, false],
		["r11_mini", "kharun", 4, 0.95, true],
		["mini_optional_02", "enigma", 4, 1.0, true],
	]
	for entry in fixed_checks:
		var node_id := str(entry[0])
		var god_id := str(entry[1])
		_enter(node_id)
		var npc := BattleContext.current_opponent()
		var node := _graph.node(node_id)
		var ai := npc.get("ai", {}) as Dictionary
		_check(str(npc.get("god_id", "")) == god_id
			and (npc.get("deck", []) as Array) == node.fixed_deck()
			and int(node.max_power_tier()) == int(entry[2]),
			"rencontres : le mini-boss '%s' reste fixe à son dieu, son deck et son palier" % node_id)
		_check(is_equal_approx(float(ai.get("precision", -1.0)), float(entry[3]))
			and bool(ai.get("anticipation", false)) == bool(entry[4]),
			"rencontres : le mini-boss '%s' conserve son IA signée" % node_id)
		_check(node.series_format() == SeriesRules.SERIES_FT2,
			"rencontres : le mini-boss '%s' reste en FT2" % node_id)
		BattleContext.clear_campaign_node()


func _affinity_count(deck: Array, god_id: String) -> int:
	var count := 0
	for raw_id in deck:
		if StoneLoader.stone_affinity(str(raw_id)) == god_id:
			count += 1
	return count


func _test_profile_mirror() -> void:
	_enter("choice_01")
	var npc := BattleContext.current_opponent()
	_check(str(npc.get("god_id", "")) == PlayerData.player_god_id
		and (npc.get("deck", []) as Array) == PlayerData.get_active_deck(),
		"rencontres : Classique profil reprend le dieu et le deck du joueur pour l'adversaire")
	BattleContext.clear_campaign_node()


func _test_failed_preparation_is_transactional() -> void:
	var node: CampaignNode = _graph.node("r09_mini1_path_1")
	var original := node.encounter.duplicate(true)
	node.encounter["generator_min_god_cards"] = DeckRules.DECK_SIZE + 1
	var attempts_before := _service.progress().attempts_for(node.id)
	var result := CampaignContext.enter_node(node.id)
	_check(not bool(result.get("ok", true))
		and _service.progress().attempts_for(node.id) == attempts_before
		and not BattleContext.has_campaign_node(),
		"rencontres : une préparation invalide ne consomme aucune tentative et ne publie aucun contexte")
	node.encounter = original


func _test_failed_attempt_save_is_transactional() -> void:
	BattleContext.clear_campaign_node()
	var progress := _service.progress().duplicate_progress()
	var failing_service := ServiceModel.new(_graph, progress,
		StoreModel.new(BAD_PATH), [])
	CampaignContext.set_service_for_tests(failing_service)
	var attempts_before := progress.attempts_for("veskar_02")
	var result := CampaignContext.enter_node("veskar_02")
	_check(not bool(result.get("ok", true))
		and failing_service.progress().attempts_for("veskar_02") == attempts_before
		and not BattleContext.has_campaign_node()
		and not BattleContext.has_mode_session(),
		"rencontres : un échec de sauvegarde ne publie ni tentative ni session partielle")
	CampaignContext.set_service_for_tests(_service)
