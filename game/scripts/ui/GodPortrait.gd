## Portrait de dieu partagé par le bestiaire, l'avant-combat et le HUD.
## Le composant ne choisit aucun dieu : il affiche les données qu'un écran lui
## fournit et applique la couleur de sa famille à son cadre.
class_name GodPortrait
extends PanelContainer

var _image: TextureRect
var _god: Dictionary = {}
var _emphasized := false
var _asset_path := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image = TextureRect.new()
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_image)


func setup(god: Dictionary) -> void:
	_god = god
	var asset := str(god.get("asset", ""))
	if asset != _asset_path:
		_asset_path = asset
		_image.texture = load(asset) as Texture2D if asset != "" else null
	_refresh_style()


func set_emphasized(value: bool) -> void:
	if value == _emphasized:
		return
	_emphasized = value
	_refresh_style()


func has_portrait() -> bool:
	return _image.texture != null


func _refresh_style() -> void:
	var color := Color(str(_god.get("color", UITheme.COL_BORDER.to_html())))
	add_theme_stylebox_override("panel", UITheme.god_portrait_style(color, _emphasized))
