## Contrat tactique RL v2, distinct de l'heuristique du bot enseignant.
## Entrees publiques uniquement ; les apercus ne consomment pas le hasard reel.
extends RefCounted

const Resolver := preload("res://scripts/engine/CombatResolver.gd")
const Monster := preload("res://scripts/engine/BattleMonster.gd")
const SIDES = MonsterSide.ALL
const MAX_PROFILES := 4096
static var _profiles: Dictionary = {}


static func scores(state: GameState, observer: int, selected_moves: Array = []) -> Dictionary:
	if state.is_game_over or state.current_player != observer:
		return {}
	var opponent := 3 - observer
	var reply := _reply_envelope(state, opponent)
	var result := {}
	var moves := RulesEngine.get_valid_moves(state, observer) if selected_moves.is_empty() else selected_moves
	for move in moves:
		var monster_id := str(move["monster_id"])
		var definition := MonsterLoader.get_monster(monster_id)
		var stochastic := int(definition.get("random_blades", 0)) > 0 or str(definition.get("coin_flip", "")) != ""
		var count := 4 if stochastic else 1
		var immediate := 0.0
		var anticipated := 0.0
		for sample in range(count):
			var simulation := state.clone()
			var row := int(move["row"])
			var col := int(move["col"])
			simulation.set_preview_seed(_seed(monster_id, row, col, sample))
			var outcome := Resolver.apply_move(simulation, row, col, monster_id, observer)
			var captures := float(outcome["captures"].size())
			immediate += captures
			anticipated += captures - _threat(simulation, opponent, reply)
		immediate /= count
		anticipated /= count
		var action := state.hand_of(observer).find(monster_id) * 16 + int(move["row"]) * 4 + int(move["col"])
		result[str(action)] = [immediate, anticipated, maxf(0.0, immediate - anticipated),
			1.0 if stochastic else 0.0, 1.0 + 2.0 * immediate]
	return result


static func _seed(monster_id: String, row: int, col: int, sample: int) -> int:
	var value: int = 0x811c9dc5
	for byte in ("%s:%d:%d:%d" % [monster_id, row, col, sample]).to_utf8_buffer():
		value = ((value ^ byte) * 16777619) & 0xffffffff
	return value


static func _reply_envelope(state: GameState, player: int) -> BattleMonster:
	if state.hand_of(player).is_empty():
		return null
	var played := {}
	for cell in state.board:
		if int(cell["placed_by"]) == player and str(cell["monster_id"]) != "":
			played[MonsterLoader.monster_lineage(str(cell["monster_id"]))] = true
	var lineages: Array = played.keys()
	lineages.sort()
	var god := state.god_of(player)
	var key := god + ":" + ",".join(lineages)
	if _profiles.has(key):
		return _profiles[key]
	var adjacent := {"top": 0, "bottom": 0, "left": 0, "right": 0}
	var ranged := adjacent.duplicate()
	for definition in MonsterLoader.get_all_monsters():
		var monster_id := str(definition["id"])
		var affinity := MonsterLoader.monster_affinity(monster_id)
		if affinity not in ["neutral", god] or played.has(MonsterLoader.monster_lineage(monster_id)):
			continue
		var normal: Dictionary = definition.get("blades", {})
		var long_blades: Dictionary = definition.get("long_blades", {})
		var axis := str(definition.get("coin_flip", ""))
		for side in SIDES:
			var alternate: String = MonsterSide.OPPOSITE[side] if (axis == "horizontal" and side in ["left", "right"]) or (axis == "vertical" and side in ["top", "bottom"]) else side
			for face in [side, alternate]:
				adjacent[side] = maxi(int(adjacent[side]), int(normal.get(face, 0)) + int(long_blades.get(face, 0)) + int(definition.get("random_blades", 0)))
				ranged[side] = maxi(int(ranged[side]), int(long_blades.get(face, 0)))
	var envelope := Monster.new()
	envelope.configure("", {})
	for side in SIDES:
		envelope.base_blades[side] = int(adjacent[side]) - int(ranged[side])
		envelope.long_blades[side] = int(ranged[side])
	if _profiles.size() >= MAX_PROFILES:
		_profiles.erase(_profiles.keys()[0])
	_profiles[key] = envelope
	return envelope


static func _threat(state: GameState, player: int, envelope: BattleMonster) -> float:
	if envelope == null:
		return 0.0
	var best := 0
	for index in range(state.cell_count()):
		var cell: Dictionary = state.board[index]
		if int(cell["cell_type"]) == GameState.CELL_BLOCKED or int(cell["owner"]) != GameState.PLAYER_NONE:
			continue
		best = maxi(best, Resolver.find_captures(state, floori(float(index) / state.board_size), index % state.board_size, player, envelope).size())
	return float(best)
