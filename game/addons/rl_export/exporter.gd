@tool
extends EditorExportPlugin

const Identity := preload("res://scripts/ai/neural/RLIdentity.gd")


func _get_name() -> String:
	return "SamStoneRLIdentity"


func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	# Exported scripts may be compiled: preserve the authoring identity before
	# conversion instead of trying to hash stripped source code on the phone.
	add_file("res://rl_rules.sha256", Identity.rules_checksum().to_utf8_buffer(), false)
