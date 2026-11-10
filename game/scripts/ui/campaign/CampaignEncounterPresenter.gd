## CampaignEncounterPresenter.gd
## Transforme un nœud de campagne en données d'affichage. Aucune rencontre
## n'est créée ici et aucune progression n'est lue ou modifiée.
class_name CampaignEncounterPresenter
extends RefCounted

const OpponentCatalogModel := preload("res://scripts/data/OpponentCatalog.gd")
const GameModeRulesModel := preload("res://scripts/domain/GameModeRules.gd")
const SeriesRulesModel := preload("res://scripts/domain/SeriesRules.gd")


static func summary(node: CampaignNode, player_god_id: String = "") -> Dictionary:
	if node == null:
		return {}
	var god_policy := node.opponent_god_policy()
	var mode := node.game_mode()
	var theme_name := _god_name(node.theme_god_id)
	var generated_god_name := _god_name(node.generator_god_id())
	var opponent_label := _opponent_label(
		node, player_god_id, mode, god_policy, theme_name, generated_god_name)
	var ai := node.ai_profile()
	var ai_label := "Précision %d %%" % int(roundf(float(ai.get("precision", 0.0)) * 100.0))
	if bool(ai.get("anticipation", false)):
		ai_label += " • anticipation"
	var deck_label := _deck_label(node, generated_god_name)
	var accent := _accent(node)
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


static func _opponent_label(node: CampaignNode, player_god_id: String,
		mode: String, god_policy: String, theme_name: String,
		generated_god_name: String) -> String:
	if mode == GameModeRulesModel.MODE_RANDOM:
		var random_label := "Aléatoire"
		if generated_god_name != "":
			random_label += " — %s imposé" % generated_god_name
			if node.generator_min_god_cards() >= DeckRules.DECK_SIZE:
				random_label += " • deck pur"
		return random_label + ((" — inspiration %s" % theme_name) \
			if theme_name != "" else "")
	if mode == GameModeRulesModel.MODE_MIRROR:
		var mirror_label := "Miroir"
		if not node.mirror_fixed_deck().is_empty() and generated_god_name != "":
			mirror_label += " — %s" % generated_god_name
		return mirror_label + ((" — inspiration %s" % theme_name) \
			if theme_name != "" else "")
	if god_policy == CampaignNode.GOD_PROFILE:
		return "Ton dieu — %s" % str(
			StoneLoader.get_god(player_god_id).get("name", "profil"))
	if node.fixed_god_id() == "":
		return OpponentCatalogModel.NEUTRAL_BOT_NAME
	return str(StoneLoader.get_god(node.fixed_god_id()).get(
		"name", node.fixed_god_id()))


static func _deck_label(node: CampaignNode, generated_god_name: String) -> String:
	match node.opponent_deck_policy():
		CampaignNode.DECK_FIXED:
			return "Deck fixe • %d cartes" % node.fixed_deck().size()
		CampaignNode.DECK_GENERATED:
			if generated_god_name == "":
				return "Deck généré selon le palier"
			return "Deck généré — %s%s" % [generated_god_name,
				" pur" if node.generator_min_god_cards() >= DeckRules.DECK_SIZE else ""]
		CampaignNode.DECK_MIRRORED:
			return "Deck miroir fixe • %d cartes" % node.mirror_fixed_deck().size() \
				if not node.mirror_fixed_deck().is_empty() else "Deck miroir du joueur"
		CampaignNode.DECK_DRAFT:
			return "Draft local • 8 choix"
	return ""


static func _accent(node: CampaignNode) -> String:
	if node.accent != "":
		return node.accent
	for god_id in [node.fixed_god_id(), node.generator_god_id()]:
		if god_id != "":
			var color := str(StoneLoader.get_god(god_id).get("color", ""))
			if color != "":
				return color
	return UITheme.COL_NEON_PINK.to_html()


static func _god_name(god_id: String) -> String:
	if god_id == "":
		return ""
	return str(StoneLoader.get_god(god_id).get("name", god_id))
