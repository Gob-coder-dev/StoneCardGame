## L'IA des adversaires, réglée par un AIProfile généré par OpponentCatalog ou
## lu dans le champ "ai" des adversaires historiques de npcs.json.
## Avec la probabilité « precision », elle joue le meilleur coup évalué (au
## hasard entre les ex aequo). Sinon elle commet une erreur crédible : un coup
## tiré au sort, pondéré par sa valeur. Plus la précision baisse, plus ce
## tirage s'aplatit ; à 0, l'IA joue au hasard sans rien évaluer.
extends AIPlayer

const Profile := preload("res://scripts/ai/AIProfile.gd")
const Evaluator := preload("res://scripts/ai/MoveEvaluator.gd")

## Température des erreurs à précision 0,5, en captures : un coup qui rapporte
## une capture de plus y est choisi e ≈ 2,7 fois plus souvent.
const ERROR_TEMPERATURE := 1.0
## Deux valeurs plus proches que cet écart sont ex aequo (moyennes de tirages).
const TIE_EPSILON := 0.000001

var profile: Profile
## Hasard des décisions de l'IA, distinct de celui de la partie. Les tests le fixent.
var rng := RandomNumberGenerator.new()


func _init(ai_profile: Profile) -> void:
	profile = ai_profile
	think_delay = profile.think_delay()
	rng.randomize()


## Le genre de choix (meilleur coup ou erreur) est tiré avant la réflexion ;
## sans précision, aucun coup n'est évalué.
func start_search(state: GameState) -> MoveSearch:
	var moves := RulesEngine.get_valid_moves(state, GameState.PLAYER_AI)
	var plays_best := rng.randf() < profile.precision
	var evaluator: Evaluator = null
	if profile.precision > 0.0:
		evaluator = Evaluator.new(state, profile.anticipation)
	return MoveSearch.new(moves, evaluator, _choose.bind(plays_best))


func _choose(scored: Array, plays_best: bool) -> Dictionary:
	var best_value := -INF
	for entry in scored:
		best_value = maxf(best_value, entry["value"])
	var temperature := error_temperature()
	var weights: Array[float] = []
	for entry in scored:
		var gap: float = best_value - float(entry["value"])
		if plays_best:
			weights.append(1.0 if gap <= TIE_EPSILON else 0.0)
		elif is_inf(temperature):
			weights.append(1.0)
		else:
			weights.append(exp(-gap / temperature))
	return scored[_weighted_index(weights)]["move"].duplicate()


## Température des erreurs : infinie à précision 0 (hasard pur), puis de plus
## en plus basse quand la précision monte.
func error_temperature() -> float:
	if profile.precision <= 0.0:
		return INF
	return ERROR_TEMPERATURE * (1.0 - profile.precision) / profile.precision


## Indice tiré au sort proportionnellement aux poids (au moins un poids positif).
func _weighted_index(weights: Array[float]) -> int:
	var total := 0.0
	for weight in weights:
		total += weight
	var target := rng.randf() * total
	var chosen := -1
	for index in range(weights.size()):
		if weights[index] <= 0.0:
			continue
		chosen = index
		target -= weights[index]
		if target < 0.0:
			break
	return chosen
