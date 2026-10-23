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

## Deck courant du joueur (Array de stone_id String)
var player_deck: Array = []

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


## ─── Persistance légère ──────────────────────────────────────────────────────

const SAVE_VERSION := SaveCodec.VERSION

const SAVE_PATH: String = "user://savegame.json"


func save() -> void:
	var data := SaveCodec.encode(player_deck, player_god_id, player_name, stats)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()


func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var content := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(content)
	if not parsed is Dictionary:
		return
	var profile := SaveCodec.decode(parsed)
	player_deck = profile["player_deck"]
	player_god_id = profile["player_god_id"]
	player_name = profile["player_name"]
	stats = profile["stats"]


func _ready() -> void:
	player_god_id = StoneLoader.default_god_id()
	load_save()


## Change le pseudo si sa longueur est comprise entre 2 et 16 caractères.
func set_player_name(value: String) -> bool:
	var clean := value.strip_edges()
	if clean.length() < 2 or clean.length() > 16:
		return false
	player_name = clean
	save()
	return true


## Remplace le deck persistant après validation. Les decks incomplets sont
## acceptés dans l'éditeur, mais jamais les doublons, inconnues ou dépassements.
func set_player_deck(value: Array) -> bool:
	if not DeckRules.validate_deck(value, false, player_god_id)["valid"]:
		return false
	player_deck = value.duplicate()
	save()
	return true


## Change de dieu et retire du deck les cartes devenues inaccessibles.
## Retourne la liste des cartes retirées pour que l'interface puisse l'annoncer.
func set_player_god(god_id: String) -> Array:
	if StoneLoader.get_god(god_id).is_empty():
		return []
	var previous := player_deck.duplicate()
	player_god_id = god_id
	player_deck = DeckRules.sanitize_deck(player_deck, player_god_id)
	var removed: Array = []
	for stone_id in previous:
		if not player_deck.has(stone_id):
			removed.append(stone_id)
	save()
	return removed
