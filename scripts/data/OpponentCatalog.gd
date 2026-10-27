## OpponentCatalog.gd
## Fabrique les adversaires des Rencontres : un dieu, un palier de cartes et une
## difficulté suffisent à produire un deck et un profil d'IA complets.
##
## Le deck ne dépend que du dieu et du palier. Les cinq difficultés d'une même
## rencontre affrontent donc les mêmes cartes : seule la façon de jouer change.
## La génération est déterministe, afin qu'une rencontre reste identique d'une
## session à l'autre sans stocker quatre-vingt-dix adversaires dans un fichier.
class_name OpponentCatalog
extends RefCounted

const AIProfileModel := preload("res://scripts/ai/AIProfile.gd")

## Paliers de puissance : seules les formes dont le niveau appartient à
## l'intervalle entrent dans le deck.
const BRACKETS: Array = [
	{"id": "n1", "name": "Niveau 1", "min_level": 1, "max_level": 1},
	{"id": "n2", "name": "Niveau 2", "min_level": 2, "max_level": 2},
	{"id": "n34", "name": "Niveau 3", "min_level": 3, "max_level": 4},
]

## Difficultés dans l'ordre d'affichage. La précision suit une valeur fixe et
## l'anticipation reste réservée au niveau le plus exigeant.
const DIFFICULTIES: Array = [
	{"id": "tres_facile", "name": "Très facile", "precision": 0.0, "anticipation": false, "stars": 1},
	{"id": "facile", "name": "Facile", "precision": 0.25, "anticipation": false, "stars": 2},
	{"id": "moyen", "name": "Moyen", "precision": 0.5, "anticipation": false, "stars": 3},
	{"id": "difficile", "name": "Difficile", "precision": 0.75, "anticipation": false, "stars": 4},
	{"id": "tres_difficile", "name": "Très difficile", "precision": 1.0, "anticipation": true, "stars": 5},
]

## Les decks thématiques gardent une majorité de cartes de la famille du dieu,
## puis complètent avec les neutres. Les paliers N3-4 n'ont que huit lignées de
## famille : les deux neutres sont indispensables pour atteindre huit cartes.
const FAMILY_CARDS: int = 6


static func default_bracket_id() -> String:
	return str(BRACKETS[0]["id"])


static func default_difficulty_id() -> String:
	return str(DIFFICULTIES[2]["id"])


static func bracket(bracket_id: String) -> Dictionary:
	for entry in BRACKETS:
		if str(entry["id"]) == bracket_id:
			return entry.duplicate(true)
	return {}


static func difficulty(difficulty_id: String) -> Dictionary:
	for entry in DIFFICULTIES:
		if str(entry["id"]) == difficulty_id:
			return entry.duplicate(true)
	return {}


## Identifiant stable d'une rencontre. Il sert de clé aux statistiques : chaque
## difficulté progresse séparément pour un même dieu et un même palier.
static func opponent_id(god_id: String, bracket_id: String, difficulty_id: String) -> String:
	return "bot_%s_%s_%s" % [god_id, bracket_id, difficulty_id]


static func stars_text(count: int) -> String:
	var filled := clampi(count, 0, 5)
	return "★".repeat(filled) + "☆".repeat(5 - filled)


## Assemble l'adversaire complet consommé par BoardController, PreBattle et le
## résultat. Renvoie un dictionnaire vide si le dieu, le palier ou la difficulté
## n'existent pas, ou si le catalogue ne permet pas un deck de huit lignées.
static func build(god_id: String, bracket_id: String, difficulty_id: String) -> Dictionary:
	var god := StoneLoader.get_god(god_id)
	var tier := bracket(bracket_id)
	var level := difficulty(difficulty_id)
	if god.is_empty() or tier.is_empty() or level.is_empty():
		return {}
	var deck := deck_for(god_id, bracket_id)
	if deck.is_empty():
		return {}
	var god_name := str(god.get("name", god_id))
	return {
		"id": opponent_id(god_id, bracket_id, difficulty_id),
		"name": "%s — %s" % [god_name, str(tier["name"])],
		"god_id": god_id,
		"description": str(god.get("description", "")),
		"quote": "",
		"difficulty": str(level["id"]),
		"difficulty_label": str(level["name"]),
		"difficulty_stars_text": stars_text(int(level["stars"])),
		"bracket_id": str(tier["id"]),
		"bracket_label": str(tier["name"]),
		"ai": {
			"precision": float(level["precision"]),
			"anticipation": bool(level["anticipation"]),
		},
		"deck": deck,
		"portrait": str(god.get("asset", "")),
	}


## Deck thématique du couple dieu × palier. La graine ne contient pas la
## difficulté : la composition reste stable pour toute la rencontre.
static func deck_for(god_id: String, bracket_id: String) -> Array:
	var tier := bracket(bracket_id)
	if tier.is_empty() or StoneLoader.get_god(god_id).is_empty():
		return []
	var minimum := int(tier["min_level"])
	var maximum := int(tier["max_level"])
	var family: Array = []
	var neutral: Array = []
	for stone in StoneLoader.get_lineages_for_god(god_id):
		var lineage_id := StoneLoader.stone_lineage(str(stone.get("id", "")))
		if lineage_id == "" or StoneLoader.lineage_max_level(lineage_id) < minimum:
			continue
		if str(stone.get("god_id", "neutral")) == "neutral":
			neutral.append(lineage_id)
		else:
			family.append(lineage_id)
	family.sort()
	neutral.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = _deck_seed(god_id, bracket_id)
	family = _shuffled(family, rng)
	neutral = _shuffled(neutral, rng)
	var lineages: Array = []
	_take(lineages, family, FAMILY_CARDS)
	_take(lineages, neutral, DeckRules.DECK_SIZE)
	_take(lineages, family, DeckRules.DECK_SIZE)
	if lineages.size() != DeckRules.DECK_SIZE:
		return []
	var deck: Array = []
	for lineage_id in lineages:
		var top_level := mini(maximum, StoneLoader.lineage_max_level(str(lineage_id)))
		var level := rng.randi_range(minimum, top_level)
		var stone_id := StoneLoader.variant_id(str(lineage_id), level)
		if stone_id == "":
			return []
		deck.append(stone_id)
	return deck


## Lignes de progression affichées par le profil : une par dieu et par palier,
## avec les cinq identifiants de difficulté à agréger.
static func progression_rows() -> Array:
	var rows: Array = []
	for god in StoneLoader.get_all_gods():
		var god_id := str(god.get("id", ""))
		for tier in BRACKETS:
			var bracket_id := str(tier["id"])
			var difficulty_ids: Array = []
			for level in DIFFICULTIES:
				difficulty_ids.append(opponent_id(god_id, bracket_id, str(level["id"])))
			rows.append({
				"label": "%s • %s" % [str(god.get("name", god_id)), str(tier["name"])],
				"color": str(god.get("color", "")),
				"difficulty_ids": difficulty_ids,
			})
	return rows


## Validation appelée par StoneLoader après le chargement des catalogues.
static func problems() -> Array[String]:
	var result: Array[String] = []
	var god_ids: Array = []
	for god in StoneLoader.get_all_gods():
		god_ids.append(str(god.get("id", "")))
	if god_ids.is_empty():
		result.append("aucun dieu chargé pour générer les adversaires.")
		return result
	for god_id in god_ids:
		for tier in BRACKETS:
			var bracket_id := str(tier["id"])
			_check_deck(str(god_id), bracket_id, tier, result)
	for tier in DIFFICULTIES:
		var profile := {
			"precision": float(tier["precision"]),
			"anticipation": bool(tier["anticipation"]),
		}
		for ai_problem in AIProfileModel.problems(profile):
			result.append("difficulté '%s' : %s." % [tier["id"], ai_problem])
	return result


static func _check_deck(god_id: String, bracket_id: String, tier: Dictionary, result: Array[String]) -> void:
	var deck := deck_for(god_id, bracket_id)
	if deck.size() != DeckRules.DECK_SIZE:
		result.append("deck %s/%s incomplet (%d/%d)." % [
			god_id, bracket_id, deck.size(), DeckRules.DECK_SIZE])
		return
	var seen: Array = []
	for raw_id in deck:
		var stone_id := str(raw_id)
		var lineage := StoneLoader.stone_lineage(stone_id)
		if not StoneLoader.has_stone(stone_id) or seen.has(lineage):
			result.append("deck %s/%s invalide." % [god_id, bracket_id])
			return
		if not StoneLoader.is_stone_available_to_god(stone_id, god_id):
			result.append("carte '%s' inaccessible à '%s'." % [stone_id, god_id])
			return
		var level := StoneLoader.stone_level(stone_id)
		if level < int(tier["min_level"]) or level > int(tier["max_level"]):
			result.append("carte '%s' hors du palier '%s'." % [stone_id, bracket_id])
			return
		seen.append(lineage)


static func _take(target: Array, source: Array, limit: int) -> void:
	for lineage_id in source:
		if target.size() >= limit:
			return
		if not target.has(lineage_id):
			target.append(lineage_id)


static func _shuffled(values: Array, rng: RandomNumberGenerator) -> Array:
	var result := values.duplicate()
	for index in range(result.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var value = result[index]
		result[index] = result[swap]
		result[swap] = value
	return result


## `String.hash()` est stable d'une session à l'autre : la rencontre garde son
## deck sans dépendre de l'ordre de chargement des dictionnaires.
static func _deck_seed(god_id: String, bracket_id: String) -> int:
	return ("%s:%s" % [god_id, bracket_id]).hash()
