## QuestDraw.gd
## Tirage quotidien déterministe : le même jour donne toujours les mêmes quêtes,
## même après un redémarrage. L'éligibilité filtre le vivier, jamais un tirage
## déjà figé dans la sauvegarde.
class_name QuestDraw
extends RefCounted

const SEED_PREFIX := "samstone-quests"


## `previous` contient les identifiants de la veille, écartés tant que le
## vivier reste assez large pour composer un tirage complet.
static func draw(dailies: Array, day_index: int, count: int,
		eligible: Callable, previous: Array = []) -> Dictionary:
	var pool := _pool(dailies, eligible, previous)
	if pool.size() < count:
		pool = _pool(dailies, eligible, [])
	if pool.is_empty():
		return {"ids": [], "carrier": ""}
	# L'ordre du catalogue ne doit jamais influencer le tirage : on trie avant
	# de tirer, puis le générateur fait le reste.
	pool.sort_custom(func(a, b): return _id_of(a) < _id_of(b))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%d" % [SEED_PREFIX, day_index])
	var remaining := pool.duplicate()
	var picked: Array = []
	for _index in range(mini(count, remaining.size())):
		var choice := rng.randi_range(0, remaining.size() - 1)
		picked.append(remaining[choice])
		remaining.remove_at(choice)
	var ids: Array[String] = []
	for raw in picked:
		ids.append(_id_of(raw))
	return {"ids": ids, "carrier": _carrier_id(picked)}


static func _id_of(value: Variant) -> String:
	return str((value as Dictionary).get("id", ""))


static func _pool(dailies: Array, eligible: Callable, forbidden: Array) -> Array:
	var pool: Array = []
	for raw in dailies:
		if not raw is Dictionary:
			continue
		var quest: Dictionary = raw
		var quest_id := str(quest.get("id", ""))
		if quest_id == "" or forbidden.has(quest_id):
			continue
		if eligible.is_valid() and not bool(eligible.call(quest)):
			continue
		pool.append(quest)
	return pool


## Les bougies vont à la quête la plus exigeante du jour. À effort égal,
## l'identifiant le plus petit tranche pour rester reproductible.
static func _carrier_id(picked: Array) -> String:
	var ordered := picked.duplicate()
	ordered.sort_custom(func(a, b): return _id_of(a) < _id_of(b))
	var carrier := ""
	var best := -1
	for raw in ordered:
		var quest: Dictionary = raw
		var effort := int(quest.get("effort", 0))
		if effort > best:
			best = effort
			carrier = str(quest.get("id", ""))
	return carrier
