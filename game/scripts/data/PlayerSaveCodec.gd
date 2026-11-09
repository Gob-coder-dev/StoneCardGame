## Format de sauvegarde et migration des profils, sans lecture/écriture disque.
extends RefCounted
const VERSION := 5
const DeckMigration := preload("res://scripts/data/DeckCatalogueMigration.gd")
const EconomyConfigModel := preload("res://scripts/data/economy/EconomyConfig.gd")
const InventoryModel := preload("res://scripts/domain/economy/PlayerInventory.gd")
const NEUTRAL_DECK_KEY := "neutral"

static func needs_catalogue_migration(raw: Dictionary) -> bool:
	if StoneLoader.resolve_saved_god_id(str(raw.get("player_god_id", ""))) != str(raw.get("player_god_id", "")):
		return true
	if raw.get("player_deck") is Array and DeckMigration.requires_conversion(raw["player_deck"]):
		return true
	if raw.get("decks_by_god") is Dictionary:
		for raw_god_id in raw["decks_by_god"]:
			if StoneLoader.resolve_saved_god_id(str(raw_god_id)) != str(raw_god_id):
				return true
		for bank in raw["decks_by_god"].values():
			if bank is Array:
				for deck in bank:
					if deck is Array and DeckMigration.requires_conversion(deck):
						return true
	if raw.get("stats") is Dictionary and raw["stats"].get("per_npc") is Dictionary:
		for raw_npc_id in raw["stats"]["per_npc"]:
			if StoneLoader.resolve_saved_npc_id(str(raw_npc_id)) != str(raw_npc_id):
				return true
	return false

static func default_stats() -> Dictionary:
	return {"games_played": 0, "wins": 0, "losses": 0, "draws": 0,
		"current_streak": 0, "best_streak": 0, "total_captures": 0, "per_npc": {}}

static func encode(decks: Dictionary, selections: Dictionary, god: String,
		player_name: String, stats: Dictionary, inventory: Dictionary = {}) -> Dictionary:
	var actual_inventory := inventory.duplicate(true) if not inventory.is_empty() \
		else _legacy_inventory().to_dict()
	return {"save_version": VERSION, "decks_by_god": decks.duplicate(true),
		"selected_deck_by_god": selections.duplicate(),
		"player_god_id": god, "player_name": player_name, "stats": stats.duplicate(true),
		"inventory": actual_inventory}

static func decode(raw: Dictionary) -> Dictionary:
	if raw.is_empty():
		return starter_profile()
	var legacy_deck: Array = raw.get("player_deck", []) if raw.get("player_deck", []) is Array else []
	var god := StoneLoader.resolve_saved_god_id(str(raw.get("player_god_id", "")))
	# Les sauvegardes sans version/dieu utilisent la famille qui conserve le plus de cartes.
	if god != "" and StoneLoader.get_god(god).is_empty():
		god = best_god_for_deck(legacy_deck)
	if not raw.has("inventory") and god == "":
		god = best_god_for_deck(legacy_deck)
	var player_name := str(raw.get("player_name", "Joueur")).strip_edges()
	if player_name.length() < 2 or player_name.length() > 16:
		player_name = "Joueur"
	var stats := default_stats()
	if raw.get("stats") is Dictionary:
		stats.merge(raw["stats"].duplicate(true), true)
	stats = _migrate_npc_stats(stats)
	var decks := _decode_decks(raw, god, legacy_deck)
	var selections := {}
	var saved_selections: Dictionary = raw.get("selected_deck_by_god", {}) if raw.get("selected_deck_by_god") is Dictionary else {}
	var canonical_selections := {}
	for raw_god_id in saved_selections:
		var god_id := StoneLoader.resolve_saved_god_id(str(raw_god_id))
		if not canonical_selections.has(god_id):
			canonical_selections[god_id] = saved_selections[raw_god_id]
	for god_id in decks:
		selections[god_id] = _decode_slot(canonical_selections.get(god_id, 0))
	var inventory := InventoryModel.from_dict(raw.get("inventory", {})) \
		if raw.has("inventory") else _legacy_inventory()
	if god != "" and not inventory.has_god(god):
		god = ""
	return encode(decks, selections, god, player_name, stats, inventory.to_dict())


static func starter_profile() -> Dictionary:
	var config := EconomyConfigModel.get_config()
	var starter: Dictionary = config.get("starter", {})
	var decks := _empty_deck_banks()
	var deck: Array = (starter.get("deck", []) as Array).duplicate()
	decks[NEUTRAL_DECK_KEY][0] = deck
	var selections := _empty_selections(decks)
	var inventory := InventoryModel.new()
	inventory.souls = maxi(0, int(starter.get("souls", 0)))
	for stone_id in deck:
		inventory.add_copies(StoneLoader.stone_lineage(str(stone_id)), 1)
	return encode(decks, selections, "", "Joueur", default_stats(), inventory.to_dict())


## Choisit le dieu qui conserve le plus de cartes d'un ancien deck. Cette règle
## appartient à la migration du profil, pas au catalogue de contenu.
static func best_god_for_deck(stone_ids: Array) -> String:
	var best_id := StoneLoader.default_god_id()
	var best_count := -1
	for god in StoneLoader.get_all_gods():
		var god_id := str(god.get("id", ""))
		var available := 0
		for raw_id in stone_ids:
			var stone_id := StoneLoader.resolve_saved_id(str(raw_id))
			if StoneLoader.is_stone_available_to_god(stone_id, god_id):
				available += 1
		if available > best_count:
			best_count = available
			best_id = god_id
	return best_id


## Toujours trois tableaux distincts par dieu. Chaque deck est nettoyé dans
## sa propre famille ; un changement de dieu ne modifie jamais les autres banques.
static func _decode_decks(raw: Dictionary, active_god: String, legacy_deck: Array) -> Dictionary:
	var saved: Dictionary = raw.get("decks_by_god", {}) if raw.get("decks_by_god") is Dictionary else {}
	var canonical_saved := {}
	for raw_god_id in saved:
		var resolved_god_id := StoneLoader.resolve_saved_god_id(str(raw_god_id))
		if not canonical_saved.has(resolved_god_id):
			canonical_saved[resolved_god_id] = saved[raw_god_id]
	var decks := _empty_deck_banks()
	for definition in StoneLoader.get_all_gods():
		var god_id := str(definition["id"])
		var slots: Array = []
		var saved_slots: Array = canonical_saved.get(god_id, []) if canonical_saved.get(god_id) is Array else []
		for slot in range(DeckRules.DECKS_PER_GOD):
			var cards: Array = saved_slots[slot] if slot < saved_slots.size() and saved_slots[slot] is Array else []
			slots.append(DeckMigration.convert(cards, god_id))
		decks[god_id] = slots
	var neutral_saved: Array = canonical_saved.get(NEUTRAL_DECK_KEY, []) \
		if canonical_saved.get(NEUTRAL_DECK_KEY) is Array else []
	for slot in range(DeckRules.DECKS_PER_GOD):
		var neutral_cards: Array = neutral_saved[slot] \
			if slot < neutral_saved.size() and neutral_saved[slot] is Array else []
		decks[NEUTRAL_DECK_KEY][slot] = _sanitize_neutral(neutral_cards)
	# Version 1 et profils sans version : conserver le deck dans l'emplacement 1.
	if not raw.has("decks_by_god") and decks.has(active_god):
		decks[active_god][0] = DeckMigration.convert(legacy_deck, active_god)
	return decks


static func _empty_deck_banks() -> Dictionary:
	var decks := {NEUTRAL_DECK_KEY: [[], [], []]}
	for definition in StoneLoader.get_all_gods():
		decks[str(definition["id"])] = [[], [], []]
	return decks


static func _empty_selections(decks: Dictionary) -> Dictionary:
	var result := {}
	for key in decks:
		result[str(key)] = 0
	return result


static func _sanitize_neutral(cards: Array) -> Array:
	var clean := DeckRules.sanitize_deck(cards)
	return clean.filter(func(stone_id):
		return StoneLoader.stone_affinity(str(stone_id)) == "neutral")


## Les profils antérieurs à l'économie conservent l'accès à leur contenu. Le
## profil de développement réel peut être remis à zéro explicitement sans que
## la migration détruise silencieusement une sauvegarde historique.
static func _legacy_inventory() -> PlayerInventory:
	var inventory := InventoryModel.new()
	inventory.first_god_discount_used = true
	for god in StoneLoader.get_all_gods():
		inventory.unlock_god(str(god.get("id", "")))
	var seen := {}
	for stone in StoneLoader.get_all_stones():
		var stone_id := str(stone.get("id", ""))
		var lineage_id := StoneLoader.stone_lineage(stone_id)
		if seen.has(lineage_id):
			continue
		seen[lineage_id] = true
		inventory.cards[lineage_id] = {
			"unlocked_level": StoneLoader.lineage_max_level(lineage_id),
			"copies": 0,
		}
	return inventory


static func _decode_slot(value: Variant) -> int:
	if (value is int or value is float) and value >= 0 and value < DeckRules.DECKS_PER_GOD:
		var index := int(value)
		if float(index) == float(value):
			return index
	return 0


static func _migrate_npc_stats(stats: Dictionary) -> Dictionary:
	var per_npc: Dictionary = stats.get("per_npc", {}) if stats.get("per_npc") is Dictionary else {}
	var canonical := {}
	for raw_npc_id in per_npc:
		var npc_id := StoneLoader.resolve_saved_npc_id(str(raw_npc_id))
		if not canonical.has(npc_id):
			canonical[npc_id] = per_npc[raw_npc_id]
	stats["per_npc"] = canonical
	return stats
