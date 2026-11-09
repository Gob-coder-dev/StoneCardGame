## PlayerData.gd
## Autoload singleton — données persistantes de la session de jeu.
## NB : pas de class_name ici — le nom "PlayerData" est défini dans project.godot
##      comme AutoLoad. Un class_name sur un AutoLoad crée un conflit dans Godot 4.
##
## À déclarer comme AutoLoad dans Project Settings :
##   Nom : PlayerData
##   Chemin : res://scripts/data/PlayerData.gd
extends Node

signal inventory_changed

const SaveCodec := preload("res://scripts/data/PlayerSaveCodec.gd")
const SaveStorage := preload("res://scripts/data/PlayerSaveStorage.gd")
const InventoryModel := preload("res://scripts/domain/economy/PlayerInventory.gd")
const ProgressionRules := preload("res://scripts/domain/economy/CardProgressionRules.gd")
const EconomyConfigModel := preload("res://scripts/data/economy/EconomyConfig.gd")

enum ProfileChange { SUCCESS, INVALID, SAVE_FAILED }

## Source unique des decks : trois emplacements par dieu, indices de 0 à 2.
## Les lectures renvoient des copies ; les écritures passent par les méthodes ci-dessous.
var _decks_by_god: Dictionary = {}
var _selected_deck_by_god: Dictionary = {}
var _inventory: PlayerInventory = null

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
func record_game(npc_id: String, winner: int, score_human: int, score_ai: int,
		captures_by_human: int) -> Error:
	var previous := stats.duplicate(true)
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

	var error := save()
	if error != OK:
		stats = previous
	return error


## Un NPC est "battu" si le joueur l'a emporté au moins une fois
func is_npc_beaten(npc_id: String) -> bool:
	var per_npc: Dictionary = stats.get("per_npc", {})
	return per_npc.has(npc_id) and per_npc[npc_id].get("wins", 0) > 0


func npc_record(npc_id: String) -> Dictionary:
	var per_npc: Dictionary = stats.get("per_npc", {})
	return per_npc.get(npc_id, { "wins": 0, "games": 0, "best_diff": -99 })


## ─── Persistance ─────────────────────────────────────────────────────────────

const SAVE_PATH: String = "user://savegame.json"
const CATALOGUE_BACKUP_SUFFIX := ".before_monsters"
var _save_path: String
var _pending_catalogue_backup: Dictionary = {}


## Le chemin peut être fourni à une instance isolée pour les tests.
func _init(save_path: String = SAVE_PATH) -> void:
	_save_path = save_path


func get_profile() -> Dictionary:
	return SaveCodec.encode(_decks_by_god, _selected_deck_by_god, player_god_id,
		player_name, stats, inventory_dict())


func save() -> Error:
	if not _pending_catalogue_backup.is_empty() and not FileAccess.file_exists(_save_path + CATALOGUE_BACKUP_SUFFIX):
		var backup_error := SaveStorage.write(_save_path + CATALOGUE_BACKUP_SUFFIX, _pending_catalogue_backup)
		if backup_error != OK:
			push_error("PlayerData: sauvegarde d'origine non conservée (%s)." % error_string(backup_error))
			return backup_error
	var error := SaveStorage.write(_save_path, get_profile())
	if error != OK:
		push_error("PlayerData: profil non enregistré (%s)." % error_string(error))
	else:
		_pending_catalogue_backup.clear()
	return error


func load_save() -> void:
	var raw := SaveStorage.read(_save_path)
	_apply_profile(SaveCodec.decode(raw))
	if SaveCodec.needs_catalogue_migration(raw):
		_pending_catalogue_backup = raw.duplicate(true)


func _apply_profile(profile: Dictionary) -> void:
	_pending_catalogue_backup = {}
	_decks_by_god = profile["decks_by_god"].duplicate(true)
	_selected_deck_by_god = profile["selected_deck_by_god"].duplicate()
	player_god_id = profile["player_god_id"]
	player_name = profile["player_name"]
	stats = profile["stats"]
	_inventory = InventoryModel.from_dict(profile.get("inventory", {}))


func _ready() -> void:
	load_save()


## Change le pseudo et l'enregistre avant d'annoncer le succès. Le résultat
## distingue une saisie invalide d'une erreur disque afin que l'interface puisse
## afficher le bon message.
func set_player_name(value: String) -> ProfileChange:
	var clean := value.strip_edges()
	if clean.length() < 2 or clean.length() > 16:
		return ProfileChange.INVALID
	if clean == player_name:
		return ProfileChange.SUCCESS
	var previous := player_name
	player_name = clean
	if save() != OK:
		player_name = previous
		return ProfileChange.SAVE_FAILED
	return ProfileChange.SUCCESS


## Copie du deck sélectionné, utilisée par la collection, l'accueil et le combat.
func get_active_deck() -> Array:
	return get_deck(player_god_id, get_selected_deck())


func get_deck(god_id: String, slot: int) -> Array:
	var key := _deck_key(god_id)
	if not _decks_by_god.has(key) or slot < 0 or slot >= DeckRules.DECKS_PER_GOD:
		return []
	return _decks_by_god[key][slot].duplicate()


func get_selected_deck(god_id: String = "") -> int:
	var actual_god := player_god_id if god_id == "" else god_id
	return int(_selected_deck_by_god.get(_deck_key(actual_god), 0))


## Chaque opération est enregistrée avant d'être annoncée comme réussie.
## En cas d'échec d'écriture, l'état précédent reste actif.
func set_player_deck(value: Array) -> bool:
	var key := _deck_key(player_god_id)
	if not _decks_by_god.has(key) or not _can_store_deck(value, player_god_id):
		return false
	var slot := get_selected_deck()
	var previous := get_active_deck()
	if previous == value:
		return true
	_decks_by_god[key][slot] = value.duplicate()
	if save() != OK:
		_decks_by_god[key][slot] = previous
		return false
	return true


## Ouvre la banque du dieu et retrouve son dernier emplacement sélectionné.
func set_player_god(god_id: String) -> bool:
	if god_id != "" and not has_unlocked_god(god_id):
		return false
	if not _decks_by_god.has(_deck_key(god_id)):
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
	var key := _deck_key(player_god_id)
	if not _decks_by_god.has(key) or slot < 0 or slot >= DeckRules.DECKS_PER_GOD:
		return false
	var previous := get_selected_deck()
	if slot == previous:
		return true
	_selected_deck_by_god[key] = slot
	if save() != OK:
		_selected_deck_by_god[key] = previous
		return false
	return true


func inventory_dict() -> Dictionary:
	_ensure_inventory()
	return _inventory.to_dict()


func souls() -> int:
	_ensure_inventory()
	return _inventory.souls


func unlocked_god_ids() -> Array:
	_ensure_inventory()
	var result: Array = _inventory.unlocked_gods.keys()
	result.sort()
	return result


func has_unlocked_god(god_id: String) -> bool:
	_ensure_inventory()
	return _inventory.has_god(god_id)


func card_entry(lineage_id: String) -> Dictionary:
	_ensure_inventory()
	return _inventory.entry(lineage_id)


func owns_stone(stone_id: String) -> bool:
	_ensure_inventory()
	return _inventory.owns_stone(stone_id)


func can_upgrade_card(lineage_id: String) -> bool:
	_ensure_inventory()
	return ProgressionRules.can_upgrade(lineage_id, _inventory.entry(lineage_id),
		_inventory.souls, EconomyConfigModel.get_config())


## Publie une copie économique seulement après l'écriture de tout le profil.
## Les services d'achat, de récompense et d'amélioration passent tous ici.
func commit_inventory(next: PlayerInventory) -> Error:
	return commit_economy(next)


## Transaction économique pouvant aussi compléter le deck neutre de départ.
## Inventaire et deck sont écrits dans le même fichier puis restaurés ensemble
## si le stockage échoue.
func commit_economy(next: PlayerInventory, neutral_deck_override: Variant = null) -> Error:
	if next == null:
		return ERR_INVALID_PARAMETER
	_ensure_inventory()
	var previous_inventory := _inventory
	var previous_decks := _decks_by_god.duplicate(true)
	_inventory = next
	if neutral_deck_override is Array:
		var candidate: Array = (neutral_deck_override as Array).duplicate()
		if not bool(DeckRules.validate_deck(candidate, false, "").get("valid", false)):
			_inventory = previous_inventory
			return ERR_INVALID_DATA
		var neutral_key := SaveCodec.NEUTRAL_DECK_KEY
		var slot := int(_selected_deck_by_god.get(neutral_key, 0))
		_decks_by_god[neutral_key][slot] = candidate
	var error := save()
	if error != OK:
		_inventory = previous_inventory
		_decks_by_god = previous_decks
	else:
		inventory_changed.emit()
	return error


func reset_to_starter_profile() -> Error:
	var previous := get_profile()
	_apply_profile(SaveCodec.starter_profile())
	var error := save()
	if error != OK:
		_apply_profile(previous)
	else:
		inventory_changed.emit()
	return error


func _can_store_deck(value: Array, god_id: String) -> bool:
	if not bool(DeckRules.validate_deck(value, false, god_id)["valid"]):
		return false
	for stone_id in value:
		if not owns_stone(str(stone_id)):
			return false
		if god_id == "" and StoneLoader.stone_affinity(str(stone_id)) != "neutral":
			return false
	return true


func _deck_key(god_id: String) -> String:
	return SaveCodec.NEUTRAL_DECK_KEY if god_id == "" else god_id


func _ensure_inventory() -> void:
	if _inventory == null:
		_inventory = InventoryModel.new()
