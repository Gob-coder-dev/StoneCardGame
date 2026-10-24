## Règles pures de composition et de modification d'un deck.
## La couche UI utilise les opérations try_* et ne modifie jamais le deck
## persistant directement.
class_name DeckRules
extends RefCounted

## Plateau 4×4 : sans case bloquée, chaque joueur pose 8 pierres.
const DECK_SIZE: int = 8
## 10 points en moyenne par pierre.
const DECK_BUDGET: int = 80

const REASON_UNKNOWN: String = "unknown_stone"
const REASON_DUPLICATE: String = "duplicate"
const REASON_FULL: String = "full"
const REASON_BUDGET: String = "budget"
const REASON_MISSING: String = "missing"
const REASON_GOD: String = "wrong_god"


static func deck_cost(stone_ids: Array) -> float:
	var total: float = 0.0
	for stone_id in stone_ids:
		total += StoneLoader.stone_cost(str(stone_id))
	return total


## Nettoie un deck chargé depuis une sauvegarde ancienne ou corrompue.
## L'ordre est conservé et le résultat peut rester incomplet.
static func sanitize_deck(stone_ids: Array, god_id: String = "") -> Array:
	var clean: Array = []
	for raw_id in stone_ids:
		var stone_id := str(raw_id)
		if not StoneLoader.has_stone(stone_id) or clean.has(stone_id):
			continue
		if god_id != "" and not StoneLoader.is_stone_available_to_god(stone_id, god_id):
			continue
		if clean.size() >= DECK_SIZE:
			break
		if deck_cost(clean) + StoneLoader.stone_cost(stone_id) <= DECK_BUDGET:
			clean.append(stone_id)
	return clean


static func validate_deck(stone_ids: Array, require_full: bool = true, god_id: String = "") -> Dictionary:
	var unique: Array = []
	for raw_id in stone_ids:
		var stone_id := str(raw_id)
		if not StoneLoader.has_stone(stone_id):
			return {"valid": false, "reason": "Pierre inconnue : %s" % stone_id}
		if unique.has(stone_id):
			return {"valid": false, "reason": "Une pierre ne peut apparaître qu'une fois."}
		if god_id != "" and not StoneLoader.is_stone_available_to_god(stone_id, god_id):
			return {"valid": false, "reason": "Cette pierre appartient à un autre dieu."}
		unique.append(stone_id)
	if unique.size() > DECK_SIZE or (require_full and unique.size() != DECK_SIZE):
		return {"valid": false, "reason": "Le deck doit contenir %d pierres." % DECK_SIZE}
	if deck_cost(unique) > DECK_BUDGET:
		return {"valid": false, "reason": "Le budget de %d points est dépassé." % DECK_BUDGET}
	return {"valid": true, "reason": ""}


static func is_deck_valid(stone_ids: Array, god_id: String = "") -> bool:
	return bool(validate_deck(stone_ids, true, god_id)["valid"])


static func replacement_cost(stone_ids: Array, old_id: String, new_id: String) -> float:
	return deck_cost(stone_ids) - StoneLoader.stone_cost(old_id) + StoneLoader.stone_cost(new_id)


static func can_replace(stone_ids: Array, old_id: String, new_id: String, god_id: String = "") -> bool:
	return bool(try_replace(stone_ids, old_id, new_id, god_id)["success"])


## Les opérations suivantes renvoient toujours une copie du deck. En cas
## d'échec, cette copie est inchangée et reason explique la cause à l'UI.
static func try_add(stone_ids: Array, stone_id: String, god_id: String = "") -> Dictionary:
	var deck := stone_ids.duplicate()
	if not StoneLoader.has_stone(stone_id):
		return _operation_result(false, deck, REASON_UNKNOWN)
	if deck.has(stone_id):
		return _operation_result(false, deck, REASON_DUPLICATE)
	if god_id != "" and not StoneLoader.is_stone_available_to_god(stone_id, god_id):
		return _operation_result(false, deck, REASON_GOD)
	if deck.size() >= DECK_SIZE:
		return _operation_result(false, deck, REASON_FULL)
	deck.append(stone_id)
	if deck_cost(deck) > DECK_BUDGET:
		return _operation_result(false, stone_ids.duplicate(), REASON_BUDGET, deck_cost(deck))
	return _operation_result(true, deck, "", deck_cost(deck))


static func try_remove(stone_ids: Array, stone_id: String) -> Dictionary:
	var deck := stone_ids.duplicate()
	var index := deck.find(stone_id)
	if index < 0:
		return _operation_result(false, deck, REASON_MISSING)
	deck.remove_at(index)
	return _operation_result(true, deck, "", deck_cost(deck))


static func try_replace(stone_ids: Array, old_id: String, new_id: String, god_id: String = "") -> Dictionary:
	var deck := stone_ids.duplicate()
	var index := deck.find(old_id)
	if index < 0:
		return _operation_result(false, deck, REASON_MISSING)
	if not StoneLoader.has_stone(new_id):
		return _operation_result(false, deck, REASON_UNKNOWN)
	if god_id != "" and not StoneLoader.is_stone_available_to_god(new_id, god_id):
		return _operation_result(false, deck, REASON_GOD)
	if new_id != old_id and deck.has(new_id):
		return _operation_result(false, deck, REASON_DUPLICATE)
	deck[index] = new_id
	var cost := deck_cost(deck)
	if cost > DECK_BUDGET:
		return _operation_result(false, stone_ids.duplicate(), REASON_BUDGET, cost)
	return _operation_result(true, deck, "", cost)


static func _operation_result(success: bool, deck: Array, reason: String, cost: float = -1.0) -> Dictionary:
	return {
		"success": success,
		"deck": deck,
		"reason": reason,
		"cost": deck_cost(deck) if cost < 0 else cost
	}
