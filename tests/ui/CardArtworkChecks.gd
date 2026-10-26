extends "res://tests/support/CombatTestSuite.gd"


func run() -> void:
	_test_catalogue_images()
	_test_shared_texture_and_fallback()
	_test_illustration_layout()


func _test_catalogue_images() -> void:
	var paths := {}
	for stone in StoneLoader.get_all_stones():
		var path := str(stone.get("asset", ""))
		if not path.is_empty():
			paths[path] = true
	var loadable := not paths.is_empty()
	for path in paths:
		if not ResourceLoader.exists(path, "Texture2D"):
			loadable = false
			continue
		var texture := load(path) as Texture2D
		loadable = loadable and texture != null and texture.get_width() > 0 and texture.get_height() > 0
	_check(loadable, "toutes les illustrations déclarées dans le catalogue se chargent comme textures")
	_check(not str(StoneLoader.get_stone("n01_n1").get("asset", "")).is_empty(),
		"les Avortons des caves utilisent leur illustration de groupe")
	var first := str(StoneLoader.get_stone("d01_n1").get("asset", ""))
	var fourth := str(StoneLoader.get_stone("d01_n4").get("asset", ""))
	_check(not fourth.is_empty() and fourth != first and ResourceLoader.exists(fourth),
		"le Porte-fièvre niveau quatre utilise sa propre illustration")


func _test_shared_texture_and_fallback() -> void:
	var definition := StoneLoader.get_stone("n01_n1")
	var first := StoneCard.new()
	var second := StoneCard.new()
	first.setup(definition)
	second.setup(definition.duplicate(true))
	_check(first._texture != null and first._texture == second._texture,
		"deux vues d'une même illustration partagent la ressource texture")
	var placeholder := definition.duplicate(true)
	placeholder["asset"] = ""
	first.setup(placeholder)
	_check(first._texture == null,
		"réutiliser une carte sans image retire l'ancienne texture et conserve le dessin provisoire")
	_check(second.mouse_filter == Control.MOUSE_FILTER_PASS,
		"une carte illustrée continue de laisser défiler le conteneur tactile")
	first.free()
	second.free()


func _test_illustration_layout() -> void:
	var card := StoneCard.new()
	card._texture = ImageTexture.create_from_image(Image.create(120, 60, false, Image.FORMAT_RGBA8))
	var bounds := Rect2(20, 30, 80, 120)
	var fitted := card._illustration_rect(bounds)
	_check(fitted.size.is_equal_approx(Vector2(80, 40))
		and fitted.get_center().is_equal_approx(bounds.get_center()),
		"une image horizontale reste proportionnée et centrée dans une carte verticale")
	card._texture = ImageTexture.create_from_image(Image.create(60, 120, false, Image.FORMAT_RGBA8))
	fitted = card._illustration_rect(bounds)
	_check(fitted.size.is_equal_approx(Vector2(60, 120))
		and fitted.get_center().is_equal_approx(bounds.get_center()),
		"une image verticale reste entière sans étirement ni rognage")
	card.free()
