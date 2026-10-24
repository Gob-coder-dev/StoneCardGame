## PlayerData.gd
## Autoload singleton — données persistantes de la session de jeu.
## NB : pas de class_name ici — le nom "PlayerData" est défini dans project.godot
##      comme AutoLoad. Un class_name sur un AutoLoad crée un conflit dans Godot 4.
##
## À déclarer comme AutoLoad dans Project Settings :
##   Nom : PlayerData
##   Chemin : res://scripts/data/PlayerData.gd
extends Node

const SaveCodec := preload("res://scripts/data/PlayerSaveCodec.gd")
const SaveStorage := preload("res://scripts/data/PlayerSaveStorage.gd")

## Source unique des decks : trois emplacements par dieu, indices de 0 à 2.
## Les lectures renvoient des copies ; les écritures passent par les méthodes ci-dessous.
var _decks_by_god: Dictionary = {}
var _selected_deck_by_god: Dictionary = {}

## Dieu équipé : il détermine les familles de cartes accessibles au deck.
var player_god_id: String = ""

## Nom local du joueur, affiché dans les menus et pendant les combats.
var player_name: String = "Joueur"

## ─── Statistiques persistantes ────────────────────────────────────────────────
## Structure :
## {
##   "games_played", "wins", "losses", "draws",
##   "current_streak", "best_streak", "total_captures",
##   "per_npc": { "<npc_id>": { "wins": int, "games": int, "best_diff": int } }
## }
var stats: Dictionary = _default_stats()


func _default_stats() -> Dictionary:
	return SaveCodec.default_stats()



func win_rate() -> int:
	var g: int = stats.get("games_played", 0)
	if g == 0:
		return 0
	return int(round(float(stats.get("wins", 0)) / float(g) * 100.0))


## Enregistre le résultat d'une partie.
## winner : 1 = humain, 2 = IA, 0 = égalité
## captures_by_human : nombre de captures réalisées par le joueur dans la partie
func record_game(npc_id: String, winner: int, score_human: int, score_ai: int, captures_by_human: int) -> void:
	stats["games_played"] = stats.get("games_played", 0) + 1
	stats["total_captures"] = stats.get("total_captures", 0) + captures_by_human

	match winner:
		1:  # victoire humaine
			stats["wins"] = stats.get("wins", 0) + 1
			stats["current_streak"] = stats.get("current_streak", 0) + 1
			if stats["current_streak"] > stats.get("best_streak", 0):
				stats["best_streak"] = stats["current_streak"]
		2:  # défaite
			stats["losses"] = stats.get("losses", 0) + 1
			stats["current_streak"] = 0
		_:  # égalité
			stats["draws"] = stats.get("draws", 0) + 1
			stats["current_streak"] = 0

	## Progression par NPC
	var per_npc: Dictionary = stats.get("per_npc", {})
	if not per_npc.has(npc_id):
		per_npc[npc_id] = { "wins": 0, "games": 0, "best_diff": -99 }
	per_npc[npc_id]["games"] += 1
	if winner == 1:
		per_npc[npc_id]["wins"] += 1
	var diff: int = score_human - score_ai
	if diff > per_npc[npc_id]["best_diff"]:
		per_npc[npc_id]["best_diff"] = diff
	stats["per_npc"] = per_npc

	save()


## Un NPC est "battu" si le joueur l'a emporté au moins une fois
func is_npc_beaten(npc_id: String) -> bool:
	var per_npc: Dictionary = stats.get("per_npc", {})
	return per_npc.has(npc_id) and per_npc[npc_id].get("wins", 0) > 0


func npc_record(npc_id: String) -> Dictionary:
	var per_npc: Dictionary = stats.get("per_npc", {})
	return per_npc.get(npc_id, { "wins": 0, "games": 0, "best_diff": -99 })


## ─── Persistance ─────────────────────────────────────────────────────────────

const SAVE_PATH: String = "user://savegame.json"
var _save_path: String


## Le chemin peut être fourni à une instance isolée pour les tests.
func _init(save_path: String = SAVE_PATH) -> void:
	_save_path = save_path


func get_profile() -> Dictionary:
	return SaveCodec.encode(_decks_by_god, _selected_deck_by_god, player_god_id, player_name, stats)


func save() -> Error:
	var error := SaveStorage.write(_save_path, get_profile())
	if error != OK:
		push_error("PlayerData: profil non enregistré (%s)." % error_string(error))
	return error


func load_save() -> void:
	_apply_profile(SaveCodec.decode(SaveStorage.read(_save_path)))


func _apply_profile(profile: Dictionary) -> void:
	_decks_by_god = profile["decks_by_god"].duplicate(true)
	_selected_deck_by_god = profile["selected_deck_by_god"].duplicate()
	player_god_id = profile["player_god_id"]
	player_name = profile["player_name"]
	stats = profile["stats"]


func _ready() -> void:
	load_save()


## Change le pseudo si sa longueur est comprise entre 2 et 16 caractères.
func set_player_name(value: String) -> bool:
	var clean := value.strip_edges()
	if clean.length() < 2 or clean.length() > 16:
		return false
	player_name = clean
	save()
	return true


## Copie du deck sélectionné, utilisée par la collection, l'accueil et le combat.
func get_active_deck() -> Array:
	return get_deck(player_god_id, get_selected_deck())


func get_deck(god_id: String, slot: int) -> Array:
	if not _decks_by_god.has(god_id) or slot < 0 or slot >= DeckRules.DECKS_PER_GOD:
		return []
	return _decks_by_god[god_id][slot].duplicate()


func get_selected_deck(god_id: String = "") -> int:
	return int(_selected_deck_by_god.get(player_god_id if god_id == "" else god_id, 0))


## Chaque opération est enregistrée avant d'être annoncée comme réussie.
## En cas d'échec d'écriture, l'état précédent reste actif.
func set_player_deck(value: Array) -> bool:
	if not _decks_by_god.has(player_god_id) or not DeckRules.validate_deck(value, false, player_god_id)["valid"]:
		return false
	var slot := get_selected_deck()
	var previous := get_active_deck()
	if previous == value:
		return true
	_decks_by_god[player_god_id][slot] = value.duplicate()
	if save() != OK:
		_decks_by_god[player_god_id][slot] = previous
		return false
	return true


## Ouvre la banque du dieu et retrouve son dernier emplacement sélectionné.
func set_player_god(god_id: String) -> bool:
	if not _decks_by_god.has(god_id):
		return false
	if god_id == player_god_id:
		return true
	var previous := player_god_id
	player_god_id = god_id
	if save() != OK:
		player_god_id = previous
		return false
	return true


func set_selected_deck(slot: int) -> bool:
	if not _decks_by_god.has(player_god_id) or slot < 0 or slot >= DeckRules.DECKS_PER_GOD:
		return false
	var previous := get_selected_deck()
	if slot == previous:
		return true
	_selected_deck_by_god[player_god_id] = slot
	if save() != OK:
		_selected_deck_by_god[player_god_id] = previous
		return false
	return true
