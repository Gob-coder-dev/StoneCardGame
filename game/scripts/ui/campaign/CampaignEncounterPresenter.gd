## CampaignEncounterPresenter.gd
## Transforme un nœud de campagne en données d'affichage. Aucune rencontre
## n'est créée ici et aucune progression n'est lue ou modifiée.
class_name CampaignEncounterPresenter
extends RefCounted

const BotIdentityModel := preload("res://scripts/data/BotIdentity.gd")
const GameModeRulesModel := preload("res://scripts/domain/GameModeRules.gd")
const SeriesRulesModel := preload("res://scripts/domain/SeriesRules.gd")
const CardPowerTierRulesModel := preload("res://scripts/domain/CardPowerTierRules.gd")
const EconomyConfigModel := preload("res://scripts/data/economy/EconomyConfig.gd")

## Traduction courte des étoiles, pour que la difficulté de l'IA ne se confonde
## pas avec la puissance des cartes.
const STAR_WORDS: Array[String] = ["Débutant", "Facile", "Moyen", "Difficile", "Expert"]
const STAR_HINTS: Array[String] = [
	"L'adversaire fait des erreurs.",
	"L'adversaire joue simplement.",
	"L'adversaire joue correctement.",
	"L'adversaire joue bien.",
	"L'adversaire joue au mieux.",
]


static func summary(node: CampaignNode, player_god_id: String = "") -> Dictionary:
	if node == null:
		return {}
	var god_policy := node.opponent_god_policy()
	var mode := node.game_mode()
	var theme_name := _god_name(node.theme_god_id)
	var generated_god_name := _god_name(node.generator_god_id())
	var opponent_label := _opponent_label(
		node, player_god_id, mode, god_policy, theme_name, generated_god_name)
	var deck_label := _deck_label(node, generated_god_name)
	var accent := _accent(node)
	var stars := ai_stars(node)
	var tier := node.max_power_tier()
	return {
		"id": node.id,
		"name": node.name,
		"chapter": node.chapter,
		"region": node.region,
		"type": node.type,
		"type_label": node.type_label(),
		"tutorial_id": node.tutorial_id,
		"opponent_label": opponent_label,
		"opponent_god_label": opponent_god_label(node, player_god_id),
		"opponent_god_id": opponent_god_id(node, player_god_id),
		"opponent_god_unknown": opponent_god_unknown(node, player_god_id),
		"player_god_id": player_god_id,
		"theme_god_id": node.theme_god_id,
		"theme_label": ("Inspiration : %s" % theme_name) if theme_name != "" else "",
		"mode_label": GameModeRulesModel.mode_label(mode),
		"mode_description": GameModeRulesModel.mode_description(mode),
		"tier_label": CardPowerTierRulesModel.label(tier),
		"power_label": CardPowerTierRulesModel.short_label(tier),
		"power_description": CardPowerTierRulesModel.description(tier),
		"tier": tier,
		"stars": stars,
		"stars_word": stars_word(stars),
		"stars_hint": stars_hint(stars),
		"rewards": reward_summary(node),
		"technical_lines": technical_lines(node),
		"deck_label": deck_label,
		"series_label": SeriesRulesModel.label(node.series_format()),
		"accent": accent,
		"requires_preparation": node.needs_preparation(),
		"is_mini_boss": node.is_mini_boss(),
		"is_boss": node.is_boss(),
		"is_tutorial": node.is_tutorial(),
	}


## Nom court du dieu combattu, pour une carte compacte : le mode est affiché
## juste à côté, donc ce libellé ne le répète jamais. Quand le mode laisse le
## dieu indéterminé, on reprend le nom que montre la préparation de rencontre.
static func opponent_god_label(node: CampaignNode, player_god_id: String = "") -> String:
	if node == null:
		return ""
	var generated := _god_name(node.generator_god_id())
	match node.opponent_god_policy():
		CampaignNode.GOD_PROFILE:
			return _god_name(player_god_id)
		CampaignNode.GOD_MIRRORED:
			if generated != "":
				return generated
			return _god_name(player_god_id) if player_god_id != "" else "Miroir"
		CampaignNode.GOD_FIXED:
			if node.fixed_god_id() != "":
				return _god_name(node.fixed_god_id())
			return BotIdentityModel.NEUTRAL_BOT_NAME
	if generated != "":
		return generated
	if node.game_mode() == GameModeRulesModel.MODE_MIRROR:
		return _god_name(player_god_id) if player_god_id != "" else "Miroir"
	return "Adversaire"


## Identité affichée dans le camp adverse. Un dieu imposé reste lui-même ; un
## mode généré sans dieu n'a aucune identité à montrer et renvoie une chaîne
## vide, que la fiche traduit par un portrait « ? ».
static func opponent_god_id(node: CampaignNode, player_god_id: String = "") -> String:
	if node == null:
		return ""
	var generated := node.generator_god_id()
	match node.opponent_god_policy():
		CampaignNode.GOD_PROFILE:
			return player_god_id
		CampaignNode.GOD_MIRRORED:
			return generated if generated != "" else player_god_id
		CampaignNode.GOD_FIXED:
			return node.fixed_god_id()
	if generated != "":
		return generated
	if node.game_mode() == GameModeRulesModel.MODE_MIRROR:
		return player_god_id
	return ""


## Un nœud à dieu fixe sans identifiant combat Pr.Stone : son portrait est
## connu. Seuls les modes générés peuvent laisser l'adversaire réellement
## indéterminé avant le lancement.
static func opponent_god_unknown(node: CampaignNode, player_god_id: String = "") -> bool:
	if node == null:
		return false
	if opponent_god_id(node, player_god_id) != "":
		return false
	return node.opponent_god_policy() != CampaignNode.GOD_FIXED


## Barème de la fiche : seule la précision de l'IA décide des étoiles,
## l'anticipation ajoute un cran. Le palier reste une puce séparée.
static func stars_word(stars: int) -> String:
	return STAR_WORDS[clampi(stars, 1, 5) - 1]


static func stars_hint(stars: int) -> String:
	return STAR_HINTS[clampi(stars, 1, 5) - 1]


static func ai_stars(node: CampaignNode) -> int:
	if node == null:
		return 1
	var ai := node.ai_profile()
	var precision := clampf(float(ai.get("precision", 0.0)), 0.0, 1.0)
	var stars := 1
	if precision >= 0.78:
		stars = 5
	elif precision >= 0.55:
		stars = 4
	elif precision >= 0.35:
		stars = 3
	elif precision >= 0.15:
		stars = 2
	if bool(ai.get("anticipation", false)):
		stars += 1
	return clampi(stars, 1, 5)


## Récompenses lisibles avant le combat : fourchette d'âmes, bougies du
## chapitre et cartes de première victoire. Une lignée inconnue est ignorée
## plutôt que d'afficher un identifiant brut.
static func reward_summary(node: CampaignNode) -> Dictionary:
	var result := {"souls_min": 0, "souls_max": 0, "candles": 0, "cards": []}
	if node == null:
		return result
	var reward := node.reward_definition()
	var minimum := maxi(0, int(reward.get("souls_min", 0)))
	result["souls_min"] = minimum
	result["souls_max"] = maxi(minimum, int(reward.get("souls_max", minimum)))
	if not reward.is_empty():
		result["candles"] = EconomyConfigModel.campaign_candles(node.chapter)
	var cards: Array = []
	var raw_cards: Variant = reward.get("card_rewards", [])
	if raw_cards is Array:
		for raw in raw_cards:
			if not raw is Dictionary:
				continue
			var lineage_id := str((raw as Dictionary).get("lineage_id", ""))
			var copies := int((raw as Dictionary).get("copies", 0))
			var monster_id := MonsterLoader.variant_id(lineage_id, 1)
			if monster_id == "" or copies <= 0:
				continue
			cards.append({
				"monster_id": monster_id,
				"name": str(MonsterLoader.get_monster(monster_id).get("name", lineage_id)),
				"copies": copies,
			})
	result["cards"] = cards
	return result


## La fiche masque les valeurs par défaut (FT1, plateau 4 × 4, deck fixe de
## huit cartes). Un boss ou un mini-boss reste l'exception : ses détails sont
## annoncés parce qu'ils font partie de la rencontre signée.
static func technical_lines(node: CampaignNode) -> Array[String]:
	var lines: Array[String] = []
	if node == null:
		return lines
	var signature := node.is_boss() or node.is_mini_boss()
	var deck := _deck_label(node, _god_name(node.generator_god_id()))
	if deck != "" and (signature or node.opponent_deck_policy() != CampaignNode.DECK_FIXED
			or node.fixed_deck().size() != DeckRules.DECK_SIZE):
		lines.append(deck)
	if signature or node.series_format() != SeriesRulesModel.SERIES_FT1:
		lines.append(SeriesRulesModel.label(node.series_format()))
	if signature or node.board_size() != GameState.DEFAULT_BOARD_SIZE:
		lines.append("Plateau %d × %d" % [node.board_size(), node.board_size()])
	if node.player_hand_size() != DeckRules.DECK_SIZE \
			or node.opponent_hand_size() != DeckRules.DECK_SIZE:
		lines.append("Main %d / %d cartes" % [
			node.player_hand_size(), node.opponent_hand_size()])
	return lines


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
			MonsterLoader.get_god(player_god_id).get("name", "profil"))
	if node.fixed_god_id() == "":
		return BotIdentityModel.NEUTRAL_BOT_NAME
	return str(MonsterLoader.get_god(node.fixed_god_id()).get(
		"name", node.fixed_god_id()))


static func _deck_label(node: CampaignNode, generated_god_name: String) -> String:
	match node.opponent_deck_policy():
		CampaignNode.DECK_FIXED:
			return "Deck fixe • %d cartes" % node.fixed_deck().size()
		CampaignNode.DECK_GENERATED:
			if generated_god_name == "":
				return "Deck généré selon la puissance"
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
			var color := str(MonsterLoader.get_god(god_id).get("color", ""))
			if color != "":
				return color
	return UITheme.COL_NEON_PINK.to_html()


static func _god_name(god_id: String) -> String:
	if god_id == "":
		return ""
	return str(MonsterLoader.get_god(god_id).get("name", god_id))
