## BoardView.gd
## Vue du plateau : construit les cases, affiche les pierres, anime les captures.
## Ne contient AUCUNE logique de jeu — on lui donne un GameState, il affiche.
##
## Point 7 (bug de zoom) réglé définitivement : le plateau est dimensionné et
## positionné UNE SEULE FOIS (build), puis plus jamais recalculé. Aucune écoute
## du signal "resized". Poser une carte ne change donc jamais la taille.
class_name BoardView
extends Control

## Émis quand le joueur touche une case jouable.
signal cell_pressed(row: int, col: int)

const GAP: float = 16.0
const SwarmLinks := preload("res://scripts/ui/combat/SwarmLinkLayer.gd")
const AnimationController := preload("res://scripts/ui/combat/BoardAnimationController.gd")
const BlockedOverlay := preload("res://scripts/ui/BlockedCellOverlay.gd")
var animations: Control

var _slots: Array = []        ## Panel par case (index 1D)
var _cards: Array = []        ## StoneCard par case (ou null)
var _swarm_link_layer: Control = null
var _built: bool = false
## Portée d'une case pour une carte glissée, en écarts entre deux cases.
## Au-delà de la moitié de la diagonale (0,71), tout le plateau est couvert.
const DROP_RADIUS: float = 0.75
var _drop_target := Vector2i(-1, -1)
var _drop_style: StyleBoxFlat = null
var _drop_previous_style: StyleBox = null
var _cell_styles: Dictionary = {}


## Construit le plateau une fois, à une taille carrée fixe calculée sur la
## largeur disponible (constante en portrait). Idempotent : ne refait rien si
## déjà construit.
func build() -> void:
	if _built:
		return
	_built = true

	for child in get_children():
		child.queue_free()
	_slots.clear()
	_cards.clear()

	var board_side: float = size.x
	if size.y > 0.0 and board_side > size.y:
		board_side = size.y
	var cell_size: float = (board_side - GAP * float(GameState.BOARD_SIZE - 1)) / float(GameState.BOARD_SIZE)
	var origin := Vector2((size.x - board_side) * 0.5, 0.0)

	for row in range(GameState.BOARD_SIZE):
		for col in range(GameState.BOARD_SIZE):
			var slot := _make_slot(row, col)
			slot.position = origin + Vector2(col * (cell_size + GAP), row * (cell_size + GAP))
			slot.size = Vector2(cell_size, cell_size)
			add_child(slot)
			_slots.append(slot)
			_cards.append(null)
	_swarm_link_layer = SwarmLinks.new()
	_swarm_link_layer.name = "SwarmLinks"
	_swarm_link_layer.position = Vector2.ZERO
	_swarm_link_layer.size = size
	add_child(_swarm_link_layer)
	animations = AnimationController.new()
	animations.name = "Animations"
	add_child(animations)
	animations.setup(self)


func _make_slot(row: int, col: int) -> Panel:
	var slot := Panel.new()
	slot.name = "cell_%d_%d" % [row, col]
	slot.add_theme_stylebox_override("panel", _cell_style(GameState.PLAYER_NONE))
	slot.gui_input.connect(_on_slot_input.bind(row, col))
	return slot


func _on_slot_input(event: InputEvent, row: int, col: int) -> void:
	var clicked: bool = event is InputEventScreenTouch and event.pressed and not event.canceled
	if event is InputEventMouseButton and event.device != -1:
		clicked = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if clicked:
		emit_signal("cell_pressed", row, col)


## Synchronise l'affichage avec l'état logique.
func refresh(state: GameState) -> void:
	if not _built:
		return
	for row in range(GameState.BOARD_SIZE):
		for col in range(GameState.BOARD_SIZE):
			var idx := GameState.cell_index(row, col)
			var cell: Dictionary = state.board[idx]
			var slot: Panel = _slots[idx]

			if cell["cell_type"] == GameState.CELL_BLOCKED:
				_apply_cell_style(idx, GameState.PLAYER_NONE, true)
				_mark_blocked(slot)
				continue
			_apply_cell_style(idx, int(cell["owner"]))

			if cell["owner"] == GameState.PLAYER_NONE:
				if _cards[idx] != null:
					_cards[idx].queue_free()
					_cards[idx] = null
				continue

			if _cards[idx] == null:
				_cards[idx] = _spawn_card(slot, cell["stone_id"], cell["owner"], cell.get("stone"))
			else:
				_cards[idx].set_combat_owner(cell["owner"])
				_cards[idx].set_battle_stone(cell.get("stone"))


func _spawn_card(slot: Panel, stone_id: String, owner_val: int, battle_stone = null) -> StoneCard:
	var card := StoneCard.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE  ## le clic va à la case
	card.position = Vector2.ZERO
	card.size = slot.size
	slot.add_child(card)
	card.setup(StoneLoader.get_stone(stone_id), owner_val, battle_stone)
	return card


## Une case reste bloquée pendant tout le match : elle n'est habillée qu'une fois.
func _mark_blocked(slot: Panel) -> void:
	if slot.get_node_or_null("BlockedMark") != null:
		return
	var overlay := BlockedOverlay.new()
	overlay.name = "BlockedMark"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot.add_child(overlay)


## La capture est montrée à l'impact, avant que le moteur ne publie son état
## final. Cette méthode ne change que l'habillage de la case concernée.
func reveal_cell_owner(row: int, col: int, owner: int) -> void:
	if row < 0 or row >= GameState.BOARD_SIZE or col < 0 or col >= GameState.BOARD_SIZE:
		return
	_apply_cell_style(GameState.cell_index(row, col), owner)


func _apply_cell_style(index: int, owner: int, blocked: bool = false) -> void:
	var slot: Panel = _slots[index]
	var style := _cell_style(owner, blocked)
	if _drop_target != Vector2i(-1, -1) and index == GameState.cell_index(_drop_target.x, _drop_target.y):
		_drop_previous_style = style
		return
	slot.add_theme_stylebox_override("panel", style)


func _cell_style(owner: int, blocked: bool = false) -> StyleBoxFlat:
	var key := "blocked" if blocked else str(owner)
	if _cell_styles.has(key):
		return _cell_styles[key]
	var style := StyleBoxFlat.new()
	if blocked:
		style.bg_color = UITheme.COL_BOARD_BLOCKED_BG
		style.border_color = UITheme.COL_BOARD_BLOCKED_EDGE
		style.set_border_width_all(6)
		style.set_corner_radius_all(4)
	elif owner == GameState.PLAYER_HUMAN:
		style.bg_color = UITheme.COL_BOARD_HUMAN_BG
		style.border_color = UITheme.COL_BOARD_HUMAN_EDGE
		style.set_border_width_all(7)
		style.set_corner_radius_all(12)
	elif owner == GameState.PLAYER_AI:
		style.bg_color = UITheme.COL_BOARD_AI_BG
		style.border_color = UITheme.COL_BOARD_AI_EDGE
		# Bord plus anguleux et horizontalement renforcé : le camp reste
		# reconnaissable autrement que par sa seule teinte.
		style.border_width_left = 5
		style.border_width_right = 5
		style.border_width_top = 8
		style.border_width_bottom = 8
		style.set_corner_radius_all(2)
	else:
		style.bg_color = UITheme.COL_BOARD_EMPTY_BG
		style.border_color = UITheme.COL_BOARD_EMPTY_EDGE
		style.set_border_width_all(2)
		style.set_corner_radius_all(7)
	_cell_styles[key] = style
	return style



## ─── Glisser une carte vers le plateau ──────────────────────────────────────

## Case acceptée la plus proche d'un point du canevas, ou (-1, -1). Une case est
## retenue jusqu'à DROP_RADIUS fois l'écart entre deux cases de son centre :
## le plateau entier est couvert et la carte peut être lâchée entre deux cases.
## accepts(row, col) -> bool décide des cases possibles ; la vue ne connaît aucune règle.
func nearest_cell(canvas_point: Vector2, accepts: Callable) -> Vector2i:
	var best := Vector2i(-1, -1)
	if not _built:
		return best
	var best_distance := INF
	for row in range(GameState.BOARD_SIZE):
		for col in range(GameState.BOARD_SIZE):
			var slot: Panel = _slots[GameState.cell_index(row, col)]
			var to_canvas := slot.get_global_transform_with_canvas()
			var reach := DROP_RADIUS * (slot.size.x + GAP) * to_canvas.get_scale().x
			var distance := canvas_point.distance_to(to_canvas * (slot.size * 0.5))
			if distance < reach and distance < best_distance and accepts.call(row, col):
				best = Vector2i(row, col)
				best_distance = distance
	return best


## Éclaire la case où la carte serait posée ; (-1, -1) retire l'éclairage.
func set_drop_target(cell: Vector2i) -> void:
	if _drop_target != Vector2i(-1, -1):
		var previous: Panel = _slots[GameState.cell_index(_drop_target.x, _drop_target.y)]
		previous.add_theme_stylebox_override("panel", _drop_previous_style)
	_drop_target = cell
	if cell == Vector2i(-1, -1):
		return
	var slot: Panel = _slots[GameState.cell_index(cell.x, cell.y)]
	_drop_previous_style = slot.get_theme_stylebox("panel")
	if _drop_style == null:
		_drop_style = StyleBoxFlat.new()
		_drop_style.bg_color = Color("#3c2a16")
		_drop_style.border_color = UITheme.COL_GOLD
		_drop_style.set_border_width_all(5)
		_drop_style.set_corner_radius_all(6)
	slot.add_theme_stylebox_override("panel", _drop_style)


## Accès géométrique pour le coordinateur d'animations.
func card_at(row: int, col: int) -> StoneCard:
	return _cards[GameState.cell_index(row, col)]

func slot_at(row: int, col: int) -> Panel:
	return _slots[GameState.cell_index(row, col)]

func replace_swarm_links(links: Array) -> void:
	_swarm_link_layer.replace_links(links)

func remove_swarm_links(links: Array) -> void:
	_swarm_link_layer.remove_links(links)

func add_swarm_links(links: Array) -> void:
	_swarm_link_layer.add_links(links)

func swarm_link_count() -> int:
	return _swarm_link_layer.link_count() if is_instance_valid(_swarm_link_layer) else 0

func set_input_enabled(enabled: bool) -> void:
	for slot in _slots:
		slot.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
