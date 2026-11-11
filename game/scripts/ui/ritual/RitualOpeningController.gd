## Mise en scène d'un tirage déjà attribué et sauvegardé. L'ouverture n'existe
## qu'en mémoire : fermer le jeu abandonne l'animation, jamais les récompenses.
extends Control

const RitualConfigModel := preload("res://scripts/data/economy/RitualConfig.gd")
const Routes := preload("res://scripts/ui/GameRoutes.gd")
const SoulIcon := preload("res://assets/ui/soul-placeholder.svg")

enum Stage { SIGIL, REWARD_BACK, REWARD_FRONT, SUMMARY, BUSY }

@onready var title_label: Label = $Margin/Page/Title
@onready var lucky_label: Label = $Margin/Page/Lucky
@onready var stage_container: Control = $Margin/Page/Stage
@onready var sigil_button: Button = $Margin/Page/Stage/ActivationButton
@onready var sigil: RitualSigil = $Margin/Page/Stage/Sigil
@onready var reward_button: Button = $Margin/Page/Stage/RewardButton
@onready var reward_content: VBoxContainer = $Margin/Page/Stage/RewardButton/Center/Content
@onready var prompt_label: Label = $Margin/Page/Prompt
@onready var summary: PanelContainer = $Margin/Page/Summary
@onready var summary_grid: GridContainer = $Margin/Page/Summary/Content/Grid
@onready var finish_button: Button = $Margin/Page/FinishButton
@onready var status_label: Label = $Margin/Page/Status
@onready var flames: RitualFlameBackdrop = $Flames

var _opening: Dictionary = {}
var _definition: Dictionary = {}
var _index := 0
var _stage := Stage.BUSY


func _ready() -> void:
	## Le sceau et la carte ont déjà leur propre son : le clic générique serait
	## un doublon. Le bouton de sortie reste une validation ordinaire.
	Audio.set_button_silent(sigil_button)
	Audio.set_button_silent(reward_button)
	Audio.set_button_sfx(finish_button, AudioCatalog.SFX_BUTTON_2)
	sigil_button.pressed.connect(_on_sigil_pressed)
	reward_button.pressed.connect(_on_reward_pressed)
	finish_button.pressed.connect(_finish)
	_opening = RitualOpeningContext.current()
	if _opening.is_empty():
		GameRoutes.go(get_tree(), Routes.SHOP)
		return
	_definition = RitualConfigModel.definition(str(_opening.get("ritual_id", "")))
	if _definition.is_empty():
		_show_error("La définition de ce Rituel est introuvable.")
		return
	title_label.text = str(_opening.get("ritual_name", "Rituel")).to_upper()
	lucky_label.visible = bool(_opening.get("lucky", false))
	sigil.setup(_definition)
	_show_sigil()


func _show_sigil() -> void:
	_stage = Stage.SIGIL
	stage_container.visible = true
	sigil.visible = true
	sigil.modulate = Color.WHITE
	sigil_button.visible = true
	sigil_button.disabled = false
	reward_button.visible = false
	summary.visible = false
	finish_button.visible = false
	prompt_label.text = "Touchez l'écran pour commencer l'invocation"


func _on_sigil_pressed() -> void:
	if _stage != Stage.SIGIL:
		return
	_stage = Stage.BUSY
	sigil_button.disabled = true
	Audio.play_sfx(AudioCatalog.SFX_BIG_FLAME)
	flames.ignite_full()
	await flames.covered
	_show_reward_back()
	await flames.finished


func _show_reward_back() -> void:
	_clear(reward_content)
	var mark := Label.new()
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.text = "✦"
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.add_theme_font_size_override("font_size", 170)
	mark.add_theme_color_override("font_color", Color(str(
		_definition.get("blood_color", "#a62f35"))).lightened(0.28))
	reward_content.add_child(mark)
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = "INVOCATION SCELLÉE"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 30)
	reward_content.add_child(label)
	reward_button.visible = true
	reward_button.modulate = Color.WHITE
	reward_button.scale = Vector2.ONE
	_stage = Stage.REWARD_BACK
	prompt_label.text = "Touchez pour révéler"


func _on_reward_pressed() -> void:
	if _stage == Stage.REWARD_BACK:
		await _reveal_current()
	elif _stage == Stage.REWARD_FRONT:
		await _advance()


func _reveal_current() -> void:
	_stage = Stage.BUSY
	var close := create_tween()
	close.tween_property(reward_button, "scale:x", 0.03, 0.18).set_trans(Tween.TRANS_QUAD)
	await close.finished
	Audio.play_sfx(AudioCatalog.SFX_REVEAL)
	var reward: Dictionary = (_opening.get("rewards", []) as Array)[_index]
	_build_reward_front(reward)
	var open := create_tween()
	open.tween_property(reward_button, "scale:x", 1.0, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await open.finished
	_stage = Stage.REWARD_FRONT
	prompt_label.text = "Touchez pour poursuivre"


func _advance() -> void:
	_stage = Stage.BUSY
	var start_position := reward_button.position
	var direction := 1.0 if _index % 2 == 0 else -1.0
	var target_position := start_position + Vector2(size.x * 0.66 * direction, 0.0)
	Audio.play_sfx(AudioCatalog.SFX_WOOSH)
	var exit_tween := create_tween()
	exit_tween.set_parallel(true)
	exit_tween.tween_property(reward_button, "modulate:a", 0.0, 0.22)
	exit_tween.tween_property(reward_button, "position", target_position, 0.28) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await exit_tween.finished
	reward_button.position = start_position
	_index += 1
	if _index >= (_opening.get("rewards", []) as Array).size():
		_show_summary()
		return
	Audio.play_sfx(AudioCatalog.SFX_LITTLE_FLAME)
	flames.ignite_minor()
	await flames.covered
	_show_reward_back()
	await flames.finished


func _build_reward_front(reward: Dictionary) -> void:
	_clear(reward_content)
	if str(reward.get("type", "")) == "souls":
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.custom_minimum_size = Vector2(240, 240)
		icon.texture = SoulIcon
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		reward_content.add_child(icon)
		_add_reward_label("×%s" % UIFormat.integer(int(reward.get("amount", 0))), 62,
			UITheme.COL_WARNING)
		_add_reward_label("ÂMES INVOQUÉES", 27, UITheme.COL_TEXT_DIM)
		return
	var card := StoneCard.new()
	card.custom_minimum_size = Vector2(420, 420)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_show_cost(false)
	card.setup(StoneLoader.get_stone(str(reward.get("stone_id", ""))), StoneCard.OWNER_NONE)
	reward_content.add_child(card)
	_add_reward_label("×%d" % int(reward.get("copies", 1)), 50, UITheme.COL_TEXT)
	if bool(reward.get("deferred", false)):
		var god := StoneLoader.get_god(str(reward.get("god_id", "")))
		_add_reward_label("CONSERVÉE DANS LE COFFRE — %s" % str(god.get("name", "DIEU VERROUILLÉ")).to_upper(),
			22, UITheme.COL_WARNING)
	if bool(reward.get("maxed", false)):
		_add_reward_label("DÉJÀ AU NIVEAU MAXIMUM", 23, UITheme.COL_WARNING)
		_add_compensation(int(reward.get("compensation_souls", 0)))


func _add_reward_label(text: String, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	reward_content.add_child(label)


func _add_compensation(amount: int) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	var prefix := Label.new()
	prefix.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prefix.text = "Dédommagement :"
	prefix.add_theme_font_size_override("font_size", 24)
	prefix.add_theme_color_override("font_color", UITheme.COL_SUCCESS)
	row.add_child(prefix)
	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.custom_minimum_size = Vector2(38, 38)
	icon.texture = SoulIcon
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var value := Label.new()
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value.text = "×%s" % UIFormat.integer(amount)
	value.add_theme_font_size_override("font_size", 24)
	value.add_theme_color_override("font_color", UITheme.COL_SUCCESS)
	row.add_child(value)
	reward_content.add_child(row)


func _show_summary() -> void:
	_stage = Stage.SUMMARY
	stage_container.visible = false
	summary.visible = true
	finish_button.visible = true
	prompt_label.text = "Le Rituel est accompli"
	_clear(summary_grid)
	var rewards: Array = _opening.get("rewards", [])
	summary_grid.columns = 2 if rewards.size() <= 4 else 3
	var tile_size := 320 if rewards.size() <= 4 else 250
	for reward in rewards:
		summary_grid.add_child(_summary_tile(reward, tile_size))


func _summary_tile(reward: Dictionary, tile_size: int) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(tile_size, tile_size + 62)
	if str(reward.get("type", "")) == "souls":
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(tile_size, tile_size)
		icon.texture = SoulIcon
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		box.add_child(icon)
		box.add_child(_small_label("×%s" % UIFormat.integer(int(reward.get("amount", 0)))))
		return box
	var card := StoneCard.new()
	card.custom_minimum_size = Vector2(tile_size, tile_size)
	card.set_show_cost(false)
	card.setup(StoneLoader.get_stone(str(reward.get("stone_id", ""))), StoneCard.OWNER_NONE)
	box.add_child(card)
	var suffix := "  •  coffre" if bool(reward.get("deferred", false)) else ""
	if bool(reward.get("maxed", false)):
		suffix = "  •  +%s âmes" % UIFormat.integer(int(reward.get("compensation_souls", 0)))
	box.add_child(_small_label("×%d%s" % [int(reward.get("copies", 1)), suffix]))
	return box


func _small_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 22)
	return label


## Une récompense de quête revient à l'écran Quêtes, un achat revient à la
## Boutique. L'origine voyage dans l'ouverture, jamais dans la sauvegarde.
func _return_route() -> String:
	return Routes.QUESTS if str(_opening.get("return_to", "")) == "quests" else Routes.SHOP


func _finish() -> void:
	if _stage != Stage.SUMMARY:
		return
	RitualOpeningContext.clear()
	GameRoutes.go(get_tree(), _return_route())


func _show_error(message: String) -> void:
	_stage = Stage.BUSY
	status_label.visible = true
	status_label.text = message
	status_label.add_theme_color_override("font_color", UITheme.COL_ERROR)
	prompt_label.text = "Les récompenses ont déjà été enregistrées."
	finish_button.visible = true
	finish_button.text = "RETOUR AUX QUÊTES" if _return_route() == Routes.QUESTS \
		else "RETOUR À LA BOUTIQUE"
	finish_button.pressed.disconnect(_finish)
	finish_button.pressed.connect(func():
		RitualOpeningContext.clear()
		GameRoutes.go(get_tree(), _return_route()))


func _clear(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	# Aucun retour normal n'est autorisé pendant un Rituel. Fermer réellement
	# l'application abandonne seulement cette mise en scène transitoire.
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_inside_tree():
		get_viewport().set_input_as_handled()

