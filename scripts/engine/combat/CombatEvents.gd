## Vocabulaire partagé et construction des événements de combat.
## Les champs restent des données sérialisables, sans nœuds ni positions écran.
class_name CombatEvents
extends RefCounted

const RANDOM_BLADE := "random_blade"
const COIN_FLIP := "coin_flip"
const WEAKEN := "weaken"
const TEMPORARY_WEAKEN := "temporary_weaken"
const WEAKNESS_EXPIRED := "weakness_expired"
const SHIELD_THEFT := "shield_theft"
const SWARM_CHANGE := "swarm_change"

static func random_blade(side: String) -> Dictionary:
	return {"type": RANDOM_BLADE, "side": side}

static func coin_flip(axis: String, flipped: bool) -> Dictionary:
	return {"type": COIN_FLIP, "axis": axis, "flipped": flipped}

static func weakness(kind: String, row: int, col: int, before: int, after: int, source_row: int = -1, source_col: int = -1, scope: String = "") -> Dictionary:
	return {"type": kind, "row": row, "col": col, "amount": absi(after - before),
		"weakness_before": before, "weakness_after": after,
		"source_row": source_row, "source_col": source_col, "scope": scope}

static func shield_theft(row: int, col: int, placements: Array, before: Dictionary, captures: Array, transfers: Array) -> Dictionary:
	return {"type": SHIELD_THEFT, "row": row, "col": col, "amount": transfers.size(),
		"placements": placements, "shields_before": before,
		"origins": captures.duplicate(true), "transfers": transfers}

static func swarm_change(row: int, col: int, members: Array, before: Array, after: Array) -> Dictionary:
	return {"type": SWARM_CHANGE, "source_row": row, "source_col": col,
		"members": members, "links_before": before, "links_after": after}
