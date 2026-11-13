## CampaignNode.gd
## Définition immuable d'un nœud de la campagne. Le nœud ne connaît ni la
## progression, ni la sauvegarde, ni une scène : il expose seulement sa
## configuration de rencontre et ses métadonnées de carte.
class_name CampaignNode
extends RefCounted

const TYPE_TUTORIAL := "tutorial"
const TYPE_NORMAL := "normal"
const TYPE_MINI_BOSS := "mini_boss"
const TYPE_BOSS := "boss"
const TYPES: Array[String] = [TYPE_TUTORIAL, TYPE_NORMAL, TYPE_MINI_BOSS, TYPE_BOSS]

const MINI_BOSS_OPTIONAL := "optional"
const MINI_BOSS_MANDATORY := "mandatory"

const SEED_FIXED := "fixed_per_node"
const SEED_PER_ATTEMPT := "per_attempt"
const SEED_POLICIES: Array[String] = [SEED_FIXED, SEED_PER_ATTEMPT]

const GOD_FIXED := "fixed"
const GOD_GENERATED := "generated"
const GOD_MIRRORED := "mirrored"
const GOD_PROFILE := "profile"
const GOD_POLICIES: Array[String] = [GOD_FIXED, GOD_GENERATED, GOD_MIRRORED, GOD_PROFILE]

const DECK_FIXED := "fixed"
const DECK_GENERATED := "generated"
const DECK_MIRRORED := "mirrored"
const DECK_DRAFT := "draft"
const DECK_POLICIES: Array[String] = [DECK_FIXED, DECK_GENERATED, DECK_MIRRORED, DECK_DRAFT]

const PER_ATTEMPT_STRIDE: int = 104729

var id: String = ""
var name: String = ""
var chapter: String = ""
var region: String = ""
var type: String = TYPE_NORMAL
var position: Vector2 = Vector2.ZERO
var dead_end: bool = false
var mini_boss_kind: String = ""
var tutorial_id: String = ""
## Etape de progression et profil d'equilibrage produits par l'outil
## d'authoring. Ils sont descriptifs et ne pilotent pas la progression joueur.
var stage_id: String = ""
var balance_profile: String = ""
## Identité de dieu utilisée pour l'accent de carte et les statistiques de
## thème. Elle ne force jamais le dieu adverse des modes Aléatoire ou Miroir.
var theme_god_id: String = ""
var accent: String = ""
var encounter: Dictionary = {}
var visual: Dictionary = {}
## Copie brute utilisée par le validateur pour refuser les champs de structure
## interdits (route choisie, branche principale, difficulté de chemin...).
var raw: Dictionary = {}


static func from_dict(source: Dictionary) -> CampaignNode:
	var node := CampaignNode.new()
	node.raw = source.duplicate(true)
	node.id = str(source.get("id", ""))
	node.name = str(source.get("name", ""))
	node.chapter = str(source.get("chapter", ""))
	node.region = str(source.get("region", ""))
	node.type = str(source.get("type", TYPE_NORMAL))
	var point: Variant = source.get("position", {})
	if point is Dictionary:
		node.position = Vector2(float(point.get("x", 0.0)), float(point.get("y", 0.0)))
	node.dead_end = bool(source.get("dead_end", false))
	node.mini_boss_kind = str(source.get("mini_boss_kind", ""))
	node.tutorial_id = str(source.get("tutorial_id", ""))
	node.stage_id = str(source.get("stage_id", ""))
	node.balance_profile = str(source.get("balance_profile", ""))
	node.theme_god_id = str(source.get("theme_god_id", ""))
	node.accent = str(source.get("accent", ""))
	var raw_encounter: Variant = source.get("encounter", {})
	node.encounter = (raw_encounter as Dictionary).duplicate(true) if raw_encounter is Dictionary else {}
	var raw_visual: Variant = source.get("visual", {})
	node.visual = (raw_visual as Dictionary).duplicate(true) if raw_visual is Dictionary else {}
	return node


func game_mode() -> String:
	return str(encounter.get("game_mode", GameModeRules.MODE_CLASSIC))


func opponent_god_policy() -> String:
	return str(encounter.get("opponent_god_policy", GOD_FIXED))


func opponent_deck_policy() -> String:
	return str(encounter.get("opponent_deck_policy", DECK_FIXED))


func fixed_god_id() -> String:
	return str(encounter.get("fixed_god_id", ""))


func theme_god() -> String:
	return theme_god_id


func fixed_deck() -> Array:
	var value: Variant = encounter.get("fixed_deck", [])
	return (value as Array).duplicate() if value is Array else []


## Contraintes optionnelles des modes générés. Un nœud ordinaire laisse ces
## champs vides ; les mini-boss peuvent imposer un dieu, une pureté de deck ou
## un deck miroir exact sans changer les règles partagées des modes.
func generator_god_id() -> String:
	return str(encounter.get("generator_god_id", ""))


func generator_min_god_cards() -> int:
	# Ne jamais corriger silencieusement la donnée source : le validateur doit
	# pouvoir signaler une valeur négative ou supérieure à la taille du deck.
	return int(encounter.get("generator_min_god_cards", 0))


func mirror_fixed_deck() -> Array:
	var value: Variant = encounter.get("mirror_fixed_deck", [])
	return (value as Array).duplicate() if value is Array else []


func generation_constraints() -> Dictionary:
	return {
		"generator_god_id": generator_god_id(),
		"generator_min_god_cards": generator_min_god_cards(),
		"mirror_fixed_deck": mirror_fixed_deck(),
	}


func max_power_tier() -> int:
	return int(encounter.get("max_power_tier", GameModeRules.DEFAULT_POWER_TIER))


func ai_profile() -> Dictionary:
	var value: Variant = encounter.get("ai_profile", {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func series_format() -> String:
	return SeriesRules.normalized(str(encounter.get("series_format", SeriesRules.SERIES_FT1)))


func seed_policy() -> String:
	return str(encounter.get("seed_policy", SEED_FIXED))


func declared_seed() -> int:
	return int(encounter.get("seed", 0))


## Les contenus générés doivent varier à chaque nouvelle tentative. Les miroirs
## dont le deck est explicitement écrit restent, eux, des rencontres signées.
func requires_per_attempt_seed() -> bool:
	var mode := game_mode()
	if mode == GameModeRules.MODE_RANDOM or mode == GameModeRules.MODE_DRAFT:
		return true
	if mode == GameModeRules.MODE_MIRROR:
		return mirror_fixed_deck().is_empty()
	return mode == GameModeRules.MODE_CLASSIC \
		and opponent_deck_policy() == DECK_GENERATED


## Identifiant d'une rencontre des anciennes campagnes, indépendant du nouvel
## équilibrage. Il permet de réduire une précision ou un palier sans perdre la
## migration d'une victoire déjà enregistrée dans les statistiques historiques.
func declared_legacy_opponent_id() -> String:
	return str(encounter.get("legacy_opponent_id", ""))


## Paramètres de plateau facultatifs. Les valeurs absentes conservent le
## comportement historique 4 × 4 / huit cartes / terrain tiré au sort.
func board_size() -> int:
	return clampi(int(encounter.get("board_size", GameState.DEFAULT_BOARD_SIZE)),
		GameState.MIN_BOARD_SIZE, GameState.MAX_BOARD_SIZE)


func player_hand_size() -> int:
	return clampi(int(encounter.get("player_hand_size", DeckRules.DECK_SIZE)),
		1, DeckRules.DECK_SIZE)


func opponent_hand_size() -> int:
	return clampi(int(encounter.get("opponent_hand_size", DeckRules.DECK_SIZE)),
		1, DeckRules.DECK_SIZE)


func allows_incomplete_player_deck() -> bool:
	return bool(encounter.get("allow_incomplete_player_deck", false))


func fixed_blocked_cells() -> Array:
	var value: Variant = encounter.get("blocked_cells", null)
	return (value as Array).duplicate(true) if value is Array else []


func uses_random_blocked_cells() -> bool:
	return not encounter.has("blocked_cells")


func forced_first_player() -> int:
	return clampi(int(encounter.get("forced_first_player", GameState.PLAYER_NONE)),
		GameState.PLAYER_NONE, GameState.PLAYER_AI)


func reward_definition() -> Dictionary:
	var value: Variant = raw.get("rewards", {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func match_setup() -> Dictionary:
	return {
		"board_size": board_size(),
		"player_hand_size": player_hand_size(),
		"opponent_hand_size": opponent_hand_size(),
		"allow_incomplete_player_deck": allows_incomplete_player_deck(),
		"blocked_cells": fixed_blocked_cells(),
		"random_blocked_cells": uses_random_blocked_cells(),
		"forced_first_player": forced_first_player(),
	}


## Graine reproductible : campagne + nœud + graine déclarée. Seule la politique
## per_attempt ajoute la tentative, ce qui évite qu'un niveau change sans raison.
func resolved_seed(campaign_version: int, attempt: int = 0) -> int:
	var base := ("%d:%s:%d" % [campaign_version, id, declared_seed()]).hash()
	if seed_policy() == SEED_PER_ATTEMPT:
		return base + maxi(0, attempt) * PER_ATTEMPT_STRIDE
	return base


func is_tutorial() -> bool:
	return type == TYPE_TUTORIAL


func is_mini_boss() -> bool:
	return type == TYPE_MINI_BOSS


func is_boss() -> bool:
	return type == TYPE_BOSS


func is_optional_mini_boss() -> bool:
	return is_mini_boss() and mini_boss_kind == MINI_BOSS_OPTIONAL


func is_mandatory_mini_boss() -> bool:
	return is_mini_boss() and mini_boss_kind == MINI_BOSS_MANDATORY


## Un mode qui n'est pas le Classique FT1 conserve des loadouts et un score de
## série au-delà d'une manche : la session doit exister même sans draft.
func needs_series_session() -> bool:
	return game_mode() != GameModeRules.MODE_CLASSIC \
		or series_format() != SeriesRules.SERIES_FT1


func needs_preparation() -> bool:
	return GameModeRules.requires_preparation(game_mode())


func type_label() -> String:
	match type:
		TYPE_TUTORIAL:
			return "Tutoriel"
		TYPE_MINI_BOSS:
			return "Mini-boss obligatoire" if is_mandatory_mini_boss() else "Mini-boss facultatif"
		TYPE_BOSS:
			return "Boss final"
	return "Rencontre"
