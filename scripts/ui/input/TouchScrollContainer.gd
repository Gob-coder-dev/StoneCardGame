extends ScrollContainer
## Garde le défilement/inertie natifs et partage le seuil avec les appuis.

var _scrolling: bool = false
var _stopping_inertia: bool = false


func _ready() -> void:
	scroll_deadzone = UITheme.TOUCH_SLOP
	scroll_started.connect(_on_scroll_started)
	scroll_ended.connect(_on_scroll_ended)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.device == -1 and event.pressed and _scrolling:
		# Dans Godot 4.7, le clic émulé précède le toucher natif et arrête
		# l'inertie. Mémoriser cette interruption jusqu'au toucher suivant.
		_stopping_inertia = true
	if event is InputEventScreenTouch and event.pressed and (_scrolling or _stopping_inertia):
		# Toucher une liste en mouvement l'arrête sans activer la carte ou
		# le bouton qui se trouve sous le doigt à cet instant.
		propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)
	elif event is InputEventScreenTouch and not event.pressed:
		_stopping_inertia = false


func _on_scroll_started() -> void:
	_scrolling = true


func _on_scroll_ended() -> void:
	_scrolling = false
