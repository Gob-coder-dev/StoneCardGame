## OpponentCatalog.gd
## Fabrique les adversaires des Rencontres à partir d'un dieu, ou du bot neutre,
## d'un palier de cartes et d'une difficulté.
##
## Le deck ne dépend que du dieu et du palier. Les cinq difficultés d'une même
## rencontre affrontent donc les mêmes cartes : seule la façon de jouer change.
## La génération est déterministe, afin qu'une rencontre reste identique d'une
## session à l'autre sans stocker cent cinq adversaires dans un fichier.
class_name OpponentCatalog
extends RefCounted

const Shuffle := preload("res://scripts/domain/SeededShuffle.gd")

const AIProfileModel := preload("res://scripts/ai/AIProfile.gd")
const BotCardTierRulesModel := preload("res://scripts/domain/BotCardTierRules.gd")

const NEUTRAL_BOT_ID := "pr_stone"
const NEUTRAL_BOT_NAME := "Pr.Stone"
## Palette du portrait : le gris de ses cheveux et de son manteau, puis le rouge
## clair de son visage et de ses fioles.
const NEUTRAL_BOT_COLOR := "#bdb4ab"
const NEUTRAL_BOT_ACCENT := "#e08a82"
const NEUTRAL_BOT_ASSET := "res://assets/gods/pr_stone.png"

## Paliers de puissance : le niveau de bot combine le niveau de forme et son
## plancher de rareté, sans modifier le niveau utilisé par le moteur.
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
## puis complètent avec les neutres. Le bot Pr.Stone ne prend que des lignées
## neutres.
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


static func neutral_opponent_id(bracket_id: String, difficulty_id: String) -> String:
	return "bot_%s_%s_%s" % [NEUTRAL_BOT_ID, bracket_id, difficulty_id]


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
	return _build_opponent(
		opponent_id(god_id, bracket_id, difficulty_id),
		"%s — %s" % [god_name, str(tier["name"])],
		god_id,
		str(god.get("description", "")),
		str(god.get("asset", "")),
		deck,
		tier,
		level
	)


static func build_neutral(bracket_id: String, difficulty_id: String) -> Dictionary:
	var tier := bracket(bracket_id)
	var level := difficulty(difficulty_id)
	if tier.is_empty() or level.is_empty():
		return {}
	var deck := neutral_deck_for(bracket_id)
	if deck.is_empty():
		return {}
	var source := neutral_source()
	return _build_opponent(
		neutral_opponent_id(bracket_id, difficulty_id),
		"%s — %s" % [str(source["name"]), str(tier["name"])],
		"",
		str(source["description"]),
		str(source.get("asset", "")),
		deck,
		tier,
		level
	)


## Fiche de la source sans dieu. Elle reste hors de gods.json : Pr.Stone ne
## doit jamais devenir un dieu jouable.
static func neutral_source() -> Dictionary:
	return {
		"id": NEUTRAL_BOT_ID,
		"name": NEUTRAL_BOT_NAME,
		"family_name": "Sans dieu • cartes neutres",
		"color": NEUTRAL_BOT_COLOR,
		"secondary_color": NEUTRAL_BOT_ACCENT,
		"description": "Adversaire sans dieu, son deck est composé uniquement de cartes neutres.",
		"asset": NEUTRAL_BOT_ASSET,
	}


static func source_for(source_id: String) -> Dictionary:
	if source_id == NEUTRAL_BOT_ID:
		return neutral_source()
	return StoneLoader.get_god(source_id)


## Les quinze niveaux d'un chemin, du palier le plus faible au plus fort puis
## dans l'ordre d'affichage des difficultés. Cet ordre est un contrat : il
## décide des déblocages et ne doit pas être recopié ailleurs.
static func levels_for(source_id: String) -> Array:
	var neutral := source_id == NEUTRAL_BOT_ID
	if not neutral and StoneLoader.get_god(source_id).is_empty():
		return []
	var levels: Array = []
	for chapter_index in range(BRACKETS.size()):
		var tier: Dictionary = BRACKETS[chapter_index]
		var bracket_id := str(tier["id"])
		for difficulty_index in range(DIFFICULTIES.size()):
			var level: Dictionary = DIFFICULTIES[difficulty_index]
			var difficulty_id := str(level["id"])
			var opponent_id_value := opponent_id(source_id, bracket_id, difficulty_id)
			if neutral:
				opponent_id_value = neutral_opponent_id(bracket_id, difficulty_id)
			levels.append({
				"index": levels.size(),
				"source_id": source_id,
				"opponent_id": opponent_id_value,
				"bracket_id": bracket_id,
				"bracket_label": str(tier["name"]),
				"chapter_index": chapter_index,
				"chapter_start": difficulty_index == 0,
				"difficulty_id": difficulty_id,
				"difficulty_label": str(level["name"]),
				"stars": int(level["stars"]),
			})
	return levels


## Retrouve la source d'un adversaire généré. Un PNJ historique de npcs.json
## ne porte pas de palier : il n'appartient à aucun chemin et renvoie "".
static func source_id_of(opponent: Dictionary) -> String:
	if str(opponent.get("bracket_id", "")) == "" or str(opponent.get("difficulty", "")) == "":
		return ""
	var god_id := str(opponent.get("god_id", ""))
	if god_id == "":
		return NEUTRAL_BOT_ID
	return god_id if not StoneLoader.get_god(god_id).is_empty() else ""


## Construit l'adversaire d'un niveau de chemin, avec ou sans dieu.
static func build_for_source(source_id: String, bracket_id: String,
		difficulty_id: String) -> Dictionary:
	if source_id == NEUTRAL_BOT_ID:
		return build_neutral(bracket_id, difficulty_id)
	return build(source_id, bracket_id, difficulty_id)


static func _build_opponent(opponent_id_value: String, display_name: String, god_id: String,
		description: String, portrait: String, deck: Array, tier: Dictionary,
		level: Dictionary) -> Dictionary:
	return {
		"id": opponent_id_value,
		"name": display_name,
		"god_id": god_id,
		"description": description,
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
		"portrait": portrait,
	}


## Deck thématique du couple dieu × palier. La graine ne contient pas la
## difficulté : la composition reste stable pour toute la rencontre.
static func deck_for(god_id: String, bracket_id: String) -> Array:
	var tier := bracket(bracket_id)
	if tier.is_empty() or StoneLoader.get_god(god_id).is_empty():
		return []
	return _make_deck(
		StoneLoader.get_lineages_for_god(god_id),
		tier,
		_deck_seed(god_id, bracket_id),
		false
	)


static func neutral_deck_for(bracket_id: String) -> Array:
	var tier := bracket(bracket_id)
	if tier.is_empty():
		return []
	return _make_deck(
		StoneLoader.get_neutral_lineages(),
		tier,
		_deck_seed(NEUTRAL_BOT_ID, bracket_id),
		true
	)


static func _make_deck(lineages: Array, tier: Dictionary, generation_seed: int,
		neutral_only: bool) -> Array:
	var minimum := int(tier["min_level"])
	var maximum := int(tier["max_level"])
	var family: Array = []
	var neutral: Array = []
	for stone in lineages:
		var lineage_id := StoneLoader.stone_lineage(str(stone.get("id", "")))
		if lineage_id == "" or _eligible_variants(lineage_id, minimum, maximum).is_empty():
			continue
		if str(stone.get("god_id", "neutral")) == "neutral":
			neutral.append(lineage_id)
		elif not neutral_only:
			family.append(lineage_id)
	family.sort()
	neutral.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = generation_seed
	family = _shuffled(family, rng)
	neutral = _shuffled(neutral, rng)
	var selected_lineages: Array = []
	if neutral_only:
		_take(selected_lineages, neutral, DeckRules.DECK_SIZE)
	else:
		_take(selected_lineages, family, FAMILY_CARDS)
		_take(selected_lineages, neutral, DeckRules.DECK_SIZE)
		_take(selected_lineages, family, DeckRules.DECK_SIZE)
	if selected_lineages.size() != DeckRules.DECK_SIZE:
		return []
	var deck: Array = []
	for lineage_id in selected_lineages:
		var variants := _eligible_variants(str(lineage_id), minimum, maximum)
		if variants.is_empty():
			return []
		deck.append(variants[rng.randi_range(0, variants.size() - 1)])
	return deck


static func _eligible_variants(lineage_id: String, minimum: int, maximum: int) -> Array:
	var result: Array = []
	for raw_id in StoneLoader.variant_ids(lineage_id):
		var stone_id := str(raw_id)
		var effective_level := BotCardTierRulesModel.effective_level(
			StoneLoader.stone_rarity(stone_id), StoneLoader.stone_level(stone_id))
		if effective_level >= minimum and effective_level <= maximum:
			result.append(stone_id)
	return result


## Les sept sources de rencontre, dans l'ordre d'affichage : les six dieux
## puis Pr.Stone. La grille et le profil lisent la même liste complète.
static func sources() -> Array:
	var result: Array = StoneLoader.get_all_gods().duplicate(true)
	result.append(neutral_source())
	return result


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
	for tier in BRACKETS:
		_check_deck("", str(tier["id"]), tier, result, true)
	for tier in DIFFICULTIES:
		var profile := {
			"precision": float(tier["precision"]),
			"anticipation": bool(tier["anticipation"]),
		}
		for ai_problem in AIProfileModel.problems(profile):
			result.append("difficulté '%s' : %s." % [tier["id"], ai_problem])
	return result


static func _check_deck(god_id: String, bracket_id: String, tier: Dictionary,
		result: Array[String], neutral_only: bool = false) -> void:
	var deck := neutral_deck_for(bracket_id) if neutral_only else deck_for(god_id, bracket_id)
	var deck_label := NEUTRAL_BOT_ID if neutral_only else god_id
	if deck.size() != DeckRules.DECK_SIZE:
		result.append("deck %s/%s incomplet (%d/%d)." % [
			deck_label, bracket_id, deck.size(), DeckRules.DECK_SIZE])
		return
	var seen: Array = []
	for raw_id in deck:
		var stone_id := str(raw_id)
		var lineage := StoneLoader.stone_lineage(stone_id)
		if not StoneLoader.has_stone(stone_id) or seen.has(lineage):
			result.append("deck %s/%s invalide." % [deck_label, bracket_id])
			return
		if neutral_only and StoneLoader.stone_affinity(stone_id) != "neutral":
			result.append("carte '%s' non neutre dans le deck %s." % [stone_id, deck_label])
			return
		if not neutral_only and not StoneLoader.is_stone_available_to_god(stone_id, god_id):
			result.append("carte '%s' inaccessible à '%s'." % [stone_id, god_id])
			return
		var effective_level := BotCardTierRulesModel.effective_level(
			StoneLoader.stone_rarity(stone_id), StoneLoader.stone_level(stone_id))
		if effective_level < int(tier["min_level"]) or effective_level > int(tier["max_level"]):
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
	Shuffle.apply(result, rng)
	return result


## `String.hash()` est stable d'une session à l'autre : la rencontre garde son
## deck sans dépendre de l'ordre de chargement des dictionnaires.
static func _deck_seed(source_id: String, bracket_id: String) -> int:
	return ("%s:%s" % [source_id, bracket_id]).hash()
