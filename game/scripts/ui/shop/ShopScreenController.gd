## Écran Boutique. Les tirages et transactions restent dans les services ; ce
## contrôleur ne fait que construire une présentation responsive et la rafraîchir.
extends Control

const Shop := preload("res://scripts/application/economy/ShopService.gd")
const Economy := preload("res://scripts/application/economy/EconomyService.gd")
const CardLayout := preload("res://scripts/ui/collection/CardGridLayout.gd")
const GodPortraitView := preload("res://scripts/ui/GodPortrait.gd")
const TouchButtonScript := preload("res://scripts/ui/input/TouchButton.gd")
const SOUL_ICON := preload("res://assets/ui/soul-placeholder.svg")

@onready var soul_balance: SoulBalance = $Content/Header/SoulBalance
@onready var rotation_label: Label = $Content/Scroll/Page/Rotation
@onready var offers_grid: GridContainer = $Content/Scroll/Page/Offers
@onready var gods_grid: GridContainer = $Content/Scroll/Page/Gods
@onready var status_label: Label = $Content/Status

var _shop := Shop.new()
var _economy := Economy.new()
var _ends_at := 0
var _rotation_id := -1


func _ready() -> void:
	$Background.room = MenuBackground.Room.PROFILE
	_refresh()
	_apply_columns()
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_on_tick)
	add_child(timer)


func _apply_columns() -> void:
	# Deux fiches par ligne sur tous les formats : la largeur logique 1080 des
	# téléphones ne doit jamais déclencher une grille « tablette » à quatre cartes.
	offers_grid.columns = 2
	gods_grid.columns = 2


func _refresh() -> void:
	_clear(offers_grid)
	_clear(gods_grid)
	var state := _shop.state()
	if not bool(state.get("ok", false)):
		_show_status(str(state.get("reason", "Boutique indisponible.")), true)
		return
	_rotation_id = int(state["rotation_id"])
	_ends_at = int(state["ends_at"])
	soul_balance.refresh()
	for offer in state.get("offers", []):
		offers_grid.add_child(_offer_panel(offer))
	for god in StoneLoader.get_all_gods():
		gods_grid.add_child(_god_panel(god))
	_update_countdown()


func _offer_panel(offer: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(
		UITheme.COL_PANEL_BG, UITheme.COL_BORDER, 3, 14))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var card := CardLayout.make_stone_card(StoneLoader.get_stone(str(offer["stone_id"])),
		StoneCard.OWNER_NONE, 210)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(card)
	var quantity := Label.new()
	quantity.text = "%s  ×%d" % [str(offer["rarity"]).to_upper(), int(offer["quantity"])]
	quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quantity.add_theme_font_size_override("font_size", 24)
	box.add_child(quantity)
	var button := TouchButtonScript.new() as Button
	button.custom_minimum_size.y = 62
	var purchased := bool(offer.get("purchased", false))
	button.text = "ACHETÉ" if purchased else UIFormat.integer(int(offer["price"]))
	button.icon = null if purchased else SOUL_ICON
	button.add_theme_constant_override("icon_max_width", 38)
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.disabled = purchased
	button.pressed.connect(_buy_offer.bind(str(offer["id"])))
	box.add_child(button)
	return panel


func _god_panel(god: Dictionary) -> PanelContainer:
	var god_id := str(god.get("id", ""))
	var owned := PlayerData.has_unlocked_god(god_id)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(
		UITheme.COL_PANEL_BG, Color(str(god.get("color", UITheme.COL_BORDER.to_html()))), 3, 14))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var portrait := GodPortraitView.new()
	portrait.custom_minimum_size = Vector2(132, 132)
	portrait.setup(god)
	row.add_child(portrait)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	var title := Label.new()
	title.text = str(god.get("name", god_id)).to_upper()
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	var button := TouchButtonScript.new() as Button
	button.custom_minimum_size.y = 58
	button.disabled = owned
	button.text = "DÉBLOQUÉ" if owned else UIFormat.integer(_economy.god_price())
	button.icon = null if owned else SOUL_ICON
	button.add_theme_constant_override("icon_max_width", 38)
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.pressed.connect(_buy_god.bind(god_id))
	box.add_child(button)
	return panel


func _buy_offer(offer_id: String) -> void:
	var result := _shop.buy_offer(offer_id)
	_show_status(str(result.get("reason", "Cartes ajoutées à votre collection.")),
		not bool(result.get("ok", false)))
	_refresh()


func _buy_god(god_id: String) -> void:
	var result := _economy.buy_god(god_id)
	var message := str(result.get("reason", "Dieu et cartes débloqués."))
	if bool(result.get("ok", false)):
		var released: Array = result.get("released_cards", [])
		var released_count := 0
		for card_reward in released:
			released_count += int(card_reward.get("copies", 0))
		if released_count > 0:
			message = "Dieu débloqué : %d récompense%s en attente récupérée%s." % [
				released_count, "s" if released_count > 1 else "",
				"es" if released_count > 1 else "e"]
	_show_status(message, not bool(result.get("ok", false)))
	_refresh()


func _on_tick() -> void:
	var duration := int(EconomyConfig.get_config().get("shop_rotation_seconds", 10800))
	var current_rotation := int(Time.get_unix_time_from_system()) / duration
	if current_rotation != _rotation_id:
		_refresh()
	else:
		_update_countdown()


func _update_countdown() -> void:
	var remaining := maxi(0, _ends_at - int(Time.get_unix_time_from_system()))
	rotation_label.text = "NOUVELLES CARTES DANS %02d:%02d:%02d" % [
		remaining / 3600, (remaining % 3600) / 60, remaining % 60]


func _show_status(message: String, error: bool) -> void:
	status_label.text = message
	status_label.visible = message != ""
	status_label.add_theme_color_override("font_color", UITheme.COL_ERROR if error else UITheme.COL_SUCCESS)


func _clear(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
