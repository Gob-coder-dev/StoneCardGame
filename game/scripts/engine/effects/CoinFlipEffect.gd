## Tire l'issue du pile ou face et échange les faces demandées.
extends RefCounted
const BattleMonsterModel := preload("res://scripts/engine/BattleMonster.gd")
const SIDES = MonsterSide.ALL

static func resolve(state: GameState, battle_monster: BattleMonsterModel, definition: Dictionary) -> Array:
	var events: Array = []
	var coin_axis := str(definition.get("coin_flip", ""))
	if coin_axis != "":
		var flipped := state.draw_random_index(2) == 1
		apply_outcome(battle_monster, coin_axis, flipped)
		events.append(CombatEvents.coin_flip(coin_axis, flipped))

	return events

## Applique une issue du pile ou face : une pièce gagnante échange les faces de
## l'axe. L'IA s'en sert pour envisager les deux issues sans tirer au sort.
static func apply_outcome(battle_monster: BattleMonsterModel, axis: String, flipped: bool) -> void:
	battle_monster.coin_flipped = flipped
	if flipped:
		var faces := MonsterSide.coin_faces(axis)
		battle_monster.swap_faces(faces[0], faces[1])
