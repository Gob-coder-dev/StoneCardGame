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

static func build(node: CampaignNode, campaign_version: int, player_god_id: String,
		player_deck: Array, attempt: int) -> Dictionary:
	if node == null:
		return _failure("Nœud de campagne absent.")
	var mode := node.game_mode()
	var tier := node.max_power_tier()
	var generation_seed := node.resolved_seed(campaign_version, attempt)
	var resolved := _resolve_mode(node, player_god_id, player_deck, generation_seed, tier)
	if not bool(resolved.get("ok", false)):
		return _failure(str(resolved.get("reason", "Rencontre invalide.")))
	resolved = _resolve_identity(resolved)
	if not bool(resolved.get("ok", false)):
		return _failure(str(resolved.get("reason", "Adversaire invalide.")))
	var opponent := _opponent(node, mode, tier, resolved)
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
		"seed": generation_seed,
		"requires_preparation": node.needs_preparation(),
		"needs_series_session": node.needs_series_session(),
		"match_setup": node.match_setup(),
	}


static func _resolve_mode(node: CampaignNode, player_god_id: String,
		player_deck: Array, generation_seed: int, tier: int) -> Dictionary:
	var result := {
		"ok": true, "reason": "", "god_id": "", "deck": [],
		"name": "", "description": "", "portrait": "",
	}
	var god_policy := node.opponent_god_policy()
	var deck_policy := node.opponent_deck_policy()
	match node.game_mode():
		GameModeRulesModel.MODE_RANDOM:
			var random_god := node.generator_god_id()
			if random_god != "":
				result.name = _god_name(random_god)
				result.description = "Deux decks de %s tirés au hasard, sans carte neutre." % result.name
				result.portrait = str(StoneLoader.get_god(random_god).get("asset", ""))
			else:
				result.name = "Adversaire"
				result.description = "Dieux et decks tirés selon les règles du mode Aléatoire."
		GameModeRulesModel.MODE_MIRROR:
			var mirror_god := node.generator_god_id()
			if not node.mirror_fixed_deck().is_empty() and mirror_god != "":
				result.name = _god_name(mirror_god)
				result.description = "Un deck miroir fixe de %s, copié pour les deux camps." % result.name
				result.portrait = str(StoneLoader.get_god(mirror_god).get("asset", ""))
			else:
				result.name = "Reflet"
				result.description = "Un seul loadout généré, copié pour les deux camps."
		GameModeRulesModel.MODE_DRAFT:
			result.god_id = player_god_id if god_policy == CampaignNode.GOD_PROFILE \
				else node.fixed_god_id()
			if result.god_id == "":
				return _mode_failure("Le niveau Sélection n'a pas de dieu adverse.")
		GameModeRulesModel.MODE_CLASSIC:
			result.god_id = player_god_id if god_policy == CampaignNode.GOD_PROFILE \
				else node.fixed_god_id()
			if result.god_id == "" and deck_policy != CampaignNode.DECK_FIXED:
				return _mode_failure("Le niveau Classique n'a pas de dieu adverse.")
			var deck_result := _classic_deck(node, player_deck, generation_seed, tier, result.god_id)
			if not bool(deck_result.get("ok", false)):
				return deck_result
			result.deck = deck_result.get("deck", [])
		_:
			return _mode_failure("Mode de campagne inconnu.")
	return result


static func _classic_deck(node: CampaignNode, player_deck: Array,
		generation_seed: int, tier: int, god_id: String) -> Dictionary:
	match node.opponent_deck_policy():
		CampaignNode.DECK_FIXED:
			return {"ok": true, "deck": node.fixed_deck()}
		CampaignNode.DECK_GENERATED:
			if god_id == "":
				return _mode_failure("Un deck généré exige un dieu adverse.")
			var generated := GeneratorModel.new().generate_for_god(generation_seed, god_id, tier)
			if not bool(generated.get("ok", false)):
				return _mode_failure(str(generated.get("reason", "Deck généré impossible.")))
			return {"ok": true, "deck": (generated.get("deck", []) as Array).duplicate()}
		CampaignNode.DECK_MIRRORED:
			return {"ok": true, "deck": player_deck.duplicate()}
	return _mode_failure("Politique de deck inconnue.")


static func _resolve_identity(resolved: Dictionary) -> Dictionary:
	var god_id := str(resolved.get("god_id", ""))
	if god_id != "":
		var god := StoneLoader.get_god(god_id)
		if god.is_empty():
			return _mode_failure("Dieu adverse introuvable : %s." % god_id)
		resolved.name = str(god.get("name", god_id))
		resolved.description = str(god.get("description", ""))
		resolved.portrait = str(god.get("asset", ""))
	if str(resolved.get("name", "")) == "":
		resolved.name = OpponentCatalogModel.NEUTRAL_BOT_NAME
	# Tout adversaire IA sans portrait utilise Pr.Stone, y compris Reflet et Aléatoire.
	if str(resolved.get("portrait", "")) == "":
		resolved.portrait = str(OpponentCatalogModel.neutral_source().get("asset", ""))
	return resolved


static func _opponent(node: CampaignNode, mode: String, tier: int,
		resolved: Dictionary) -> Dictionary:
	return {
		"id": "campaign_%s" % node.id,
		# Le nom du combattant reste court dans le HUD, le pile ou face et le
		# résultat. Le titre narratif appartient à la fiche de campagne.
		"name": str(resolved.get("name", "")),
		"combatant_name": str(resolved.get("name", "")),
		"encounter_name": node.name,
		"mode_label": GameModeRulesModel.mode_label(mode),
		"god_id": str(resolved.get("god_id", "")),
		"description": str(resolved.get("description", "")),
		"quote": "",
		"difficulty": "campaign",
		"difficulty_label": node.type_label(),
		"difficulty_stars_text": "",
		"bracket_id": "tier%d" % tier,
		"bracket_label": "Palier %d" % tier,
		"ai": node.ai_profile(),
		"deck": (resolved.get("deck", []) as Array).duplicate(),
		"portrait": str(resolved.get("portrait", "")),
		"campaign_node_id": node.id,
		"series": node.series_format(),
		"match_setup": node.match_setup(),
		"rewards": node.reward_definition(),
	}


static func _mode_failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


## Identifiant historique d'une rencontre générée. Une victoire ancienne ne
## peut être convertie que si ce niveau est le seul à revendiquer cet
## identifiant : le profil ne mémorisait ni deck ni nœud.
static func legacy_opponent_id(node: CampaignNode) -> String:
	if node == null or node.game_mode() != GameModeRulesModel.MODE_CLASSIC:
		return ""
	var declared := node.declared_legacy_opponent_id()
	if declared != "":
		return declared
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
