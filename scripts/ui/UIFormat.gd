## Formats de texte communs à l'interface.
class_name UIFormat
extends RefCounted

## Points sans décimale inutile, avec la virgule française : « 12 » ou « 12,5 ».
static func cost(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return ("%.1f" % value).replace(".", ",")
