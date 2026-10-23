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
var animations: Control

var _slots: Array = []        ## Panel par case (index 1D)
var _cards: Array = []        ## StoneCard par case (ou null)
var _swarm_link_layer: Control = null
var _built: bool = false


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
	var cell_size: float = (board_side - GAP * 2.0) / float(GameState.BOARD_SIZE)
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
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#241810")
	sb.border_color = Color("#4a3a22")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	slot.add_theme_stylebox_override("panel", sb)
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
				_mark_blocked(slot)
				continue

			if cell["owner"] == GameState.PLAYER_NONE:
				if _cards[idx] != null:
					_cards[idx].queue_free()
					_cards[idx] = null
				continue

			if _cards[idx] == null:
				_cards[idx] = _spawn_card(slot, cell["stone_id"], cell["owner"], cell.get("stone"))
			else:
				_cards[idx].set_owner_color(cell["owner"])
				_cards[idx].set_battle_stone(cell.get("stone"))


func _spawn_card(slot: Panel, stone_id: String, owner_val: int, battle_stone = null) -> StoneCard:
	var card := StoneCard.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE  ## le clic va à la case
	card.position = Vector2.ZERO
	card.size = slot.size
	slot.add_child(card)
	card.setup(StoneLoader.get_stone(stone_id), owner_val, battle_stone)
	return card


func _mark_blocked(slot: Panel) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#140c06")
	sb.border_color = Color("#2a2018")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	slot.add_theme_stylebox_override("panel", sb)
	if slot.get_node_or_null("BlockedMark") == null:
		var lbl := Label.new()
		lbl.name = "BlockedMark"
		lbl.text = "✕"
		lbl.add_theme_font_size_override("font_size", 40)
		lbl.add_theme_color_override("font_color", Color("#4a3a28"))
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(lbl)



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
