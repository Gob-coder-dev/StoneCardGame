## Format de sauvegarde et migration des profils, sans lecture/écriture disque.
extends RefCounted
const VERSION := 3

static func default_stats() -> Dictionary:
	return {"games_played": 0, "wins": 0, "losses": 0, "draws": 0,
		"current_streak": 0, "best_streak": 0, "total_captures": 0, "per_npc": {}}

static func encode(decks: Dictionary, selections: Dictionary, god: String, player_name: String, stats: Dictionary) -> Dictionary:
	return {"save_version": VERSION, "decks_by_god": decks.duplicate(true),
		"selected_deck_by_god": selections.duplicate(),
		"player_god_id": god, "player_name": player_name, "stats": stats.duplicate(true)}

static func decode(raw: Dictionary) -> Dictionary:
	var legacy_deck: Array = raw.get("player_deck", []) if raw.get("player_deck", []) is Array else []
	var god := str(raw.get("player_god_id", ""))
	# Les sauvegardes sans version/dieu utilisent la famille qui conserve le plus de cartes.
	if StoneLoader.get_god(god).is_empty():
		god = StoneLoader.best_god_for_deck(legacy_deck)
	var player_name := str(raw.get("player_name", "Joueur")).strip_edges()
	if player_name.length() < 2 or player_name.length() > 16:
		player_name = "Joueur"
	var stats := default_stats()
	if raw.get("stats") is Dictionary:
		stats.merge(raw["stats"].duplicate(true), true)
	var decks := _decode_decks(raw, god, legacy_deck)
	var selections := {}
	var saved_selections: Dictionary = raw.get("selected_deck_by_god", {}) if raw.get("selected_deck_by_god") is Dictionary else {}
	for god_id in decks:
		selections[god_id] = _decode_slot(saved_selections.get(god_id, 0))
	return encode(decks, selections, god, player_name, stats)


## Toujours trois tableaux distincts par dieu. Chaque deck est nettoyé dans
## sa propre famille ; un changement de dieu ne modifie jamais les autres banques.
static func _decode_decks(raw: Dictionary, active_god: String, legacy_deck: Array) -> Dictionary:
	var saved: Dictionary = raw.get("decks_by_god", {}) if raw.get("decks_by_god") is Dictionary else {}
	var decks := {}
	for definition in StoneLoader.get_all_gods():
		var god_id := str(definition["id"])
		var slots: Array = []
		var saved_slots: Array = saved.get(god_id, []) if saved.get(god_id) is Array else []
		for slot in range(DeckRules.DECKS_PER_GOD):
			var cards: Array = saved_slots[slot] if slot < saved_slots.size() and saved_slots[slot] is Array else []
			slots.append(DeckRules.sanitize_deck(cards, god_id))
		decks[god_id] = slots
	# Version 1 et profils sans version : conserver le deck dans l'emplacement 1.
	if not raw.has("decks_by_god") and decks.has(active_god):
		decks[active_god][0] = DeckRules.sanitize_deck(legacy_deck, active_god)
	return decks


static func _decode_slot(value: Variant) -> int:
	if (value is int or value is float) and value >= 0 and value < DeckRules.DECKS_PER_GOD:
		var index := int(value)
		if float(index) == float(value):
			return index
	return 0
