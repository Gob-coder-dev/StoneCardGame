## Lecture et écriture sûres du fichier de profil sur le disque.
## Le format et la migration appartiennent à PlayerSaveCodec ; ce fichier
## garantit seulement qu'un profil n'est jamais perdu par une écriture.
extends RefCounted

## Le nouveau profil est d'abord écrit à côté, puis remplace l'ancien.
const TEMP_SUFFIX := ".tmp"
## Un profil illisible est renommé avec ce suffixe au lieu d'être écrasé.
const UNREADABLE_SUFFIX := ".unreadable"


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
	if FileAccess.file_exists(path):
		var profile = _parse(path)
		if profile is Dictionary:
			return profile
		var aside := path + UNREADABLE_SUFFIX
		if FileAccess.file_exists(aside):
			DirAccess.remove_absolute(aside)
		DirAccess.rename_absolute(path, aside)
		push_warning("Profil illisible mis de côté : %s" % aside)
	var temp_path := path + TEMP_SUFFIX
	if FileAccess.file_exists(temp_path):
		var recovered = _parse(temp_path)
		if recovered is Dictionary:
			DirAccess.rename_absolute(temp_path, path)
			return recovered
	return {}


## Contenu JSON du fichier, ou null s'il ne peut pas être lu ou analysé.
static func _parse(path: String):
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	# JSON.new() signale l'erreur par son code, sans message dans le journal.
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data
