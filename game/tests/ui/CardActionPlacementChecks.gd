## Régressions de géométrie des tiroirs : collection, deck et carte sans jauge.
extends "res://tests/support/CombatTestSuite.gd"

const Placement := preload("res://scripts/ui/collection/CardActionPlacement.gd")


func run() -> void:
	var layer := Control.new()
	layer.position = Vector2(17.0, 23.0)
	add_child(layer)
	var wrapper := Control.new()
	wrapper.position = Vector2(120.0, 210.0)
	wrapper.size = Vector2(280.0, 360.0)
	add_child(wrapper)
	var card := StoneCard.new()
	card.position = Vector2(30.0, 10.0)
	card.size = Vector2(200.0, 200.0)
	card.setup(StoneLoader.get_stone("la_gueule_sous_le_lit_n1"))
	wrapper.add_child(card)
	var progress := Control.new()
	progress.name = "Progress"
	progress.position = Vector2(30.0, 238.0)
	progress.size = Vector2(200.0, 36.0)
	wrapper.add_child(progress)
	await get_tree().process_frame

	var wrapper_rect := Placement.control_rect_in(layer, wrapper)
	var progress_rect := Placement.control_rect_in(layer, progress)
	var card_rect := Placement.control_rect_in(layer, card)
	var collection := Placement.resolve(layer, wrapper, card, true)
	_check(is_equal_approx(float(collection["x"]), wrapper_rect.position.x)
		and is_equal_approx(float(collection["width"]), wrapper_rect.size.x)
		and is_equal_approx(float(collection["bottom"]), progress_rect.end.y),
		"tiroir : la collection garde sa largeur historique et suit la jauge visible")

	var deck := Placement.resolve(layer, wrapper, card, false)
	_check(is_equal_approx(float(deck["x"]), progress_rect.position.x)
		and is_equal_approx(float(deck["width"]), progress_rect.size.x)
		and is_equal_approx(float(deck["bottom"]), progress_rect.end.y),
		"tiroir : le deck s'aligne exactement sur sa jauge")

	progress.visible = false
	var deck_legendary := Placement.resolve(layer, wrapper, card, false)
	var collection_legendary := Placement.resolve(layer, wrapper, card, true)
	_check(is_equal_approx(float(deck_legendary["x"]), card_rect.position.x)
		and is_equal_approx(float(deck_legendary["width"]), card_rect.size.x),
		"tiroir : sans jauge, le deck reprend la largeur de la carte")
	_check(float(deck_legendary["bottom"]) < card_rect.end.y
		and is_equal_approx(float(deck_legendary["bottom"]),
			float(collection_legendary["bottom"]))
		and is_equal_approx(float(collection_legendary["x"]), wrapper_rect.position.x)
		and is_equal_approx(float(collection_legendary["width"]), wrapper_rect.size.x),
		"tiroir : une carte sans lame basse ne conserve aucune marge verticale vide")

	var drawer_scene := load("res://scenes/ui/CardActionDrawer.tscn") as PackedScene
	var deck_drawer := drawer_scene.instantiate() as CardActionDrawer
	var collection_drawer := drawer_scene.instantiate() as CardActionDrawer
	layer.add_child(deck_drawer)
	layer.add_child(collection_drawer)
	deck_drawer.setup("la_gueule_sous_le_lit_n1", CardActionDrawer.Source.DECK)
	collection_drawer.setup("la_gueule_sous_le_lit_n1",
		CardActionDrawer.Source.COLLECTION)
	await get_tree().process_frame
	_check(deck_drawer.info_button.custom_minimum_size.y
		< collection_drawer.info_button.custom_minimum_size.y
		and deck_drawer.primary_button.custom_minimum_size.y
		< collection_drawer.primary_button.custom_minimum_size.y,
		"tiroir : seule la variante du deck utilise des actions compactes")

	# Le texte natif du bouton Améliorer ne doit jamais élargir le tiroir du
	# deck au-delà de la jauge, même avec son prix affiché sur deux lignes.
	deck_drawer.upgrade_button.visible = true
	deck_drawer.upgrade_button.set_content(
		"AMÉLIORER", true, 1500, UITheme.COL_WARNING)
	var deck_drawer_height := deck_drawer.get_combined_minimum_size().y
	deck_drawer.custom_minimum_size = Vector2(progress_rect.size.x,
		deck_drawer_height)
	deck_drawer.size = deck_drawer.custom_minimum_size
	await get_tree().process_frame
	_check(is_equal_approx(deck_drawer.size.x, progress_rect.size.x)
		and deck_drawer.upgrade_button.clip_text
		and not collection_drawer.upgrade_button.clip_text,
		"tiroir : Améliorer respecte la largeur de la jauge uniquement dans le deck")

	wrapper.queue_free()
	layer.queue_free()
	await get_tree().process_frame
