## Génère une bibliothèque de decks fixes pour la campagne, avec le générateur
## réel du jeu. Le script est hors runtime : les decks retenus sont ensuite
## recopiés explicitement dans la définition de campagne par le constructeur.
extends Node

const GeneratorModel := preload("res://scripts/domain/LoadoutGenerator.gd")
const OUTPUT := "res://tools/campaign_deck_library.json"
const GODS: Array[String] = ["veskar", "nerava", "kharun", "ilyr", "sylkha", "enigma"]
const TIERS: Array[int] = [1, 2, 3, 4]
const VARIANTS_PER_BUCKET: int = 24


func _ready() -> void:
	var library := {}
	var generator := GeneratorModel.new()
	for god_index in range(GODS.size()):
		var god_id := GODS[god_index]
		for tier in TIERS:
			var key := "%s_n%d" % [god_id, tier]
			var decks: Array = []
			var seen := {}
			for index in range(VARIANTS_PER_BUCKET):
				var seed := 13000 + god_index * 1000 + tier * 100 + index
				var result := generator.generate_for_god(seed, god_id, tier)
				if not bool(result.get("ok", false)):
					continue
				var deck: Array = result["deck"]
				var validation := DeckRules.validate_deck(deck, true, god_id)
				if not bool(validation.get("valid", false)):
					continue
				var identity := _identity(deck)
				if seen.has(identity):
					continue
				seen[identity] = true
				decks.append({
					"seed": seed,
					"deck": deck,
					"total_points": result.get("total_points", 0.0),
				})
			library[key] = decks
			print("%s : %d decks uniques / %d tentatives" % [key, decks.size(),
				VARIANTS_PER_BUCKET])
	var neutral := {}
	for tier in [1, 2]:
		var key := "neutral_n%d" % tier
		var decks: Array = []
		var seen := {}
		for index in range(VARIANTS_PER_BUCKET):
			var seed: int = 15000 + int(tier) * 100 + index
			var result := generator.generate_for_god(seed, "", tier)
			if not bool(result.get("ok", false)):
				continue
			var deck: Array = result["deck"]
			var validation := DeckRules.validate_deck(deck, true, "")
			if not bool(validation.get("valid", false)):
				continue
			var identity := _identity(deck)
			if seen.has(identity):
				continue
			seen[identity] = true
			decks.append({"seed": seed, "deck": deck,
				"total_points": result.get("total_points", 0.0)})
		neutral[key] = decks
		print("%s : %d decks uniques" % [key, decks.size()])
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file == null:
		printerr("Impossible d'écrire ", OUTPUT)
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify({"version": 1, "gods": library, "neutral": neutral},
		"  ", false))
	file.close()
	print("Bibliothèque écrite dans ", OUTPUT)
	get_tree().quit(0)


static func _identity(deck: Array) -> String:
	var sorted_deck: Array = deck.duplicate()
	sorted_deck.sort()
	return "|".join(sorted_deck)
