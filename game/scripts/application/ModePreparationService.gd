## Service applicatif de préparation des loadouts. Il concentre l'usage de
## LoadoutGenerator et DraftEngine sans connaître le réseau ni une scène.
class_name ModePreparationService
extends RefCounted

var _generator: LoadoutGenerator
var _god_ids: Array = []


func _init(pool: Array = [], god_ids: Array = []) -> void:
	_generator = LoadoutGenerator.new(pool)
	_god_ids = god_ids.duplicate()
	if _god_ids.is_empty():
		for god in StoneLoader.get_all_gods():
			_god_ids.append(str(god.get("id", "")))


## Les contraintes sont optionnelles : les appels PVP historiques gardent leurs
## dieux aléatoires et leurs decks miroirs générés. La campagne les renseigne
## pour un dieu imposé, une pureté de deck ou un deck miroir exact.
func prepare_immediate(mode: String, seed: int, max_tier: int,
		profile_one: Dictionary, profile_two: Dictionary,
		constraints: Dictionary = {}) -> Dictionary:
	match mode:
		GameModeRules.MODE_CLASSIC:
			return _classic(profile_one, profile_two)
		GameModeRules.MODE_RANDOM:
			return _random(seed, max_tier, constraints)
		GameModeRules.MODE_MIRROR:
			return _mirror(seed, max_tier, constraints)
		GameModeRules.MODE_DRAFT:
			return {"ok": false, "reason": "Le mode Sélection exige une session de draft."}
	return {"ok": false, "reason": "Mode de jeu inconnu."}


func create_draft(seed: int, max_tier: int, profile_one: Dictionary,
		profile_two: Dictionary, duration_seconds: float = DraftEngine.DEFAULT_DURATION_SECONDS) -> Dictionary:
	var god_one := str(profile_one.get("god_id", ""))
	var god_two := str(profile_two.get("god_id", ""))
	if god_one == "" or god_two == "":
		return {"ok": false, "reason": "Dieu manquant pour le mode Sélection."}
	var draft := DraftEngine.new()
	var started := draft.start(seed, god_one, god_two, max_tier, duration_seconds)
	if not bool(started.get("ok", false)):
		return {"ok": false, "reason": str(started.get("reason", "Draft impossible."))}
	return {"ok": true, "reason": "", "draft": draft}


func loadouts_from_draft(draft: DraftEngine, seed: int) -> Dictionary:
	if draft == null or not draft.is_complete():
		return {"ok": false, "reason": "Le draft n'est pas terminé."}
	var result := draft.result()
	if not bool(result.get("ok", false)):
		return {"ok": false, "reason": str(result.get("reason", "Draft invalide."))}
	var one := GameLoadout.create(str(result["god_one"]), result["deck_one"], seed)
	var two := GameLoadout.create(str(result["god_two"]), result["deck_two"], seed)
	return _success(one, two)


func _classic(profile_one: Dictionary, profile_two: Dictionary) -> Dictionary:
	var one := GameLoadout.create(str(profile_one.get("god_id", "")),
		profile_one.get("deck", []))
	var two := GameLoadout.create(str(profile_two.get("god_id", "")),
		profile_two.get("deck", []))
	if not one.is_valid() or not two.is_valid():
		return {"ok": false, "reason": "Un deck classique est incomplet ou incompatible."}
	return _success(one, two)


func _random(seed: int, max_tier: int, constraints: Dictionary = {}) -> Dictionary:
	var god_id := str(constraints.get("generator_god_id", ""))
	var min_god_cards := int(constraints.get("generator_min_god_cards", 0))
	var generator := _generator
	var god_ids := _god_ids
	if god_id != "":
		generator = _generator_for_god(god_id, min_god_cards)
		god_ids = [god_id]
	var generated := generator.generate_random(seed, god_ids, max_tier)
	if not bool(generated.get("ok", false)):
		return generated
	return _success(
		GameLoadout.create(str(generated["god_one"]), generated["deck_one"], seed),
		GameLoadout.create(str(generated["god_two"]), generated["deck_two"], seed)
	)


func _mirror(seed: int, max_tier: int, constraints: Dictionary = {}) -> Dictionary:
	var god_id := str(constraints.get("generator_god_id", ""))
	var raw_fixed: Variant = constraints.get("mirror_fixed_deck", [])
	var fixed_deck: Array = (raw_fixed as Array).duplicate() if raw_fixed is Array else []
	if not fixed_deck.is_empty():
		if god_id == "":
			return {"ok": false, "reason": "Un deck miroir imposé exige un dieu."}
		var one := GameLoadout.create(god_id, fixed_deck, seed)
		if not one.is_valid():
			return {"ok": false, "reason": "Le deck miroir imposé est invalide."}
		return _success(one, one.copy())
	var generator := _generator
	var god_ids := _god_ids
	if god_id != "":
		generator = _generator_for_god(god_id, int(constraints.get("generator_min_god_cards", 0)))
		god_ids = [god_id]
	var generated := generator.generate_mirror(seed, god_ids, max_tier)
	if not bool(generated.get("ok", false)):
		return generated
	var one := GameLoadout.create(str(generated["god_id"]), generated["deck"], seed)
	return _success(one, one.copy())


## Un générateur local filtré évite de modifier le catalogue partagé. Pour un
## deck pur, seules les cartes du dieu imposé restent dans le pool ; les cartes
## neutres sont conservées uniquement pour les contraintes partielles.
func _generator_for_god(god_id: String, min_god_cards: int) -> LoadoutGenerator:
	var pure := min_god_cards >= DeckRules.DECK_SIZE
	var pool: Array = []
	for raw in StoneLoader.get_all_stones():
		if not raw is Dictionary:
			continue
		var affinity := str((raw as Dictionary).get("god_id", "neutral"))
		if affinity == god_id or (not pure and affinity == "neutral"):
			pool.append(raw)
	return LoadoutGenerator.new(pool)


static func _success(one: GameLoadout, two: GameLoadout) -> Dictionary:
	return {"ok": true, "reason": "", "loadout_one": one, "loadout_two": two}

