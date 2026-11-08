## CampaignEncounterFactory.gd
## Transforme un CampaignNode en adversaire et en configuration de session
## compatibles avec BattleContext et CampaignModeSession. Il réutilise les
## règles partagées (GameModeRules, CardPowerTierRules, LoadoutGenerator) et ne
## dépend jamais du PVP ni d'un transport réseau.
class_name CampaignEncounterFactory
extends RefCounted

const GeneratorModel := preload("res://scripts/domain/LoadoutGenerator.gd")
const OpponentCatalogModel := preload("res://scripts/data/OpponentCatalog.gd")
const GameModeRulesModel := preload("res://scripts/domain/GameModeRules.gd")
const SeriesRulesModel := preload("res://scripts/domain/SeriesRules.gd")

const NEUTRAL_SOURCE_ID := "pr_stone"


static func build(node: CampaignNode, campaign_version: int, player_god_id: String,
		player_deck: Array, attempt: int) -> Dictionary:
	if node == null:
		return _failure("Nœud de campagne absent.")
	var mode := node.game_mode()
	var tier := node.max_power_tier()
	var seed := node.resolved_seed(campaign_version, attempt)
	var opponent_god := ""
	var opponent_deck: Array = []
	var display_name := ""
	var description := ""
	var portrait := ""
	var god_policy := node.opponent_god_policy()
	var deck_policy := node.opponent_deck_policy()

	match mode:
		GameModeRulesModel.MODE_RANDOM:
			var random_god := node.generator_god_id()
			if random_god != "":
				display_name = "Aléatoire — %s" % _god_name(random_god)
				description = "Deux decks de %s tirés au hasard, sans carte neutre." % _god_name(random_god)
				portrait = str(StoneLoader.get_god(random_god).get("asset", ""))
			else:
				display_name = "Aléatoire"
				description = "Dieux et decks tirés selon les règles du mode Aléatoire."
		GameModeRulesModel.MODE_MIRROR:
			var mirror_god := node.generator_god_id()
			if not node.mirror_fixed_deck().is_empty() and mirror_god != "":
				display_name = "Miroir — %s" % _god_name(mirror_god)
				description = "Un deck miroir fixe de %s, copié pour les deux camps." % _god_name(mirror_god)
				portrait = str(StoneLoader.get_god(mirror_god).get("asset", ""))
			else:
				display_name = "Miroir"
				description = "Un seul loadout généré, copié pour les deux camps."
		GameModeRulesModel.MODE_DRAFT:
			opponent_god = player_god_id if god_policy == CampaignNode.GOD_PROFILE \
				else node.fixed_god_id()
			if opponent_god == "":
				return _failure("Le niveau Sélection n'a pas de dieu adverse.")
		GameModeRulesModel.MODE_CLASSIC:
			opponent_god = player_god_id if god_policy == CampaignNode.GOD_PROFILE \
				else node.fixed_god_id()
			if opponent_god == "" and deck_policy != CampaignNode.DECK_FIXED:
				return _failure("Le niveau Classique n'a pas de dieu adverse.")
			match deck_policy:
				CampaignNode.DECK_FIXED:
					opponent_deck = node.fixed_deck()
				CampaignNode.DECK_GENERATED:
					if opponent_god == "":
						return _failure("Un deck généré exige un dieu adverse.")
					var generated := GeneratorModel.new().generate_for_god(
						seed, opponent_god, tier)
					if not bool(generated.get("ok", false)):
						return _failure(str(generated.get("reason", "Deck généré impossible.")))
					opponent_deck = (generated.get("deck", []) as Array).duplicate()
				CampaignNode.DECK_MIRRORED:
					opponent_deck = player_deck.duplicate()
				_:
					return _failure("Politique de deck inconnue.")

		_:
			return _failure("Mode de campagne inconnu.")

	if display_name == "":
		display_name = OpponentCatalogModel.NEUTRAL_BOT_NAME
	if opponent_god != "":
		var god := StoneLoader.get_god(opponent_god)
		if god.is_empty():
			return _failure("Dieu adverse introuvable : %s." % opponent_god)
		display_name = str(god.get("name", opponent_god))
		description = str(god.get("description", ""))
		portrait = str(god.get("asset", ""))

	var opponent := {
		"id": "campaign_%s" % node.id,
		"name": "%s — %s" % [display_name, node.name],
		"god_id": opponent_god,
		"description": description,
		"quote": "",
		"difficulty": "campaign",
		"difficulty_label": node.type_label(),
		"difficulty_stars_text": "",
		"bracket_id": "tier%d" % tier,
		"bracket_label": "Palier %d" % tier,
		"ai": node.ai_profile(),
		"deck": opponent_deck,
		"portrait": portrait,
		"campaign_node_id": node.id,
		"series": node.series_format(),
	}
	return {
		"ok": true,
		"reason": "",
		"opponent": opponent,
		"mode_config": {
			"mode": mode,
			"power_tier": tier,
			"series": node.series_format(),
			"generator_god_id": node.generator_god_id(),
			"generator_min_god_cards": node.generator_min_god_cards(),
			"mirror_fixed_deck": node.mirror_fixed_deck(),
		},
		"seed": seed,
		"requires_preparation": node.needs_preparation(),
		"needs_series_session": node.needs_series_session(),
	}


## Fiche de niveau pour la boîte de dialogue. Elle ne lit pas la progression et
## ne décide pas si le niveau est jouable : l'état vient du service.
static func summary(node: CampaignNode, player_god_id: String = "") -> Dictionary:
	if node == null:
		return {}
	var god_policy := node.opponent_god_policy()
	var mode := node.game_mode()
	var opponent_label := ""
	var theme_name := _god_name(node.theme_god_id)
	var generated_god_name := _god_name(node.generator_god_id())
	match mode:
		GameModeRulesModel.MODE_RANDOM:
			if generated_god_name != "":
				opponent_label = "Aléatoire — %s imposé" % generated_god_name
				if node.generator_min_god_cards() >= DeckRules.DECK_SIZE:
					opponent_label += " • deck pur"
			else:
				opponent_label = "Aléatoire"
			if theme_name != "":
				opponent_label += " — inspiration %s" % theme_name
		GameModeRulesModel.MODE_MIRROR:
			if not node.mirror_fixed_deck().is_empty() and generated_god_name != "":
				opponent_label = "Miroir — %s" % generated_god_name
			else:
				opponent_label = "Miroir"
			if theme_name != "":
				opponent_label += " — inspiration %s" % theme_name
		_:
			if god_policy == CampaignNode.GOD_PROFILE:
				var player_god := StoneLoader.get_god(player_god_id)
				opponent_label = "Ton dieu — %s" % str(player_god.get("name", "profil"))
			elif node.fixed_god_id() == "":
				opponent_label = OpponentCatalogModel.NEUTRAL_BOT_NAME
			else:
				opponent_label = str(StoneLoader.get_god(node.fixed_god_id()).get("name",
					node.fixed_god_id()))
	var ai := node.ai_profile()
	var ai_label := "Précision %d %%" % int(roundf(float(ai.get("precision", 0.0)) * 100.0))
	if bool(ai.get("anticipation", false)):
		ai_label += " • anticipation"
	var deck_label := ""
	match node.opponent_deck_policy():
		CampaignNode.DECK_FIXED:
			deck_label = "Deck fixe • %d cartes" % node.fixed_deck().size()
		CampaignNode.DECK_GENERATED:
			if generated_god_name != "":
				deck_label = "Deck généré — %s" % generated_god_name
				if node.generator_min_god_cards() >= DeckRules.DECK_SIZE:
					deck_label += " pur"
			else:
				deck_label = "Deck généré selon le palier"
		CampaignNode.DECK_MIRRORED:
			if not node.mirror_fixed_deck().is_empty():
				deck_label = "Deck miroir fixe • %d cartes" % node.mirror_fixed_deck().size()
			else:
				deck_label = "Deck miroir du joueur"
		CampaignNode.DECK_DRAFT:
			deck_label = "Draft local • 8 choix"
	var accent := node.accent
	if accent == "" and node.fixed_god_id() != "":
		accent = str(StoneLoader.get_god(node.fixed_god_id()).get("color", ""))
	if accent == "" and node.generator_god_id() != "":
		accent = str(StoneLoader.get_god(node.generator_god_id()).get("color", ""))
	if accent == "":
		accent = UITheme.COL_NEON_PINK.to_html()
	return {
		"id": node.id,
		"name": node.name,
		"chapter": node.chapter,
		"region": node.region,
		"type": node.type,
		"type_label": node.type_label(),
		"tutorial_id": node.tutorial_id,
		"opponent_label": opponent_label,
		"theme_god_id": node.theme_god_id,
		"theme_label": ("Inspiration : %s" % theme_name) if theme_name != "" else "",
		"mode_label": GameModeRulesModel.mode_label(mode),
		"tier_label": "Palier %d" % node.max_power_tier(),
		"ai_label": ai_label,
		"deck_label": deck_label,
		"series_label": SeriesRulesModel.label(node.series_format()),
		"accent": accent,
		"requires_preparation": node.needs_preparation(),
		"is_mini_boss": node.is_mini_boss(),
		"is_boss": node.is_boss(),
		"is_tutorial": node.is_tutorial(),
	}


## Identifiant historique d'une rencontre générée. Une victoire ancienne ne
## peut être convertie que si ce niveau est le seul à revendiquer cet
## identifiant : le profil ne mémorisait ni deck ni nœud.
static func legacy_opponent_id(node: CampaignNode) -> String:
	if node == null or node.game_mode() != GameModeRulesModel.MODE_CLASSIC:
		return ""
	if node.opponent_god_policy() != CampaignNode.GOD_FIXED:
		return ""
	var difficulty := _legacy_difficulty(node.ai_profile())
	if difficulty == "":
		return ""
	var bracket := _legacy_bracket(node.max_power_tier())
	if node.fixed_god_id() == "":
		return OpponentCatalogModel.neutral_opponent_id(bracket, difficulty)
	return OpponentCatalogModel.opponent_id(node.fixed_god_id(), bracket, difficulty)


static func _god_name(god_id: String) -> String:
	if god_id == "":
		return ""
	return str(StoneLoader.get_god(god_id).get("name", god_id))


static func _legacy_bracket(tier: int) -> String:
	if tier <= 1:
		return "n1"
	if tier == 2:
		return "n2"
	return "n34"


static func _legacy_difficulty(ai: Dictionary) -> String:
	var precision := float(ai.get("precision", -1.0))
	var anticipation := bool(ai.get("anticipation", false))
	if is_equal_approx(precision, 0.0) and not anticipation:
		return "tres_facile"
	if is_equal_approx(precision, 0.25) and not anticipation:
		return "facile"
	if is_equal_approx(precision, 0.5) and not anticipation:
		return "moyen"
	if is_equal_approx(precision, 0.75) and not anticipation:
		return "difficile"
	if is_equal_approx(precision, 1.0) and anticipation:
		return "tres_difficile"
	return ""


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "opponent": {}, "mode_config": {}, "seed": 0}
