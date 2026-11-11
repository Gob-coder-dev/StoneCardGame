## Noms canoniques des scènes qui composent la boucle de jeu.
##
## Les contrôleurs ne recopient plus de chemins `res://` : une scène renommée
## ne demande qu'une modification ici. `go()` centralise aussi le diagnostic
## d'un changement de scène impossible au lieu de laisser une erreur muette.
class_name GameRoutes
extends RefCounted

const MAIN_MENU := "res://scenes/menus/MainMenu.tscn"
const SHOP := "res://scenes/menus/ShopScreen.tscn"
const RITUAL_OPENING := "res://scenes/menus/RitualOpening.tscn"
const COLLECTION := "res://scenes/menus/CollectionScreen.tscn"
const HOW_TO_PLAY := "res://scenes/menus/HowToPlay.tscn"
const STATS := "res://scenes/menus/Stats.tscn"
const QUESTS := "res://scenes/menus/Quests.tscn"
const ENCOUNTER_SELECT := "res://scenes/menus/EncounterSelect.tscn"
const ENCOUNTER_PATH := "res://scenes/menus/EncounterPath.tscn"
const CAMPAIGN_MAP := "res://scenes/campaign/CampaignMap.tscn"
const CAMPAIGN_PREPARATION := "res://scenes/campaign/CampaignPreparation.tscn"
const PRE_BATTLE := "res://scenes/menus/PreBattle.tscn"
const BOARD := "res://scenes/game/Board.tscn"
const CAMPAIGN_RESULT := "res://scenes/menus/Result.tscn"
const PVP_LOBBY := "res://scenes/menus/PvpLobby.tscn"
const PVP_PREPARATION := "res://scenes/menus/PvpPreparation.tscn"
const PVP_RESULT := "res://scenes/menus/PvpResult.tscn"


static func go(tree: SceneTree, scene_path: String) -> Error:
	if tree == null or scene_path.is_empty() or not ResourceLoader.exists(scene_path, "PackedScene"):
		push_error("GameRoutes: scène introuvable '%s'." % scene_path)
		return ERR_FILE_NOT_FOUND
	var error := tree.change_scene_to_file(scene_path)
	if error != OK:
		push_error("GameRoutes: ouverture impossible de '%s' (%s)." % [
			scene_path, error_string(error)])
	return error


## Point d'entrée commun aux contrôleurs testables. Une suite peut injecter un
## changement de scène sans que chaque écran recopie ce branchement.
static func go_with_override(tree: SceneTree, override: Callable,
		scene_path: String) -> Error:
	if override.is_valid():
		override.call(scene_path)
		return OK
	return go(tree, scene_path)
