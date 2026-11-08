## Outil hors runtime : produit les decks fixes avec le générateur réel du jeu.
## Il garantit le budget et le palier mieux qu'un calcul Python séparé.
extends Node

const GeneratorModel := preload("res://scripts/domain/LoadoutGenerator.gd")
const OUTPUT := "res://tools/campaign_decks.json"

const REQUESTS := [
	["neutral_n1", "", 1, 4101],
	["neutral_n2", "", 2, 4102],
	["veskar_n2", "veskar", 2, 4103],
	["kharun_n2", "kharun", 2, 4104],
	["ilyr_n3", "ilyr", 3, 4105],
	["sylkha_n3", "sylkha", 3, 4106],
	["enigma_n3", "enigma", 3, 4107],
	["enigma_n4", "enigma", 4, 4108],
	["sylkha_n4", "sylkha", 4, 4109],
]


func _ready() -> void:
	var output := {}
	var generator := GeneratorModel.new()
	for request in REQUESTS:
		var label := str(request[0])
		var god_id := str(request[1])
		var tier := int(request[2])
		var seed := int(request[3])
		var result := generator.generate_for_god(seed, god_id, tier)
		if not bool(result.get("ok", false)):
			printerr("Deck impossible pour ", label, " : ", result.get("reason", ""))
			get_tree().quit(1)
			return
		var deck: Array = result["deck"]
		var validation := DeckRules.validate_deck(deck, true, god_id)
		if not bool(validation.get("valid", false)):
			printerr("Deck invalide pour ", label, " : ", validation.get("reason", ""))
			get_tree().quit(1)
			return
		output[label] = deck
		print("%s : %s points / %d cartes" % [label,
			result.get("total_points", 0.0), deck.size()])
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file == null:
		printerr("Impossible d'écrire ", OUTPUT)
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(output, "  "))
	file.close()
	print("Decks écrits dans ", OUTPUT)
	get_tree().quit(0)
