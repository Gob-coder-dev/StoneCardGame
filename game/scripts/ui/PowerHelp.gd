## Légende commune aux règles et à l’aide des dieux. Les valeurs viennent du moteur.
extends RefCounted

const Effects := preload("res://scripts/domain/MonsterEffects.gd")
const Badge := preload("res://scripts/ui/PowerBadge.gd")

const BY_GOD := {
	"veskar": ["fortune", "coin_horizontal", "coin_vertical"],
	"nerava": ["weaken_miss", "weaken_adjacent"],
	"kharun": ["shield"],
	"ilyr": ["long"],
	"sylkha": ["swarm"],
	"enigma": ["theft"],
}

const ENTRIES := {
	"fortune": ["Lames aléatoires",
		"À la pose, les lames roses vont au hasard sur les faces qui ont de la place. La carte indique leur nombre. Chaque lame coûte {random_cost} point."],
	"coin_horizontal": ["Pile ou face horizontal",
		"À la pose, une chance sur deux d’échanger la gauche et la droite avant l’attaque."],
	"coin_vertical": ["Pile ou face vertical",
		"À la pose, une chance sur deux d’échanger le haut et le bas avant l’attaque."],
	"weaken_miss": ["Échec corrosif",
		"Chaque ennemi qui résiste à l’attaque perd {corrosion} de force par face jusqu’à la fin de ton prochain coup. Ses boucliers restent actifs."],
	"weaken_adjacent": ["Miasme",
		"Dans le camp de Nérava, ce monstre retire 1 de force par face aux ennemis qui le touchent. Les auras se cumulent. Une carte posée à côté attaque d’abord si elle le peut, puis subit le malus."],
	"shield": ["Bouclier",
		"Chaque bouclier ajoute 1 en défense sur sa face et coûte {shield_cost} point. Avec 2 lames et 1 bouclier, la face attaque à 2 et défend à 3."],
	"long": ["Horizon · Lames longues",
		"Au contact, toutes les lames comptent. À distance, seules les bleues frappent. Elles traversent le vide, les alliés et les cibles capturées. Un ennemi qui résiste ou une case bloquée arrête le tir. Chaque lame bleue coûte {long_cost} point."],
	"swarm": ["Essaim",
		"Dans le camp de Sylkha, les monstres Essaim qui se touchent par les côtés forment un groupe. Chacun gagne {swarm_per_ally} lames par autre membre, jusqu’à +{swarm_cap}, dans ses places libres. Une capture peut couper le groupe et retirer le bonus."],
	"theft": ["Pillage",
		"Après une capture, les lames actives et boucliers de la face vaincue donnent des boucliers au pilleur. Ils se répartissent au hasard sur ses trois autres faces, selon la place disponible. La cible garde ses symboles."],
}


static func title(kind: String) -> String:
	return str(ENTRIES[kind][0])


static func description(kind: String) -> String:
	return str(ENTRIES[kind][1]).format({
		"random_cost": UIFormat.cost(MonsterCostRules.RANDOM_BLADE_COST),
		"shield_cost": UIFormat.cost(MonsterCostRules.SHIELD_COST),
		"long_cost": UIFormat.cost(MonsterCostRules.LONG_BLADE_COST),
		"corrosion": Effects.CORROSION_AMOUNT,
		"swarm_per_ally": Effects.BLADES_PER_ALLY,
		"swarm_cap": Effects.SWARM_CAP,
	})


static func make_badge(kind: String, tint: Color, count: int, height: float) -> Control:
	var badge := Badge.new()
	badge.kind = kind
	badge.color = tint
	badge.count = count
	badge.custom_minimum_size = Vector2(height * (1.6 if count > 0 else 1.0), height)
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return badge
