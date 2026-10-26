extends "res://tests/support/CombatTestSuite.gd"


func run() -> void:
	_test_catalogue_images()
	_test_shared_texture_and_fallback()
	_test_illustration_layout()
	_test_level_badge_layout()
	_test_rarity_and_board_ownership_styles()


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


func _test_level_badge_layout() -> void:
	var card := StoneCard.new()
	card.setup(StoneLoader.get_stone("f01_n1"))
	var compact_and_aligned := true
	for edge in [220.0, 964.0]:
		var art := Rect2(Vector2.ONE * edge * 0.1, Vector2.ONE * edge * 0.7)
		var badge := card._level_badge_rect(art, edge)
		var text_width := ThemeDB.fallback_font.get_string_size("N1", HORIZONTAL_ALIGNMENT_LEFT,
			-1, maxi(12, int(edge * 0.07))).x
		compact_and_aligned = compact_and_aligned and badge.end.is_equal_approx(art.end) \
			and badge.size.x > text_width and badge.size.x <= text_width * 1.5
	_check(compact_and_aligned,
		"le niveau reste lisible dans un badge compact, aligné au coin inférieur droit de l'illustration")
	card.free()


func _test_rarity_and_board_ownership_styles() -> void:
	var rarity_colors := {}
	for rarity in ["common", "rare", "epic", "legendary"]:
		rarity_colors[UITheme.rarity_color(rarity).to_html()] = true
	_check(rarity_colors.size() == 4
		and UITheme.rarity_color("unknown") == UITheme.COL_RARITY_COMMON,
		"les quatre raretés ont des liserés distincts et un repli commun sûr")

	var state := _state_with_hands([], [])
	_force_instance(state, 0, 0, "fx_plain", GameState.PLAYER_HUMAN)
	_force_instance(state, 0, 1, "fx_plain", GameState.PLAYER_AI)
	state.apply_blocked_cells([Vector2i(1, 1)])
	var view := BoardView.new()
	view.size = Vector2(900, 900)
	add_child(view)
	view.build()
	view.refresh(state)
	var human := view.slot_at(0, 0).get_theme_stylebox("panel") as StyleBoxFlat
	var ai := view.slot_at(0, 1).get_theme_stylebox("panel") as StyleBoxFlat
	var blocked := view.slot_at(1, 1).get_theme_stylebox("panel") as StyleBoxFlat
	_check(human.bg_color == UITheme.COL_BOARD_HUMAN_BG
		and ai.bg_color == UITheme.COL_BOARD_AI_BG
		and human.corner_radius_top_left != ai.corner_radius_top_left,
		"le camp est porté par deux cases fortement colorées et de géométries différentes")
	_check(blocked.bg_color == UITheme.COL_BOARD_BLOCKED_BG
		and view.slot_at(1, 1).get_node_or_null("BlockedMark") is BlockedCellOverlay,
		"une case interdite utilise le fond renforcé et la croix vectorielle adaptable")
	view.reveal_cell_owner(0, 1, GameState.PLAYER_HUMAN)
	var captured := view.slot_at(0, 1).get_theme_stylebox("panel") as StyleBoxFlat
	_check(captured.bg_color == UITheme.COL_BOARD_HUMAN_BG,
		"la vue peut révéler le nouveau propriétaire d'une case au moment de l'impact")
	view.free()
