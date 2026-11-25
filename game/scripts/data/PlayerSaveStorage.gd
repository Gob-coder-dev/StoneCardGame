## Lecture et écriture sûres du fichier de profil sur le disque.
## Le format et la migration appartiennent à PlayerSaveCodec ; ce fichier
## garantit seulement qu'un profil n'est jamais perdu par une écriture.
extends RefCounted

const Json := preload("res://scripts/data/JsonFile.gd")

## Le nouveau profil est d'abord écrit à côté, puis remplace l'ancien.
const TEMP_SUFFIX := ".tmp"
## Un profil illisible est renommé avec ce suffixe au lieu d'être écrasé.
const UNREADABLE_SUFFIX := ".unreadable"
enum ReadState { CLEAN, RECOVERED, ARCHIVED, FAILED }


## Écrit data en JSON. Le profil précédent n'est remplacé qu'une fois le
## nouveau fichier complet : une coupure pendant l'écriture le laisse intact.
static func write(path: String, data: Dictionary) -> Error:
	var temp_path := path + TEMP_SUFFIX
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data))
	var error := file.get_error()
	file.close()
	if error != OK:
		DirAccess.remove_absolute(temp_path)
		return error
	return DirAccess.rename_absolute(temp_path, path)


## Lit le profil, ou {} s'il n'en existe aucun. Un fichier illisible est mis de
## côté pour que la prochaine sauvegarde ne le détruise pas. Si un remplacement
## a été interrompu, le nouveau profil resté à côté est récupéré.
static func read(path: String) -> Dictionary:
	return read_result(path)["data"]


static func read_result(path: String, validator: Callable = Callable()) -> Dictionary:
	var archived := false
	if FileAccess.file_exists(path):
		var profile: Variant = read_valid(path, validator)
		if profile != null:
			return _result(ReadState.CLEAN, profile)
		var error := _archive(path)
		if error != OK:
			return _result(ReadState.FAILED, {}, error)
		archived = true
	var temp_path := path + TEMP_SUFFIX
	if FileAccess.file_exists(temp_path):
		var recovered: Variant = read_valid(temp_path, validator)
		if recovered != null:
			var restore_error := DirAccess.rename_absolute(temp_path, path)
			if restore_error != OK:
				return _result(ReadState.FAILED, recovered, restore_error)
			return _result(ReadState.RECOVERED, recovered)
		var error := _archive(temp_path)
		if error != OK:
			return _result(ReadState.FAILED, {}, error)
		archived = true
	return _result(ReadState.ARCHIVED if archived else ReadState.CLEAN, {})


static func read_valid(path: String, validator: Callable) -> Variant:
	var data: Variant = Json.read(path)
	if data is Dictionary and (not validator.is_valid() or validator.call(data)):
		return data
	return null


static func _archive(path: String) -> Error:
	var base := path + UNREADABLE_SUFFIX
	var target := base
	var index := 1
	while FileAccess.file_exists(target) or DirAccess.dir_exists_absolute(target):
		target = "%s.%d" % [base, index]
		index += 1
	return DirAccess.rename_absolute(path, target)


static func _result(state: ReadState, data: Dictionary, error: Error = OK) -> Dictionary:
	return {"state": state, "data": data, "error": error}
