## Durées visuelles. Le moteur attend des fins effectives, jamais ces durées.
## Aucune résolution de combat ne dépend de ces durées.
extends RefCounted

const PLACEMENT: float = 0.18
const WINDUP: float = 0.08
const FLIGHT_PER_CELL: float = 0.17
const RECOVERY: float = 0.28


static func hit_time(distance: int) -> float:
	return WINDUP + float(distance) * FLIGHT_PER_CELL


static func flight_end(attacks: Array) -> float:
	var distance := 1
	for attack in attacks:
		distance = maxi(distance, int(attack["endpoint"]["distance"]))
	return hit_time(distance)


static func attack_duration(attacks: Array) -> float:
	return 0.0 if attacks.is_empty() else flight_end(attacks) + RECOVERY

const PREPARATION := 1.1
const PILLAGE := 1.7
## Miasme et Échec corrosif partagent la même traînée de poison.
const WEAKEN := 1.15
const WEAKNESS_REPAIR := 0.48
const SWARM := 0.90

static func effects_duration(events: Array) -> float:
	var duration := 0.0
	for event in events:
		match event.get("type", ""):
			CombatEvents.SHIELD_THEFT: duration = maxf(duration, PILLAGE)
			CombatEvents.WEAKEN: duration = maxf(duration, WEAKEN)
			CombatEvents.TEMPORARY_WEAKEN: duration = maxf(duration, WEAKEN)
			CombatEvents.WEAKNESS_EXPIRED: duration = maxf(duration, WEAKNESS_REPAIR)
	return duration


## Durée prévue de la présentation d'une étape du moteur.
static func step_duration(step: CombatPresentation) -> float:
	match step.kind:
		CombatPresentation.Kind.PLACEMENT: return PLACEMENT
		CombatPresentation.Kind.PREPARATION: return PREPARATION
		CombatPresentation.Kind.SWARM: return SWARM
		CombatPresentation.Kind.ATTACK: return attack_duration(step.events)
		CombatPresentation.Kind.EFFECTS: return effects_duration(step.events)
	return 0.0


## Délai accordé en plus de la durée prévue avant d'interrompre une animation
## qui ne signale jamais sa fin. La partie continue alors avec l'état final.
const WATCHDOG_MARGIN := 2.0
