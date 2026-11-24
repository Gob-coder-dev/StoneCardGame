## Validation des catalogues après chargement. Renvoie la liste des problèmes
## trouvés au lieu de les afficher : MonsterLoader les signale, les tests les lisent.
extends RefCounted

const Effects := preload("res://scripts/domain/MonsterEffects.gd")
const PowerTierRules := preload("res://scripts/domain/CardPowerTierRules.gd")

## Validation du format des nouvelles lignées avant leur indexation.
static func lineage_problems(lineage: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var id := str(lineage.get("id", ""))
	var maximum := MonsterEvolutionRules.max_level(str(lineage.get("rarity", "")))
	var forms = lineage.get("levels")
	if id.is_empty() or maximum == 0 or not forms is Array:
		problems.append("lignée invalide '%s' : identifiant, rareté ou niveaux." % id)
		return problems
	if forms.size() != maximum:
		problems.append("la lignée '%s' doit avoir %d niveaux." % [id, maximum])
	if lineage.has("power_cost"):
		problems.append("la lignée '%s' utilise l'ancien champ power_cost." % id)
	var seen := {}
	for index in range(forms.size()):
		var form = forms[index]
		if not form is Dictionary:
			problems.append("forme invalide dans '%s'." % id)
			continue
		var form_id := str(form.get("id", ""))
		if form_id.is_empty() or seen.has(form_id):
			problems.append("identifiant de forme absent ou dupliqué dans '%s'." % id)
		seen[form_id] = true
		if form.has("god_id") or form.has("rarity") or form.has("lineage_id") or form.has("max_level") or form.has("power_cost"):
			problems.append("une forme de '%s' redéfinit l'identité de sa lignée." % id)
		if form.has("level") and form["level"] != index + 1:
			problems.append("niveaux non consécutifs dans '%s'." % id)
		var definition := lineage.duplicate(true)
		definition.erase("levels")
		definition.merge(form, true)
		if _check_evolution_shape(definition, problems):
			# L'existence de la famille sera vérifiée avec les vrais dieux après chargement.
			_check_monster(definition, {str(lineage.get("god_id", "neutral")): {}}, problems)
	for problem in PowerTierRules.lineage_problems(lineage):
		problems.append(problem)
	return problems


static func _check_evolution_shape(monster: Dictionary, problems: Array[String]) -> bool:
	var valid := true
	for field in ["blades", "shields", "long_blades"]:
		var sides: Variant = {}
		if field == "blades" or monster.has(field):
			sides = monster.get(field)
		if not sides is Dictionary:
			valid = false
			continue
		for side in sides:
			valid = valid and MonsterSide.ALL.has(side) and _integer_count(sides[side], BattleMonster.MAX_MARKERS_PER_SIDE)
	valid = valid and _integer_count(monster.get("random_blades", 0), BattleMonster.MAX_MARKERS_PER_SIDE * MonsterSide.ALL.size())
	valid = valid and monster.get("effects", []) is Array
	if not valid:
		problems.append("statistiques ou symboles invalides sur la forme '%s'." % monster.get("id", ""))
	return valid


static func _integer_count(value: Variant, maximum: int) -> bool:
	return (value is int or value is float) and value >= 0 and value <= maximum and value == floor(float(value))


static func find_problems(monsters: Array, gods: Dictionary, default_god_id: String) -> Array[String]:
	var problems: Array[String] = []
	if not gods.has(default_god_id):
		problems.append("dieu par défaut inconnu '%s'." % default_god_id)
	for monster in monsters:
		_check_monster(monster, gods, problems)
	return problems


static func _check_monster(monster: Dictionary, gods: Dictionary, problems: Array[String]) -> void:
	var monster_id := str(monster.get("id", ""))
	var god_id := str(monster.get("god_id", "neutral"))
	if god_id != "neutral" and not gods.has(god_id):
		problems.append("famille inconnue '%s' sur '%s'." % [god_id, monster_id])
	var random_count := int(monster.get("random_blades", 0))
	var coin_axis := str(monster.get("coin_flip", ""))
	if coin_axis != "" and not MonsterSide.COIN_AXES.has(coin_axis):
		problems.append("axe de pile ou face inconnu '%s' sur '%s'." % [coin_axis, monster_id])
	if random_count > 0 and coin_axis != "":
		problems.append("les deux pouvoirs Fortune sont combinés sur '%s'." % monster_id)
	var decline_power_count := 0
	for effect in monster.get("effects", []):
		if not Effects.ALL.has(str(effect)):
			problems.append("pouvoir inconnu '%s' sur '%s'." % [effect, monster_id])
		if Effects.DECLINE.has(str(effect)):
			decline_power_count += 1
	if decline_power_count > 1:
		problems.append("plusieurs pouvoirs Déclin sont combinés sur '%s'." % monster_id)
	var capacity := 0
	var max_markers := BattleMonster.MAX_MARKERS_PER_SIDE
	for side in MonsterSide.ALL:
		var base := int(monster.get("blades", {}).get(side, 0))
		var long_count := int(monster.get("long_blades", {}).get(side, 0))
		var shield_count := int(monster.get("shields", {}).get(side, 0))
		if base < 0 or long_count < 0 or shield_count < 0 or base + long_count + shield_count > max_markers:
			problems.append("plus de %d symboles ou valeur négative sur %s/%s." % [max_markers, monster_id, side])
		capacity += maxi(0, max_markers - base - long_count - shield_count)
	if random_count < 0 or random_count > capacity:
		problems.append("lames aléatoires impossibles sur '%s'." % monster_id)
