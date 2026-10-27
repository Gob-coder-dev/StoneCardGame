## Réseau Essaim persistant. Il conserve uniquement les connexions que le
## moteur a validées ; les cartes et les bonus restent gérés ailleurs.
extends Control

const VineStyle := preload("res://scripts/ui/combat/SwarmVineStyle.gd")
const RESTING_OPACITY: float = 0.72

var _links := {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 4


func replace_links(links: Array) -> void:
	_links.clear()
	add_links(links)


func add_links(links: Array) -> void:
	for link_value in links:
		var link: Dictionary = link_value
		_links[str(link.get("key", ""))] = link.duplicate(true)
	queue_redraw()


func remove_links(links: Array) -> void:
	for link in links:
		_links.erase(str(link.get("key", "")))
	queue_redraw()


func link_count() -> int:
	return _links.size()


func _draw() -> void:
	var keys: Array = _links.keys()
	keys.sort()
	for key in keys:
		var link: Dictionary = _links[key]
		var seed := absi(hash(key)) % 97
		VineStyle.draw_vine(self, link["start"], link["end"],
			float(link.get("square", 100.0)), RESTING_OPACITY, seed)
