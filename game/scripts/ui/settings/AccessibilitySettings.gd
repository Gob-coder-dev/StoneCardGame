extends Node

const PATH := "user://accessibility.cfg"
const SECTION := "display"
const KEY := "reduced_motion"

var reduced_motion := false


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		reduced_motion = config.get_value(SECTION, KEY, false) == true


func set_reduced_motion(enabled: bool) -> Error:
	var config := ConfigFile.new()
	config.set_value(SECTION, KEY, enabled)
	var result := config.save(PATH)
	if result == OK:
		reduced_motion = enabled
	return result
