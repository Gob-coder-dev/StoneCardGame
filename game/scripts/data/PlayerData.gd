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
## Émis après chaque écriture de l'état des quêtes, dans la même sauvegarde
## atomique que les monnaies lorsqu'une récompense est réclamée.
signal quests_changed

const SaveCodec := preload("res://scripts/data/PlayerSaveCodec.gd")
const StatsRules := preload("res://scripts/domain/ProfileStatsRules.gd")
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
## État brut des quêtes, écrit et relu par QuestService.
var _quests: Dictionary = {}
## Reçu et identité de la manche dont les autres écritures restent à confirmer.
var _pending_campaign_result: Dictionary = {}
var _profile_revision := 0

## Dieu équipé : il détermine les familles de cartes accessibles au deck.
var player_god_id: String = ""

## Nom local du joueur, affiché dans les menus et pendant les combats.
var player_name: String = "Joueur"

## ─── Statistiques persistantes ────────────────────────────────────────────────
## Totaux, records et ventilations par contexte, dieu joué et mode.
var stats: Dictionary = _default_stats()
## Uniquement conservé jusqu'à la conversion réussie du fichier de campagne.
var legacy_campaign_stats: Dictionary = {}


func _default_stats() -> Dictionary:
	return SaveCodec.default_stats()



func win_rate() -> int:
	return StatsRules.win_rate(stats)


## Enregistre une manche terminée : winner 1 = local, 2 = adverse, 0 = égalité.
func record_match(result: Dictionary, result_key: String = "") -> Error:
	return _commit_stats(StatsRules.record_match(stats, result, result_key))


func record_match_with_quests(result: Dictionary, key: String,
		inventory: PlayerInventory, quests: Dictionary) -> Error:
	if inventory == null:
		return ERR_INVALID_PARAMETER
	if key != "" and stats.get("recent_results", []).has(key):
		return OK
	return _commit_stats(StatsRules.record_match(stats, result, key), inventory, null, quests)


func pending_campaign_result() -> Dictionary:
	return _pending_campaign_result.duplicate(true)


## Le résultat local, son reçu et l'inventaire associé partagent la même écriture.
func stage_campaign_result(pending: Dictionary, inventory: PlayerInventory,
		neutral_deck_override: Variant = null) -> Error:
	if not _pending_campaign_result.is_empty():
		return ERR_BUSY
	_pending_campaign_result = pending.duplicate(true)
	var next_stats := StatsRules.record_match(stats, pending["result"], pending["key"])
	var error := _commit_stats(next_stats, inventory, neutral_deck_override)
	if error != OK:
		_pending_campaign_result = {}
	return error


func finish_campaign_result(key: String) -> Error:
	if _pending_campaign_result.get("key") != key:
		return ERR_INVALID_DATA
	var previous := _pending_campaign_result
	_pending_campaign_result = {}
	var error := save()
	if error != OK:
		_pending_campaign_result = previous
	return error


## Un abandon casse la série de victoires sans inventer une manche jouée.
func record_forfeit(result: Dictionary = {}) -> Error:
	# Un abandon de série n'est pas une manche supplémentaire.
	var next := stats.duplicate(true)
	next["current_streak"] = 0
	var scope := str(result.get("scope", "campaign"))
	var god := str(result.get("player_god_id", ""))
	if god == "":
		god = "godless"
	var mode := str(result.get("mode", "classic"))
	for pair in [["by_scope", scope], ["by_god", god], ["by_mode", mode],
			["by_god", "%s:%s" % [scope, god]], ["by_mode", "%s:%s" % [scope, mode]]]:
		if next.get(pair[0], {}).has(pair[1]):
			next[pair[0]][pair[1]]["current_streak"] = 0
	return _commit_stats(next)


func _commit_stats(next: Dictionary, inventory: PlayerInventory = null,
		neutral_deck_override: Variant = null, quests: Variant = null) -> Error:
	var previous := stats
	stats = next
	var error := save() if inventory == null else commit_economy(inventory, neutral_deck_override, quests)
	if error != OK:
		stats = previous
	return error


## Retire les anciens compteurs après écriture réussie de leur conversion.
func finish_campaign_migration() -> Error:
	if legacy_campaign_stats.is_empty():
		return OK
	var previous := legacy_campaign_stats
	legacy_campaign_stats = {}
	var error := save()
	if error != OK:
		legacy_campaign_stats = previous
	return error


## ─── Persistance ─────────────────────────────────────────────────────────────

const SAVE_PATH: String = "user://savegame.json"
var _save_path: String
## Une sauvegarde créée par une version future reste intacte, même après un achat.
var profile_load_error: Error = OK
var profile_load_notice: String = ""


## Le chemin peut être fourni à une instance isolée pour les tests.
func _init(save_path: String = SAVE_PATH) -> void:
	_save_path = save_path


func get_profile() -> Dictionary:
	return SaveCodec.encode(_decks_by_god, _selected_deck_by_god, player_god_id,
		player_name, stats, inventory_dict(), _quests, legacy_campaign_stats,
		_pending_campaign_result)


func profile_revision() -> int:
	return _profile_revision


func save() -> Error:
	if profile_load_error != OK:
		return profile_load_error
	var error := SaveStorage.write(_save_path, get_profile())
	if error != OK:
		push_error("PlayerData: profil non enregistré (%s)." % error_string(error))
	else:
		_profile_revision += 1
	return error


func load_save() -> void:
	var result := SaveStorage.read_result(_save_path, SaveCodec.is_complete)
	var raw: Dictionary = result["data"]
	profile_load_error = result["error"]
	profile_load_notice = ""
	if not SaveCodec.supports(raw):
		profile_load_error = ERR_UNAVAILABLE
		profile_load_notice = "Ce profil nécessite une version plus récente de Beastpact."
		raw = {}
	elif profile_load_error != OK:
		profile_load_notice = "Le profil est inaccessible. L’enregistrement est suspendu."
	elif result["state"] == SaveStorage.ReadState.RECOVERED:
		profile_load_notice = "Votre profil a été récupéré depuis la sauvegarde temporaire."
	elif result["state"] == SaveStorage.ReadState.ARCHIVED:
		profile_load_notice = "Le profil endommagé a été archivé. Un nouveau profil est ouvert."
	_apply_profile(SaveCodec.decode(raw))


func _apply_profile(profile: Dictionary) -> void:
	_decks_by_god = profile["decks_by_god"].duplicate(true)
	_selected_deck_by_god = profile["selected_deck_by_god"].duplicate()
	player_god_id = profile["player_god_id"]
	player_name = profile["player_name"]
	stats = profile["stats"]
	legacy_campaign_stats = profile.get("legacy_campaign_stats", {}).duplicate(true)
	_inventory = InventoryModel.from_dict(profile.get("inventory", {}))
	_quests = profile.get("quests", {}).duplicate(true) \
		if profile.get("quests", {}) is Dictionary else {}
	var pending: Variant = profile.get("pending_campaign_result", {})
	_pending_campaign_result = pending.duplicate(true) if pending is Dictionary else {}
	_profile_revision += 1


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


func quests_dict() -> Dictionary:
	return _quests.duplicate(true)


func souls() -> int:
	_ensure_inventory()
	return _inventory.souls


func candles() -> int:
	_ensure_inventory()
	return _inventory.candles


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


func pending_card_reward_count() -> int:
	_ensure_inventory()
	return _inventory.pending_lineage_count()


func pending_card_reward_copy_count() -> int:
	_ensure_inventory()
	return _inventory.pending_copy_count()


func pending_card_rewards_by_god() -> Dictionary:
	_ensure_inventory()
	return _inventory.pending_rewards_by_god().duplicate(true)


func owns_monster(monster_id: String) -> bool:
	_ensure_inventory()
	return _inventory.owns_monster(monster_id)


## Projection unique consommée par les jauges, tiroirs et fiches. Les vues ne
## relisent ainsi ni la configuration ni la même entrée d'inventaire deux fois.
func card_upgrade_state(lineage_id: String) -> Dictionary:
	_ensure_inventory()
	var entry := _inventory.entry(lineage_id)
	var config := EconomyConfigModel.get_config()
	var requirement := ProgressionRules.requirement(
		lineage_id, int(entry.get("unlocked_level", 0)), config)
	return {
		"entry": entry,
		"requirement": requirement,
		"can_upgrade": ProgressionRules.meets_requirement(entry, _inventory.souls, requirement),
	}


## Publie une copie économique seulement après l'écriture de tout le profil.
## Les services d'achat, de récompense et d'amélioration passent tous ici.
func commit_inventory(next: PlayerInventory) -> Error:
	return commit_economy(next)


## Transaction économique pouvant aussi compléter le deck neutre de départ.
## Inventaire et deck sont écrits dans le même fichier puis restaurés ensemble
## si le stockage échoue.
func commit_economy(next: PlayerInventory, neutral_deck_override: Variant = null,
		quests: Variant = null) -> Error:
	if next == null:
		return ERR_INVALID_PARAMETER
	_ensure_inventory()
	var previous_inventory := _inventory
	var previous_quests := _quests
	var previous_deck: Array
	var neutral_bank: Array = []
	var neutral_slot := -1
	if neutral_deck_override is Array:
		var candidate: Array = neutral_deck_override
		if not bool(DeckRules.validate_deck(candidate, false, "").get("valid", false)):
			return ERR_INVALID_DATA
		var neutral_key := SaveCodec.NEUTRAL_DECK_KEY
		neutral_bank = _decks_by_god[neutral_key]
		neutral_slot = int(_selected_deck_by_god.get(neutral_key, 0))
		previous_deck = neutral_bank[neutral_slot]
		neutral_bank[neutral_slot] = candidate.duplicate()
	var inventory_updated := not previous_inventory.same_visible_items(next)
	var quests_updated: bool = quests is Dictionary and _quests != quests
	_inventory = next
	if quests_updated:
		_quests = (quests as Dictionary).duplicate(true)
	var error := save()
	if error != OK:
		_inventory = previous_inventory
		_quests = previous_quests
		if neutral_slot >= 0:
			neutral_bank[neutral_slot] = previous_deck
	else:
		if inventory_updated or (neutral_slot >= 0 and previous_deck != neutral_bank[neutral_slot]):
			inventory_changed.emit()
		if quests_updated:
			quests_changed.emit()
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
	for monster_id in value:
		if not owns_monster(str(monster_id)):
			return false
		if god_id == "" and MonsterLoader.monster_affinity(str(monster_id)) != "neutral":
			return false
	return true


func _deck_key(god_id: String) -> String:
	return SaveCodec.NEUTRAL_DECK_KEY if god_id == "" else god_id


func _ensure_inventory() -> void:
	if _inventory == null:
		_inventory = InventoryModel.new()
