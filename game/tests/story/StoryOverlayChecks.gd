## Rendu des overlays : portraits, machine à écrire, fermeture et spotlight.
## Les contrôles restent hors écran ; seules les propriétés vérifiables en
## headless sont contrôlées.
extends "res://tests/support/CombatTestSuite.gd"

const DialogueModel := preload("res://scripts/ui/story/DialogueOverlay.gd")
const SpotlightModel := preload("res://scripts/ui/story/SpotlightOverlay.gd")
const SessionModel := preload("res://scripts/application/story/StorySession.gd")


func run() -> void:
	await _test_dialogue_overlay()
	await _test_spotlight_overlay()
	await _test_spotlight_banner_on_tall_phone()


## Une scène Control de taille fixe : les overlays pleine page prennent leur
## taille par les ancres, jamais par une affectation directe de `size`.
func _make_stage() -> Control:
	var stage := Control.new()
	add_child(stage)
	stage.size = Vector2(1080, 1920)
	return stage


func _test_dialogue_overlay() -> void:
	var stage := _make_stage()
	var overlay := DialogueModel.new()
	stage.add_child(overlay)
	await get_tree().process_frame
	var closed := [false]
	overlay.closed.connect(func(): closed[0] = true)
	var session := SessionModel.new()
	session.sequence = {
		"id": "test_seq",
		"lines": [
			{"speaker": "pr_stone", "text": "Bienvenue, [b]joueur[/b]."},
			{"speaker": "pr_stone", "text": "Deuxième ligne."},
		],
	}
	session.context = {
		"characters": {
			"pr_stone": {
				"name": "Pr. Stone",
				"asset": "res://assets/gods/pr_stone.png",
				"color": "#bdb4ab",
				"side": "left",
			},
		},
	}
	overlay.show_session(session)
	_check(overlay.visible and overlay._index == 0,
		"dialogue : la séquence s'ouvre sur la première ligne")
	_check(overlay._left_portrait.visible and not overlay._right_portrait.visible,
		"dialogue : le portrait du locuteur est affiché à gauche")
	var fit := overlay._left_portrait.get_child(0) as AspectRatioContainer
	_check(overlay._left_image.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		and not overlay._left_portrait.clip_contents and fit is AspectRatioContainer
		and fit.get_child(0) == overlay._left_image,
		"dialogue : les portraits gardent leurs proportions et ne sont jamais rognés")
	# Vérifier la géométrie réelle après la passe de layout : le carré du
	# portrait doit rester à l'intérieur de son cadre, sans débordement.
	await get_tree().process_frame
	var slot_rect := overlay._left_portrait.get_global_rect()
	var fit_rect := fit.get_global_rect()
	var image_rect := overlay._left_image.get_global_rect()
	_check(slot_rect.encloses(fit_rect) and fit_rect.encloses(image_rect)
		and image_rect.size.x > 0.0
		and is_equal_approx(image_rect.size.x, image_rect.size.y),
		"dialogue : le carré du portrait reste entièrement contenu dans son cadre")
	_check(overlay._name_label.text == "PR. STONE",
		"dialogue : le nom du locuteur est affiché en capitales")
	_check(overlay._text.text.contains("Bienvenue"),
		"dialogue : le texte de la première ligne est chargé")
	_check(overlay._box.get_global_rect().position.y > 0.0,
		"dialogue : la boîte de texte est placée dans l'écran")
	overlay._typing = true
	overlay._visible_chars = 0.0
	overlay._advance()
	_check(not overlay._typing and overlay._text.visible_characters == -1,
		"dialogue : un premier appui révèle immédiatement toute la ligne")
	overlay._advance()
	_check(overlay._index == 1,
		"dialogue : un deuxième appui passe à la ligne suivante")
	overlay._typing = false
	overlay._advance()
	_check(not overlay.visible and closed[0],
		"dialogue : le dernier appui ferme l'overlay et signale la fin")
	stage.free()


func _test_spotlight_overlay() -> void:
	var stage := _make_stage()
	var target := Control.new()
	target.position = Vector2(540, 1420)
	target.size = Vector2(220, 220)
	stage.add_child(target)
	var spotlight := SpotlightModel.new()
	stage.add_child(spotlight)
	await get_tree().process_frame
	spotlight.show_target(target, "Touche la carte entourée.")
	_check(spotlight.visible and spotlight._blockers.size() == 4,
		"spotlight : le voile et ses quatre zones de blocage sont actifs")
	_check(spotlight._hole.has_point(target.get_global_rect().get_center()),
		"spotlight : le trou laisse la cible visible")
	_check(spotlight._hole.size.x > target.size.x and spotlight._hole.size.y > target.size.y,
		"spotlight : le trou déborde la cible pour rendre le contour lisible")
	_check(spotlight._banner.visible and spotlight._prompt.text != "",
		"spotlight : la consigne est affichée")
	_check(spotlight._banner.position.y < target.position.y,
		"spotlight : la consigne se place au-dessus d'une cible basse")
	var center := target.get_global_rect().get_center()
	var covered := false
	for blocker in spotlight._blockers:
		covered = covered or blocker.get_global_rect().has_point(center)
	_check(not covered,
		"spotlight : aucune zone de blocage ne recouvre la cible cliquable")
	var advanced := [0]
	spotlight.advance_requested.connect(func(): advanced[0] += 1)
	spotlight.show_target(target, "Le profil, les statistiques et les chemins.", true)
	_check(spotlight._advance_button.visible and spotlight._target_blocker.visible
		and spotlight._target_blocker.get_global_rect().has_point(center),
		"spotlight : une étape de présentation affiche SUIVANT et neutralise la cible")
	spotlight._advance_button.pressed.emit()
	_check(advanced[0] == 1,
		"spotlight : le bouton SUIVANT publie un seul événement d'avancement")
	target.position = Vector2(540, 200)
	await get_tree().process_frame
	spotlight._update_geometry()
	_check(spotlight._banner.position.y > target.position.y + target.size.y,
		"spotlight : la consigne se place sous une cible haute")
	spotlight.hide_spotlight()
	_check(not spotlight.visible,
		"spotlight : la fin de l'étape retire le voile")
	stage.free()


## Régression téléphone allongé : la consigne doit rester dans une zone de
## lecture proche du contenu, et non se coller au bord opposé de l'écran.
func _test_spotlight_banner_on_tall_phone() -> void:
	var stage := Control.new()
	add_child(stage)
	stage.size = Vector2(1080, 2400)
	var target := Control.new()
	target.position = Vector2(420, 2140)
	target.size = Vector2(240, 150)
	stage.add_child(target)
	var spotlight := SpotlightModel.new()
	stage.add_child(spotlight)
	await get_tree().process_frame
	spotlight.show_target(target, "Ouvre le cabinet : DECKS.")
	var banner_center_y := spotlight._banner.get_global_rect().get_center().y
	_check(banner_center_y <= stage.size.y * 0.76 + 1.0
		and banner_center_y >= stage.size.y * 0.24 - 1.0,
		"spotlight : sur un téléphone allongé, la consigne basse reste dans la zone de lecture")
	_check(spotlight._banner.get_global_rect().end.y < spotlight._hole.position.y,
		"spotlight : la consigne recentrée ne masque pas une cible basse")
	target.position = Vector2(420, 150)
	await get_tree().process_frame
	spotlight._update_geometry()
	banner_center_y = spotlight._banner.get_global_rect().get_center().y
	_check(banner_center_y >= stage.size.y * 0.24 - 1.0
		and spotlight._banner.get_global_rect().position.y > spotlight._hole.end.y,
		"spotlight : une cible haute garde sa consigne recentrée en dessous")
	stage.free()
