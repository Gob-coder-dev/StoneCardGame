## Déclin : Miasme après capture, expiration puis nouvel échec corrosif.
## PostAttackEffectResolver décide si la pierre posée possède le pouvoir.
extends RefCounted
const BattleStoneModel := preload("res://scripts/engine/BattleStone.gd")
const SIDES = StoneSide.ALL
const Board := preload("res://scripts/engine/combat/CombatBoard.gd")

## Miasme : chaque voisine, alliée ou adverse, perd définitivement 1 force.
static func apply_miasma(state: GameState, row: int, col: int) -> Array:
	var effects: Array = []
	for adjacent in GameState.get_adjacent_positions(row, col):
		var adjacent_stone := Board.stone_at(state.get_cell(adjacent["row"], adjacent["col"]))
		if adjacent_stone != null:
			var weakness_before := adjacent_stone.weakness()
			adjacent_stone.permanent_weakness += 1
			effects.append(CombatEvents.weakness(CombatEvents.WEAKEN, adjacent["row"], adjacent["col"],
			weakness_before, adjacent_stone.weakness(), row, col, "adjacent"))
	return effects

## Échec corrosif : chaque pierre adverse qui a résisté à l'attaque, de près
## ou à distance, perd 1 force jusqu'à la fin du prochain coup du lanceur.
## Les pierres capturées, non attaquées ou hors de portée ne sont pas touchées.
static func apply_failed_attack(state: GameState, row: int, col: int, player: int, attacks: Array) -> Array:
	var effects: Array = []
	for attack in attacks:
		for hit in attack.get("hits", []):
			if bool(hit["success"]):
				continue
			var cell := state.get_cell(int(hit["row"]), int(hit["col"]))
			var target := Board.stone_at(cell)
			if target == null or cell["owner"] == player or cell["owner"] == GameState.PLAYER_NONE:
				continue
			var weakness_before := target.weakness()
			target.temporary_weakness += 1
			target.temporary_weakness_owner = player
			effects.append(CombatEvents.weakness(CombatEvents.TEMPORARY_WEAKEN,
				int(hit["row"]), int(hit["col"]), weakness_before, target.weakness(),
				row, col, "failed_attack"))
	return effects

static func expire_for_player(state: GameState, player: int) -> Array:
	var events: Array = []
	for index in range(state.board.size()):
		var cell: Dictionary = state.board[index]
		var stone := Board.stone_at(cell)
		if stone != null and stone.temporary_weakness_owner == player:
			var weakness_before := stone.weakness()
			stone.temporary_weakness = 0
			stone.temporary_weakness_owner = GameState.PLAYER_NONE
			events.append(CombatEvents.weakness(CombatEvents.WEAKNESS_EXPIRED,
				index / GameState.BOARD_SIZE, index % GameState.BOARD_SIZE,
				weakness_before, stone.weakness()))
	return events
