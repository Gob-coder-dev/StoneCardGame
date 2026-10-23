## Règles et légendes visuelles partageant les pictogrammes des cartes.
extends Control

const Badge := preload("res://scripts/ui/PowerBadge.gd")
const Swarm := preload("res://scripts/engine/effects/SwarmSystem.gd")

const GOD_RULES := {
	"inari": [
		{"kind": "fortune", "count": 2, "title": "Lames aléatoires ×2",
			"text": "Le nombre indique combien de lames roses seront ajoutées. À la pose, elles tournent puis rejoignent leurs faces tirées au sort. Chaque lame coûte {random_cost} point. Une face pleine ne peut plus en recevoir."},
		{"kind": "coin_horizontal", "title": "Pile ou face horizontal ↔",
			"text": "Une pièce est lancée au-dessus de la carte : ✓ échange gauche et droite, ✕ conserve les valeurs. Chaque issue a une chance sur deux. Exemple : gauche 0 / droite 2 devient gauche 2 / droite 0 si ✓ apparaît."},
		{"kind": "coin_vertical", "title": "Pile ou face vertical ↕",
			"text": "Même lancer, mais ✓ échange le haut et le bas. L'échange est révélé avant les captures. Une carte Fortune possède un seul de ces trois pouvoirs."}
	],
	"izanami": [
		{"kind": "weaken_miss", "title": "Échec corrosif −1",
			"text": "Quand cette carte attaque une pierre adverse sans réussir à la capturer, de près ou avec une lame bleue, un poison atteint cette pierre et lui retire 1 force sur chaque face. Les pierres capturées, non attaquées ou hors de portée ne sont pas touchées. Le malus reste actif pendant le tour adverse puis pendant votre coup suivant, et expire après ce coup. Les lames neutralisées apparaissent fissurées ; les boucliers restent fonctionnels."},
		{"kind": "weaken_adjacent", "title": "Miasme autour de la pierre",
			"text": "Le point central et ses quatre voisins représentent les cases adjacentes. Après toutes les tentatives de capture, une aura violette atteint chaque pierre voisine, alliée ou adverse, et lui retire définitivement 1 force sur chaque face, y compris après une capture. Chaque niveau de faiblesse brise visuellement une lame par face, sans affecter les boucliers. Une carte Déclin ne possède qu'un seul pouvoir."}
	],
	"hachiman": [
		{"kind": "shield", "title": "Rempart : le demi-cercle",
			"text": "Un demi-cercle est un bouclier : il occupe un emplacement comme une lame, mais défend uniquement. Exemple : 2 lames + 1 bouclier = 2 d'attaque et 3 de défense. Il coûte {shield_cost} point. Lames et boucliers ne dépassent jamais {max_markers} symboles au total sur une face."}
	],
	"tsukuyomi": [
		{"kind": "long", "title": "Horizon : la grande lame bleue",
			"text": "Une lame bleue attaque au contact et sur toute sa ligne. Exemple : 2 lames normales + 2 lames longues = 4 d'attaque voisine et 2 à distance. Après chaque capture, les bleues transpercent la pierre et continuent avec leur force distante inchangée. Elles traversent les alliés et les cases vides ; un ennemi qui résiste ou une case bloquée les arrête. Aucun tir ne part sans ennemi atteignable sur la ligne. À distance, seules les lames bleues s'activent. Une lame longue coûte {long_cost} point."}
	],
	"okuninushi": [
		{"kind": "swarm", "title": "Essaim : les trois points reliés",
			"text": "Les pierres Essaim alliées reliées par leurs côtés forment un groupe. Plusieurs lianes vertes croisées restent visibles entre toute la largeur de leurs bords, puis une impulsion y fait pousser leurs lames d'aura. Chaque membre reçoit une lame par autre membre, jusqu'à +{swarm_cap}, dans ses emplacements libres. Exemple : un groupe de 3 renforce chacune de ses pierres de 2 lames. Capturer un maillon coupe les lianes concernées et rétracte les bonus perdus."}
	],
	"susanoo": [
		{"kind": "theft", "title": "Pillage : le cercle avec un +",
			"text": "Après une capture, les symboles vaincus sont aspirés puis un répartiteur orange révèle les boucliers gagnés. Exemple : vaincre une face avec 2 lames et 1 bouclier donne jusqu'à 3 boucliers, distribués au hasard dans les emplacements libres des trois autres faces : la face qui a capturé n'en reçoit pas, et un symbole sans place est perdu. La pierre capturée conserve ses symboles. Chaque face reste limitée à {max_markers} symboles au total."}
	]
}

@onready var rules_text: RichTextLabel = $Content/Scroll/RulesPanel/Page/RulesText
@onready var god_rules: VBoxContainer = $Content/Scroll/RulesPanel/Page/GodRules
@onready var end_text: RichTextLabel = $Content/Scroll/RulesPanel/Page/EndText


func _ready() -> void:
	var values := _rule_values()
	rules_text.text = _rules_bbcode().format(values)
	for god in StoneLoader.get_all_gods():
		_add_god_rules(god, values)
	end_text.text = """[color=#ffe060][font_size=44]Fin de partie[/font_size][/color]

Quand toutes les cases jouables sont remplies, on compte les pierres de chaque camp. Celui qui en contrôle le plus gagne.

[color=#ffe060][font_size=44]Conseil[/font_size][/color]

Regarde les côtés faibles déjà exposés et garde une pierre capable de les attaquer au bon moment."""


## Valeurs lues dans les règles du code, pour que les textes ne s'en écartent pas.
static func _rule_values() -> Dictionary:
	return {
		"deck_size": DeckRules.DECK_SIZE,
		"deck_budget": DeckRules.DECK_BUDGET,
		"normal_cost": UIFormat.cost(StoneCostRules.NORMAL_BLADE_COST),
		"random_cost": UIFormat.cost(StoneCostRules.RANDOM_BLADE_COST),
		"shield_cost": UIFormat.cost(StoneCostRules.SHIELD_COST),
		"long_cost": UIFormat.cost(StoneCostRules.LONG_BLADE_COST),
		"swarm_cap": Swarm.SWARM_CAP,
		"max_markers": BattleStone.MAX_MARKERS_PER_SIDE,
	}


func _add_god_rules(god: Dictionary, values: Dictionary) -> void:
	var color := Color(str(god["color"]))
	var heading := _make_text("[font_size=40][color=#%s]%s • %s[/color][/font_size]" % [color.to_html(false), god["name"], god["family_name"]])
	god_rules.add_child(heading)
	for rule in GOD_RULES.get(str(god["id"]), []):
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_theme_constant_override("separation", 18)
		var badge := Badge.new()
		badge.kind = str(rule["kind"])
		badge.color = color
		badge.count = int(rule.get("count", 0))
		badge.custom_minimum_size = Vector2(132 if badge.count > 0 else 76, 76)
		badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(badge)
		row.add_child(_make_text("[b]%s[/b]\n%s" % [rule["title"], str(rule["text"]).format(values)]))
		god_rules.add_child(row)


func _make_text(value: String) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size", 34)
	label.add_theme_font_size_override("bold_font_size", 34)
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.text = value
	return label


func _rules_bbcode() -> String:
	return """[color=#ffe060][font_size=44]But du jeu[/font_size][/color]

Contrôler le plus de pierres possible sur le plateau quand toutes les cases sont remplies.

[color=#ffe060][font_size=44]Le plateau[/font_size][/color]

Une grille de 3×3. Certaines parties comportent une case bloquée (marquée ✕) où personne ne peut jouer.

[color=#ffe060][font_size=44]Les pierres[/font_size][/color]

Chaque pierre possède des symboles sur ses 4 côtés (haut, bas, gauche, droite). Une face contient au maximum [color=#ffe060]{max_markers} symboles au total[/color] : lames normales, lames spéciales et boucliers partagent les mêmes emplacements.

Tu choisis {deck_size} pierres pour ton deck, dans la limite de [color=#ffe060]{deck_budget} points[/color]. Une lame normale coûte {normal_cost} point. Les lames aléatoires, boucliers, lames longues et pouvoirs sont comptés selon leur coût propre.

[color=#ffe060][font_size=44]Déroulement d'un tour[/font_size][/color]

Un tirage au sort décide qui commence. À tour de rôle, chaque joueur pose une pierre de sa main sur une case libre. Les animations révèlent ses pouvoirs avant de donner la main au joueur suivant.

[color=#ffe060][font_size=44]Capturer une pierre[/font_size][/color]

Quand tu poses une pierre à côté d'une pierre adverse, on compare les côtés qui se touchent.

Si [color=#60d060]ton attaque est strictement supérieure à sa défense[/color] sur le côté face-à-face, tu captures cette pierre : elle passe dans ton camp.

En cas d'[color=#f0d88a]égalité[/color], personne ne capture. Une pierre peut capturer plusieurs cibles d'un coup. Il n'y a pas de capture en chaîne.

[color=#ffe060][font_size=44]Dieux et logos des pouvoirs[/font_size][/color]

Tu équipes un dieu dans le menu Cartes. Ton deck peut contenir les cartes neutres et les cartes propres à sa famille. Changer de dieu retire du deck les cartes incompatibles.

Le contour de chaque pierre reprend la couleur de sa famille. Les logos en haut à droite annoncent ses pouvoirs. Voici les mêmes pictogrammes et leur fonctionnement :"""
