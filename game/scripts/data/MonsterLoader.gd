## MonsterLoader.gd
## Charge et met en cache les données des monstres depuis le manifeste de familles.
## Utilisé comme Autoload (singleton) dans le projet.
## NB : pas de class_name ici — le nom "MonsterLoader" est défini dans project.godot
##      comme AutoLoad, ce qui le rend accessible globalement sans class_name.
##
## Accès depuis n'importe quel script : MonsterLoader.get_monster("avortons_des_caves_n1")
extends Node

const ContentChecks := preload("res://scripts/data/ContentValidator.gd")

const MONSTERS_MANIFEST_PATH: String = "res://data/monsters/manifest.json"
const GODS_PATH: String = "res://data/gods.json"

## Dictionnaire indexé par monster_id -> dict complet du monstre
var _monsters: Dictionary = {}

## Liste ordonnée de toutes les formes ; la collection les regroupe par lignée.
var _monsters_list: Array = []
## Une lignée contient ses identifiants de formes dans l'ordre des niveaux.
var _lineages: Dictionary = {}


## Dieux jouables et ordre d'affichage.
var _gods: Dictionary = {}
var _gods_list: Array = []
var _default_god_id: String = ""


func _ready() -> void:
	_load_monsters()
	_load_gods()
	for problem in ContentChecks.find_problems(_monsters_list, _gods, _default_god_id):
		push_error("MonsterLoader: " + problem)


## ─── Chargement ───────────────────────────────────────────────────────────────

func _load_monsters() -> void:
	var manifest := _read_json_dictionary(MONSTERS_MANIFEST_PATH)
	var families: Variant = manifest.get("families")
	if not families is Array:
		push_error("MonsterLoader: manifeste invalide dans %s" % MONSTERS_MANIFEST_PATH)
		return
	var seen_families := {}
	for entry in families:
		_load_monster_family(entry, seen_families)

	print("MonsterLoader: %d monstres chargés." % _monsters_list.size())


func _load_monster_family(entry: Variant, seen_families: Dictionary) -> void:
	if not entry is Dictionary:
		push_error("MonsterLoader: entrée de famille invalide dans le manifeste.")
		return
	var family_id := str(entry.get("id", ""))
	var path := str(entry.get("path", ""))
	if family_id.is_empty() or path.is_empty() or seen_families.has(family_id):
		push_error("MonsterLoader: famille de monstres invalide '%s'." % family_id)
		return
	seen_families[family_id] = true
	var parsed := _read_json_dictionary(path)
	var lineages: Variant = parsed.get("lineages")
	if not lineages is Array or str(parsed.get("family_id", "")) != family_id:
		push_error("MonsterLoader: fichier de famille invalide dans %s" % path)
		return
	for lineage in lineages:
		if not lineage is Dictionary or str(lineage.get("god_id", "neutral")) != family_id:
			push_error("MonsterLoader: lignée hors de la famille '%s' dans %s." % [family_id, path])
			continue
		_index_lineage(lineage)


func _read_json_dictionary(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("MonsterLoader: impossible d'ouvrir %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_error("MonsterLoader: format JSON invalide dans %s" % path)
		return {}
	return parsed


func _index_monster(definition: Dictionary, lineage: String, level: int, maximum: int) -> void:
	var monster := definition.duplicate(true)
	monster["lineage_id"] = lineage
	monster["level"] = level
	monster["max_level"] = maximum
	_monsters[monster["id"]] = monster
	_monsters_list.append(monster)
	if not _lineages.has(lineage):
		_lineages[lineage] = []
	_lineages[lineage].append(monster["id"])


func _index_lineage(lineage: Dictionary) -> void:
	var problems := ContentChecks.lineage_problems(lineage)
	if problems.is_empty():
		for form in lineage["levels"]:
			if _monsters.has(str(form["id"])):
				problems.append("identifiant de forme déjà utilisé '%s'." % form["id"])
	if _lineages.has(str(lineage.get("id", ""))):
		problems.append("lignée déjà utilisée '%s'." % lineage.get("id", ""))
	if not problems.is_empty():
		for problem in problems:
			push_error("MonsterLoader: " + problem)
		return
	var common := lineage.duplicate(true)
	common.erase("levels")
	var forms: Array = lineage["levels"]
	for index in range(forms.size()):
		var definition := common.duplicate(true)
		definition.merge(forms[index], true)
		_index_monster(definition, str(lineage["id"]), index + 1, forms.size())


func _load_gods() -> void:
	var file := FileAccess.open(GODS_PATH, FileAccess.READ)
	if file == null:
		push_error("MonsterLoader: impossible d'ouvrir " + GODS_PATH)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not parsed.get("gods") is Array:
		push_error("MonsterLoader: catalogue de dieux invalide")
		return
	_default_god_id = str(parsed.get("default_god_id", ""))
	for god in parsed["gods"]:
		_gods[str(god["id"])] = god
		_gods_list.append(god)


## ─── Accès aux monstres ────────────────────────────────────────────────────────

## Copie complète de la définition : l'appelant peut la modifier sans toucher
## au catalogue. Pour une simple question, préférer les lectures ci-dessous.
func get_monster(monster_id: String) -> Dictionary:
	return _monsters.get(monster_id, {}).duplicate(true)


## Lectures indexées sans copie, pour les questions posées des milliers de fois
## pendant les simulations. Elles ne renvoient qu'un booléen : le catalogue
## reste protégé.
func has_monster(monster_id: String) -> bool:
	return _monsters.has(monster_id)


func monster_lineage(monster_id: String) -> String:
	return str(_monsters.get(monster_id, {}).get("lineage_id", monster_id))


func monster_level(monster_id: String) -> int:
	return int(_monsters.get(monster_id, {}).get("level", 1))


func monster_rarity(monster_id: String) -> String:
	return str(_monsters.get(monster_id, {}).get("rarity", ""))


func lineage_max_level(lineage_id: String) -> int:
	return _lineages.get(lineage_id, []).size()


func variant_id(lineage_id: String, level: int) -> String:
	var forms: Array = _lineages.get(lineage_id, [])
	return str(forms[level - 1]) if MonsterEvolutionRules.is_valid_level(level, forms.size()) else ""


func variant_ids(lineage_id: String) -> Array:
	return _lineages.get(lineage_id, []).duplicate()


func preview_variant(monster_id: String, requested: int) -> String:
	var lineage := monster_lineage(monster_id)
	return variant_id(lineage, MonsterEvolutionRules.preview_level(requested, lineage_max_level(lineage)))


func has_effect(monster_id: String, effect: String) -> bool:
	var monster = _monsters.get(monster_id)
	if monster == null:
		return false
	var effects = monster.get("effects")
	return effects is Array and effects.has(effect)


## Retourne toutes les monstres sous forme de liste.
func get_all_monsters() -> Array:
	return _monsters_list.duplicate(true)


func get_all_monster_ids() -> Array[String]:
	var result: Array[String] = []
	for monster in _monsters_list:
		result.append(str(monster["id"]))
	return result


## Identifiants de lignées, sans copier les définitions complètes. Utilisé par
## les métriques de collection, qui n'ont besoin que des compteurs.
func lineage_ids() -> Array[String]:
	var result: Array[String] = []
	for lineage_id in _lineages:
		result.append(str(lineage_id))
	return result


## Coût d'un monstre du catalogue, 0 si introuvable. La règle vit dans MonsterCostRules.
func monster_cost(monster_id: String) -> float:
	# MonsterCostRules lit seulement la définition : inutile de la copier.
	return MonsterCostRules.cost(_monsters.get(monster_id, {}))


## Coût exact en quarts de point : unité de comparaison des générateurs.
func monster_cost_quarters(monster_id: String) -> int:
	return MonsterCostRules.cost_quarters(_monsters.get(monster_id, {}))


## Palier de puissance effectif d'une forme. Une éventuelle exception
## `power_tier` du catalogue remplace la formule rareté + niveau.
func monster_power_tier(monster_id: String) -> int:
	return CardPowerTierRules.effective_tier(_monsters.get(monster_id, {}))


func build_hand(monster_ids: Array) -> Array:
	var hand: Array = []
	for sid in monster_ids:
		if _monsters.has(sid):
			hand.append(sid)
		else:
			push_error("MonsterLoader: monstre '%s' introuvable." % sid)
	return hand

## ─── Accès aux dieux et aux familles ─────────────────────────────────────────

func get_god(god_id: String) -> Dictionary:
	return _gods.get(god_id, {}).duplicate(true)


func get_all_gods() -> Array:
	return _gods_list.duplicate(true)


func default_god_id() -> String:
	if _gods.has(_default_god_id):
		return _default_god_id
	return str(_gods_list[0].get("id", "")) if not _gods_list.is_empty() else ""


func is_monster_available_to_god(monster_id: String, god_id: String) -> bool:
	if not _gods.has(god_id):
		return false
	var affinity := monster_affinity(monster_id)
	return affinity != "" and (affinity == "neutral" or affinity == god_id)


## Lecture du catalogue sans copie : famille du monstre, ou "" si inconnue.
## L'activation d'un pouvoir posé appartient à CombatBoard, pas au catalogue.
func monster_affinity(monster_id: String) -> String:
	var monster: Dictionary = _monsters.get(monster_id, {})
	if monster.is_empty():
		return ""
	return str(monster.get("god_id", "neutral"))


func get_monsters_for_god(god_id: String) -> Array:
	var result: Array = []
	for monster_id in get_monster_ids_for_god(god_id):
		result.append(get_monster(monster_id))
	return result


## Lecture légère pour l'IA et les index : évite de copier chaque dictionnaire
## complet lorsque seuls les identifiants sont nécessaires.
func get_monster_ids_for_god(god_id: String) -> Array[String]:
	var result: Array[String] = []
	for monster in _monsters_list:
		var monster_id := str(monster["id"])
		if is_monster_available_to_god(monster_id, god_id):
			result.append(monster_id)
	return result


## Une seule entrée par monstre ; les formes sont consultées via variant_id().
func get_lineages_for_god(god_id: String) -> Array:
	var result: Array = []
	# L'index contient déjà une entrée par lignée : seules ses premières formes
	# sont copiées, au lieu de copier puis dédupliquer toutes les évolutions.
	for forms in _lineages.values():
		if not forms.is_empty() and is_monster_available_to_god(str(forms[0]), god_id):
			result.append(get_monster(str(forms[0])))
	return result


func get_neutral_lineages() -> Array:
	var result: Array = []
	var seen := {}
	for monster in _monsters_list:
		if str(monster.get("god_id", "neutral")) != "neutral":
			continue
		var lineage := monster_lineage(str(monster["id"]))
		if not seen.has(lineage):
			seen[lineage] = true
			result.append(monster.duplicate(true))
	return result
