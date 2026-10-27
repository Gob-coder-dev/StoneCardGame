## Déclin : aura du Miasme après les captures, expiration puis nouvel échec corrosif.
## PostAttackEffectResolver fixe l'ordre ; ce système calcule les malus.
extends RefCounted
const BattleStoneModel := preload("res://scripts/engine/BattleStone.gd")
const SIDES = StoneSide.ALL
const Board := preload("res://scripts/engine/combat/CombatBoard.gd")
const Effects := preload("res://scripts/domain/StoneEffects.gd")

## Miasme : aura continue. Chaque pierre adverse voisine d'une pierre Miasme
## active perd 1 force sur chaque face, cumulée par pierre Miasme voisine.
## Recalculée après les captures de chaque coup : une carte posée à côté
## attaque d'abord normalement, puis subit le malus. Une pierre Miasme n'est
## active que dans un camp dont le dieu est le sien (règle des dieux) ; une
## pierre qui change de camp ou perd sa voisine Miasme retrouve sa force.
## Retourne un événement WEAKEN par pierre plus affaiblie et WEAKNESS_EXPIRED
## par pierre soulagée. La source d'un WEAKEN est de préférence la pierre posée.
static func update_miasma(state: GameState, source_row: int, source_col: int) -> Array:
	var events: Array = []
	# Les IA simulent des milliers de coups : sans Miasme actif ni malus à
	# retirer, on s'arrête après un seul passage sur le plateau.
	var active := PackedByteArray()
	active.resize(state.board.size())
	var needs_update := false
	for index in range(state.board.size()):
		var cell: Dictionary = state.board[index]
		if Board.has_active_power(state, cell, Effects.WEAKEN_ADJACENT):
			active[index] = 1
			needs_update = true
		else:
			var stone := Board.stone_at(cell)
			needs_update = needs_update or (stone != null and stone.miasma_weakness > 0)
	if not needs_update:
		return events
	var source_index := GameState.cell_index(source_row, source_col)
	for index in range(state.board.size()):
		var cell: Dictionary = state.board[index]
		var stone := Board.stone_at(cell)
		if stone == null:
			continue
		var row := index / GameState.BOARD_SIZE
		var col := index % GameState.BOARD_SIZE
		var aura := 0
		var aura_source := -1
		if int(cell["owner"]) != GameState.PLAYER_NONE:
			for adjacent in GameState.get_adjacent_positions(row, col):
				var neighbor_index := GameState.cell_index(adjacent["row"], adjacent["col"])
				if active[neighbor_index] == 0:
					continue
				if int(state.board[neighbor_index]["owner"]) == int(cell["owner"]):
					continue
				aura += 1
				if aura_source < 0 or neighbor_index == source_index:
					aura_source = neighbor_index
		if aura == stone.miasma_weakness:
			continue
		var weakness_before := stone.weakness()
		var increased := aura > stone.miasma_weakness
		stone.miasma_weakness = aura
		if increased:
			events.append(CombatEvents.weakness(CombatEvents.WEAKEN, row, col,
				weakness_before, stone.weakness(),
				aura_source / GameState.BOARD_SIZE, aura_source % GameState.BOARD_SIZE, "adjacent"))
		else:
			events.append(CombatEvents.weakness(CombatEvents.WEAKNESS_EXPIRED, row, col,
				weakness_before, stone.weakness(), -1, -1, "adjacent"))
	return events


## Échec corrosif : chaque pierre adverse qui a résisté à l'attaque, de près
## ou à distance, perd Effects.CORROSION_AMOUNT de force jusqu'à la fin du prochain
## coup du lanceur. Les pierres capturées, non attaquées ou hors de portée ne
## sont pas touchées.
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
			target.temporary_weakness += Effects.CORROSION_AMOUNT
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
