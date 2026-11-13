## Régression ciblée : les flammes doivent remplir leur Control et conserver
## leur densité procédurale sur téléphone, tablette et écran large.
extends "res://tests/support/CombatTestSuite.gd"

const FlameBackdrop := preload("res://scripts/ui/ritual/RitualFlameBackdrop.gd")


func run() -> void:
	var backdrop: RitualFlameBackdrop = FlameBackdrop.new()
	add_child(backdrop)
	await get_tree().process_frame
	var formats: Array[Vector2] = [
		Vector2(1080.0, 1920.0),
		Vector2(1220.0, 2712.0), # Xiaomi Redmi Note 14 Pro
		Vector2(1200.0, 1920.0),
		Vector2(1800.0, 2880.0), # Xiaomi Pad 6
		Vector2(1536.0, 2048.0),
		Vector2(1920.0, 1080.0),
		Vector2(1920.0, 1200.0),
	]
	for format in formats:
		backdrop.size = format
		await get_tree().process_frame
		var expected := format.x / format.y
		var actual := float(backdrop._flame_material.get_shader_parameter(
			"render_aspect"))
		_check(backdrop._surface.size.is_equal_approx(format),
			"flammes : la surface couvre entièrement le format %s" % str(format))
		_check(is_equal_approx(actual, expected),
			"flammes : le shader reçoit le ratio réel du format %s" % str(format))

	backdrop.coverage = 0.63
	_check(is_equal_approx(float(backdrop._flame_material.get_shader_parameter(
		"coverage")), 0.63),
		"flammes : le redimensionnement ne perturbe pas la progression de l'embrasement")
	backdrop.queue_free()
	await get_tree().process_frame
