@tool
extends EditorExportPlugin

const Identity := preload("res://scripts/data/RulesIdentity.gd")


func _get_name() -> String:
	return "BeastpactRLIdentity"


func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	# Exported scripts may be compiled: preserve the authoring identity before
	# conversion instead of trying to hash stripped source code on the phone.
	add_file(Identity.RL_RULES_PATH, Identity.rl_checksum().to_utf8_buffer(), false)
	add_file(Identity.LAN_RULES_PATH, Identity.lan_checksum().to_utf8_buffer(), false)
