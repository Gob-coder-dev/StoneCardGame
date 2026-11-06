## Vérifie le domaine pur des modes PVP, sans scène ni socket :
## paliers de puissance, Aléatoire, Miroir, draft Sélection, séries et salon.
extends "res://tests/support/CombatTestSuite.gd"

const PowerRules := preload("res://scripts/domain/CardPowerTierRules.gd")
const GeneratorModel := preload("res://scripts/domain/LoadoutGenerator.gd")
const DraftModel := preload("res://scripts/domain/DraftEngine.gd")
const RulesModel := preload("res://scripts/domain/MatchRules.gd")
const SeriesModel := preload("res://scripts/domain/SeriesState.gd")
const SeriesEngineModel := preload("res://scripts/domain/SeriesEngine.gd")
const LoadoutModel := preload("res://scripts/domain/Loadout.gd")


func run() -> void:
	_test_power_tiers()
	_test_random()
	_test_mirror()
	_test_draft()
	_test_series()
	_test_lobby_rules()


func _god_ids() -> Array:
	var result: Array = []
	for god in StoneLoader.get_all_gods():
		result.append(str(god["id"]))
	return result


func _first_form(rarity: String, level: int = 1) -> Dictionary:
	for stone in StoneLoader.get_all_stones():
		if str(stone.get("rarity", "")) == rarity and int(stone.get("level", 0)) == level:
			return stone
	return {}


func _test_power_tiers() -> void:
	var legendary := _first_form("legendary", 1)
	var rare := _first_form("rare", 1)
	var epic := _first_form("epic", 1)
	var common_one := _first_form("common", 1)
	var common_two := _first_form("common", 2)
	_check(not legendary.is_empty() and not rare.is_empty() and not epic.is_empty()
		and not common_one.is_empty() and not common_two.is_empty(),
		"paliers : les formes de référence existent dans le catalogue")
	_check(PowerRules.effective_tier(legendary) == 4,
		"paliers : une légendaire niveau 1 vaut le palier 4")
	_check(not PowerRules.is_allowed(legendary, 1)
		and not PowerRules.is_allowed(legendary, 2)
		and not PowerRules.is_allowed(legendary, 3)
		and PowerRules.is_allowed(legendary, 4),
		"paliers : une légendaire niveau 1 est refusée sous le palier 4")
	_check(not PowerRules.is_allowed(rare, 1) and PowerRules.is_allowed(rare, 2),
		"paliers : une rare niveau 1 entre à partir du palier 2")
	_check(not PowerRules.is_allowed(epic, 2) and PowerRules.is_allowed(epic, 3),
		"paliers : une épique niveau 1 entre à partir du palier 3")
	_check(PowerRules.is_allowed(common_one, 1) and PowerRules.is_allowed(common_one, 4),
		"paliers : une commune niveau 1 reste autorisée aux paliers supérieurs")
	_check(not PowerRules.is_allowed(common_two, 1) and PowerRules.is_allowed(common_two, 2),
		"paliers : une commune niveau 2 exige le palier 2")

	var exception := {"id": "exception", "rarity": "legendary", "level": 1, "power_tier": 4}
	_check(PowerRules.tier_problem(exception) == "" and PowerRules.effective_tier(exception) == 4,
		"paliers : une exception power_tier valide remplace la formule")
	var invalid := exception.duplicate()
	invalid["power_tier"] = 5
	_check(PowerRules.tier_problem(invalid) != "",
		"paliers : une exception hors bornes est refusée")

	var coherent := {
		"id": "fx_coherent", "rarity": "common",
		"levels": [{"id": "fx_c1"}, {"id": "fx_c2"}, {"id": "fx_c3"}, {"id": "fx_c4"}],
	}
	_check(PowerRules.lineage_problems(coherent).is_empty(),
		"paliers : une lignée commune cohérente ne produit aucune erreur")
	var decreasing := {
		"id": "fx_decreasing", "rarity": "rare",
		"levels": [{"id": "fx_r1"}, {"id": "fx_r2"}, {"id": "fx_r3", "power_tier": 2}],
	}
	_check(not PowerRules.lineage_problems(decreasing).is_empty(),
		"paliers : une baisse explicite de palier dans une évolution est signalée")


func _card(id: String, lineage: String, cost_q: int, god_id: String = "veskar",
		tier: int = 1) -> Dictionary:
	return {
		"id": id,
		"lineage_id": lineage,
		"god_id": god_id,
		"rarity": "common",
		"level": 1,
		"power_tier": tier,
		"cost_q": cost_q,
	}


func _validate_deck(gen: LoadoutGenerator, deck: Array, god_id: String,
		max_tier: int, total_q: int) -> bool:
	if deck.size() != DeckRules.DECK_SIZE:
		return false
	var lineages := {}
	var sum := 0
	for raw_id in deck:
		var stone_id := str(raw_id)
		var card := gen.card(stone_id)
		if card.is_empty() or int(card["tier"]) > max_tier:
			return false
		var affinity := str(card["god_id"])
		if affinity != "neutral" and affinity != god_id:
			return false
		if lineages.has(str(card["lineage"])):
			return false
		lineages[str(card["lineage"])] = true
		sum += int(card["cost_q"])
	return sum == total_q and sum <= DeckRules.DECK_BUDGET * StoneCostRules.COST_SCALE


func _test_random() -> void:
	var gen := GeneratorModel.new()
	var gods := _god_ids()
	var first := gen.generate_random(424242, gods, 4)
	_check(bool(first.get("ok", false)),
		"aléatoire : deux dieux et deux decks complets sont trouvés")
	if not bool(first.get("ok", false)):
		return
	_validate_random_result(gen, first, "aléatoire")
	var second := gen.generate_random(424242, gods, 4)
	_check(second["god_one"] == first["god_one"] and second["god_two"] == first["god_two"]
		and second["deck_one"] == first["deck_one"] and second["deck_two"] == first["deck_two"]
		and int(second["total_quarters"]) == int(first["total_quarters"]),
		"aléatoire : la même graine reproduit exactement dieux, cartes et total")
	_check(int(first["total_quarters"]) <= DeckRules.DECK_BUDGET * StoneCostRules.COST_SCALE,
		"aléatoire : le budget maximal est respecté")
	_check(gen.card(str((first["deck_one"] as Array)[0]))["tier"] <= 4
		and gen.card(str((first["deck_two"] as Array)[0]))["tier"] <= 4,
		"aléatoire : les cartes respectent le palier maximal")

	var tier_one := gen.generate_random(42, gods, 1)
	_check(bool(tier_one.get("ok", false)),
		"aléatoire : le palier 1 choisit un couple de dieux réellement compatible")
	if bool(tier_one.get("ok", false)):
		var tier_one_total := int(tier_one["total_quarters"])
		_check(_validate_deck(gen, tier_one["deck_one"], str(tier_one["god_one"]),
			1, tier_one_total)
			and _validate_deck(gen, tier_one["deck_two"], str(tier_one["god_two"]),
				1, tier_one_total),
			"aléatoire : les deux decks palier 1 ont huit cartes et le même total")
	var observed_totals := {}
	for probe_seed in range(12):
		var generated := gen.generate_random(9000 + probe_seed, gods, 1)
		if bool(generated.get("ok", false)):
			observed_totals[int(generated["total_quarters"])] = true
	_check(observed_totals.size() > 1,
		"aléatoire : la limite commune de points varie avec la graine")

	var sparse := GeneratorModel.new([_card("fx_a", "fx_a", 40)], 8, 80)
	var failure := sparse.generate_random(1, ["veskar"], 4)
	_check(not bool(failure.get("ok", false)) and str(failure.get("reason", "")) != "",
		"aléatoire : un catalogue insuffisant échoue explicitement")


func _validate_random_result(gen: LoadoutGenerator, result: Dictionary, label: String) -> void:
	var total := int(result["total_quarters"])
	_check(_validate_deck(gen, result["deck_one"], str(result["god_one"]), 4, total),
		"%s : le deck du joueur 1 est complet, légal et au total annoncé" % label)
	_check(_validate_deck(gen, result["deck_two"], str(result["god_two"]), 4, total),
		"%s : le deck du joueur 2 est complet, légal et au même total" % label)


func _test_mirror() -> void:
	var gen := GeneratorModel.new()
	var mirror := gen.generate_mirror(8080, _god_ids(), 4)
	_check(bool(mirror.get("ok", false)), "miroir : un loadout légal est généré")
	if not bool(mirror.get("ok", false)):
		return
	var deck: Array = mirror["deck"]
	_check(_validate_deck(gen, deck, str(mirror["god_id"]), 4,
		int(mirror["total_quarters"])), "miroir : le deck est complet et légal")
	var copy := LoadoutGenerator.duplicate_loadout(mirror)
	(copy["deck"] as Array).append("intrus")
	_check((mirror["deck"] as Array).size() == DeckRules.DECK_SIZE
		and (copy["deck"] as Array).size() == DeckRules.DECK_SIZE + 1,
		"miroir : la copie profonde est indépendante du loadout d'origine")
	_check(not mirror.has("starting_player"),
		"miroir : le premier joueur reste indépendant du loadout")
	var tier_one := gen.generate_mirror(42, _god_ids(), 1)
	_check(bool(tier_one.get("ok", false))
		and _validate_deck(gen, tier_one.get("deck", []), str(tier_one.get("god_id", "")),
			1, int(tier_one.get("total_quarters", -1))),
		"miroir : un deck complet est également généré au palier 1")


func _test_draft() -> void:
	var draft := DraftModel.new()
	var started := draft.start(777, "veskar", "nerava", 4, 60.0)
	_check(bool(started.get("ok", false)), "sélection : un draft complet démarre")
	if not bool(started.get("ok", false)):
		return
	var public_one := draft.public_state(GameState.PLAYER_ONE)
	_check((public_one["offers_one"] as Array).size() == 2
		and (public_one["offers_two"] as Array).size() == 2,
		"sélection : les quatre propositions sont visibles")
	_check(not public_one.has("opponent_deck") and not public_one.has("opponent_chosen"),
		"sélection : la vue publique n'expose ni deck ni choix adverse")
	# La paire adverse montrée dépend de l'étape du lecteur, jamais de la
	# progression réelle de l'adversaire. Les quatre lignes du contrat sont
	# couvertes par des drafts séparés pour ne pas perturber le draft principal.
	var ahead_two := DraftModel.new()
	_check(ahead_two.start(90210, "veskar", "nerava", 4, 60.0).get("ok", false),
		"projection : un draft de contrôle démarre")
	for index in range(5):
		var pair_two := ahead_two.offers_for(GameState.PLAYER_TWO)
		ahead_two.choose(GameState.PLAYER_TWO, str(pair_two[0]))
	var view_zero := ahead_two.public_state(GameState.PLAYER_ONE)
	_check(int(view_zero["own_step"]) == 0 and int(view_zero["opponent_step"]) == 5,
		"projection : local 0 / adversaire 5 est signalé")
	_check(view_zero["offers_two"] == ahead_two.offers_for_step(GameState.PLAYER_TWO, 0)
		and view_zero["offers_two"] != ahead_two.offers_for(GameState.PLAYER_TWO),
		"projection : local 0 / adversaire 5 montre la paire adverse de l'étape 0")
	for index in range(3):
		var pair_two_end := ahead_two.offers_for(GameState.PLAYER_TWO)
		ahead_two.choose(GameState.PLAYER_TWO, str(pair_two_end[0]))
	for index in range(4):
		var pair_one := ahead_two.offers_for(GameState.PLAYER_ONE)
		ahead_two.choose(GameState.PLAYER_ONE, str(pair_one[0]))
	var view_four := ahead_two.public_state(GameState.PLAYER_ONE)
	_check(int(view_four["own_step"]) == 4 and int(view_four["opponent_step"]) == 8,
		"projection : local 4 / adversaire 8 est signalé")
	_check(view_four["offers_one"] == ahead_two.offers_for_step(GameState.PLAYER_ONE, 4)
		and view_four["offers_two"] == ahead_two.offers_for_step(GameState.PLAYER_TWO, 4),
		"projection : local 4 / adversaire 8 conserve les deux paires de l'étape 4")
	for index in range(3):
		var pair_one_end := ahead_two.offers_for(GameState.PLAYER_ONE)
		ahead_two.choose(GameState.PLAYER_ONE, str(pair_one_end[0]))
	var view_seven := ahead_two.public_state(GameState.PLAYER_ONE)
	_check(int(view_seven["own_step"]) == 7 and int(view_seven["opponent_step"]) == 8
		and view_seven["offers_two"] == ahead_two.offers_for_step(GameState.PLAYER_TWO, 7),
		"projection : local 7 / adversaire 8 montre la paire adverse de l'étape 7")
	var opposing := DraftModel.new()
	_check(opposing.start(31337, "veskar", "nerava", 4, 60.0).get("ok", false),
		"projection : un second draft de contrôle démarre")
	for index in range(2):
		var early_two := opposing.offers_for(GameState.PLAYER_TWO)
		opposing.choose(GameState.PLAYER_TWO, str(early_two[0]))
	for index in range(4):
		var early_one := opposing.offers_for(GameState.PLAYER_ONE)
		opposing.choose(GameState.PLAYER_ONE, str(early_one[0]))
	var view_four_two := opposing.public_state(GameState.PLAYER_ONE)
	_check(int(view_four_two["own_step"]) == 4 and int(view_four_two["opponent_step"]) == 2
		and view_four_two["offers_two"] == opposing.offers_for_step(GameState.PLAYER_TWO, 4),
		"projection : local 4 / adversaire 2 montre la paire adverse de l'étape 4")

	var offers_one := draft.offers_for(GameState.PLAYER_ONE)
	var offers_two := draft.offers_for(GameState.PLAYER_TWO)
	_check(draft.generator.cost_quarters(str(offers_one[0]))
		== draft.generator.cost_quarters(str(offers_one[1]))
		and draft.generator.cost_quarters(str(offers_two[0]))
		== draft.generator.cost_quarters(str(offers_two[1]))
		and draft.generator.cost_quarters(str(offers_one[0]))
		== draft.generator.cost_quarters(str(offers_two[0])),
		"sélection : les quatre cartes de l'étape ont le même coût")
	_check(draft.generator.lineage_of(str(offers_one[0]))
		!= draft.generator.lineage_of(str(offers_one[1]))
		and draft.generator.lineage_of(str(offers_two[0]))
		!= draft.generator.lineage_of(str(offers_two[1])),
		"sélection : chaque paire utilise deux lignées distinctes")
	# Le plan complet est vérifié au démarrage : chaque branche de chaque paire
	# produit un deck légal et de même total. Aucun témoin de complétion séparé
	# n'est nécessaire dans l'API publique.

	var steps := 0
	var duplicate_rejected := false
	while not draft.is_complete() and steps < 24:
		var one_now := draft.offers_for(GameState.PLAYER_ONE)
		var two_now := draft.offers_for(GameState.PLAYER_TWO)
		var pick_one := str(one_now[steps % 2])
		var pick_two := str(two_now[(steps + 1) % 2])
		var first_choice := draft.choose(GameState.PLAYER_ONE, pick_one)
		_check(bool(first_choice.get("ok", false)), "sélection : le joueur 1 valide une proposition")
		if steps == 0:
			duplicate_rejected = not bool(draft.choose(GameState.PLAYER_ONE, pick_two).get("ok", true))
		var second_choice := draft.choose(GameState.PLAYER_TWO, pick_two)
		_check(bool(second_choice.get("ok", false)), "sélection : le joueur 2 valide une proposition")
		steps += 1
	_check(duplicate_rejected, "sélection : un second choix du même joueur est refusé")
	_check(draft.is_complete(), "sélection : le draft se termine après huit étapes")
	var result := draft.result()
	_check(bool(result.get("ok", false)), "sélection : le résultat final est légal")
	_check((result["deck_one"] as Array).size() == DeckRules.DECK_SIZE
		and (result["deck_two"] as Array).size() == DeckRules.DECK_SIZE,
		"sélection : les deux decks sont complets")
	_check(int(result["total_quarters"]) == draft.generator.deck_cost_sum(result["deck_one"])
		and draft.generator.deck_cost_sum(result["deck_one"])
		== draft.generator.deck_cost_sum(result["deck_two"]),
		"sélection : les deux decks ont exactement le même total en quarts")
	_check(_validate_deck(draft.generator, result["deck_one"], "veskar", 4,
		int(result["total_quarters"])), "sélection : le deck 1 respecte dieu, palier et budget")
	_check(_validate_deck(draft.generator, result["deck_two"], "nerava", 4,
		int(result["total_quarters"])), "sélection : le deck 2 respecte dieu, palier et budget")

	var timeout_a := DraftModel.new()
	var timeout_b := DraftModel.new()
	_check(timeout_a.start(31415, "veskar", "nerava", 4, 1.0).get("ok", false)
		and timeout_b.start(31415, "veskar", "nerava", 4, 1.0).get("ok", false),
		"sélection : deux drafts identiques démarrent pour le timeout")
	_check(not timeout_a.advance(0.5) and not timeout_a.is_complete(),
		"sélection : le timeout n'est pas encore atteint")
	_check(timeout_a.advance(0.5) and timeout_a.is_complete(),
		"sélection : le timeout autoritaire complète les choix manquants")
	timeout_b.advance(1.0)
	_check(timeout_a.result()["deck_one"] == timeout_b.result()["deck_one"]
		and timeout_a.result()["deck_two"] == timeout_b.result()["deck_two"],
		"sélection : la complétion automatique est déterministe pour une même graine")
	_check(timeout_a.remaining_seconds() == 0.0,
		"sélection : le compte à rebours tombe à zéro après le timeout")

	var sparse_pool: Array = []
	for index in range(4):
		sparse_pool.append(_card("fx_s%d" % index, "fx_s%d" % index, 40))
	var sparse := DraftModel.new(sparse_pool, 8, 80)
	var sparse_result := sparse.start(1, "veskar", "nerava", 4, 60.0)
	_check(not bool(sparse_result.get("ok", false)),
		"sélection : un catalogue insuffisant échoue sans deck incomplet")


func _rules(mode: String, series: String) -> Dictionary:
	var config := RulesModel.default_config()
	config["mode"] = mode
	config["series"] = series
	return config


func _test_series() -> void:
	var stats_before: Dictionary = PlayerData.stats.duplicate(true)
	var ft1 := SeriesEngineModel.begin("s-ft1", _rules(RulesModel.MODE_CLASSIC,
		RulesModel.SERIES_FT1), 1)
	var one := SeriesEngineModel.record_round(ft1, GameState.PLAYER_ONE, 10, 4)
	_check(bool(one.get("ok", false)) and bool(one["series_finished"])
		and int(one["final_winner"]) == GameState.PLAYER_ONE,
		"séries : FT1 se termine à la première victoire")
	_check(not bool(SeriesEngineModel.record_round(ft1, GameState.PLAYER_TWO).get("ok", true)),
		"séries : une série terminée refuse une nouvelle manche")

	var ft2 := SeriesEngineModel.begin("s-ft2", _rules(RulesModel.MODE_CLASSIC,
		RulesModel.SERIES_FT2), 2)
	SeriesEngineModel.record_round(ft2, GameState.PLAYER_ONE, 9, 5)
	SeriesEngineModel.record_round(ft2, GameState.PLAYER_TWO, 4, 8)
	var draw := SeriesEngineModel.record_round(ft2, GameState.PLAYER_NONE, 6, 6)
	_check(bool(draw.get("ok", false)) and not bool(draw["series_finished"])
		and ft2.wins_one == 1 and ft2.wins_two == 1 and ft2.ties == 1,
		"séries : une égalité FT2 ne donne aucun point et ne termine pas la série")
	var ft2_end := SeriesEngineModel.record_round(ft2, GameState.PLAYER_ONE, 7, 3)
	_check(bool(ft2_end["series_finished"]) and ft2.wins_one == 2
		and ft2.wins_two == 1 and ft2.ties == 1,
		"séries : FT2 se termine au seuil de deux victoires malgré l'égalité")

	var ft3 := SeriesEngineModel.begin("s-ft3", _rules(RulesModel.MODE_RANDOM,
		RulesModel.SERIES_FT3), 3)
	for index in range(2):
		SeriesEngineModel.record_round(ft3, GameState.PLAYER_ONE, 8, 3)
		SeriesEngineModel.record_round(ft3, GameState.PLAYER_TWO, 2, 8)
	var ft3_end := SeriesEngineModel.record_round(ft3, GameState.PLAYER_ONE, 9, 6)
	_check(bool(ft3_end["series_finished"]) and ft3.wins_one == 3
		and ft3.wins_two == 2 and ft3.total_scored_rounds() == 5,
		"séries : FT3 se termine au seuil de trois victoires")

	var classic := SeriesEngineModel.begin("s-keep", _rules(RulesModel.MODE_CLASSIC,
		RulesModel.SERIES_FT2), 4)
	var loadout_one := LoadoutModel.create("veskar", ["de_boiteux_n1", "jumeau_de_cuivre_n1",
		"valet_a_lenvers_n1", "ogre_a_deux_bouches_n1", "le_nud_hurlant_n2",
		"croupier_manchot_n1", "griffe_a_jetons_n2", "devoracle_n2"], GameState.PLAYER_ONE,
		"s-keep", "prep-1", 1, classic.rules_revision)
	var loadout_two := loadout_one.copy()
	SeriesEngineModel.remember_loadouts(classic, loadout_one, loadout_two)
	var reused := SeriesEngineModel.prepare_round(classic)
	_check(bool(reused.get("ok", false)) and bool(reused["reused"])
		and (reused["loadout_one"] as Loadout).deck == loadout_one.deck,
		"séries : Classique conserve les loadouts entre les manches")
	(reused["loadout_one"] as Loadout).deck.append("intrus")
	_check(classic.loadout_one.deck.size() == DeckRules.DECK_SIZE,
		"séries : le loadout conservé n'est pas partagé avec l'appelant")

	var random_series := SeriesEngineModel.begin("s-gen", _rules(RulesModel.MODE_RANDOM,
		RulesModel.SERIES_FT2), 5)
	SeriesEngineModel.remember_loadouts(random_series, loadout_one, loadout_two)
	_check(random_series.loadout_one == null and random_series.loadout_two == null,
		"séries : Aléatoire ne conserve pas les loadouts")
	var regenerated := SeriesEngineModel.prepare_round(random_series)
	_check(bool(regenerated.get("ok", false)) and not bool(regenerated["reused"])
		and regenerated["loadout_one"] == null,
		"séries : Aléatoire redemande une génération à la manche suivante")

	var serialized := classic.to_dict()
	var restored := SeriesModel.from_dict(serialized)
	_check(restored.loadout_one != null and restored.loadout_two != null
		and restored.loadout_one.deck == classic.loadout_one.deck,
		"séries : la sérialisation conserve les loadouts des modes qui les gardent")
	_check(PlayerData.stats == stats_before,
		"séries : aucun résultat n'est écrit dans les statistiques de campagne")


func _test_lobby_rules() -> void:
	var config := RulesModel.default_config()
	_check(not RulesModel.summary(config).contains("Palier maximal"),
		"salon : le résumé classique ne mentionne pas un palier inactif")
	var refused := RulesModel.apply_change(config, "mode", RulesModel.MODE_RANDOM, false)
	_check(not bool(refused.get("ok", false))
		and str(refused["reason"]).contains("hôte"),
		"salon : seul l'hôte peut modifier le mode")
	var changed := RulesModel.apply_change(config, "mode", RulesModel.MODE_RANDOM, true)
	_check(bool(changed.get("ok", false)) and bool(changed["changed"])
		and int(changed["config"]["revision"]) == 1,
		"salon : une modification incrémente la révision")
	_check(RulesModel.summary(changed["config"]).contains("Palier maximal"),
		"salon : le résumé des modes générés indique leur palier")
	var tier_one_random := RulesModel.apply_change(changed["config"], "power_tier", 1, true)
	_check(bool(tier_one_random.get("ok", false))
		and int(tier_one_random["config"]["power_tier"]) == 1,
		"salon : Aléatoire accepte le palier 1")
	var draft_mode := RulesModel.apply_change(tier_one_random["config"], "mode",
		RulesModel.MODE_DRAFT, true)
	_check(bool(draft_mode.get("ok", false))
		and int(draft_mode["config"]["power_tier"]) == 2
		and not bool(RulesModel.apply_change(draft_mode["config"], "power_tier", 1,
			true).get("ok", true)),
		"salon : Sélection relève le palier minimal à 2 au lieu de lancer un draft impossible")
	config = changed["config"]
	RulesModel.apply_ready(config, GameState.PLAYER_ONE, 1, true)
	config = RulesModel.apply_ready(config, GameState.PLAYER_ONE, 1, true)["config"]
	config = RulesModel.apply_ready(config, GameState.PLAYER_TWO, 1, true)["config"]
	_check(RulesModel.both_ready(config), "salon : les deux PRÊT sont enregistrés")
	var stale := RulesModel.apply_ready(config, GameState.PLAYER_ONE, 0, true)
	_check(not bool(stale.get("ok", false))
		and str(stale["reason"]).contains("périmée"),
		"salon : un PRÊT d'une ancienne révision est refusé")
	var tier_change := RulesModel.apply_change(config, "power_tier", 3, true)
	_check(bool(tier_change.get("ok", false))
		and int(tier_change["config"]["revision"]) == 2
		and not bool(tier_change["config"]["ready_one"])
		and not bool(tier_change["config"]["ready_two"]),
		"salon : toute modification remet les deux joueurs à PAS PRÊT")
	var locked := RulesModel.lock(tier_change["config"])
	_check(bool(locked["locked"]), "salon : les règles se verrouillent après accord")
	var locked_edit := RulesModel.apply_change(locked, "series", RulesModel.SERIES_FT3, true)
	_check(not bool(locked_edit.get("ok", false))
		and str(locked_edit["reason"]).contains("verrouillées"),
		"salon : les règles verrouillées ne peuvent plus être modifiées")
	_check(RulesModel.can_transition(RulesModel.PHASE_LOBBY_EDITING, RulesModel.PHASE_RULES_READY)
		and RulesModel.can_transition(RulesModel.PHASE_RULES_READY, RulesModel.PHASE_PREPARING)
		and not RulesModel.can_transition(RulesModel.PHASE_LOBBY_EDITING, RulesModel.PHASE_IN_MATCH),
		"salon : les transitions de phases refusent les sauts incohérents")
