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


static func _god_name(god_id: String) -> String:
	if god_id == "":
		return ""
	return str(StoneLoader.get_god(god_id).get("name", god_id))
