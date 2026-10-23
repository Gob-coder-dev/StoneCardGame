## Instance mutable d'une pierre pendant une partie.
## La définition du catalogue reste immuable ; seuls les résultats aléatoires,
## affaiblissements, boucliers volés et bonus Swarm vivent ici.
class_name BattleStone
extends Resource

const SIDES = StoneSide.ALL
## Une face accueille au plus quatre symboles, tous types confondus.
const MAX_MARKERS_PER_SIDE: int = 4
## Ordre stable des symboles sur une face. Le moteur numérote les symboles dans
## cet ordre ; la vue l'utilise pour les dessiner et les animer.
const MARKER_KINDS: Array[String] = ["normal", "random", "swarm", "long", "shield"]

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


## Les cartes de faces ne contiennent que des nombres : une copie simple suffit.
func clone():
	var result = get_script().new()
	result.instance_id = instance_id
	result.stone_id = stone_id
	result.base_blades = base_blades.duplicate()
	result.random_blades = random_blades.duplicate()
	result.long_blades = long_blades.duplicate()
	result.shields = shields.duplicate()
	result.swarm_blades = swarm_blades.duplicate()
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
	return maxi(0, MAX_MARKERS_PER_SIDE - marker_count(side))


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
	for kind in MARKER_KINDS:
		for _index in range(marker_count_of(kind, side)):
			result.append({"kind": kind, "index": result.size()})
	return result

## Nombre de symboles d'un type de MARKER_KINDS sur une face.
func marker_count_of(kind: String, side: String) -> int:
	match kind:
		"normal": return int(base_blades.get(side, 0))
		"random": return int(random_blades.get(side, 0))
		"swarm": return int(swarm_blades.get(side, 0))
		"long": return int(long_blades.get(side, 0))
		"shield": return int(shields.get(side, 0))
	return 0

## Indice du premier symbole d'un type sur une face : nombre de symboles des
## types qui le précèdent dans MARKER_KINDS.
func marker_offset(kind: String, side: String) -> int:
	var offset := 0
	for previous in MARKER_KINDS:
		if previous == kind:
			break
		offset += marker_count_of(previous, side)
	return offset

func defending_marker_indices(side: String) -> Array[int]:
	var indices: Array[int] = []
	var effective_blades := attack(side)
	for marker in markers_for_side(side):
		if marker["kind"] == "shield" or int(marker["index"]) < effective_blades:
			indices.append(int(marker["index"]))
	return indices
