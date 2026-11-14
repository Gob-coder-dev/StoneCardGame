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


## Le chemin est injectable pour isoler les tests du fichier du joueur.
func _init(save_path: String = DEFAULT_PATH) -> void:
	_path = save_path


func path() -> String:
	return _path


func exists() -> bool:
	return FileAccess.file_exists(_path)


func load_raw() -> Dictionary:
	return Storage.read(_path)


func load_progress() -> CampaignProgress:
	return ProgressModel.from_dict(load_raw())


func save(progress: CampaignProgress) -> Error:
	if progress == null:
		return ERR_INVALID_PARAMETER
	return Storage.write(_path, progress.to_dict())
