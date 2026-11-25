## Écran Boutique. Les tirages et transactions restent dans les services ; ce
## contrôleur ne fait que construire une présentation responsive et la rafraîchir.
extends Control

const Shop := preload("res://scripts/application/economy/ShopService.gd")
const Economy := preload("res://scripts/application/economy/EconomyService.gd")
const Rituals := preload("res://scripts/application/economy/RitualService.gd")
const AccessService := preload("res://scripts/application/progression/ProgressionAccessService.gd")
const RitualOffer := preload("res://scripts/ui/shop/RitualOfferCard.gd")
const GodOffer := preload("res://scripts/ui/shop/GodOfferCard.gd")
const Routes := preload("res://scripts/ui/GameRoutes.gd")
const CardLayout := preload("res://scripts/ui/collection/CardGridLayout.gd")
const TouchButtonScript := preload("res://scripts/ui/input/TouchButton.gd")
const SOUL_ICON := preload("res://assets/ui/soul-placeholder.svg")
const CANDLE_ICON := preload("res://assets/ui/candle-placeholder.svg")
const REFRESH_CONFIRMATION := "Voulez-vous vraiment réinitialiser la boutique ?"
const GodIdentityModel := preload("res://scripts/data/GodIdentity.gd")

@onready var soul_balance: SoulBalance = $Content/Header/CurrencyBalances/SoulBalance
@onready var candle_balance: CandleBalance = $Content/Header/CurrencyBalances/CandleBalance
@onready var rotation_label: Label = $Content/Scroll/Page/RotationRow/Rotation
@onready var scroll: ScrollContainer = $Content/Scroll
@onready var refresh_button: ShopRefreshButton = $Content/Scroll/Page/RotationRow/RefreshButton
@onready var offers_grid: GridContainer = $Content/Scroll/Page/Offers
@onready var rituals_grid: GridContainer = $Content/Scroll/Page/Rituals
@onready var gods_grid: GridContainer = $Content/Scroll/Page/Gods
@onready var status_label: Label = $Content/Status
@onready var purchase_modal: ShopPurchaseModal = $PurchaseModal
@onready var refresh_popup: ConfirmPopup = $RefreshPopup

var _shop := Shop.new()
var _economy := Economy.new()
var _rituals := Rituals.new()
var _ends_at := 0
var _purchase_in_progress := false
var _refresh_in_progress := false
var _refresh_price := 0


func _ready() -> void:
	$Background.room = MenuBackground.Room.PROFILE
	$Background.set_god(GodIdentityModel.player(PlayerData.player_god_id))
	purchase_modal.confirmed.connect(_confirm_purchase)
	refresh_button.pressed.connect(_open_refresh_confirmation)
	refresh_popup.confirmed.connect(_confirm_refresh)
	_refresh()
	_apply_columns()
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_on_tick)
	add_child(timer)


func menu_page_activated() -> void:
	var offset := scroll.scroll_vertical
	_refresh()
	scroll.set_deferred("scroll_vertical", offset)


func _apply_columns() -> void:
	# Deux fiches par ligne sur tous les formats : la largeur logique 1080 des
	# téléphones ne doit jamais déclencher une grille « tablette » à quatre cartes.
	offers_grid.columns = 2
	rituals_grid.columns = 2
	gods_grid.columns = 2


func menu_swipe_allowed() -> bool:
	return not purchase_modal.visible and not refresh_popup.is_open() \
		and not _purchase_in_progress and not _refresh_in_progress


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and not get_meta("menu_preview", false):
		MenuNavigation.cancel_for_back()


func _refresh(now_unix: int = 0) -> void:
	if now_unix <= 0:
		now_unix = int(Time.get_unix_time_from_system())
	_clear(offers_grid)
	_clear(rituals_grid)
	_clear(gods_grid)
	var preview: bool = get_meta("menu_preview", false)
	var access := AccessService.new().state(preview)
	var state := _shop.state(now_unix, not preview, access)
	if not bool(state.get("ok", false)):
		_show_status(str(state.get("reason", "Boutique indisponible.")), true)
		refresh_button.setup(0, false, "Boutique indisponible.")
		rotation_label.text = ""
		return
	_ends_at = int(state["ends_at"])
	soul_balance.refresh()
	candle_balance.refresh()
	for offer in state.get("offers", []):
		offers_grid.add_child(_offer_panel(offer))
	var ritual_state := _rituals.state(access)
	if not bool(ritual_state.get("ok", false)):
		_show_status("La configuration des Rituels est invalide.", true)
	for definition in ritual_state.get("rituals", []):
		var card := RitualOffer.new()
		card.setup(definition)
		card.selection_requested.connect(_show_ritual_offer)
		rituals_grid.add_child(card)
	for god in MonsterLoader.get_all_gods():
		gods_grid.add_child(_god_panel(god))
	_update_refresh_button(state)
	_update_countdown(now_unix)


func _update_refresh_button(state: Dictionary) -> void:
	_refresh_price = maxi(0, int(state.get("refresh_price", 0)))
	var available := bool(state.get("can_refresh", false)) and _refresh_price > 0
	var reason := ""
	if not available:
		reason = "Pas assez de bougies." if PlayerData.candles() < _refresh_price \
			else "Aucune carte disponible."
	refresh_button.setup(_refresh_price, available, reason)


func _offer_panel(offer: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(
		UITheme.COL_PANEL_BG, UITheme.COL_BORDER, 3, 14))
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var card := CardLayout.make_monster_card(MonsterLoader.get_monster(str(offer["monster_id"])),
		MonsterCard.OWNER_NONE, 210)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(card)
	var quantity := Label.new()
	quantity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quantity.text = "%s  ×%d" % [str(offer["rarity"]).to_upper(), int(offer["quantity"])]
	quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quantity.add_theme_font_size_override("font_size", 24)
	box.add_child(quantity)
	var button := TouchButtonScript.new() as Button
	Audio.set_button_sfx(button, AudioCatalog.SFX_PURCHASE)
	button.custom_minimum_size.y = 62
	var purchased := bool(offer.get("purchased", false))
	button.text = "ACHETÉ" if purchased else UIFormat.integer(int(offer["price"]))
	button.icon = null if purchased else SOUL_ICON
	button.add_theme_constant_override("icon_max_width", 38)
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.disabled = purchased
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE if purchased \
		else Control.MOUSE_FILTER_PASS
	button.pressed.connect(_buy_offer.bind(str(offer["id"])))
	box.add_child(button)
	return panel


func _god_panel(god: Dictionary) -> GodOfferCard:
	var god_id := str(god.get("id", ""))
	var owned := PlayerData.has_unlocked_god(god_id)
	var card := GodOffer.new()
	card.setup(god, owned, _economy.god_price())
	card.selection_requested.connect(_show_god_offer)
	return card


func _buy_offer(offer_id: String) -> void:
	var result := _shop.buy_offer(offer_id)
	_show_status(str(result.get("reason", "Cartes ajoutées à votre collection.")),
		not bool(result.get("ok", false)))
	_refresh()


func _buy_god(god_id: String) -> Dictionary:
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
	return result


func _buy_ritual(ritual_id: String) -> Dictionary:
	var result := _rituals.purchase(ritual_id)
	if not bool(result.get("ok", false)):
		_show_status(str(result.get("reason", "Rituel indisponible.")), true)
	_refresh()
	return result


func _show_ritual_offer(ritual_id: String) -> void:
	var state := _rituals.state()
	for definition in state.get("rituals", []):
		if str(definition.get("id", "")) == ritual_id:
			purchase_modal.show_ritual(definition, PlayerData.candles())
			return
	_show_status("Ce Rituel est introuvable.", true)


func _show_god_offer(god_id: String) -> void:
	var god := MonsterLoader.get_god(god_id)
	if god.is_empty() or PlayerData.has_unlocked_god(god_id):
		return
	var gifts: Array = EconomyConfig.get_config().get("god_gifts", {}).get(god_id, [])
	purchase_modal.show_god(god, _economy.god_price(), PlayerData.souls(), gifts)


func _confirm_purchase(kind: String, offer_id: String) -> void:
	if _purchase_in_progress:
		return
	_purchase_in_progress = true
	purchase_modal.set_busy(true)
	if kind == "god":
		var god_result := _buy_god(offer_id)
		purchase_modal.close()
		_purchase_in_progress = false
		if not bool(god_result.get("ok", false)):
			_show_status(str(god_result.get("reason", "Achat impossible.")), true)
		return
	if kind == "ritual":
		var ritual_result := _buy_ritual(offer_id)
		if bool(ritual_result.get("ok", false)):
			var opening: Dictionary = ritual_result.get("opening", {})
			if RitualOpeningContext.begin(opening):
				purchase_modal.close()
				if _open_ritual() == OK:
					return
				# L'achat est déjà validé. Abandonner également la présentation
				# transitoire garantit qu'un échec de navigation ne crée jamais de
				# mécanisme implicite de reprise.
				RitualOpeningContext.clear()
			_show_status("L'ouverture visuelle du Rituel est indisponible, mais les récompenses sont acquises.", true)
	purchase_modal.set_busy(false)
	_purchase_in_progress = false


func _open_ritual() -> Error:
	return GameRoutes.go(get_tree(), Routes.RITUAL_OPENING)


func _open_refresh_confirmation() -> void:
	if refresh_button.disabled or _refresh_in_progress or _refresh_price <= 0:
		return
	refresh_popup.open(REFRESH_CONFIRMATION,
		"×%s" % UIFormat.integer(_refresh_price), CANDLE_ICON, "ANNULER")


func _confirm_refresh() -> void:
	if _refresh_in_progress:
		return
	_refresh_in_progress = true
	var result := _shop.refresh()
	_refresh_in_progress = false
	if bool(result.get("ok", false)):
		_show_status("Boutique réinitialisée.", false)
	else:
		_show_status(str(result.get("reason", "Réinitialisation impossible.")), true)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if refresh_popup.is_open():
		refresh_popup.dismiss()
		get_viewport().set_input_as_handled()
		return
	if purchase_modal.visible and not _purchase_in_progress:
		purchase_modal.close()
		get_viewport().set_input_as_handled()


func _on_tick() -> void:
	if get_meta("menu_preview", false):
		return
	var now := int(Time.get_unix_time_from_system())
	if now >= _ends_at:
		_refresh(now)
	else:
		_update_countdown(now)


func _update_countdown(now_unix: int) -> void:
	var remaining := maxi(0, _ends_at - now_unix)
	rotation_label.text = "NOUVELLES CARTES DANS %02d:%02d:%02d" % [
		floori(float(remaining) / 3600.0), floori(float(remaining % 3600) / 60.0), remaining % 60]


func _show_status(message: String, error: bool) -> void:
	status_label.text = message
	status_label.visible = message != ""
	status_label.add_theme_color_override("font_color", UITheme.COL_ERROR if error else UITheme.COL_SUCCESS)


func _clear(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
