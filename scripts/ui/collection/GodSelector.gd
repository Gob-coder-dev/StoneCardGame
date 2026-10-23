## Vue du sélecteur de dieu. La modification du deck reste au contrôleur.
extends RefCounted
signal god_selected(god_id: String)
const TouchButtonScript := preload("res://scripts/ui/input/TouchButton.gd")
var god_button: Button
var god_description: Label
var god_menu: PanelContainer
var god_options: VBoxContainer

func _init(button: Button, description: Label, menu: PanelContainer, options: VBoxContainer) -> void:
	god_button = button
	god_description = description
	god_menu = menu
	god_options = options
	_setup_god_menu()

func _setup_god_menu() -> void:
	for child in god_options.get_children():
		child.queue_free()
	for god in StoneLoader.get_all_gods():
		var option: Button = TouchButtonScript.new()
		option.custom_minimum_size = Vector2(0, 92)
		option.add_theme_font_size_override("font_size", 32)
		option.text = "%s • %s" % [
			str(god.get("name", "Dieu")).to_upper(),
			str(god.get("family_name", "Famille")).to_upper()
		]
		option.add_theme_color_override("font_color", Color(str(god.get("color", "#f0d88a"))))
		option.pressed.connect(god_selected.emit.bind(str(god.get("id", ""))))
		god_options.add_child(option)

func refresh(god_id: String) -> void:
	var god := StoneLoader.get_god(god_id)
	god_button.text = "%s • %s  %s" % [
		str(god.get("name", "Dieu")).to_upper(),
		str(god.get("family_name", "Famille")).to_upper(),
		"▲" if god_menu.visible else "▼"
	]
	god_description.text = str(god.get("description", ""))
	var god_color := Color(str(god.get("color", "#f0d88a")))
	god_button.add_theme_color_override("font_color", god_color)
