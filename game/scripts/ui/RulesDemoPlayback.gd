## Lit en boucle les clips visibles. Libère les flux sortis de la fenêtre.
extends Node

const DIRECTORY := "res://assets/rules_demos/"

var _scroll: ScrollContainer
var _page: VBoxContainer
var _slots: Array[TextureRect] = []
var _players: Dictionary[TextureRect, VideoStreamPlayer] = {}
var _app_paused := false


func setup(scroll: ScrollContainer, page: VBoxContainer) -> void:
	_scroll = scroll
	_page = page
	set_process(false)


func add_clip(id: String) -> void:
	var poster := load(DIRECTORY + id + ".png") as Texture2D
	var slot := TextureRect.new()
	slot.name = id
	slot.texture = poster
	slot.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var aspect := float(poster.get_width()) / poster.get_height()
	slot.resized.connect(func(): slot.custom_minimum_size.y = roundf(slot.size.x / aspect))
	_slots.append(slot)
	_page.add_child(slot)
	set_process(true)


func clear() -> void:
	set_process(false)
	for slot in _players.keys():
		_stop_clip(slot)
	_slots.clear()


func _process(_delta: float) -> void:
	var visible_rect := _scroll.get_global_rect() if _scroll.is_visible_in_tree() else Rect2()
	for slot in _slots:
		var visible := visible_rect.intersection(slot.get_global_rect()).has_area()
		if visible and not _players.has(slot) and not _app_paused:
			_start_clip(slot)
		elif not visible and _players.has(slot):
			_stop_clip(slot)


func _start_clip(slot: TextureRect) -> void:
	var player := VideoStreamPlayer.new()
	player.expand = true
	player.loop = true
	player.volume = 0.0
	player.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player.stream = load(DIRECTORY + str(slot.name) + ".ogv") as VideoStream
	_players[slot] = player
	slot.add_child(player)
	player.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	player.play()


func _stop_clip(slot: TextureRect) -> void:
	var player := _players[slot]
	_players.erase(slot)
	player.stop()
	player.queue_free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_RESUMED:
		_app_paused = what == NOTIFICATION_APPLICATION_PAUSED
		for player in _players.values():
			player.paused = _app_paused
