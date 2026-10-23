## Formats de texte communs à l'interface.
class_name UIFormat
extends RefCounted

static func cost(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return "%.1f" % value
