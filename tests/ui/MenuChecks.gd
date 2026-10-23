extends "res://tests/support/CombatTestSuite.gd"

func run() -> void:
	await _test_god_selector_ui()
	await _test_rules_legends()
	await _test_collection_incremental_refresh()

func _test_god_selector_ui() -> void:
	var saved_deck: Array = PlayerData.player_deck.duplicate()
	var saved_god: String = PlayerData.player_god_id
	PlayerData.player_god_id = "inari"
	PlayerData.player_deck = ["kappa", "tanuki", "ronin", "naginata_monk", "kitsune"]
	var scene: PackedScene = load("res://scenes/menus/CollectionScreen.tscn")
	var page: Control = scene.instantiate()
	add_child(page)
	await get_tree().process_frame
	await get_tree().process_frame
	var button: Button = page.get_node("Content/Scroll/Page/GodPanel/GodContent/GodButton")
	var menu: PanelContainer = page.get_node("Content/Scroll/Page/GodMenu")
	var options: VBoxContainer = page.get_node("Content/Scroll/Page/GodMenu/GodOptions")
	button.pressed.emit()
	await get_tree().process_frame
	_check(menu.visible and options.get_child_count() == 6, "le sélecteur affiche les six dieux dans le défilement")
	page.queue_free()
	await get_tree().process_frame
	PlayerData.player_deck = saved_deck
	PlayerData.player_god_id = saved_god


func _test_rules_legends() -> void:
	var scene: PackedScene = load("res://scenes/menus/HowToPlay.tscn")
	var page: Control = scene.instantiate()
	add_child(page)
	await get_tree().process_frame
	var legends: VBoxContainer = page.get_node("Content/Scroll/RulesPanel/Page/GodRules")
	var kinds := {}
	for row in legends.get_children():
		if row is HBoxContainer:
			var badge: Control = row.get_child(0)
			kinds[badge.kind] = true
	var all_documented := true
	for stone in StoneLoader.get_all_stones():
		for badge in Symbols.badges_for(stone):
			all_documented = all_documented and kinds.has(badge["kind"])
	_check(all_documented and kinds.size() == 9, "les règles montrent et expliquent tous les pictogrammes utilisés sur les cartes")
	page.queue_free()
	await get_tree().process_frame


func _test_collection_incremental_refresh() -> void:
	var previous := PlayerData.player_deck.duplicate()
	var scene: PackedScene = load("res://scenes/menus/CollectionScreen.tscn")
	var page: Control = scene.instantiate()
	add_child(page)
	await get_tree().process_frame
	var card: StoneCard = page.collection_rows.get_child(0).get_child(0).get_child(0)
	var identity := card.get_instance_id()
	page._current_deck = []
	page._refresh_all()
	await get_tree().process_frame
	_check(is_instance_valid(card) and card.get_instance_id() == identity,
		"rafraîchir le deck conserve les nœuds de la collection")
	page.queue_free()
	PlayerData.player_deck = previous
	await get_tree().process_frame
