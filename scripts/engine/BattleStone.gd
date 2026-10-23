## Instance mutable d'une pierre pendant une partie.
## La définition du catalogue reste immuable ; seuls les résultats aléatoires,
## affaiblissements, boucliers volés et bonus Swarm vivent ici.
class_name BattleStone
extends Resource

const SIDES = StoneSide.ALL

var instance_id: int = 0
var stone_id: String = ""
var base_blades: Dictionary = {}
var random_blades: Dictionary = {}
var long_blades: Dictionary = {}
var shields: Dictionary = {}
var swarm_blades: Dictionary = {}
var permanent_weakness: int = 0
var temporary_weakness: int = 0
var temporary_weakness_owner: int = 0
var coin_flipped: bool = false


func configure(id: String, definition: Dictionary, uid: int = 0) -> void:
	instance_id = uid
	stone_id = id
	base_blades = _side_map(definition.get("blades", {}))
	long_blades = _side_map(definition.get("long_blades", {}))
	shields = _side_map(definition.get("shields", {}))
	random_blades = _side_map({})
	swarm_blades = _side_map({})


func clone():
	var result = get_script().new()
	result.instance_id = instance_id
	result.stone_id = stone_id
	result.base_blades = base_blades.duplicate(true)
	result.random_blades = random_blades.duplicate(true)
	result.long_blades = long_blades.duplicate(true)
	result.shields = shields.duplicate(true)
	result.swarm_blades = swarm_blades.duplicate(true)
	result.permanent_weakness = permanent_weakness
	result.temporary_weakness = temporary_weakness
	result.temporary_weakness_owner = temporary_weakness_owner
	result.coin_flipped = coin_flipped
	return result


func normal_blades(side: String) -> int:
	return int(base_blades.get(side, 0)) \
		+ int(random_blades.get(side, 0)) \
		+ int(swarm_blades.get(side, 0))


## Nombre de symboles physiques sur une face. Une lame normale, aléatoire,
## d'aura ou longue et un bouclier occupent tous exactement un emplacement.
func marker_count(side: String) -> int:
	return normal_blades(side) \
		+ int(long_blades.get(side, 0)) \
		+ int(shields.get(side, 0))


func free_marker_slots(side: String) -> int:
	return maxi(0, 4 - marker_count(side))


func weakness() -> int:
	return permanent_weakness + temporary_weakness


func attack(side: String) -> int:
	return maxi(0, normal_blades(side) + int(long_blades.get(side, 0)) - weakness())


func ranged_attack(side: String) -> int:
	return maxi(0, int(long_blades.get(side, 0)) - weakness())


func defense(side: String) -> int:
	return attack(side) + int(shields.get(side, 0))


func swap_faces(first: String, second: String) -> void:
	for values in [base_blades, random_blades, long_blades, shields]:
		var previous = values.get(first, 0)
		values[first] = values.get(second, 0)
		values[second] = previous


func _side_map(source: Dictionary) -> Dictionary:
	var result := {}
	for side in SIDES:
		result[side] = int(source.get(side, 0))
	return result

## Liste sémantique des symboles physiques. Le moteur définit l'ordre stable,
## la vue ajoute uniquement les coordonnées de dessin.
func markers_for_side(side: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var kinds := ["normal", "random", "swarm", "long", "shield"]
	var maps := [base_blades, random_blades, swarm_blades, long_blades, shields]
	for group in range(kinds.size()):
		for _index in range(int(maps[group].get(side, 0))):
			result.append({"kind": kinds[group], "index": result.size()})
	return result

func defending_marker_indices(side: String) -> Array[int]:
	var indices: Array[int] = []
	var effective_blades := attack(side)
	for marker in markers_for_side(side):
		if marker["kind"] == "shield" or int(marker["index"]) < effective_blades:
			indices.append(int(marker["index"]))
	return indices
