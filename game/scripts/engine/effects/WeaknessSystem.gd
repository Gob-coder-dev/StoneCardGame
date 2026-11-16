## Déclin : aura du Miasme après les captures, expiration puis nouvel échec corrosif.
## PostAttackEffectResolver fixe l'ordre ; ce système calcule les malus.
extends RefCounted
const BattleMonsterModel := preload("res://scripts/engine/BattleMonster.gd")
const SIDES = MonsterSide.ALL
const Board := preload("res://scripts/engine/combat/CombatBoard.gd")
const Effects := preload("res://scripts/domain/MonsterEffects.gd")

## Miasme : aura continue. Chaque monstre adverse voisine d'un monstre Miasme
## active perd 1 force sur chaque face, cumulé par monstre Miasme voisin.
## Recalculée après les captures de chaque coup : une carte posée à côté
## attaque d'abord normalement, puis subit le malus. Un monstre Miasme n'est
## active que dans un camp dont le dieu est le sien (règle des dieux) ; une
## monstre qui change de camp ou perd son voisin Miasme retrouve sa force.
## Retourne un événement WEAKEN par monstre plus affaibli et WEAKNESS_EXPIRED
## par monstre soulagé. La source d'un WEAKEN est de préférence le monstre posé.
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
			var monster := Board.monster_at(cell)
			needs_update = needs_update or (monster != null and monster.miasma_weakness > 0)
	if not needs_update:
		return events
	var source_index := state.index_of(source_row, source_col)
	for index in range(state.board.size()):
		var cell: Dictionary = state.board[index]
		var monster := Board.monster_at(cell)
		if monster == null:
			continue
		var row := floori(float(index) / state.board_size)
		var col := index % state.board_size
		var aura := 0
		var aura_source := -1
		if int(cell["owner"]) != GameState.PLAYER_NONE:
			for adjacent in state.adjacent_positions(row, col):
				var neighbor_index := state.index_of(adjacent["row"], adjacent["col"])
				if active[neighbor_index] == 0:
					continue
				if int(state.board[neighbor_index]["owner"]) == int(cell["owner"]):
					continue
				aura += 1
				if aura_source < 0 or neighbor_index == source_index:
					aura_source = neighbor_index
		if aura == monster.miasma_weakness:
			continue
		var weakness_before := monster.weakness()
		var increased := aura > monster.miasma_weakness
		monster.miasma_weakness = aura
		if increased:
			events.append(CombatEvents.weakness(CombatEvents.WEAKEN, row, col,
				weakness_before, monster.weakness(),
				floori(float(aura_source) / state.board_size), aura_source % state.board_size, "adjacent"))
		else:
			events.append(CombatEvents.weakness(CombatEvents.WEAKNESS_EXPIRED, row, col,
				weakness_before, monster.weakness(), -1, -1, "adjacent"))
	return events


## Échec corrosif : chaque monstre adverse qui a résisté à l'attaque, de près
## ou à distance, perd Effects.CORROSION_AMOUNT de force jusqu'à la fin du prochain
## coup du lanceur. Les monstres capturés, non attaqués ou hors de portée ne
## sont pas touchées.
static func apply_failed_attack(state: GameState, row: int, col: int, player: int, attacks: Array) -> Array:
	var effects: Array = []
	for attack in attacks:
		for hit in attack.get("hits", []):
			if bool(hit["success"]):
				continue
			var cell := state.get_cell(int(hit["row"]), int(hit["col"]))
			var target := Board.monster_at(cell)
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
		var monster := Board.monster_at(cell)
		if monster != null and monster.temporary_weakness_owner == player:
			var weakness_before := monster.weakness()
			monster.temporary_weakness = 0
			monster.temporary_weakness_owner = GameState.PLAYER_NONE
			events.append(CombatEvents.weakness(CombatEvents.WEAKNESS_EXPIRED,
				floori(float(index) / state.board_size), index % state.board_size,
				weakness_before, monster.weakness()))
	return events
