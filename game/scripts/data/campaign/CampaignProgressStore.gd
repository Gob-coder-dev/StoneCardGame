## CampaignProgressStore.gd
## Persistance isolée de la progression de campagne. Le fichier est distinct du
## profil : une campagne ne réécrit jamais les decks, le pseudo ni les
## statistiques générales. L'écriture passe par le même remplacement atomique
## que PlayerSaveStorage.
class_name CampaignProgressStore
extends RefCounted

const Storage := preload("res://scripts/data/PlayerSaveStorage.gd")
const ProgressModel := preload("res://scripts/domain/campaign/CampaignProgress.gd")
const DEFAULT_PATH := "user://campaign_progress.json"

var _path: String = DEFAULT_PATH
var load_error: Error = OK
var load_notice: String = ""


## Le chemin est injectable pour isoler les tests du fichier du joueur.
func _init(save_path: String = DEFAULT_PATH) -> void:
	_path = save_path


func path() -> String:
	return _path


func exists() -> bool:
	return FileAccess.file_exists(_path)


func load_raw() -> Dictionary:
	var result := Storage.read_result(_path, ProgressModel.is_complete)
	var raw: Dictionary = result["data"]
	load_error = result["error"]
	if not ProgressModel.supports(raw):
		load_error = ERR_UNAVAILABLE
	if result["state"] == Storage.ReadState.RECOVERED:
		load_notice = "Votre progression a été récupérée depuis la sauvegarde temporaire."
	elif result["state"] == Storage.ReadState.ARCHIVED:
		load_notice = "La progression endommagée a été archivée. Une nouvelle carte est ouverte."
	return raw


func load_progress() -> CampaignProgress:
	var raw := load_raw()
	return ProgressModel.from_dict(raw) if load_error == OK else null


func preview_progress() -> CampaignProgress:
	var raw: Variant = Storage.read_valid(_path, ProgressModel.is_complete)
	if raw == null:
		raw = Storage.read_valid(_path + Storage.TEMP_SUFFIX, ProgressModel.is_complete)
	return ProgressModel.from_dict(raw) if raw is Dictionary else null


func schema_error() -> Error:
	load_raw()
	return load_error


func save(progress: CampaignProgress) -> Error:
	if progress == null:
		return ERR_INVALID_PARAMETER
	var error := schema_error()
	if error != OK:
		return error
	return Storage.write(_path, progress.to_dict())
