## Applique le thème commun à tout l'arbre, une fois que le SceneTree existe.
##
## Le thème déclaré par `gui/theme/custom` est chargé avant l'arbre : son script
## ne peut donc pas le remplir sans faire remonter des erreurs au débogueur.
## Il arrive vide ici et reçoit tous ses styles maintenant.
extends Node

const THEME_PATH: String = "res://assets/ui/samstone_theme.tres"
const ThemeBuilder := preload("res://scripts/ui/RefugeTheme.gd")


func _ready() -> void:
	var theme := load(THEME_PATH) as Theme
	if theme == null:
		push_error("InterfaceTheme: thème introuvable (%s)" % THEME_PATH)
		return
	ThemeBuilder.apply(theme)
	get_tree().root.theme = theme
