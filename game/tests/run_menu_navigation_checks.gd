## Navigation entre les cinq scènes réelles, avec les événements du viewport.
## Le profil est isolé et les gestes sont testés pendant et après la transition.
extends Node

const Fixture := preload("res://tests/support/PlayerProfileFixture.gd")
const Routes := preload("res://scripts/ui/GameRoutes.gd")
const Log := preload("res://tests/support/TestLog.gd")
const PAGES := [Routes.SHOP, Routes.COLLECTION, Routes.MAIN_MENU, Routes.QUESTS, Routes.HOW_TO_PLAY]

var _checks := 0
var _failures: Array[String] = []
var _log := Log.new()
var _fixture: RefCounted
var _page: Control


func _ready() -> void:
	Log.current = _log
	OS.add_logger(_log)
	StoryService.auto_start_tutorials = false
	Input.emulate_touch_from_mouse = true
	Input.use_accumulated_input = false
	_fixture = Fixture.new()
	_run.call_deferred()


func _run() -> void:
	for source in range(PAGES.size()):
		for direction in [-1, 1]:
			var target: int = source - int(direction)
			await _open(source)
			var original := _page
			var nav: Control = _page.get_node("BottomNav")
			var nav_rect := nav.get_global_rect()
			var origin := _point(0.5, 0.45)
			var end := origin + Vector2(_page.size.x * 0.38 * direction, 0)
			await _drag(origin, end)
			if target >= 0 and target < PAGES.size():
				_check(MenuNavigation._incoming != null
					and MenuNavigation._incoming.scene_file_path == PAGES[target],
					"le vrai voisin est construit pendant le geste %d vers %d" % [source, target])
				_check(absf(MenuNavigation._incoming.position.x - original.position.x
					+ direction * original.size.x) < 1.0,
					"les deux pages restent jointives pendant le glissement")
				_check(nav.get_global_rect().is_equal_approx(nav_rect),
					"la barre du bas reste fixe")
				_check(MenuNavigation._incoming.process_mode == Node.PROCESS_MODE_DISABLED,
					"le voisin est inactif avant validation")
			else:
				_check(MenuNavigation._incoming == null,
					"les extrémités restent sans boucle")
			_touch(end, false)
			await _settled()
			var expected: int = target if target >= 0 and target < PAGES.size() else source
			_page = get_tree().current_scene as Control
			_check(_page != null and _page.scene_file_path == PAGES[expected],
				"le relâchement ouvre la bonne page %d" % expected)
			_check(is_zero_approx(_page.position.x) and _page.can_process(),
				"la page finale est centrée et interactive")
	await _canceled_gestures()
	await _card_gestures()
	await _blocked_gestures()
	await _navbar()
	await _traverse()
	await _cached_pages()
	await _resize_and_exit()
	await _finish()


func _canceled_gestures() -> void:
	await _open(1)
	var origin := _point(0.5, 0.42)
	var scroll: ScrollContainer = _page.get_node("Content/Scroll")
	await _drag(origin, origin + Vector2(0, -240))
	_touch(origin + Vector2(0, -240), false)
	await _settled()
	_check(scroll.scroll_vertical > 60 and MenuNavigation._incoming == null,
		"un geste vertical défile sans navigation")
	await _open(2)
	origin = _point(0.5, 0.45)
	await _drag(origin, origin + Vector2(65, 0))
	_touch(origin + Vector2(65, 0), false)
	await _settled()
	_check(get_tree().current_scene == _page and is_zero_approx(_page.position.x),
		"un geste court revient à la page courante")
	for interrupted in [true, false]:
		await _drag(origin, origin + Vector2(400, 0))
		if interrupted:
			_touch(origin + Vector2(400, 0), false, true)
		else:
			MenuNavigation.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
			_touch(origin + Vector2(400, 0), false)
		await _settled()
		_check(get_tree().current_scene == _page and is_zero_approx(_page.position.x)
			and MenuNavigation._incoming == null, "un geste interrompu restaure la page")


func _blocked_gestures() -> void:
	await _open(1)
	for modal in [_page.info_sheet, _page.pending_rewards_vault]:
		modal.show()
		var origin := _point(0.5, 0.4)
		await _drag(origin, origin + Vector2(450, 0))
		_touch(origin + Vector2(450, 0), false)
		await _settled()
		_check(get_tree().current_scene == _page and MenuNavigation._incoming == null,
			"une fenêtre ouverte garde le geste dans le menu Decks")
		modal.hide()
	await _open(0)
	_page.refresh_popup.open("TEST")
	var origin := _point(0.5, 0.4)
	await _drag(origin, origin + Vector2(-450, 0))
	_touch(origin + Vector2(-450, 0), false)
	await _settled()
	_check(get_tree().current_scene == _page and MenuNavigation._incoming == null,
		"une confirmation de boutique bloque la navigation tactile")
	_page.refresh_popup.dismiss()


func _card_gestures() -> void:
	await _open(1)
	var wrapper := _page.deck_rows.get_child(0).get_child(0) as Control
	var card := wrapper.get_child(0) as Control
	var origin := card.get_global_rect().get_center()
	var anchor := StoryService.get_anchor("collection.deck_panel")
	await _drag(origin, origin + Vector2(-85, 0))
	_check(StoryService.get_anchor("collection.deck_panel") == anchor,
		"un aperçu ne remplace pas les ancres de la page courante")
	_touch(origin + Vector2(-85, 0), false)
	await _settled()
	_check(_page._drawer.drawer == null,
		"un glissement sur une carte n’ouvre pas son tiroir")
	var scroll: ScrollContainer = _page.scroll
	await _drag(origin, origin + Vector2(0, -200))
	_touch(origin + Vector2(0, -200), false)
	await _settled()
	_check(scroll.scroll_vertical > 40, "le défilement vertical fonctionne après un glissement annulé")
	await _open(2)
	origin = _point(0.5, 0.45)
	Input.use_accumulated_input = true
	await _drag(origin, origin + Vector2(400, 0))
	_touch(origin + Vector2(400, 0), false)
	await _settled()
	_page = get_tree().current_scene
	_check(_page.scene_file_path == Routes.COLLECTION,
		"les événements regroupés utilisés sur téléphone permettent la navigation")
	Input.use_accumulated_input = false


func _resize_and_exit() -> void:
	await _open(2)
	var origin := _point(0.5, 0.45)
	await _drag(origin, origin + Vector2(400, 0))
	get_tree().root.size_changed.emit()
	_touch(origin + Vector2(400, 0), false)
	await _settled()
	_check(MenuNavigation._incoming == null and is_zero_approx(_page.position.x),
		"un redimensionnement pendant le geste restaure les positions")
	await _drag(origin, origin + Vector2(400, 0))
	_page.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	_touch(origin + Vector2(400, 0), false)
	await _settled()
	_check(get_tree().current_scene == _page and MenuNavigation._incoming == null,
		"le retour Android annule la transition en cours")
	await _drag(origin, origin + Vector2(400, 0))
	var source := _page
	Routes.go(get_tree(), Routes.STATS)
	await _settled()
	_check(not is_instance_valid(source) and MenuNavigation._incoming == null
		and get_tree().current_scene.scene_file_path == Routes.STATS,
		"une sortie vers un écran secondaire nettoie les deux menus")
	_check(MenuNavigation._cache._pages.is_empty() and not MenuNavigation._cache.is_processing(),
		"sortir des menus libère et arrête le cache")
	_page = get_tree().current_scene


func _navbar() -> void:
	await _open(4)
	var button: Control = _page.get_node("BottomNav/Tabs/ShopButton")
	var point := button.get_global_rect().get_center()
	_touch(point, true)
	_touch(point, false)
	await _settled()
	_page = get_tree().current_scene
	_check(_page.scene_file_path == Routes.SHOP, "le clic Règles vers Boutique ouvre la destination choisie")


func _traverse() -> void:
	await _open(4)
	for target in [3, 2, 1, 0, 1, 2, 3, 4]:
		var direction := 1 if target < PAGES.find(_page.scene_file_path) else -1
		var origin := _point(0.5, 0.45)
		var end := origin + Vector2(_page.size.x * 0.38 * direction, 0)
		await _drag(origin, end)
		_touch(end, false)
		await _settled()
		_page = get_tree().current_scene
		_check(_page.scene_file_path == PAGES[target], "la navigation successive atteint %s" % PAGES[target])


func _open(index: int) -> void:
	MenuNavigation.cancel()
	get_tree().current_scene = self
	get_tree().scene_changed.emit()
	if is_instance_valid(_page):
		_page.queue_free()
	await get_tree().process_frame
	_page = (load(PAGES[index]) as PackedScene).instantiate()
	get_tree().root.add_child(_page)
	get_tree().current_scene = _page
	get_tree().scene_changed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await _warm_cache()


func _warm_cache() -> void:
	for frame in range(180):
		var cache := MenuNavigation._cache
		if cache._pages.size() == cache._wanted.size():
			return
		await get_tree().process_frame
	var cache := MenuNavigation._cache
	_check(false, "les voisins sont préparés pendant le repos (%s, %s)" % [
		cache._pages.keys(), cache._wanted])


func _cached_pages() -> void:
	await _open(3)
	var cache := MenuNavigation._cache
	var quests := _page
	var rules: Control = cache._pages[Routes.HOW_TO_PLAY]
	var timer := quests.get_child(quests.get_child_count() - 1) as Timer
	_check(cache._pages.size() == 2, "le cache contient seulement les deux voisins")
	_check(not rules.visible and not rules.can_process() and rules._demos._players.is_empty(),
		"les règles préparées restent invisibles et sans décodeur vidéo")
	Routes.go(get_tree(), Routes.HOW_TO_PLAY)
	_check(MenuNavigation._incoming == rules, "la navigation réutilise la page déjà préparée")
	await _settled()
	_page = get_tree().current_scene
	_check(_page == rules and not rules._demos._players.is_empty(),
		"les vidéos démarrent lorsque les règles deviennent actives")
	var time_left := timer.time_left
	await _settled()
	_check(is_equal_approx(timer.time_left, time_left) and not quests.can_process(),
		"le minuteur des quêtes est suspendu dans le cache")
	Routes.go(get_tree(), Routes.QUESTS)
	await _settled()
	_page = get_tree().current_scene
	_check(rules._demos._players.is_empty(), "quitter les règles libère les décodeurs vidéo")
	Routes.go(get_tree(), Routes.HOW_TO_PLAY)
	await _settled()
	_page = get_tree().current_scene
	_check(not rules._demos._players.is_empty(), "revenir aux règles relance les vidéos visibles")
	rules._select_tab(rules.Tab.DECKS)
	await _settled()
	rules.scroll.scroll_vertical = 200
	var scroll_position: int = rules.scroll.scroll_vertical
	Routes.go(get_tree(), Routes.QUESTS)
	await _settled()
	_page = get_tree().current_scene
	_check(_page == quests, "le retour réutilise aussi la page quittée")
	Routes.go(get_tree(), Routes.HOW_TO_PLAY)
	await _settled()
	_page = get_tree().current_scene
	_check(_page == rules and rules._active_tab == rules.Tab.DECKS
		and rules.scroll.scroll_vertical == scroll_position,
		"un aller-retour conserve l’onglet et le défilement des règles")
	await _open(1)
	var old_home: Control = cache._pages[Routes.MAIN_MENU]
	var previous_name := PlayerData.player_name
	PlayerData.set_player_name("Navigation cache")
	# Aucun délai de maintenance : la validation doit aussi fonctionner à la prise.
	Routes.go(get_tree(), Routes.MAIN_MENU)
	var updated := MenuNavigation._incoming
	_check(updated != old_home and updated.profile_button.text.begins_with("Navigation cache"),
		"une donnée modifiée invalide immédiatement une page préparée")
	await _settled()
	_page = get_tree().current_scene
	PlayerData.set_player_name(previous_name)
	await _warm_cache()
	_check(cache._pages.size() <= 2, "le cache reste borné après invalidation")


func _point(x: float, y: float) -> Vector2:
	return _page.size * Vector2(x, y)


func _touch(point: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = point
	event.pressed = pressed
	event.canceled = canceled
	_inject(event)


func _drag(origin: Vector2, end: Vector2) -> void:
	_touch(origin, true)
	for step in range(1, 9):
		var event := InputEventScreenDrag.new()
		event.position = origin.lerp(end, step / 8.0)
		event.relative = (end - origin) / 8.0
		_inject(event)
		await get_tree().process_frame


func _inject(event: InputEvent) -> void:
	Input.parse_input_event(event.xformed_by(get_tree().root.get_final_transform()))


func _settled() -> void:
	await get_tree().create_timer(0.4).timeout


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		printerr("FAIL: ", message)


func _finish() -> void:
	MenuNavigation.cancel()
	get_tree().current_scene = self
	get_tree().scene_changed.emit()
	if is_instance_valid(_page):
		_page.queue_free()
	await get_tree().process_frame
	_fixture.restore()
	OS.remove_logger(_log)
	Log.current = null
	var problems: Array[String] = _log.problems()
	for problem in problems:
		printerr(problem)
	print("MENU_NAVIGATION_CHECKS: %d checks, %d failed, %d Godot errors" % [
		_checks, _failures.size(), problems.size()])
	Audio.quit_game(0 if _failures.is_empty() and problems.is_empty() else 1)
