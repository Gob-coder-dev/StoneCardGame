## StoneLoader.gd
## Charge et met en cache les données des pierres depuis stones.json.
## Utilisé comme Autoload (singleton) dans le projet.
## NB : pas de class_name ici — le nom "StoneLoader" est défini dans project.godot
##      comme AutoLoad, ce qui le rend accessible globalement sans class_name.
##
## Accès depuis n'importe quel script : StoneLoader.get_stone("ashigaru")
extends Node

const ContentChecks := preload("res://scripts/data/ContentValidator.gd")

const STONES_PATH: String = "res://data/stones.json"
const NPCS_PATH: String = "res://data/npcs.json"
const GODS_PATH: String = "res://data/gods.json"

## Dictionnaire indexé par stone_id -> dict complet de la pierre
var _stones: Dictionary = {}

## Liste ordonnée de toutes les pierres (pour affichage collection)
var _stones_list: Array = []

## Dictionnaire indexé par npc_id -> dict complet du NPC
var _npcs: Dictionary = {}

## Dieux jouables et ordre d'affichage.
var _gods: Dictionary = {}
var _gods_list: Array = []
var _default_god_id: String = ""


func _ready() -> void:
	_load_stones()
	_load_gods()
	_load_npcs()
	for problem in ContentChecks.find_problems(_stones_list, _gods, _npcs.values(), _default_god_id):
		push_error("StoneLoader: " + problem)


## ─── Chargement ───────────────────────────────────────────────────────────────

func _load_stones() -> void:
	var file := FileAccess.open(STONES_PATH, FileAccess.READ)
	if file == null:
		push_error("StoneLoader: impossible d'ouvrir %s" % STONES_PATH)
		return
	var content := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(content)
	if parsed == null or not parsed.has("stones"):
		push_error("StoneLoader: format JSON invalide dans %s" % STONES_PATH)
		return

	for stone in parsed["stones"]:
		_stones[stone["id"]] = stone
		_stones_list.append(stone)

	print("StoneLoader: %d pierres chargées." % _stones_list.size())


func _load_npcs() -> void:
	var file := FileAccess.open(NPCS_PATH, FileAccess.READ)
	if file == null:
		push_error("StoneLoader: impossible d'ouvrir %s" % NPCS_PATH)
		return
	var content := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(content)
	if parsed == null or not parsed.has("npcs"):
		push_error("StoneLoader: format JSON invalide dans %s" % NPCS_PATH)
		return

	for npc in parsed["npcs"]:
		_npcs[npc["id"]] = npc

	print("StoneLoader: %d NPCs chargés." % _npcs.size())


func _load_gods() -> void:
	var file := FileAccess.open(GODS_PATH, FileAccess.READ)
	if file == null:
		push_error("StoneLoader: impossible d'ouvrir " + GODS_PATH)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not parsed.get("gods") is Array:
		push_error("StoneLoader: catalogue de dieux invalide")
		return
	_default_god_id = str(parsed.get("default_god_id", ""))
	for god in parsed["gods"]:
		_gods[str(god["id"])] = god
		_gods_list.append(god)


## ─── Accès aux pierres ────────────────────────────────────────────────────────

## Copie complète de la définition : l'appelant peut la modifier sans toucher
## au catalogue. Pour une simple question, préférer les lectures ci-dessous.
func get_stone(stone_id: String) -> Dictionary:
	return _stones.get(stone_id, {}).duplicate(true)


## Lectures indexées sans copie, pour les questions posées des milliers de fois
## pendant les simulations. Elles ne renvoient qu'un booléen : le catalogue
## reste protégé.
func has_stone(stone_id: String) -> bool:
	return _stones.has(stone_id)


func has_effect(stone_id: String, effect: String) -> bool:
	var stone = _stones.get(stone_id)
	if stone == null:
		return false
	var effects = stone.get("effects")
	return effects is Array and effects.has(effect)


## Enregistre une pierre fabriquée à la main (utilisé par les tests unitaires
## pour injecter des pierres de lames connues sans dépendre de stones.json).
func register_stone(stone_id: String, top: int, bottom: int, left: int, right: int, extras: Dictionary = {}) -> void:
	var stone := {
		"id": stone_id,
		"name": stone_id,
		"blades": { "top": top, "bottom": bottom, "left": left, "right": right }
	}
	stone.merge(extras, true)
	_stones[stone_id] = stone


## Retourne toutes les pierres sous forme de liste.
func get_all_stones() -> Array:
	return _stones_list.duplicate(true)


## Coût d'une pierre du catalogue, 0 si introuvable. La règle vit dans StoneCostRules.
func stone_cost(stone_id: String) -> float:
	# StoneCostRules lit seulement la définition : inutile de la copier.
	return StoneCostRules.cost(_stones.get(stone_id, {}))


func build_hand(stone_ids: Array) -> Array:
	var hand: Array = []
	for sid in stone_ids:
		if _stones.has(sid):
			hand.append(sid)
		else:
			push_error("StoneLoader: pierre '%s' introuvable." % sid)
	return hand

## ─── Accès aux NPCs ───────────────────────────────────────────────────────────

func get_npc(npc_id: String) -> Dictionary:
	return _npcs.get(npc_id, {}).duplicate(true)


## Retourne la liste des NPCs triée par difficulté (easy → hard)
func get_npcs_ordered() -> Array:
	var order := { "easy": 0, "medium": 1, "hard": 2 }
	var list := _npcs.values().duplicate(true)
	list.sort_custom(func(a, b):
		return order.get(a["difficulty"], 99) < order.get(b["difficulty"], 99)
	)
	return list


## ─── Accès aux dieux et aux familles ────────────────────────────────────────

func get_god(god_id: String) -> Dictionary:
	return _gods.get(god_id, {}).duplicate(true)


func get_all_gods() -> Array:
	return _gods_list.duplicate(true)


func default_god_id() -> String:
	if _gods.has(_default_god_id):
		return _default_god_id
	return str(_gods_list[0].get("id", "")) if not _gods_list.is_empty() else ""


func is_stone_available_to_god(stone_id: String, god_id: String) -> bool:
	if not _gods.has(god_id):
		return false
	var affinity := stone_affinity(stone_id)
	return affinity != "" and (affinity == "neutral" or affinity == god_id)


## Lecture du catalogue sans copie : famille de la pierre, ou "" si inconnue.
## L'activation d'un pouvoir posé appartient à CombatBoard, pas au catalogue.
func stone_affinity(stone_id: String) -> String:
	var stone: Dictionary = _stones.get(stone_id, {})
	if stone.is_empty():
		return ""
	return str(stone.get("god_id", "neutral"))


func get_stones_for_god(god_id: String) -> Array:
	var result: Array = []
	for stone in _stones_list:
		if is_stone_available_to_god(str(stone["id"]), god_id):
			result.append(stone.duplicate(true))
	return result


## Migration des sauvegardes antérieures au système de dieux : choisit le dieu
## qui rend le plus de cartes de l'ancien deck encore accessibles.
func best_god_for_deck(stone_ids: Array) -> String:
	var best_id := default_god_id()
	var best_count := -1
	for god in _gods_list:
		var god_id := str(god.get("id", ""))
		var available := 0
		for raw_id in stone_ids:
			if is_stone_available_to_god(str(raw_id), god_id):
				available += 1
		if available > best_count:
			best_count = available
			best_id = god_id
	return best_id
