## OpponentCatalog.gd
## Fabrique les adversaires des Rencontres à partir d'un dieu, ou du bot neutre,
## d'un palier de cartes et d'une difficulté.
##
## Le deck ne dépend que du dieu et du palier. Les cinq difficultés d'une même
## rencontre affrontent donc les mêmes cartes : seule la façon de jouer change.
## La génération est déterministe, afin qu'une rencontre reste identique d'une
## session à l'autre sans stocker cent cinq adversaires dans un fichier.
extends RefCounted

const Shuffle := preload("res://scripts/domain/SeededShuffle.gd")

const AIProfileModel := preload("res://scripts/ai/AIProfile.gd")
const BotCardTierRulesModel := preload("res://tests/support/BotCardTierFixture.gd")

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
	var god := MonsterLoader.get_god(god_id)
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
	return MonsterLoader.get_god(source_id)


## Les quinze niveaux d'un chemin, du palier le plus faible au plus fort puis
## dans l'ordre d'affichage des difficultés. Cet ordre est un contrat : il
## décide des déblocages et ne doit pas être recopié ailleurs.
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
	if tier.is_empty() or MonsterLoader.get_god(god_id).is_empty():
		return []
	return _make_deck(
		MonsterLoader.get_lineages_for_god(god_id),
		tier,
		_deck_seed(god_id, bracket_id),
		false
	)


static func neutral_deck_for(bracket_id: String) -> Array:
	var tier := bracket(bracket_id)
	if tier.is_empty():
		return []
	return _make_deck(
		MonsterLoader.get_neutral_lineages(),
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
	for monster in lineages:
		var lineage_id := MonsterLoader.monster_lineage(str(monster.get("id", "")))
		if lineage_id == "" or _eligible_variants(lineage_id, minimum, maximum).is_empty():
			continue
		if str(monster.get("god_id", "neutral")) == "neutral":
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
	for raw_id in MonsterLoader.variant_ids(lineage_id):
		var monster_id := str(raw_id)
		var effective_level := BotCardTierRulesModel.effective_level(
			MonsterLoader.monster_rarity(monster_id), MonsterLoader.monster_level(monster_id))
		if effective_level >= minimum and effective_level <= maximum:
			result.append(monster_id)
	return result


## Les sept sources de rencontre, dans l'ordre d'affichage : les six dieux
## puis Pr.Stone. La grille et le profil lisent la même liste complète.
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

static func get_npcs_ordered() -> Array:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/support/opponents.json"))
	return data.get("npcs", [])


static func get_npc(id: String) -> Dictionary:
	for npc in get_npcs_ordered():
		if str(npc.get("id", "")) == id:
			return npc.duplicate(true)
	return {}
