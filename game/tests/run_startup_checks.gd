## Démarrage réel et compilation de tous les scripts de production.
## Le lanceur connecte un débogueur dès le lancement pour recevoir les warnings.
extends Node

var _failed := 0


func _ready() -> void:
	_compile_directory("res://scripts")
	StoryService.auto_start_tutorials = false
	# Ignorer le cache : InterfaceTheme a déjà actualisé sa propre instance.
	var theme := ResourceLoader.load("res://assets/ui/samstone_theme.tres", "Theme",
		ResourceLoader.CACHE_MODE_IGNORE) as Theme
	_check(theme != null and theme.get_script() == null,
		"le thème chargé avant l'arbre ne possède pas de constructeur de script")
	_check(theme != null and theme.has_stylebox("normal", "PrimaryButton")
		and theme.get_font_size("font_size", "ScreenTitle") == UITheme.FONT_TITLE,
		"l'aperçu de l'éditeur contient les styles et polices du jeu")
	var scene := load("res://scenes/menus/MainMenu.tscn") as PackedScene
	_check(scene != null, "l'accueil se charge")
	if scene != null:
		var page := scene.instantiate()
		add_child(page)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(page.is_node_ready(), "l'accueil s'initialise")
		page.queue_free()
		await get_tree().process_frame
	print("STARTUP_CHECKS: %d failed" % _failed)
	Audio.quit_game(0 if _failed == 0 else 1)


func _compile_directory(path: String) -> void:
	for file in DirAccess.get_files_at(path):
		if file.ends_with(".gd"):
			var script := load(path.path_join(file)) as Script
			_check(script != null and script.can_instantiate(), "compilation : " + file)
	for directory in DirAccess.get_directories_at(path):
		_compile_directory(path.path_join(directory))


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", label)
