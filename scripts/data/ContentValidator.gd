## Validation des catalogues après chargement. Renvoie la liste des problèmes
## trouvés au lieu de les afficher : StoneLoader les signale, les tests les lisent.
extends RefCounted

const Effects := preload("res://scripts/domain/StoneEffects.gd")
const AIProfileModel := preload("res://scripts/ai/AIProfile.gd")

## Validation du format des nouvelles lignées avant leur indexation.
static func lineage_problems(lineage: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var id := str(lineage.get("id", ""))
	var maximum := StoneEvolutionRules.max_level(str(lineage.get("rarity", "")))
	var forms = lineage.get("levels")
	if id.is_empty() or maximum == 0 or not forms is Array:
		problems.append("lignée invalide '%s' : identifiant, rareté ou niveaux." % id)
		return problems
	if forms.size() != maximum:
		problems.append("la lignée '%s' doit avoir %d niveaux." % [id, maximum])
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
		if form.has("god_id") or form.has("rarity") or form.has("lineage_id") or form.has("max_level"):
			problems.append("une forme de '%s' redéfinit l'identité de sa lignée." % id)
		if form.has("level") and form["level"] != index + 1:
			problems.append("niveaux non consécutifs dans '%s'." % id)
		var definition := lineage.duplicate(true)
		definition.erase("levels")
		definition.merge(form, true)
		if _check_evolution_shape(definition, problems):
			# L'existence de la famille sera vérifiée avec les vrais dieux après chargement.
			_check_stone(definition, {str(lineage.get("god_id", "neutral")): {}}, problems)
	return problems


static func _check_evolution_shape(stone: Dictionary, problems: Array[String]) -> bool:
	var valid := true
	for field in ["blades", "shields", "long_blades"]:
		var sides = stone.get(field, {} if field != "blades" else null)
		if not sides is Dictionary:
			valid = false
			continue
		for side in sides:
			valid = valid and StoneSide.ALL.has(side) and _integer_count(sides[side], BattleStone.MAX_MARKERS_PER_SIDE)
	valid = valid and _integer_count(stone.get("random_blades", 0), BattleStone.MAX_MARKERS_PER_SIDE * StoneSide.ALL.size())
	valid = valid and stone.get("effects", []) is Array
	var cost = stone.get("power_cost", 0.0)
	valid = valid and (cost is int or cost is float) and cost >= 0
	if not valid:
		problems.append("statistiques ou symboles invalides sur la forme '%s'." % stone.get("id", ""))
	return valid


static func _integer_count(value: Variant, maximum: int) -> bool:
	return (value is int or value is float) and value >= 0 and value <= maximum and value == floor(float(value))


static func find_problems(stones: Array, gods: Dictionary, npcs: Array, default_god_id: String) -> Array[String]:
	var problems: Array[String] = []
	if not gods.has(default_god_id):
		problems.append("dieu par défaut inconnu '%s'." % default_god_id)
	for stone in stones:
		_check_stone(stone, gods, problems)
	for npc in npcs:
		_check_npc(npc, gods, problems)
	return problems


static func _check_stone(stone: Dictionary, gods: Dictionary, problems: Array[String]) -> void:
	var stone_id := str(stone.get("id", ""))
	var god_id := str(stone.get("god_id", "neutral"))
	if god_id != "neutral" and not gods.has(god_id):
		problems.append("famille inconnue '%s' sur '%s'." % [god_id, stone_id])
	var random_count := int(stone.get("random_blades", 0))
	var coin_axis := str(stone.get("coin_flip", ""))
	if coin_axis != "" and not StoneSide.COIN_AXES.has(coin_axis):
		problems.append("axe de pile ou face inconnu '%s' sur '%s'." % [coin_axis, stone_id])
	if random_count > 0 and coin_axis != "":
		problems.append("les deux pouvoirs Fortune sont combinés sur '%s'." % stone_id)
	var decline_power_count := 0
	for effect in stone.get("effects", []):
		if not Effects.ALL.has(str(effect)):
			problems.append("pouvoir inconnu '%s' sur '%s'." % [effect, stone_id])
		if Effects.DECLINE.has(str(effect)):
			decline_power_count += 1
	if decline_power_count > 1:
		problems.append("plusieurs pouvoirs Déclin sont combinés sur '%s'." % stone_id)
	var capacity := 0
	var max_markers := BattleStone.MAX_MARKERS_PER_SIDE
	for side in StoneSide.ALL:
		var base := int(stone.get("blades", {}).get(side, 0))
		var long_count := int(stone.get("long_blades", {}).get(side, 0))
		var shield_count := int(stone.get("shields", {}).get(side, 0))
		if base < 0 or long_count < 0 or shield_count < 0 or base + long_count + shield_count > max_markers:
			problems.append("plus de %d symboles ou valeur négative sur %s/%s." % [max_markers, stone_id, side])
		capacity += maxi(0, max_markers - base - long_count - shield_count)
	if random_count < 0 or random_count > capacity:
		problems.append("lames aléatoires impossibles sur '%s'." % stone_id)


static func _check_npc(npc: Dictionary, gods: Dictionary, problems: Array[String]) -> void:
	var npc_id := str(npc.get("id", ""))
	var god_id := str(npc.get("god_id", ""))
	if not gods.has(god_id):
		problems.append("dieu inconnu pour le NPC '%s'." % npc_id)
	for ai_problem in AIProfileModel.problems(npc.get("ai")):
		problems.append("%s pour le NPC '%s'." % [ai_problem, npc_id])
	# Les adversaires ne sont pas soumis au budget du joueur, seulement à la taille du deck.
	if npc.get("deck", []).size() != DeckRules.DECK_SIZE:
		problems.append("le deck du NPC '%s' doit contenir %d pierres." % [npc_id, DeckRules.DECK_SIZE])
	var seen: Array = []
	for stone_id in npc.get("deck", []):
		var lineage := StoneLoader.stone_lineage(str(stone_id))
		if seen.has(lineage) or not StoneLoader.is_stone_available_to_god(str(stone_id), god_id):
			problems.append("deck incompatible pour le NPC '%s'." % npc_id)
		seen.append(lineage)
