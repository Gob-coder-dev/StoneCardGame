## Règles pures de composition et de modification d'un deck.
## La couche UI utilise les opérations try_* et ne modifie jamais le deck
## persistant directement.
class_name DeckRules
extends RefCounted

const CatalogueModel := preload("res://scripts/data/MonsterLoader.gd")

## Plateau 4×4 : sans case bloquée, chaque joueur pose 8 monstres.
const DECK_SIZE: int = 8
## 10 points en moyenne par monstre.
const DECK_BUDGET: int = 80
## Emplacements indépendants sauvegardés pour chaque dieu.
const DECKS_PER_GOD: int = 3

const REASON_UNKNOWN: String = "unknown_monster"
const REASON_DUPLICATE: String = "duplicate"
const REASON_FULL: String = "full"
const REASON_BUDGET: String = "budget"
const REASON_MISSING: String = "missing"
const REASON_GOD: String = "wrong_god"


static func deck_cost(monster_ids: Array, catalogue: CatalogueModel = null) -> float:
	var source := catalogue if catalogue != null else MonsterLoader
	var total: float = 0.0
	for monster_id in monster_ids:
		total += source.monster_cost(str(monster_id))
	return total


## Total exact en quarts de point, pour les générateurs et les comparaisons
## d'égalité. Aucun float n'entre dans cette somme.
static func deck_quarters(monster_ids: Array) -> int:
	var total := 0
	for monster_id in monster_ids:
		total += MonsterLoader.monster_cost_quarters(str(monster_id))
	return total


## Nombre de monstres appartenant réellement au dieu. Les neutres ne comptent
## pas : cette règle sert aux loadouts qui imposent une affinité minimale.
static func affinity_count(monster_ids: Array, god_id: String) -> int:
	var count := 0
	for monster_id in monster_ids:
		if MonsterLoader.monster_affinity(str(monster_id)) == god_id:
			count += 1
	return count


static func budget_quarters() -> int:
	return DECK_BUDGET * MonsterCostRules.COST_SCALE


## Nettoie un deck chargé depuis une sauvegarde ancienne ou corrompue.
## L'ordre est conservé et le résultat peut rester incomplet.
static func sanitize_deck(monster_ids: Array, god_id: String = "") -> Array:
	var clean: Array = []
	for raw_id in monster_ids:
		var monster_id := str(raw_id)
		if not MonsterLoader.has_monster(monster_id) or lineage_index(clean, MonsterLoader.monster_lineage(monster_id)) >= 0:
			continue
		if god_id != "" and not MonsterLoader.is_monster_available_to_god(monster_id, god_id):
			continue
		if clean.size() >= DECK_SIZE:
			break
		if deck_cost(clean) + MonsterLoader.monster_cost(monster_id) <= DECK_BUDGET:
			clean.append(monster_id)
	return clean


static func validate_deck(monster_ids: Array, require_full: bool = true, god_id: String = "") -> Dictionary:
	var unique: Array = []
	for raw_id in monster_ids:
		var monster_id := str(raw_id)
		if not MonsterLoader.has_monster(monster_id):
			return {"valid": false, "reason": "Monstre inconnu : %s" % monster_id}
		if lineage_index(unique, MonsterLoader.monster_lineage(monster_id)) >= 0:
			return {"valid": false, "reason": "Un monstre ne peut apparaître qu'une fois."}
		if god_id != "" and not MonsterLoader.is_monster_available_to_god(monster_id, god_id):
			return {"valid": false, "reason": "Ce monstre appartient à un autre dieu."}
		unique.append(monster_id)
	if unique.size() > DECK_SIZE or (require_full and unique.size() != DECK_SIZE):
		return {"valid": false, "reason": "Le deck doit contenir %d monstres." % DECK_SIZE}
	if deck_cost(unique) > DECK_BUDGET:
		return {"valid": false, "reason": "Le budget de %d points est dépassé." % DECK_BUDGET}
	return {"valid": true, "reason": ""}


static func is_deck_valid(monster_ids: Array, god_id: String = "") -> bool:
	return bool(validate_deck(monster_ids, true, god_id)["valid"])


static func replacement_cost(monster_ids: Array, old_id: String, new_id: String) -> float:
	return deck_cost(monster_ids) - MonsterLoader.monster_cost(old_id) + MonsterLoader.monster_cost(new_id)


static func can_replace(monster_ids: Array, old_id: String, new_id: String, god_id: String = "") -> bool:
	return bool(try_replace(monster_ids, old_id, new_id, god_id)["success"])


## Les opérations suivantes renvoient toujours une copie du deck. En cas
## d'échec, cette copie est inchangée et reason explique la cause à l'UI.
static func try_add(monster_ids: Array, monster_id: String, god_id: String = "",
		catalogue: CatalogueModel = null) -> Dictionary:
	var source := catalogue if catalogue != null else MonsterLoader
	var deck := monster_ids.duplicate()
	if not source.has_monster(monster_id):
		return _operation_result(false, deck, REASON_UNKNOWN)
	if lineage_index(deck, source.monster_lineage(monster_id), source) >= 0:
		return _operation_result(false, deck, REASON_DUPLICATE)
	if god_id != "" and not source.is_monster_available_to_god(monster_id, god_id):
		return _operation_result(false, deck, REASON_GOD)
	if deck.size() >= DECK_SIZE:
		return _operation_result(false, deck, REASON_FULL)
	deck.append(monster_id)
	var cost := deck_cost(deck, source)
	if cost > DECK_BUDGET:
		return _operation_result(false, monster_ids.duplicate(), REASON_BUDGET, cost)
	return _operation_result(true, deck, "", cost)


static func try_remove(monster_ids: Array, monster_id: String) -> Dictionary:
	var deck := monster_ids.duplicate()
	var index := deck.find(monster_id)
	if index < 0:
		return _operation_result(false, deck, REASON_MISSING)
	deck.remove_at(index)
	return _operation_result(true, deck, "", deck_cost(deck))


## Vider un deck ne supprime pas son emplacement : seule sa composition est
## effacée, et le joueur peut le reconstruire immédiatement.
static func try_clear(_monster_ids: Array) -> Dictionary:
	return _operation_result(true, [], "")


static func try_replace(monster_ids: Array, old_id: String, new_id: String, god_id: String = "",
		catalogue: CatalogueModel = null) -> Dictionary:
	var source := catalogue if catalogue != null else MonsterLoader
	var deck := monster_ids.duplicate()
	var index := deck.find(old_id)
	if index < 0:
		return _operation_result(false, deck, REASON_MISSING)
	if not source.has_monster(new_id):
		return _operation_result(false, deck, REASON_UNKNOWN)
	if god_id != "" and not source.is_monster_available_to_god(new_id, god_id):
		return _operation_result(false, deck, REASON_GOD)
	var duplicate_index := lineage_index(deck, source.monster_lineage(new_id), source)
	if duplicate_index >= 0 and duplicate_index != index:
		return _operation_result(false, deck, REASON_DUPLICATE)
	deck[index] = new_id
	var cost := deck_cost(deck, source)
	if cost > DECK_BUDGET:
		return _operation_result(false, monster_ids.duplicate(), REASON_BUDGET, cost)
	return _operation_result(true, deck, "", cost)


static func lineage_index(monster_ids: Array, lineage_id: String, catalogue: CatalogueModel = null) -> int:
	var source := catalogue if catalogue != null else MonsterLoader
	for index in range(monster_ids.size()):
		if source.monster_lineage(str(monster_ids[index])) == lineage_id:
			return index
	return -1


static func try_set_level(monster_ids: Array, lineage_id: String, level: int, god_id: String = "") -> Dictionary:
	var index := lineage_index(monster_ids, lineage_id)
	if index < 0:
		return _operation_result(false, monster_ids.duplicate(), REASON_MISSING)
	var variant := MonsterLoader.variant_id(lineage_id, level)
	return try_replace(monster_ids, str(monster_ids[index]), variant, god_id)


static func _operation_result(success: bool, deck: Array, reason: String, cost: float = -1.0) -> Dictionary:
	return {
		"success": success,
		"deck": deck,
		"reason": reason,
		"cost": deck_cost(deck) if cost < 0 else cost
	}
