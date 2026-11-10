## Solde compact de bougies, actualisé par la même source d'inventaire que les âmes.
class_name CandleBalance
extends PanelContainer

@onready var amount_label: Label = $Content/Amount


func _ready() -> void:
	if not PlayerData.inventory_changed.is_connected(refresh):
		PlayerData.inventory_changed.connect(refresh)
	refresh()


func refresh() -> void:
	amount_label.text = UIFormat.integer(PlayerData.candles())
