## Format de sauvegarde et migration des profils, sans lecture/écriture disque.
extends RefCounted
const VERSION := 1

static func default_stats() -> Dictionary:
	return {"games_played": 0, "wins": 0, "losses": 0, "draws": 0,
		"current_streak": 0, "best_streak": 0, "total_captures": 0, "per_npc": {}}

static func encode(deck: Array, god: String, player_name: String, stats: Dictionary) -> Dictionary:
	return {"save_version": VERSION, "player_deck": deck.duplicate(),
		"player_god_id": god, "player_name": player_name, "stats": stats.duplicate(true)}

static func decode(raw: Dictionary) -> Dictionary:
	var deck: Array = raw.get("player_deck", []) if raw.get("player_deck", []) is Array else []
	var god := str(raw.get("player_god_id", ""))
	# Les sauvegardes sans version/dieu utilisent la famille qui conserve le plus de cartes.
	if StoneLoader.get_god(god).is_empty():
		god = StoneLoader.best_god_for_deck(deck)
	var player_name := str(raw.get("player_name", "Joueur")).strip_edges()
	if player_name.length() < 2 or player_name.length() > 16:
		player_name = "Joueur"
	var stats := default_stats()
	if raw.get("stats") is Dictionary:
		stats.merge(raw["stats"].duplicate(true), true)
	return encode(DeckRules.sanitize_deck(deck, god), god, player_name, stats)
