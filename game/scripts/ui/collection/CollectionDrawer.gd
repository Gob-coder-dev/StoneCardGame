## Maintient le tiroir de carte au-dessus de la grille et ajuste sa position.
extends RefCounted

const DrawerScene := preload("res://scenes/ui/CardActionDrawer.tscn")
const Placement := preload("res://scripts/ui/collection/CardActionPlacement.gd")
const GAP := 10.0
const MARGIN := 24.0
const BASE_SPACER := 30.0

var drawer: CardActionDrawer
var card: MonsterCard
var adjusting_scroll := false
var _wrapper: Control
var _monster_id := ""
var _source := CardActionDrawer.Source.COLLECTION
var _layer: Control
var _scroll: ScrollContainer
var _spacer: Control


func _init(layer: Control, scroll: ScrollContainer, spacer: Control) -> void:
	_layer = layer
	_scroll = scroll
	_spacer = spacer


func matches(monster_id: String, source: CardActionDrawer.Source) -> bool:
	return is_instance_valid(drawer) and _monster_id == monster_id and _source == source


func open(monster_id: String, wrapper: VBoxContainer, source: CardActionDrawer.Source) -> CardActionDrawer:
	_monster_id = monster_id
	_source = source
	_wrapper = wrapper
	card = wrapper.get_child(0) as MonsterCard
	if card != null:
		card.set_selected(true)
	drawer = DrawerScene.instantiate() as CardActionDrawer
	_layer.add_child(drawer)
	drawer.setup(monster_id, source)
	drawer.hide()
	_reveal(drawer, _layer.get_tree())
	return drawer


func close() -> void:
	if is_instance_valid(card):
		card.set_selected(false)
	if is_instance_valid(drawer):
		var parent := drawer.get_parent()
		if parent != null:
			parent.remove_child(drawer)
		drawer.queue_free()
	drawer = null
	card = null
	_wrapper = null
	_monster_id = ""
	adjusting_scroll = false
	_spacer.custom_minimum_size.y = BASE_SPACER


func position_drawer() -> void:
	if not _has_target(drawer):
		return
	var placement := _placement()
	if placement.is_empty():
		return
	var drawer_size := Vector2(maxf(1.0, float(placement["width"])), drawer.get_combined_minimum_size().y)
	drawer.custom_minimum_size = drawer_size
	drawer.size = drawer_size
	drawer.position = Vector2(float(placement["x"]), float(placement["bottom"]) + GAP)


func _reveal(opened: CardActionDrawer, tree: SceneTree) -> void:
	await tree.process_frame
	if not _has_target(opened):
		return
	var height := drawer.get_combined_minimum_size().y
	adjusting_scroll = true
	_spacer.custom_minimum_size.y = maxf(BASE_SPACER, height + GAP + MARGIN)
	await tree.process_frame
	if not _has_target(opened):
		return
	var visible_rect := Placement.control_rect_in(_layer, _scroll)
	var overflow := float(_placement().get("bottom", 0.0)) + GAP + height - (visible_rect.end.y - MARGIN)
	if overflow > 0.0:
		_scroll.scroll_vertical += ceili(overflow)
		await tree.process_frame
	if _has_target(opened):
		adjusting_scroll = false
		position_drawer()
		drawer.show()


func _has_target(opened: CardActionDrawer) -> bool:
	return is_instance_valid(opened) and opened == drawer and is_instance_valid(_wrapper) \
		and is_instance_valid(card) and is_instance_valid(_layer)


func _placement() -> Dictionary:
	return Placement.resolve(_layer, _wrapper, card, _source == CardActionDrawer.Source.COLLECTION)
