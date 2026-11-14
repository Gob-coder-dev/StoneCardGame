## Lecture JSON sans journal implicite : le consommateur décide du traitement d'une erreur.
extends RefCounted


static func read(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null
