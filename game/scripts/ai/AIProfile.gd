## Réglage d'une IA, construit par OpponentCatalog ou lu dans le champ "ai" d'un
## adversaire historique de npcs.json :
##   "ai": { "precision": 0.5, "anticipation": false }
##
## precision    : probabilité de jouer le meilleur coup évalué. Sinon l'IA fait
##                une erreur crédible : un coup tiré au sort, d'autant plus
##                souvent choisi qu'il rapporte. 0 joue au hasard, 1 ne se trompe pas.
## anticipation : l'IA retire de chaque coup la meilleure riposte adverse, puis
##                calcule exactement les derniers coups de la partie.
extends RefCounted

const KEYS: Array[String] = ["precision", "anticipation"]

var precision: float = 0.0
var anticipation: bool = false


## Un profil invalide, déjà signalé au chargement par ContentValidator, joue au hasard.
func _init(data: Variant = {}) -> void:
	if not problems(data).is_empty():
		return
	precision = float(data["precision"])
	anticipation = bool(data["anticipation"])


## Délai minimal avant de jouer, en secondes : une IA plus réfléchie prend
## visiblement son temps (0,6 s au hasard, 0,8 s à mi-précision, 1,2 s au maximum).
func think_delay() -> float:
	return 0.6 + 0.4 * precision + (0.2 if anticipation else 0.0)


## Problèmes d'un profil d'IA ; liste vide si le profil est valide.
static func problems(data: Variant) -> Array[String]:
	var result: Array[String] = []
	if not data is Dictionary:
		result.append("profil d'IA absent (champ \"ai\")")
		return result
	for key in data:
		if not KEYS.has(str(key)):
			result.append("réglage d'IA inconnu '%s'" % key)
	var value = data.get("precision")
	if not (value is float or value is int) or value < 0.0 or value > 1.0:
		result.append("précision d'IA attendue entre 0 et 1")
	if not data.get("anticipation") is bool:
		result.append("anticipation d'IA attendue à true ou false")
	return result
