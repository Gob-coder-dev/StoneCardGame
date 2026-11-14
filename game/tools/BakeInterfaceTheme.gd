## Régénère l'aperçu de thème de l'éditeur depuis la même fabrique que le runtime.
## Exécuter avec --headless --path game --script res://tools/BakeInterfaceTheme.gd.
extends SceneTree

const Builder := preload("res://scripts/ui/RefugeTheme.gd")
const THEME_PATH := "res://assets/ui/samstone_theme.tres"


func _initialize() -> void:
	_bake.call_deferred()


func _bake() -> void:
	var theme := load(THEME_PATH) as Theme
	Builder.apply(theme)
	_stable_style_ids(theme)
	var error := ResourceSaver.save(theme, THEME_PATH)
	if error == OK:
		# ResourceSaver omet les UID hors mode éditeur ; conserver celui de la ressource.
		error = ResourceSaver.set_uid(THEME_PATH, ResourceUID.text_to_id("uid://c8gkxgjdms0em"))
	print("THEME_BAKE: ", error_string(error))
	var audio := root.get_node_or_null("Audio")
	if audio != null:
		audio.quit_game(0 if error == OK else 1)
	else:
		quit(0 if error == OK else 1)


## Une régénération identique ne doit pas changer les identifiants au hasard.
func _stable_style_ids(theme: Theme) -> void:
	var assigned := {}
	var types := theme.get_type_list()
	types.sort()
	for theme_type in types:
		var names := theme.get_stylebox_list(theme_type)
		names.sort()
		for style_name in names:
			var style := theme.get_stylebox(style_name, theme_type)
			if not assigned.has(style):
				style.resource_scene_unique_id = "Style_%s_%s" % [theme_type, style_name]
				assigned[style] = true
