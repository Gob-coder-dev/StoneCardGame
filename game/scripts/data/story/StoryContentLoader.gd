## StoryContentLoader.gd
## Charge les dialogues et les chapitres guidés, puis vérifie leurs références
## internes. Le chargement ne dépend ni de la campagne ni d'une scène : il
## retourne les problèmes au service, qui peut désactiver le scénario sans
## bloquer le jeu.
class_name StoryContentLoader
extends RefCounted

const DIALOGUES_PATH := "res://data/story/dialogues.json"
const TUTORIALS_PATH := "res://data/story/tutorials.json"
const SPEAKER_POLICIES: Array[String] = ["opponent_god", "theme_god", "player_god"]


static func read(dialogues_path: String = DIALOGUES_PATH,
		tutorials_path: String = TUTORIALS_PATH) -> Dictionary:
	var problems: Array[String] = []
	var dialogues := _parse(dialogues_path, "dialogues", problems)
	var tutorials := _parse(tutorials_path, "tutoriels", problems)
	if dialogues.is_empty() or tutorials.is_empty():
		return {
			"ok": false,
			"dialogues": dialogues,
			"tutorials": tutorials,
			"problems": problems,
		}
	_validate_dialogues(dialogues, problems)
	_validate_tutorials(tutorials, dialogues, problems)
	return {
		"ok": problems.is_empty(),
		"dialogues": dialogues,
		"tutorials": tutorials,
		"problems": problems,
	}


static func _parse(path: String, label: String, problems: Array[String]) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		problems.append("Scénario : %s illisible (%s)." % [label, path])
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		problems.append("Scénario : %s JSON invalide (%s, ligne %d)." % [
			label, path, json.get_error_line()])
		return {}
	if not json.data is Dictionary:
		problems.append("Scénario : %s doit être un objet JSON (%s)." % [label, path])
		return {}
	return json.data as Dictionary


static func _validate_dialogues(data: Dictionary, problems: Array[String]) -> void:
	var characters: Variant = data.get("characters", {})
	if not characters is Dictionary or (characters as Dictionary).is_empty():
		problems.append("Scénario : la table 'characters' est absente ou vide.")
		characters = {}
	else:
		for key in (characters as Dictionary).keys():
			var character_id := str(key)
			var character: Variant = (characters as Dictionary)[key]
			if not character is Dictionary:
				problems.append("Scénario : le personnage '%s' n'est pas un objet." % character_id)
				continue
			var entry: Dictionary = character
			var policy := str(entry.get("policy", ""))
			if policy != "":
				if not SPEAKER_POLICIES.has(policy):
					problems.append("Scénario : politique de locuteur inconnue '%s' pour '%s'." % [
						policy, character_id])
				continue
			if str(entry.get("name", "")).strip_edges() == "":
				problems.append("Scénario : le personnage '%s' n'a pas de nom." % character_id)
			var asset := str(entry.get("asset", ""))
			if asset == "" or not ResourceLoader.exists(asset, "Texture2D"):
				problems.append("Scénario : portrait introuvable pour '%s' (%s)." % [
					character_id, asset])
	var sequences: Variant = data.get("sequences", {})
	if not sequences is Dictionary or (sequences as Dictionary).is_empty():
		problems.append("Scénario : la table 'sequences' est absente ou vide.")
		sequences = {}
	else:
		for key in (sequences as Dictionary).keys():
			var sequence_id := str(key)
			var sequence: Variant = (sequences as Dictionary)[key]
			if not sequence is Dictionary:
				problems.append("Scénario : la séquence '%s' n'est pas un objet." % sequence_id)
				continue
			var entry: Dictionary = sequence
			entry["id"] = sequence_id
			var lines: Variant = entry.get("lines", [])
			if not lines is Array or (lines as Array).is_empty():
				problems.append("Scénario : la séquence '%s' n'a aucune ligne." % sequence_id)
				continue
			for line_index in range((lines as Array).size()):
				var line: Variant = (lines as Array)[line_index]
				if not line is Dictionary:
					problems.append("Scénario : ligne %d de '%s' invalide." % [
						line_index + 1, sequence_id])
					continue
				var entry_line: Dictionary = line
				var speaker := str(entry_line.get("speaker", ""))
				if str(entry_line.get("text", "")).strip_edges() == "":
					problems.append("Scénario : ligne %d de '%s' sans texte." % [
						line_index + 1, sequence_id])
				if speaker == "":
					problems.append("Scénario : ligne %d de '%s' sans locuteur." % [
						line_index + 1, sequence_id])
				elif not (characters as Dictionary).has(speaker) \
						and not SPEAKER_POLICIES.has(speaker):
					problems.append("Scénario : locuteur inconnu '%s' dans '%s'." % [
						speaker, sequence_id])
	var triggers: Variant = data.get("triggers", [])
	if not triggers is Array:
		problems.append("Scénario : 'triggers' doit être un tableau.")
		return
	var trigger_ids := {}
	for trigger_index in range((triggers as Array).size()):
		var trigger: Variant = (triggers as Array)[trigger_index]
		if not trigger is Dictionary:
			problems.append("Scénario : déclencheur %d invalide." % (trigger_index + 1))
			continue
		var entry: Dictionary = trigger
		var trigger_id := str(entry.get("id", ""))
		if trigger_id == "":
			problems.append("Scénario : déclencheur %d sans identifiant." % (trigger_index + 1))
		elif trigger_ids.has(trigger_id):
			problems.append("Scénario : déclencheur dupliqué '%s'." % trigger_id)
		else:
			trigger_ids[trigger_id] = true
		var sequence_id := str(entry.get("sequence", ""))
		if not (sequences as Dictionary).has(sequence_id):
			problems.append("Scénario : déclencheur '%s' vers une séquence inconnue '%s'." % [
				trigger_id, sequence_id])
		if not StoryTriggerRules.EVENTS.has(str(entry.get("event", ""))):
			problems.append("Scénario : événement inconnu '%s' pour '%s'." % [
				str(entry.get("event", "")), trigger_id])


static func _validate_tutorials(data: Dictionary, dialogues: Dictionary,
		problems: Array[String]) -> void:
	var sequences: Dictionary = dialogues.get("sequences", {})
	var chapters: Variant = data.get("chapters", {})
	if not chapters is Dictionary or (chapters as Dictionary).is_empty():
		problems.append("Tutoriels : la table 'chapters' est absente ou vide.")
		return
	for key in (chapters as Dictionary).keys():
		var chapter_id := str(key)
		var chapter: Variant = (chapters as Dictionary)[key]
		if not chapter is Dictionary:
			problems.append("Tutoriels : le chapitre '%s' n'est pas un objet." % chapter_id)
			continue
		var entry: Dictionary = chapter
		entry["id"] = chapter_id
		var match_setup: Variant = entry.get("match", {})
		if match_setup != null and not match_setup is Dictionary:
			problems.append("Tutoriels : le setup de match de '%s' n'est pas un objet." % chapter_id)
		elif match_setup is Dictionary and not (match_setup as Dictionary).is_empty():
			_validate_match(chapter_id, match_setup, problems)
		var entry_node := str(entry.get("entry_node_id", ""))
		var entry_scene := str(entry.get("entry_scene", ""))
		if entry_node == "" and entry_scene == "":
			problems.append("Tutoriels : le chapitre '%s' n'a pas de point d'entrée." % chapter_id)
		if entry_scene != "" and not ResourceLoader.exists(entry_scene, "PackedScene"):
			problems.append("Tutoriels : scène d'entrée introuvable pour '%s' (%s)." % [
				chapter_id, entry_scene])
		var outro := str(entry.get("outro", ""))
		if outro != "" and not sequences.has(outro):
			problems.append("Tutoriels : séquence de sortie inconnue '%s' pour '%s'." % [
				outro, chapter_id])
		var steps: Variant = entry.get("steps", [])
		if not steps is Array or (steps as Array).is_empty():
			problems.append("Tutoriels : le chapitre '%s' n'a aucune étape." % chapter_id)
			continue
		var step_ids := {}
		for step_index in range((steps as Array).size()):
			var step: Variant = (steps as Array)[step_index]
			if not step is Dictionary:
				problems.append("Tutoriels : étape %d de '%s' invalide." % [
					step_index + 1, chapter_id])
				continue
			var entry_step: Dictionary = step
			var step_id := str(entry_step.get("id", ""))
			if step_id == "":
				problems.append("Tutoriels : étape %d de '%s' sans identifiant." % [
					step_index + 1, chapter_id])
			elif step_ids.has(step_id):
				problems.append("Tutoriels : étape dupliquée '%s' dans '%s'." % [
					step_id, chapter_id])
			else:
				step_ids[step_id] = true
			var anchor_id := str(entry_step.get("anchor", ""))
			var scene_path := str(entry_step.get("scene", ""))
			var dialogue := str(entry_step.get("dialogue", ""))
			var wait_for := str(entry_step.get("wait_for", ""))
			if anchor_id == "" and dialogue == "" and wait_for == "":
				problems.append("Tutoriels : étape '%s' de '%s' sans action." % [
					step_id, chapter_id])
			if scene_path != "" and not ResourceLoader.exists(scene_path, "PackedScene"):
				problems.append("Tutoriels : scène introuvable '%s' pour l'étape '%s'." % [
					scene_path, step_id])
			if wait_for != "" and not StoryTriggerRules.WAIT_EVENTS.has(wait_for):
				problems.append("Tutoriels : événement d'attente inconnu '%s' dans '%s'." % [
					wait_for, chapter_id])
			if dialogue != "" and not sequences.has(dialogue):
				problems.append("Tutoriels : dialogue inconnu '%s' dans '%s'." % [
					dialogue, chapter_id])


static func _validate_match(chapter_id: String, setup: Dictionary,
		problems: Array[String]) -> void:
	if setup.has("board_size"):
		var board_size := int(setup.get("board_size", 0))
		if board_size < GameState.MIN_BOARD_SIZE or board_size > GameState.MAX_BOARD_SIZE:
			problems.append("Tutoriels : taille de plateau invalide dans '%s'." % chapter_id)
	for hand_key in ["player_hand_size", "opponent_hand_size"]:
		if setup.has(hand_key):
			var hand_size := int(setup.get(hand_key, 0))
			if hand_size < 1 or hand_size > DeckRules.DECK_SIZE:
				problems.append("Tutoriels : '%s' invalide dans '%s'." % [
					hand_key, chapter_id])
	for deck_key in ["player_deck", "opponent_deck"]:
		## Un chapitre peut ne préciser que la géométrie du plateau ; les decks
		## restent alors ceux de la campagne.
		if not setup.has(deck_key):
			continue
		var deck: Variant = setup.get(deck_key, [])
		if not deck is Array or (deck as Array).is_empty():
			problems.append("Tutoriels : '%s' du chapitre '%s' est vide ou invalide." % [
				deck_key, chapter_id])
			continue
		for value in (deck as Array):
			if not value is String or str(value).strip_edges() == "":
				problems.append("Tutoriels : carte invalide dans '%s' du chapitre '%s'." % [
					deck_key, chapter_id])
	if setup.has("first_player"):
		var first := int(setup.get("first_player", 0))
		if first != 0 and first != 1 and first != 2:
			problems.append("Tutoriels : premier joueur invalide dans '%s'." % chapter_id)
	for stone in setup.get("initial_stones", []):
		if not stone is Dictionary or str(stone.get("stone_id", "")) == "":
			problems.append("Tutoriels : pierre initiale invalide dans '%s'." % chapter_id)
			continue
		if int(stone.get("row", -1)) < 0 or int(stone.get("col", -1)) < 0:
			problems.append("Tutoriels : position initiale invalide dans '%s'." % chapter_id)
		var owner := int(stone.get("owner", 2))
		if owner != 1 and owner != 2:
			problems.append("Tutoriels : propriétaire initial invalide dans '%s'." % chapter_id)
	for pos in setup.get("blocked_cells", []):
		if not pos is Array or (pos as Array).size() < 2:
			problems.append("Tutoriels : case bloquée invalide dans '%s'." % chapter_id)
			continue
		if int((pos as Array)[0]) < 0 or int((pos as Array)[1]) < 0:
			problems.append("Tutoriels : case bloquée invalide dans '%s'." % chapter_id)
	for move in setup.get("opponent_plan", []):
		if not move is Dictionary or str(move.get("stone_id", "")) == "":
			problems.append("Tutoriels : coup du bot invalide dans '%s'." % chapter_id)
			continue
		if int(move.get("row", -1)) < 0 or int(move.get("col", -1)) < 0:
			problems.append("Tutoriels : position du bot invalide dans '%s'." % chapter_id)
