## Formats de texte communs à l'interface.
class_name UIFormat
extends RefCounted

## Coûts en quarts de point, sans zéro final : « 12 », « 12,5 », « 12,75 ».
static func cost(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return ("%.2f" % value).trim_suffix("0").replace(".", ",")


## Entier lisible avec espaces fines par groupes de trois.
static func integer(value: int) -> String:
	var digits := str(absi(value))
	var groups: Array[String] = []
	while digits.length() > 3:
		groups.push_front(digits.right(3))
		digits = digits.left(digits.length() - 3)
	groups.push_front(digits)
	return ("-" if value < 0 else "") + " ".join(groups)


## Nom compact pour les zones de combat. Les anciennes sauvegardes peuvent
## encore contenir un libellé composé avec des tirets ; seule l'identité du
## combattant doit apparaître dans les plaques et messages de tour.
static func combatant_name(value: String, max_characters: int = 20) -> String:
	var compact := value.strip_edges()
	var parts := compact.split(" — ", false)
	if parts.size() > 1:
		var first := str(parts[0]).strip_edges()
		# Ancien format de campagne : "Mode — Dieu — Titre du niveau".
		compact = str(parts[1]).strip_edges() if GameModeRules.MODE_LABELS.values().has(first) \
			else first
	if compact == "":
		compact = "Adversaire"
	if max_characters > 1 and compact.length() > max_characters:
		return compact.left(max_characters - 1).strip_edges() + "…"
	return compact
