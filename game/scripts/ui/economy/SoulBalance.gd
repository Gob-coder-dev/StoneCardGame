## Solde compact réutilisable dans les menus. Le logo temporaire peut être
## remplacé sans modifier les scènes ni les contrôleurs.
class_name SoulBalance
extends PanelContainer

@onready var amount_label: Label = $Content/Amount


func _ready() -> void:
	if not PlayerData.inventory_changed.is_connected(refresh):
		PlayerData.inventory_changed.connect(refresh)
	refresh()


func refresh() -> void:
	amount_label.text = UIFormat.integer(PlayerData.souls())
