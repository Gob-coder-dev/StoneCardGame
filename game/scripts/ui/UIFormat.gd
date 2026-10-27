## Formats de texte communs à l'interface.
class_name UIFormat
extends RefCounted

## Coûts en quarts de point, sans zéro final : « 12 », « 12,5 », « 12,75 ».
static func cost(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return ("%.2f" % value).trim_suffix("0").replace(".", ",")
