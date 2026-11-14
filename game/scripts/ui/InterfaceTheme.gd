## Applique le thème commun à tout l'arbre, une fois que le SceneTree existe.
##
## `gui/theme/custom` charge une ressource sans script avant l'arbre. Ses styles
## enregistrés servent à l'aperçu de l'éditeur ; la même fabrique les actualise
## ici, après création du SceneTree, sans exécuter de code au chargement précoce.
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
