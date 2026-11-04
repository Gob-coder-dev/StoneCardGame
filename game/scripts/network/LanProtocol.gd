## LanProtocol.gd
## Contrat du mode PVP local : version, types de messages et validation stricte.
##
## Règles :
##   - un message ne contient que des types Godot simples (Dictionary, Array,
##     String, int, float, bool) — jamais d'objet ni de ressource ;
##   - chaque champ est contrôlé en type, en taille et en bornes ;
##   - les clés inconnues sont refusées : tout ajout de champ change la version.
## Ce fichier ne connaît ni socket, ni scène, ni règle de combat.
class_name LanProtocol
extends RefCounted

## Version du protocole. Toute modification du format la fait changer.
const VERSION: int = 2

## Ports du mode local. Les deux appareils sont sur le même réseau Wi-Fi.
const DISCOVERY_PORT: int = 45454
const GAME_PORT: int = 45555
## Deux participants au total : l'hôte et un seul client.
const MAX_PARTICIPANTS: int = 2
const SERVER_ID: int = 1

## Bornes de toutes les données reçues d'un pair.
const MAX_NAME_LENGTH: int = 16
const MIN_NAME_LENGTH: int = 2
const MAX_APP_VERSION_LENGTH: int = 24
const MAX_GOD_ID_LENGTH: int = 32
const MAX_STONE_ID_LENGTH: int = 64
const MAX_ID_LENGTH: int = 64
const MAX_REASON_LENGTH: int = 120
const MAX_STATUS_LENGTH: int = 24
const MAX_DECK_SIZE: int = DeckRules.DECK_SIZE
const MAX_BLOCKED_CELLS: int = 2
## Score maximal d'un camp : une case par cellule du plateau 4 × 4.
const MAX_SCORE: int = 16
## Taille maximale d'une annonce UDP ou d'un message encodé en JSON.
const MAX_MESSAGE_CHARS: int = 4096
const FINGERPRINT_LENGTH: int = 64
const BEACON_MARKER: String = "samstone"

## Sentinelle de lecture entière : aucune valeur légitime ne l'utilise.
const INVALID_INT: int = -2147483648

const KIND_HELLO: String = "hello"
const KIND_HELLO_ACK: String = "hello_ack"
const KIND_HELLO_REJECT: String = "hello_reject"
const KIND_LOBBY_STATE: String = "lobby_state"
const KIND_READY: String = "ready"
const KIND_MATCH_START: String = "match_start"
const KIND_MOVE_INTENT: String = "move_intent"
const KIND_MOVE_ACCEPTED: String = "move_accepted"
const KIND_MOVE_REJECTED: String = "move_rejected"
const KIND_TURN_ACK: String = "turn_ack"
const KIND_TURN_CONFIRMED: String = "turn_confirmed"
const KIND_MATCH_END: String = "match_end"
## Accord de lancement : chaque appareil le demande (après le pile ou face, ou
## pour une revanche), et l'hôte diffuse `match_start` quand les deux l'ont
## demandé. Un seul camp ne peut donc pas lancer la partie à la place de l'autre.
const KIND_START_REQUEST: String = "start_request"
const KIND_DESYNC: String = "desync"
const KIND_BYE: String = "bye"

const KINDS: Array[String] = [
	KIND_HELLO, KIND_HELLO_ACK, KIND_HELLO_REJECT, KIND_LOBBY_STATE, KIND_READY,
	KIND_MATCH_START, KIND_MOVE_INTENT, KIND_MOVE_ACCEPTED, KIND_MOVE_REJECTED,
	KIND_TURN_ACK, KIND_TURN_CONFIRMED, KIND_MATCH_END, KIND_START_REQUEST,
	KIND_DESYNC, KIND_BYE,
]

## Empreinte calculée une fois par session : elle identifie les catalogues et
## les règles livrés avec l'application. Deux versions différentes ne peuvent
## pas se tromper mutuellement.
static var _catalogue_fingerprint: String = ""


## ─── Identité de la version ──────────────────────────────────────────────────

static func app_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


static func catalogue_fingerprint() -> String:
	if _catalogue_fingerprint != "":
		return _catalogue_fingerprint
	var text := ""
	for path in ["res://data/stones.json", "res://data/gods.json"]:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		text += file.get_as_text()
		file.close()
	_catalogue_fingerprint = text.sha256_text()
	return _catalogue_fingerprint


## Raison d'incompatibilité, ou chaîne vide si les versions sont compatibles.
static func compatibility_problem(handshake: Dictionary) -> String:
	if _integer(handshake.get("protocol_version")) != VERSION:
		return "Version du protocole incompatible."
	if str(handshake.get("app_version", "")) != app_version():
		return "Versions de l'application incompatibles."
	if str(handshake.get("catalogue", "")) != catalogue_fingerprint():
		return "Catalogues de cartes incompatibles."
	return ""


## Champs d'identité communs aux messages de poignée de main.
static func identity_fields() -> Dictionary:
	return {
		"protocol_version": VERSION,
		"app_version": app_version(),
		"catalogue": catalogue_fingerprint(),
	}


## ─── Encodage / décodage ─────────────────────────────────────────────────────

## Enveloppe JSON complète, ou chaîne vide si le message est invalide.
static func encode(kind: String, payload: Dictionary) -> String:
	if not validate(kind, payload)["ok"]:
		return ""
	var text := JSON.stringify({"v": VERSION, "kind": kind, "payload": payload}, "", false)
	if text.length() > MAX_MESSAGE_CHARS:
		return ""
	return text


## Décode une enveloppe JSON. Aucune désérialisation d'objet n'est possible :
## JSON ne produit que des valeurs simples.
static func decode(text: String) -> Dictionary:
	if text.length() == 0 or text.length() > MAX_MESSAGE_CHARS:
		return _decoded(false, "", {}, "Messages trop long ou vide.")
	## `JSON.new()` évite l'erreur moteur que `parse_string` imprime pour un
	## paquet hostile : un message illisible reste un simple refus.
	var json := JSON.new()
	if json.parse(text) != OK:
		return _decoded(false, "", {}, "Enveloppe illisible.")
	var parsed: Variant = json.data
	if not parsed is Dictionary:
		return _decoded(false, "", {}, "Enveloppe illisible.")
	var envelope: Dictionary = parsed
	if not _shape(envelope, ["v", "kind", "payload"]):
		return _decoded(false, "", {}, "Enveloppe incomplète.")
	if _integer(envelope.get("v")) != VERSION:
		return _decoded(false, "", {}, "Version d'enveloppe incompatible.")
	if not envelope.get("kind") is String or not envelope.get("payload") is Dictionary:
		return _decoded(false, "", {}, "Enveloppe mal typée.")
	var kind := str(envelope["kind"])
	var payload: Dictionary = envelope["payload"]
	var check := validate(kind, payload)
	if not check["ok"]:
		return _decoded(false, kind, {}, str(check["reason"]))
	return _decoded(true, kind, payload, "")


static func _decoded(ok: bool, kind: String, payload: Dictionary, reason: String) -> Dictionary:
	return {"ok": ok, "kind": kind, "payload": payload, "reason": reason}


## ─── Validation ──────────────────────────────────────────────────────────────

## Vérifie la forme complète d'un message. Le résultat contient une raison
## lisible en cas de refus. Aucune règle de jeu ici : seulement le format.
static func validate(kind: String, payload: Dictionary) -> Dictionary:
	if not KINDS.has(kind):
		return _verdict(false, "Type de message inconnu.")
	if not payload is Dictionary:
		return _verdict(false, "Charge utile mal typée.")
	match kind:
		KIND_HELLO:
			return _validate_hello(payload)
		KIND_HELLO_ACK:
			return _validate_hello_ack(payload)
		KIND_HELLO_REJECT:
			if not _shape(payload, ["reason"]):
				return _verdict(false, "Refus mal formé.")
			if not _text(payload.get("reason"), MAX_REASON_LENGTH) or str(payload["reason"]) == "":
				return _verdict(false, "Motif de refus invalide.")
			return _verdict(true, "")
		KIND_LOBBY_STATE:
			return _validate_lobby_state(payload)
		KIND_READY:
			if not _shape(payload, ["ready"]) or not payload.get("ready") is bool:
				return _verdict(false, "État prêt invalide.")
			return _verdict(true, "")
		KIND_MATCH_START:
			return _validate_match_start(payload)
		KIND_MOVE_INTENT:
			return _validate_move(payload, false)
		KIND_MOVE_ACCEPTED:
			return _validate_move(payload, true)
		KIND_MOVE_REJECTED:
			if not _shape(payload, ["match_id", "sequence", "reason"]):
				return _verdict(false, "Refus de coup mal formé.")
			if not _match_id(payload.get("match_id")):
				return _verdict(false, "match_id invalide.")
			if _integer(payload.get("sequence")) == INVALID_INT:
				return _verdict(false, "Séquence invalide.")
			if not _text(payload.get("reason"), MAX_REASON_LENGTH):
				return _verdict(false, "Motif invalide.")
			return _verdict(true, "")
		KIND_TURN_ACK:
			return _validate_turn_proof(payload)
		KIND_TURN_CONFIRMED:
			return _validate_turn_proof(payload)
		KIND_MATCH_END:
			return _validate_match_end(payload)
		KIND_START_REQUEST:
			if not _shape(payload, ["match_id"]):
				return _verdict(false, "Demande de lancement mal formée.")
			if not _match_id(payload.get("match_id")):
				return _verdict(false, "match_id invalide.")
			return _verdict(true, "")
		KIND_DESYNC:
			if not _shape(payload, ["match_id", "sequence", "reason"]):
				return _verdict(false, "Désynchronisation mal formée.")
			if not _match_id(payload.get("match_id")):
				return _verdict(false, "match_id invalide.")
			if _integer(payload.get("sequence")) == INVALID_INT:
				return _verdict(false, "Séquence invalide.")
			if not _text(payload.get("reason"), MAX_REASON_LENGTH):
				return _verdict(false, "Motif invalide.")
			return _verdict(true, "")
		KIND_BYE:
			if not _shape(payload, []):
				return _verdict(false, "Message de départ mal formé.")
			return _verdict(true, "")
	return _verdict(false, "Type de message inconnu.")


static func _validate_hello(payload: Dictionary) -> Dictionary:
	if not _shape(payload, ["protocol_version", "app_version", "catalogue",
			"name", "god_id", "deck"]):
		return _verdict(false, "Poignée de main incomplète.")
	if _integer(payload.get("protocol_version")) == INVALID_INT:
		return _verdict(false, "Version de protocole invalide.")
	if not _text(payload.get("app_version"), MAX_APP_VERSION_LENGTH):
		return _verdict(false, "Version d'application invalide.")
	if not _fingerprint(payload.get("catalogue")):
		return _verdict(false, "Empreinte de catalogue invalide.")
	if not _player_name(payload.get("name")):
		return _verdict(false, "Pseudo invalide.")
	if not _god_id(payload.get("god_id")):
		return _verdict(false, "Dieu invalide.")
	if not _deck_shape(payload.get("deck")):
		return _verdict(false, "Deck invalide.")
	return _verdict(true, "")


static func _validate_hello_ack(payload: Dictionary) -> Dictionary:
	if not _shape(payload, ["protocol_version", "app_version", "catalogue",
			"name", "god_id", "you_are"]):
		return _verdict(false, "Accusé de poignée de main incomplet.")
	if _integer(payload.get("protocol_version")) == INVALID_INT:
		return _verdict(false, "Version de protocole invalide.")
	if not _text(payload.get("app_version"), MAX_APP_VERSION_LENGTH):
		return _verdict(false, "Version d'application invalide.")
	if not _fingerprint(payload.get("catalogue")):
		return _verdict(false, "Empreinte de catalogue invalide.")
	if not _player_name(payload.get("name")):
		return _verdict(false, "Pseudo invalide.")
	if not _god_id(payload.get("god_id")):
		return _verdict(false, "Dieu invalide.")
	if not _side(payload.get("you_are")) or int(payload["you_are"]) != GameState.PLAYER_TWO:
		return _verdict(false, "Place attribuée invalide.")
	return _verdict(true, "")


static func _validate_lobby_state(payload: Dictionary) -> Dictionary:
	if not _shape(payload, ["host", "client", "status"]):
		return _verdict(false, "État du salon incomplet.")
	if not _participant_summary(payload.get("host")):
		return _verdict(false, "Hôte mal décrit.")
	if not _participant_summary(payload.get("client")):
		return _verdict(false, "Client mal décrit.")
	if not _text(payload.get("status"), MAX_STATUS_LENGTH):
		return _verdict(false, "Statut de salon invalide.")
	return _verdict(true, "")


static func _validate_match_start(payload: Dictionary) -> Dictionary:
	if not _shape(payload, ["match_id", "seed", "blocked_cells",
			"starting_player", "participants"]):
		return _verdict(false, "Configuration de partie incomplète.")
	if not _match_id(payload.get("match_id")):
		return _verdict(false, "match_id invalide.")
	if _integer(payload.get("seed")) == INVALID_INT:
		return _verdict(false, "Graine invalide.")
	if not _blocked_cells(payload.get("blocked_cells")):
		return _verdict(false, "Cases bloquées invalides.")
	if not _side(payload.get("starting_player")):
		return _verdict(false, "Premier joueur invalide.")
	var participants: Variant = payload.get("participants")
	if not participants is Array or participants.size() != MAX_PARTICIPANTS:
		return _verdict(false, "Participants invalides.")
	var sides := {}
	var peers := {}
	for entry in participants:
		if not _participant(entry):
			return _verdict(false, "Participant mal décrit.")
		var side := int(entry["side"])
		var peer := int(entry["peer_id"])
		if sides.has(side) or peers.has(peer):
			return _verdict(false, "Participants en double.")
		sides[side] = true
		peers[peer] = true
	if not sides.has(GameState.PLAYER_ONE) or not sides.has(GameState.PLAYER_TWO):
		return _verdict(false, "Camps incomplets.")
	return _verdict(true, "")


static func _validate_move(payload: Dictionary, with_sequence: bool) -> Dictionary:
	var keys := ["match_id", "player", "row", "col", "stone_id"]
	if with_sequence:
		keys.append("sequence")
	if not _shape(payload, keys):
		return _verdict(false, "Coup mal formé.")
	if not _match_id(payload.get("match_id")):
		return _verdict(false, "match_id invalide.")
	if not _side(payload.get("player")):
		return _verdict(false, "Joueur du coup invalide.")
	if not _coordinate(payload.get("row")) or not _coordinate(payload.get("col")):
		return _verdict(false, "Coordonnées invalides.")
	if not _text(payload.get("stone_id"), MAX_STONE_ID_LENGTH) or str(payload["stone_id"]) == "":
		return _verdict(false, "Carte invalide.")
	if with_sequence:
		var sequence := _integer(payload.get("sequence"))
		if sequence == INVALID_INT or sequence < 1:
			return _verdict(false, "Séquence invalide.")
	return _verdict(true, "")


static func _validate_turn_proof(payload: Dictionary) -> Dictionary:
	if not _shape(payload, ["match_id", "sequence", "fingerprint"]):
		return _verdict(false, "Preuve de tour incomplète.")
	if not _match_id(payload.get("match_id")):
		return _verdict(false, "match_id invalide.")
	var sequence := _integer(payload.get("sequence"))
	if sequence == INVALID_INT or sequence < 0:
		return _verdict(false, "Séquence invalide.")
	if not _fingerprint(payload.get("fingerprint")):
		return _verdict(false, "Empreinte d'état invalide.")
	return _verdict(true, "")


static func _validate_match_end(payload: Dictionary) -> Dictionary:
	if not _shape(payload, ["match_id", "winner", "score_one", "score_two"]):
		return _verdict(false, "Fin de partie incomplète.")
	if not _match_id(payload.get("match_id")):
		return _verdict(false, "match_id invalide.")
	var winner := _integer(payload.get("winner"))
	if winner == INVALID_INT or winner < GameState.PLAYER_NONE or winner > GameState.PLAYER_TWO:
		return _verdict(false, "Vainqueur invalide.")
	for key in ["score_one", "score_two"]:
		var score := _integer(payload.get(key))
		if score == INVALID_INT or score < 0 or score > MAX_SCORE:
			return _verdict(false, "Score invalide.")
	return _verdict(true, "")


## ─── Annonce de découverte ───────────────────────────────────────────────────

## Petit beacon JSON diffusé sur le port de découverte. Il ne sert qu'à
## proposer une partie : aucune donnée de combat n'y figure.
static func make_beacon(host_name: String, port: int, players: int) -> Dictionary:
	return {
		"beacon": BEACON_MARKER,
		"protocol_version": VERSION,
		"app_version": app_version(),
		"catalogue": catalogue_fingerprint(),
		"name": host_name,
		"port": port,
		"players": players,
	}


static func validate_beacon(payload: Variant) -> Dictionary:
	if not payload is Dictionary:
		return _verdict(false, "Annonce illisible.")
	if not _shape(payload, ["beacon", "protocol_version", "app_version",
			"catalogue", "name", "port", "players"]):
		return _verdict(false, "Annonce incomplète.")
	if str(payload.get("beacon", "")) != BEACON_MARKER:
		return _verdict(false, "Annonce étrangère.")
	if _integer(payload.get("protocol_version")) != VERSION:
		return _verdict(false, "Annonce d'une autre version.")
	if not _text(payload.get("app_version"), MAX_APP_VERSION_LENGTH):
		return _verdict(false, "Version d'annonce invalide.")
	if not _fingerprint(payload.get("catalogue")):
		return _verdict(false, "Empreinte d'annonce invalide.")
	if not _player_name(payload.get("name")):
		return _verdict(false, "Pseudo d'annonce invalide.")
	var port := _integer(payload.get("port"))
	if port == INVALID_INT or port < 1024 or port > 65535:
		return _verdict(false, "Port d'annonce invalide.")
	var players := _integer(payload.get("players"))
	if players == INVALID_INT or players < 1 or players > MAX_PARTICIPANTS:
		return _verdict(false, "Joueurs d'annonce invalides.")
	return _verdict(true, "")


## ─── Contrôles élémentaires ──────────────────────────────────────────────────

static func _verdict(ok: bool, reason: String) -> Dictionary:
	return {"ok": ok, "reason": reason}


## Refuse toute clé non prévue : le format reste strictement fermé.
static func _shape(value: Variant, keys: Array) -> bool:
	if not value is Dictionary:
		return false
	for key in value:
		if not keys.has(key):
			return false
	for key in keys:
		if not value.has(key):
			return false
	return true


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and not (value is bool)


static func _integer(value: Variant) -> int:
	if not _number(value):
		return INVALID_INT
	var as_float := float(value)
	if as_float != floorf(as_float) or absf(as_float) > 9007199254740992.0:
		return INVALID_INT
	return int(as_float)


static func _text(value: Variant, max_length: int) -> bool:
	return value is String and (value as String).length() <= max_length


static func _player_name(value: Variant) -> bool:
	if not _text(value, MAX_NAME_LENGTH):
		return false
	var name := (value as String).strip_edges()
	return name.length() >= MIN_NAME_LENGTH and name.length() <= MAX_NAME_LENGTH


static func _match_id(value: Variant) -> bool:
	return _text(value, MAX_ID_LENGTH) and (value as String).length() >= 1


static func _god_id(value: Variant) -> bool:
	if not _text(value, MAX_GOD_ID_LENGTH):
		return false
	var god_id := str(value)
	return god_id == "" or StoneLoader.get_god(god_id).size() > 0


static func _fingerprint(value: Variant) -> bool:
	return _text(value, FINGERPRINT_LENGTH) and (value as String).length() == FINGERPRINT_LENGTH


static func _side(value: Variant) -> bool:
	var side := _integer(value)
	return side == GameState.PLAYER_ONE or side == GameState.PLAYER_TWO


static func _coordinate(value: Variant) -> bool:
	var coordinate := _integer(value)
	return coordinate >= 0 and coordinate < GameState.BOARD_SIZE


static func _score(value: Variant) -> bool:
	var score := _integer(value)
	return score != INVALID_INT and score >= 0 and score <= MAX_SCORE


static func _deck_shape(value: Variant) -> bool:
	if not value is Array:
		return false
	var deck: Array = value
	if deck.size() > MAX_DECK_SIZE:
		return false
	for entry in deck:
		if not _text(entry, MAX_STONE_ID_LENGTH) or (entry as String).length() == 0:
			return false
	return true


static func _blocked_cells(value: Variant) -> bool:
	if not value is Array:
		return false
	var cells: Array = value
	if cells.size() > MAX_BLOCKED_CELLS:
		return false
	var seen := {}
	for entry in cells:
		if not entry is Array or (entry as Array).size() != 2:
			return false
		var row := _integer((entry as Array)[0])
		var col := _integer((entry as Array)[1])
		if row < 0 or row >= GameState.BOARD_SIZE or col < 0 or col >= GameState.BOARD_SIZE:
			return false
		var key := row * GameState.BOARD_SIZE + col
		if seen.has(key):
			return false
		seen[key] = true
	return true


static func _participant_summary(value: Variant) -> bool:
	if not _shape(value, ["name", "god_id", "deck_valid", "ready"]):
		return false
	if not _player_name(value.get("name")) or not _god_id(value.get("god_id")):
		return false
	return value.get("deck_valid") is bool and value.get("ready") is bool


static func _participant(value: Variant) -> bool:
	if not _shape(value, ["peer_id", "side", "name", "god_id", "deck"]):
		return false
	var peer_id := _integer(value.get("peer_id"))
	if peer_id == INVALID_INT or peer_id <= 0:
		return false
	if not _side(value.get("side")):
		return false
	if not _player_name(value.get("name")) or not _god_id(value.get("god_id")):
		return false
	return _deck_shape(value.get("deck"))
