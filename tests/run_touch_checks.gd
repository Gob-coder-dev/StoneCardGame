## Régressions tactiles avec de vrais événements routés par le Viewport.
## Exécuter : godot --headless --fixed-fps 60 --path . res://tests/TouchInputChecks.tscn
## Ne nécessite pas GUT et ne modifie pas la sauvegarde du joueur.
extends Node

const TestLog := preload("res://tests/support/TestLog.gd")
const ProfileFixture := preload("res://tests/support/PlayerProfileFixture.gd")
## Secondes de jeu : avec --fixed-fps 60, la limite ne dépend pas de la machine.
const TIME_LIMIT := 120.0

var _checks: int = 0
var _failures: Array[String] = []
var _log: TestLog = TestLog.new()
var _finished := false
var _profile: ProfileFixture

@onready var root: Window = get_tree().root


func _ready() -> void:
	TestLog.current = _log
	OS.add_logger(_log)
	get_tree().create_timer(TIME_LIMIT).timeout.connect(_on_time_limit)
	_run.call_deferred()


func _on_time_limit() -> void:
	if not _finished:
		_failures.append("temps limite de %d s dépassé" % TIME_LIMIT)
		_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if _profile != null:
		_profile.restore()
	OS.remove_logger(_log)
	TestLog.current = null
	var problems: Array[String] = _log.problems()
	print("TACTILE : %d vérifications, %d échec(s), %d erreur(s) Godot." % [_checks, _failures.size(), problems.size()])
	# printerr : les échecs sont comptés ici, pas comme des erreurs Godot.
	for failure in _failures:
		printerr("ÉCHEC : ", failure)
	for problem in problems:
		printerr("ERREUR GODOT : ", problem)
	get_tree().quit(0 if _failures.is_empty() and problems.is_empty() else 1)


func _run() -> void:
	# Donne au serveur headless le même indicateur tactile qu'Android.
	Input.emulate_touch_from_mouse = true
	Input.use_accumulated_input = false
	_profile = ProfileFixture.new()
	await _check_rules_scroll()
	await _check_deck_slots()
	await _check_collection()
	await _check_button_inputs()
	await _check_main_menu()
	await _check_other_menus()
	await _check_buffered_input()
	await _check_battle_touch()
	await _check_battle_drag()
	_finish()


func _check_rules_scroll() -> void:
	var page := await _open_scene("res://scenes/menus/HowToPlay.tscn")
	var scroll: ScrollContainer = page.get_node("Content/Scroll")
	var text: RichTextLabel = scroll.get_node("RulesPanel/Page/RulesText")
	_check(scroll.get_v_scroll_bar().max_value > scroll.size.y, "règles : le contenu dépasse l'écran")
	await _swipe(_point(text, Vector2(200, 350)), Vector2(0, -240))
	_check(scroll.scroll_vertical > 100, "règles : glisser depuis le texte fait défiler")
	var badge: Control = scroll.get_node("RulesPanel/Page/GodRules").get_child(1).get_child(0)
	scroll.ensure_control_visible(badge)
	await _settle()
	var before := scroll.scroll_vertical
	await _swipe(_center(badge), Vector2(0, -220))
	_check(scroll.scroll_vertical > before + 60, "règles : glisser depuis un logo fait aussi défiler")
	await _remove(page)


func _check_deck_slots() -> void:
	var page := await _open_scene("res://scenes/menus/CollectionScreen.tscn")
	var scroll: ScrollContainer = page.get_node("Content/Scroll")
	var slots: HBoxContainer = scroll.get_node("Page/DeckSlots")
	var second: Button = slots.get_child(1)
	await _swipe(_center(second), Vector2(0, -180))
	_check(scroll.scroll_vertical > 60 and PlayerData.get_selected_deck() == 0,
		"decks : glisser depuis un numéro fait défiler sans changer de deck")
	await _reset_scroll(scroll)
	await _tap(_center(second))
	_check(PlayerData.get_selected_deck() == 1 and second.button_pressed
		and page._current_deck.is_empty(), "decks : un toucher sélectionne une seule fois le deuxième emplacement")
	_check(second.get_theme_stylebox("hover") == second.get_theme_stylebox("normal"),
		"decks : actualiser la sélection ne réactive pas le survol pendant un geste tactile")
	await _tap(_center(second))
	_check(second.button_pressed and PlayerData.get_selected_deck() == 1,
		"decks : retoucher le numéro actif conserve sa sélection")
	await _tap(_center(slots.get_child(0)))
	_check(PlayerData.get_active_deck() == ProfileFixture.DECK and not page.status_label.visible,
		"decks : revenir au premier deck restaure ses cartes sans message de sauvegarde")
	await _remove(page)


func _check_collection() -> void:
	var page := await _open_scene("res://scenes/menus/CollectionScreen.tscn")
	var scroll: ScrollContainer = page.get_node("Content/Scroll")
	var deck_rows: VBoxContainer = scroll.get_node("Page/DeckPanel/DeckContent/DeckRows")
	var first_card: StoneCard = deck_rows.get_child(0).get_child(0).get_child(0)
	await _swipe(_center(first_card), Vector2(0, -150))
	_check(scroll.scroll_vertical > 50, "deck : glisser depuis une carte fait défiler")
	_check(not is_instance_valid(page._action_drawer), "deck : un glissement n'ouvre pas le tiroir")
	await _reset_scroll(scroll)
	await _tap(_center(first_card))
	_check(is_instance_valid(page._action_drawer), "deck : un appui ouvre le tiroir")
	await _tap(_center(first_card))
	_check(not is_instance_valid(page._action_drawer), "deck : un second appui referme le tiroir une seule fois")
	await _swipe(_center(first_card), Vector2(0, -220))
	_check(scroll._scrolling, "défilement : l'inertie est active après le geste")
	var visible_card := _find_visible_card(scroll, scroll.get_global_rect())
	if visible_card != null:
		var stopped_at := scroll.scroll_vertical
		await _tap(_center(visible_card))
		_check(not is_instance_valid(page._action_drawer), "inertie : toucher une carte arrête la liste sans l'ouvrir")
		_check(scroll.scroll_vertical == stopped_at, "inertie : la liste reste arrêtée après le toucher")
	else:
		_check(false, "inertie : une carte est visible pour tester l'arrêt")
	await _reset_scroll(scroll)
	var first_position := _center(first_card)
	_press(first_position)
	_press(first_position, 1)
	_release(first_position, false, 1)
	await _settle()
	_check(not is_instance_valid(page._action_drawer), "multitouch : le second doigt ne termine pas l'appui du premier")
	_release(first_position)
	await _settle()
	_check(is_instance_valid(page._action_drawer), "multitouch : le premier doigt déclenche une seule action")
	page._close_action_drawer()
	await _settle()

	# Les cartes du deck sont masquées dans la collection : prendre la première affichée.
	var collection_card: StoneCard = null
	for wrapper in scroll.get_node("Page/CollectionRows").get_child(0).get_children():
		if wrapper.visible:
			collection_card = wrapper.get_child(0)
			break
	scroll.ensure_control_visible(collection_card)
	await _settle()
	var before := scroll.scroll_vertical
	await _swipe(_center(collection_card), Vector2(0, -180))
	_check(scroll.scroll_vertical > before + 60, "collection : glisser sur l'illustration fait défiler")
	_check(not is_instance_valid(page._action_drawer), "collection : aucune sélection accidentelle")

	var sort: Button = scroll.get_node("Page/CollectionHeader/SortButton")
	await _reset_scroll(scroll)
	await _swipe(_center(sort), Vector2(0, -180))
	_check(scroll.scroll_vertical > 60, "tri : un glissement démarré sur le bouton fait défiler")
	_check(not page.sort_menu.visible, "tri : glisser n'ouvre pas les options")
	await _reset_scroll(scroll)
	var sort_center := _center(sort)
	_press(sort_center)
	_drag(sort_center + Vector2(70, 0), Vector2(70, 0))
	_drag(sort_center, Vector2(-70, 0))
	_release(sort_center)
	await _settle()
	_check(not page.sort_menu.visible, "tri : revenir au point de départ après un glissement reste annulé")

	var crossing_start := _center(sort) + Vector2(0, 170)
	await _swipe(crossing_start, Vector2(0, -300))
	_check(not page.sort_menu.visible, "tri : traverser le bouton n'active rien")
	_check(sort.get_theme_stylebox("hover") == sort.get_theme_stylebox("normal"), "tri : aucune surbrillance de souris pendant le toucher")
	await _reset_scroll(scroll)
	await _tap(_center(sort))
	_check(page.sort_menu.visible, "tri : un véritable appui ouvre les options")
	var cost_option: Button = scroll.get_node("Page/SortMenu/SortOptions/CostButton")
	scroll.ensure_control_visible(cost_option)
	await _settle()
	await _tap(_center(cost_option))
	_check(page._sort_mode == 1 and not page.sort_menu.visible, "tri : choisir le coût fonctionne au tactile")

	await _reset_scroll(scroll)
	first_card = deck_rows.get_child(0).get_child(0).get_child(0)
	_press(_center(first_card))
	_release(_center(first_card), true)
	await _settle()
	_check(not is_instance_valid(page._action_drawer), "carte : un toucher annulé par le système n'active rien")
	await _tap(_center(first_card))
	if is_instance_valid(page._action_drawer):
		var info_button: Button = page._action_drawer.get_node("Actions/InfoButton")
		scroll.ensure_control_visible(info_button)
		await _settle()
		await _swipe(_center(info_button), Vector2(0, -150))
		_check(not page.info_sheet.visible, "tiroir : glisser sur Infos n'ouvre pas la fiche")
		await _reset_scroll(scroll)
		scroll.ensure_control_visible(info_button)
		await _settle()
		await _tap(_center(info_button))
		_check(page.info_sheet.visible, "tiroir : toucher Infos ouvre la fiche")
		var modal_scroll := scroll.scroll_vertical
		await _swipe(Vector2(200, 180), Vector2(0, -100))
		_check(scroll.scroll_vertical == modal_scroll, "fenêtre : les gestes ne traversent pas le fond modal")
		await _tap(Vector2(200, 100))
		_check(not page.info_sheet.visible, "fenêtre : toucher le fond ferme la fiche")
	await _remove(page)


func _check_button_inputs() -> void:
	# Chargé ici : une erreur dans ce script est comptée au lieu de bloquer le lanceur.
	var button: Button = load("res://scripts/ui/input/TouchButton.gd").new()
	button.text = "TEST"
	button.position = Vector2(100, 100)
	button.size = Vector2(300, 100)
	root.add_child(button)
	await _settle()
	var activations := [0]
	button.pressed.connect(func(): activations[0] += 1)
	var position := _center(button)
	_press(position)
	_check(activations[0] == 0, "bouton : aucune action avant le relâchement")
	_release(position)
	_check(activations[0] == 1, "bouton : un toucher déclenche exactement une action")
	_press(position)
	_release(position, true)
	_check(activations[0] == 1, "bouton : un toucher annulé ne déclenche rien")

	button.grab_focus()
	var accept := InputEventKey.new()
	accept.keycode = KEY_ENTER
	accept.pressed = true
	Input.parse_input_event(accept)
	accept = InputEventKey.new()
	accept.keycode = KEY_ENTER
	Input.parse_input_event(accept)
	_check(activations[0] == 2, "bouton : l'activation au clavier/manette reste disponible")
	_mouse_move(position)
	_mouse_button(position, true)
	_mouse_button(position, false)
	_check(activations[0] == 3, "bouton : le clic de souris physique reste disponible")
	_check(button.get_theme_stylebox("hover") != button.get_theme_stylebox("normal"), "bouton : le survol de souris est restauré")
	button.disabled = true
	await _tap(position)
	_check(activations[0] == 3, "bouton : une action désactivée reste inactive au toucher")
	await _remove(button)


func _check_main_menu() -> void:
	var menu := await _open_scene("res://scenes/menus/MainMenu.tscn")
	for path in ["Content/Header/ProfileButton", "Content/Hero/PlayButton"]:
		var button: Button = menu.get_node(path)
		# Les vrais changements de scène fermeraient la suite : on compte seulement.
		for connection in button.pressed.get_connections():
			button.pressed.disconnect(connection["callable"])
		var activations := [0]
		button.pressed.connect(func(): activations[0] += 1)
		await _tap(_center(button))
		_check(activations[0] == 1, "accueil : un toucher sur %s déclenche une seule action" % button.name)
		await _swipe(_center(button), Vector2(0, -150))
		_check(activations[0] == 1, "accueil : glisser depuis %s ne déclenche rien" % button.name)
	await _remove(menu)


func _check_other_menus() -> void:
	var stats := await _open_scene("res://scenes/menus/Stats.tscn")
	var scroll: ScrollContainer = stats.get_node("Root/Scroll")
	var edit: Button = scroll.get_node("Content/ProfilePanel/ProfileContent/PseudoRow/EditButton")
	await _tap(_center(edit))
	_check(stats.edit_row.visible, "profil : un seul appui ouvre l'édition du pseudo")
	stats._cancel_edit()
	# Les six adversaires actuels peuvent tenir sur un grand écran. Préparer
	# une liste longue pour vérifier le défilement sans dépendre des stats sauvées.
	scroll.get_node("Content/NPCPanel/NPCList").custom_minimum_size.y = 1400
	await _settle()
	var value_before := scroll.scroll_vertical
	await _swipe(_point(scroll, Vector2(100, 400)), Vector2(0, -200))
	_check(scroll.scroll_vertical > value_before, "profil : défilement tactile des statistiques")
	await _remove(stats)
	var levels := await _open_scene("res://scenes/menus/LevelSelect.tscn")
	var first_npc: Button = levels.get_node("Root/NPCListScroll/NPCList").get_child(0)
	await _tap(_center(first_npc))
	_check(levels.profile_panel.visible, "adversaires : les boutons dynamiques fonctionnent au toucher")
	await _remove(levels)


func _check_buffered_input() -> void:
	# Vérifie aussi le regroupement d'événements utilisé par défaut en jeu.
	Input.use_accumulated_input = true
	var page := await _open_scene("res://scenes/menus/HowToPlay.tscn")
	var scroll: ScrollContainer = page.get_node("Content/Scroll")
	await _swipe(_point(scroll, Vector2(200, 400)), Vector2(0, -240))
	_check(scroll.scroll_vertical > 100, "entrée regroupée : le défilement fonctionne avec les réglages du jeu")
	await _remove(page)
	Input.use_accumulated_input = false


func _check_battle_touch() -> void:
	var saved_npc: String = BattleContext.selected_npc_id
	var saved_first: int = BattleContext.forced_first_player
	BattleContext.selected_npc_id = "hiro"
	BattleContext.forced_first_player = GameState.PLAYER_HUMAN
	var board := await _open_scene("res://scenes/game/Board.tscn")
	var hand: HandView = board.get_node("Root/HandView")
	var card: StoneCard = hand.get_child(0).get_child(0)
	await _tap(_center(card))
	_check(board._selected_stone_id != "", "combat : sélectionner une carte avec un toucher natif")
	var slot: Panel = board.get_node("Root/BoardArea/BoardView/cell_1_1")
	var state: GameState = board.turn_manager.get_state()
	# Le plateau peut comporter une case bloquée : choisir une case libre.
	for index in range(state.board.size()):
		if state.board[index]["cell_type"] != GameState.CELL_BLOCKED:
			slot = board.get_node("Root/BoardArea/BoardView").get_node("cell_%d_%d" % [
				index / GameState.BOARD_SIZE, index % GameState.BOARD_SIZE])
			break
	await _tap(_center(slot))
	_check(state.human_hand.size() == DeckRules.DECK_SIZE - 1, "combat : une seule carte est posée au toucher")
	await _remove(board)
	BattleContext.selected_npc_id = saved_npc
	BattleContext.forced_first_player = saved_first


## Glisser une carte de la main jusqu'au plateau, au doigt puis à la souris.
func _check_battle_drag() -> void:
	var saved_npc: String = BattleContext.selected_npc_id
	var saved_first: int = BattleContext.forced_first_player
	BattleContext.selected_npc_id = "hiro"

	var board := await _open_battle(GameState.PLAYER_HUMAN)
	var hand: HandView = board.get_node("Root/HandView")
	var view: BoardView = board.get_node("Root/BoardArea/BoardView")
	var state: GameState = board.turn_manager.get_state()
	var cell := _free_cell(state)
	var card: StoneCard = hand.get_child(0).get_child(0)
	var start := _center(card)
	var lift: float = board._card_drag.TOUCH_LIFT * view.slot_at(0, 0).size.y
	var release := _center(view.slot_at(cell.x, cell.y)) + Vector2(0, lift)
	_press(start)
	for step in range(1, 9):
		var point := start.lerp(release, float(step) / 8.0)
		_drag(point, (release - start) / 8.0)
		await get_tree().process_frame
	await _settle()
	_check(board._card_drag.is_dragging() and view._drop_target == cell and card.modulate.a < 1.0,
		"glisser : la copie suit le doigt et la case visée s'éclaire")
	_release(release)
	await _settle()
	_check(state.human_hand.size() == DeckRules.DECK_SIZE - 1 and state.get_cell(cell.x, cell.y)["owner"] == GameState.PLAYER_HUMAN
		and view._drop_target == Vector2i(-1, -1) and board._card_drag.get_child_count() == 0,
		"glisser : relâcher sur une case y pose la carte une seule fois")
	await _remove(board)

	board = await _open_battle(GameState.PLAYER_HUMAN)
	hand = board.get_node("Root/HandView")
	view = board.get_node("Root/BoardArea/BoardView")
	state = board.turn_manager.get_state()
	cell = _free_cell(state)
	card = hand.get_child(0).get_child(0)
	# Lâchée un peu à côté du centre, la carte va quand même sur la case la plus proche.
	var near := _center(view.slot_at(cell.x, cell.y)) + Vector2(view.slot_at(0, 0).size.x * 0.3, lift)
	await _drag_touch(_center(card), near)
	_check(state.human_hand.size() == DeckRules.DECK_SIZE - 1 and state.get_cell(cell.x, cell.y)["owner"] == GameState.PLAYER_HUMAN,
		"glisser : une carte lâchée près d'une case est posée sur cette case")
	await _remove(board)

	board = await _open_battle(GameState.PLAYER_HUMAN)
	hand = board.get_node("Root/HandView")
	state = board.turn_manager.get_state()
	card = hand.get_child(0).get_child(0)
	await _drag_touch(_center(card), _center(card) + Vector2(0, 260))
	_check(state.human_hand.size() == DeckRules.DECK_SIZE and board._selected_stone_id == ""
		and is_equal_approx(card.modulate.a, 1.0) and board._card_drag.get_child_count() == 0,
		"glisser : relâcher hors du plateau ne joue rien et la carte revient sans sélection")
	_press(_center(card))
	_drag(_center(card) + Vector2(8, 0), Vector2(8, 0))
	_release(_center(card) + Vector2(8, 0))
	await _settle()
	_check(board._selected_stone_id == card.get_stone_id() and state.human_hand.size() == DeckRules.DECK_SIZE,
		"glisser : un petit mouvement reste un appui qui sélectionne la carte")
	await _remove(board)

	board = await _open_battle(GameState.PLAYER_HUMAN)
	hand = board.get_node("Root/HandView")
	view = board.get_node("Root/BoardArea/BoardView")
	state = board.turn_manager.get_state()
	cell = _free_cell(state)
	card = hand.get_child(0).get_child(0)
	var mouse_start := _center(card)
	var mouse_end := _center(view.slot_at(cell.x, cell.y))
	_mouse_move(mouse_start)
	_mouse_button(mouse_start, true)
	for step in range(1, 9):
		_mouse_move(mouse_start.lerp(mouse_end, float(step) / 8.0))
		await get_tree().process_frame
	_mouse_button(mouse_end, false)
	await _settle()
	_check(state.human_hand.size() == DeckRules.DECK_SIZE - 1 and state.get_cell(cell.x, cell.y)["owner"] == GameState.PLAYER_HUMAN,
		"glisser : la souris pose aussi la carte sur la case visée")
	await _remove(board)

	board = await _open_battle(GameState.PLAYER_AI)
	hand = board.get_node("Root/HandView")
	view = board.get_node("Root/BoardArea/BoardView")
	state = board.turn_manager.get_state()
	cell = _free_cell(state)
	card = hand.get_child(0).get_child(0)
	await _drag_touch(_center(card), _center(view.slot_at(cell.x, cell.y)) + Vector2(0, lift))
	_check(state.human_hand.size() == DeckRules.DECK_SIZE and state.get_cell(cell.x, cell.y)["owner"] != GameState.PLAYER_HUMAN,
		"glisser : aucune carte ne peut être posée pendant le tour adverse")
	await _remove(board)

	BattleContext.selected_npc_id = saved_npc
	BattleContext.forced_first_player = saved_first


func _open_battle(first_player: int) -> Control:
	BattleContext.forced_first_player = first_player
	return await _open_scene("res://scenes/game/Board.tscn")


## Première case jouable : le plateau peut comporter une case bloquée.
func _free_cell(state: GameState) -> Vector2i:
	for index in range(state.board.size()):
		var cell: Dictionary = state.board[index]
		if cell["cell_type"] != GameState.CELL_BLOCKED and cell["owner"] == GameState.PLAYER_NONE:
			return Vector2i(index / GameState.BOARD_SIZE, index % GameState.BOARD_SIZE)
	return Vector2i(-1, -1)


func _drag_touch(start: Vector2, finish: Vector2) -> void:
	_press(start)
	for step in range(1, 9):
		_drag(start.lerp(finish, float(step) / 8.0), (finish - start) / 8.0)
		await get_tree().process_frame
	_release(finish)
	await _settle()


func _open_scene(path: String) -> Control:
	var scene: PackedScene = load(path)
	var page := scene.instantiate() as Control
	root.add_child(page)
	await _settle()
	return page


func _remove(node: Node) -> void:
	root.remove_child(node)
	node.queue_free()
	await _settle()


func _reset_scroll(scroll: ScrollContainer) -> void:
	var point := _point(scroll, Vector2(3, 50))
	_press(point)
	_release(point, true)
	scroll.scroll_vertical = 0
	await _settle()


func _tap(position: Vector2) -> void:
	_press(position)
	_release(position)
	await _settle()


func _swipe(start: Vector2, movement: Vector2) -> void:
	_press(start)
	for step in range(1, 9):
		_drag(start + movement * (float(step) / 8.0), movement / 8.0)
		await get_tree().process_frame
	_release(start + movement)
	await _settle()


func _press(position: Vector2, index: int = 0) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = true
	_inject(event)


func _release(position: Vector2, canceled: bool = false, index: int = 0) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.canceled = canceled
	_inject(event)


func _drag(position: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.position = position
	event.relative = relative
	_inject(event)


func _mouse_move(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	_inject(event)


func _mouse_button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	_inject(event)


func _inject(event: InputEvent) -> void:
	# L'entrée passe par Input, y compris l'émulation native et le routage GUI.
	# Les contrôles vivent dans le canevas 1080p ; l'OS reçoit des pixels écran.
	Input.parse_input_event(event.xformed_by(root.get_final_transform()))


func _point(control: Control, local_point: Vector2) -> Vector2:
	return control.get_global_transform_with_canvas() * local_point


func _center(control: Control) -> Vector2:
	return _point(control, control.size * 0.5)


func _find_visible_card(node: Node, rect: Rect2) -> StoneCard:
	if node is CanvasItem and not node.is_visible_in_tree():
		return null
	if node is StoneCard and rect.has_point(_center(node)):
		return node
	for child in node.get_children():
		var found := _find_visible_card(child, rect)
		if found != null:
			return found
	return null


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame


func _check(condition: bool, label: String) -> void:
	_checks += 1
	print("%s %s" % ["OK" if condition else "ÉCHEC", label])
	if not condition:
		_failures.append(label)
