## Validation des catalogues après chargement. Renvoie la liste des problèmes
## trouvés au lieu de les afficher : StoneLoader les signale, les tests les lisent.
extends RefCounted

const Effects := preload("res://scripts/domain/StoneEffects.gd")

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
	if not AIPlayer.LEVELS.has(str(npc.get("ai_level", ""))):
		problems.append("niveau d'IA inconnu pour le NPC '%s'." % npc_id)
	# Les adversaires ne sont pas soumis au budget du joueur, seulement à la taille du deck.
	if npc.get("deck", []).size() != DeckRules.DECK_SIZE:
		problems.append("le deck du NPC '%s' doit contenir %d pierres." % [npc_id, DeckRules.DECK_SIZE])
	var seen: Array = []
	for stone_id in npc.get("deck", []):
		if seen.has(stone_id) or not StoneLoader.is_stone_available_to_god(str(stone_id), god_id):
			problems.append("deck incompatible pour le NPC '%s'." % npc_id)
		seen.append(stone_id)
