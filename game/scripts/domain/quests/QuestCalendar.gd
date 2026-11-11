## QuestCalendar.gd
## Horloge des quêtes quotidiennes. Elle suit l'horloge de l'appareil pour que
## « minuit » corresponde à ce que le joueur lit sur son téléphone, sans base de
## fuseaux ni règle de changement d'heure. Le biais est toujours injecté : les
## tests n'attendent jamais une vraie heure et aucune scène ne tire l'heure.
class_name QuestCalendar
extends RefCounted

const SECONDS_PER_DAY := 86400


## Indice du jour local. Deux instants du même jour local renvoient le même
## nombre, y compris juste avant et juste après minuit.
static func day_index(unix_seconds: int, bias_minutes: int) -> int:
	return floori(float(unix_seconds + bias_minutes * 60) / float(SECONDS_PER_DAY))


static func seconds_until_next_day(unix_seconds: int, bias_minutes: int) -> int:
	var shifted := unix_seconds + bias_minutes * 60
	return SECONDS_PER_DAY - posmod(shifted, SECONDS_PER_DAY)


static func system_bias_minutes() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0))


static func today() -> int:
	return day_index(int(Time.get_unix_time_from_system()), system_bias_minutes())


static func seconds_to_reset() -> int:
	return seconds_until_next_day(int(Time.get_unix_time_from_system()),
		system_bias_minutes())
