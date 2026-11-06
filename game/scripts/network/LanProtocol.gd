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
const VERSION: int = 5

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
## Délais applicatifs : ENet garantit la livraison, mais pas qu'un pair vivant
## continue le protocole. Ces bornes empêchent une attente infinie.
const START_AGREEMENT_TIMEOUT_SECONDS: float = 30.0
const TURN_CONFIRM_TIMEOUT_SECONDS: float = 30.0

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
## Messages de règles, préparation et série. L'hôte les diffuse ; le client ne
## peut envoyer que son PRÊT, son choix de draft et sa confirmation de loadout.
const KIND_RULES_UPDATE: String = "rules_update"
const KIND_RULES_LOCK: String = "rules_lock"
const KIND_PREPARE_START: String = "prepare_start"
const KIND_LOADOUT_REVEAL: String = "loadout_reveal"
const KIND_LOADOUT_READY: String = "loadout_ready"
const KIND_LOADOUT_CONFIRM: String = "loadout_confirm"
const KIND_DRAFT_OFFERS: String = "draft_offers"
const KIND_DRAFT_CHOICE: String = "draft_choice"
const KIND_DRAFT_FINISHED: String = "draft_finished"
const KIND_ROUND_START: String = "round_start"
const KIND_ROUND_RESULT: String = "round_result"
const KIND_SERIES_STATE: String = "series_state"
## Présence PVP : chaque camp annonce uniquement son écran courant. Cette
## information ne déclenche jamais la navigation du pair.
const KIND_PVP_PRESENCE: String = "pvp_presence"
const KIND_DRAFT_PROGRESS: String = "draft_progress"
## Les présences autorisées sont volontairement explicites et fermées.
const PRESENCES: Array[String] = ["lobby", "preparation", "pre_battle", "in_match", "result"]

const KINDS: Array[String] = [
	KIND_HELLO, KIND_HELLO_ACK, KIND_HELLO_REJECT, KIND_LOBBY_STATE, KIND_READY,
	KIND_MATCH_START, KIND_MOVE_INTENT, KIND_MOVE_ACCEPTED, KIND_MOVE_REJECTED,
	KIND_TURN_ACK, KIND_TURN_CONFIRMED, KIND_MATCH_END, KIND_START_REQUEST,
	KIND_DESYNC, KIND_BYE, KIND_RULES_UPDATE, KIND_RULES_LOCK, KIND_PREPARE_START,
	KIND_LOADOUT_REVEAL, KIND_LOADOUT_READY, KIND_LOADOUT_CONFIRM, KIND_DRAFT_OFFERS,
	KIND_DRAFT_CHOICE, KIND_DRAFT_FINISHED, KIND_ROUND_START, KIND_ROUND_RESULT,
	KIND_SERIES_STATE, KIND_PVP_PRESENCE, KIND_DRAFT_PROGRESS,
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
			return _validate_ready(payload)
		KIND_MATCH_START:
			return _validate_match_start(payload, false)
		KIND_ROUND_START:
			return _validate_match_start(payload, true)
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
		KIND_RULES_UPDATE:
			return _validate_rules_update(payload)
		KIND_RULES_LOCK:
			return _validate_rules_lock(payload)
		KIND_PREPARE_START:
			return _validate_prepare_start(payload)
		KIND_LOADOUT_REVEAL:
			return _validate_loadout(payload)
		KIND_DRAFT_FINISHED:
			return _validate_loadout(payload)
		KIND_LOADOUT_READY:
			return _validate_loadout_ready(payload)
		KIND_LOADOUT_CONFIRM:
			return _validate_confirm(payload)
		KIND_DRAFT_OFFERS:
			return _validate_draft_offers(payload)
		KIND_DRAFT_CHOICE:
			return _validate_draft_choice(payload)
		KIND_DRAFT_PROGRESS:
			return _validate_draft_progress(payload)
		KIND_ROUND_RESULT:
			return _validate_round_result(payload)
		KIND_SERIES_STATE:
			return _validate_series_state(payload)
		KIND_PVP_PRESENCE:
			return _validate_presence(payload)
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
	var legacy := ["host", "client", "status"]
	var extended := legacy + ["mode", "series", "power_tier", "rules_revision",
		"phase", "series_id", "preparation_id"]
	if not _shape(payload, legacy) and not _shape(payload, extended):
		return _verdict(false, "État du salon incomplet.")
	if not _participant_summary(payload.get("host")):
		return _verdict(false, "Hôte mal décrit.")
	if not _participant_summary(payload.get("client")):
		return _verdict(false, "Client mal décrit.")
	if not _text(payload.get("status"), MAX_STATUS_LENGTH):
		return _verdict(false, "Statut de salon invalide.")
	if _shape(payload, extended):
		if not _mode(payload.get("mode")) or not _series_format(payload.get("series")):
			return _verdict(false, "Règles de salon invalides.")
		if not _power_tier(payload.get("power_tier")) or not _rules_revision(payload.get("rules_revision")):
			return _verdict(false, "Règles de salon invalides.")
		if not _phase(payload.get("phase")):
			return _verdict(false, "Phase de salon invalide.")
		if not _optional_id(payload.get("series_id"), MAX_ID_LENGTH) \
				or not _optional_id(payload.get("preparation_id"), MAX_ID_LENGTH):
			return _verdict(false, "Identifiant de salon invalide.")
	return _verdict(true, "")


static func _validate_ready(payload: Dictionary) -> Dictionary:
	if _shape(payload, ["ready"]) and payload.get("ready") is bool:
		return _verdict(true, "")
	if not _shape(payload, ["ready", "rules_revision"]):
		return _verdict(false, "État prêt invalide.")
	if not payload.get("ready") is bool or not _rules_revision(payload.get("rules_revision")):
		return _verdict(false, "État prêt invalide.")
	return _verdict(true, "")


static func _validate_match_start(payload: Dictionary, require_series: bool) -> Dictionary:
	var base := ["match_id", "seed", "blocked_cells", "starting_player", "participants"]
	var extended := base + ["series_id", "rules_revision", "preparation_id",
		"round_index", "mode", "series", "power_tier"]
	var has_series := _shape(payload, extended)
	if not _shape(payload, base) and not has_series:
		return _verdict(false, "Configuration de partie incomplète.")
	if require_series and not has_series:
		return _verdict(false, "Lancement de manche sans identifiants de série.")
	if has_series:
		var series_ok := _series_id(payload.get("series_id")) and _rules_revision(payload.get("rules_revision")) and _optional_id(payload.get("preparation_id"), MAX_ID_LENGTH) and _round_index(payload.get("round_index")) and _mode(payload.get("mode")) and _series_format(payload.get("series")) and _power_tier(payload.get("power_tier"))
		if not series_ok:
			return _verdict(false, "Identifiants de série invalides.")
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


static func _validate_rules_update(payload: Dictionary) -> Dictionary:
	if not _shape(payload, ["mode", "series", "power_tier", "rules_revision"]):
		return _verdict(false, "Mise à jour des règles incomplète.")
	if not _mode(payload.get("mode")) or not _series_format(payload.get("series")) \
			or not _power_tier(payload.get("power_tier")) \
			or not _rules_revision(payload.get("rules_revision")):
		return _verdict(false, "Règles invalides.")
	return _verdict(true, "")


static func _validate_rules_lock(payload: Dictionary) -> Dictionary:
	if not _shape(payload, ["rules_revision"]):
		return _verdict(false, "Verrouillage des règles incomplet.")
	if not _rules_revision(payload.get("rules_revision")):
		return _verdict(false, "Révision invalide.")
	return _verdict(true, "")


static func _validate_prepare_start(payload: Dictionary) -> Dictionary:
	if not _shape(payload, ["series_id", "preparation_id", "rules_revision",
			"round_index", "mode", "series", "power_tier", "deadline_unix_ms"]):
		return _verdict(false, "Préparation incomplète.")
	if not _series_id(payload.get("series_id")) \
			or not _preparation_id(payload.get("preparation_id")) \
			or not _rules_revision(payload.get("rules_revision")) \
			or not _round_index(payload.get("round_index")) \
			or not _mode(payload.get("mode")) or not _series_format(payload.get("series")) \
			or not _power_tier(payload.get("power_tier")):
		return _verdict(false, "Préparation invalide.")
	if not _deadline(payload.get("deadline_unix_ms")):
		return _verdict(false, "Échéance invalide.")
	return _verdict(true, "")


static func _validate_loadout(payload: Dictionary) -> Dictionary:
	if not _shape(payload, ["series_id", "preparation_id", "rules_revision",
			"round_index", "god_id", "deck", "total_quarters"]):
		return _verdict(false, "Loadout incomplet.")
	if not _series_id(payload.get("series_id")) \
			or not _preparation_id(payload.get("preparation_id")) \
			or not _rules_revision(payload.get("rules_revision")) \
			or not _round_index(payload.get("round_index")):
		return _verdict(false, "Identifiants de loadout invalides.")
	if not _god_id(payload.get("god_id")) or str(payload.get("god_id", "")) == "":
		return _verdict(false, "Dieu de loadout invalide.")
	if not _deck_shape(payload.get("deck")):
		return _verdict(false, "Deck de loadout invalide.")
	var total := _integer(payload.get("total_quarters"))
	if total == INVALID_INT or total < 0 or total > DeckRules.DECK_BUDGET * StoneCostRules.COST_SCALE:
		return _verdict(false, "Total de loadout invalide.")
	return _verdict(true, "")


static func _validate_loadout_ready(payload: Dictionary) -> Dictionary:
	if not _shape(payload, ["series_id", "preparation_id", "rules_revision",
			"round_index", "side", "ready"]):
		return _verdict(false, "Confirmation de loadout incomplète.")
	if not _series_id(payload.get("series_id")) \
			or not _preparation_id(payload.get("preparation_id")) \
			or not _rules_revision(payload.get("rules_revision")) \
			or not _round_index(payload.get("round_index")) \
			or not _side(payload.get("side")):
		return _verdict(false, "Confirmation de loadout invalide.")
	if not payload.get("ready") is bool:
		return _verdict(false, "État de confirmation invalide.")
	return _verdict(true, "")


static func _validate_confirm(payload: Dictionary) -> Dictionary:
	if not _shape(payload, ["series_id", "preparation_id", "rules_revision", "round_index"]):
		return _verdict(false, "Confirmation incomplète.")
	if not _series_id(payload.get("series_id")) \
			or not _preparation_id(payload.get("preparation_id")) \
			or not _rules_revision(payload.get("rules_revision")) \
			or not _round_index(payload.get("round_index")):
		return _verdict(false, "Confirmation invalide.")
	return _verdict(true, "")


static func _validate_draft_offers(payload: Dictionary) -> Dictionary:
	if not _shape(payload, ["series_id", "preparation_id", "rules_revision",
			"round_index", "step_one", "step_two", "complete_one", "complete_two",
			"viewer_side", "offers_step", "offers_one", "offers_two", "deadline_unix_ms"]):
		return _verdict(false, "Offres de draft incomplètes.")
	if not _series_id(payload.get("series_id")) \
			or not _preparation_id(payload.get("preparation_id")) \
			or not _rules_revision(payload.get("rules_revision")) \
			or not _round_index(payload.get("round_index")):
		return _verdict(false, "Identifiants de draft invalides.")
	for key in ["step_one", "step_two"]:
		var step := _integer(payload.get(key))
		if step == INVALID_INT or step < 0 or step > DeckRules.DECK_SIZE:
			return _verdict(false, "Étape de draft invalide.")
	if not payload.get("complete_one") is bool or not payload.get("complete_two") is bool:
		return _verdict(false, "Fin de draft invalide.")
	for side in [GameState.PLAYER_ONE, GameState.PLAYER_TWO]:
		var step_key := "step_one" if side == GameState.PLAYER_ONE else "step_two"
		var complete_key := "complete_one" if side == GameState.PLAYER_ONE else "complete_two"
		var actual_step := int(payload.get(step_key))
		if bool(payload.get(complete_key)) != (actual_step == DeckRules.DECK_SIZE):
			return _verdict(false, "Fin de draft incohérente.")
	if not _side(payload.get("viewer_side")):
		return _verdict(false, "Destinataire des offres invalide.")
	var viewer_side := int(payload.get("viewer_side"))
	var offers_step := _integer(payload.get("offers_step"))
	if offers_step == INVALID_INT or offers_step < 0 or offers_step > DeckRules.DECK_SIZE:
		return _verdict(false, "Étape des offres invalide.")
	var viewer_step := int(payload.get("step_one")) if viewer_side == GameState.PLAYER_ONE \
		else int(payload.get("step_two"))
	if offers_step != viewer_step:
		return _verdict(false, "Étape des offres incohérente avec le destinataire.")
	if not _draft_offers_at_step(payload.get("offers_one"), offers_step) \
			or not _draft_offers_at_step(payload.get("offers_two"), offers_step):
		return _verdict(false, "Propositions de draft invalides.")
	if not _deadline(payload.get("deadline_unix_ms")):
		return _verdict(false, "Échéance de draft invalide.")
	return _verdict(true, "")


## Les deux paires projetées appartiennent à l'étape du destinataire, pas aux
## étapes réelles des deux camps. Une étape 8 signifie que son draft est fini.
static func _draft_offers_at_step(value: Variant, step: int) -> bool:
	if step == DeckRules.DECK_SIZE:
		return value is Array and (value as Array).is_empty()
	if step < 0 or step > DeckRules.DECK_SIZE:
		return false
	return _offers(value)


static func _validate_draft_choice(payload: Dictionary) -> Dictionary:
	if not _shape(payload, ["series_id", "preparation_id", "rules_revision",
			"round_index", "own_step", "stone_id"]):
		return _verdict(false, "Choix de draft incomplet.")
	if not _series_id(payload.get("series_id")) \
			or not _preparation_id(payload.get("preparation_id")) \
			or not _rules_revision(payload.get("rules_revision")) \
			or not _round_index(payload.get("round_index")):
		return _verdict(false, "Identifiants de choix invalides.")
	var step := _integer(payload.get("own_step"))
	if step == INVALID_INT or step < 0 or step >= DeckRules.DECK_SIZE:
		return _verdict(false, "Étape de choix invalide.")
	if not _text(payload.get("stone_id"), MAX_STONE_ID_LENGTH) or str(payload.get("stone_id", "")) == "":
		return _verdict(false, "Carte de choix invalide.")
	return _verdict(true, "")


static func _validate_draft_progress(payload: Dictionary) -> Dictionary:
	if not _shape(payload, ["series_id", "preparation_id", "rules_revision",
			"round_index", "own_step", "own_deck", "own_complete"]):
		return _verdict(false, "Progression de draft incomplète.")
	if not _series_id(payload.get("series_id")) \
			or not _preparation_id(payload.get("preparation_id")) \
			or not _rules_revision(payload.get("rules_revision")) \
			or not _round_index(payload.get("round_index")):
		return _verdict(false, "Identifiants de progression invalides.")
	var step := _integer(payload.get("own_step"))
	if step == INVALID_INT or step < 0 or step > DeckRules.DECK_SIZE:
		return _verdict(false, "Étape de progression invalide.")
	if not _deck_shape(payload.get("own_deck")):
		return _verdict(false, "Deck local invalide.")
	if int((payload.get("own_deck", []) as Array).size()) != step:
		return _verdict(false, "Deck local incohérent avec la progression.")
	if not payload.get("own_complete") is bool:
		return _verdict(false, "Fin de progression invalide.")
	if bool(payload.get("own_complete")) != (step == DeckRules.DECK_SIZE):
		return _verdict(false, "Fin de progression incohérente.")
	return _verdict(true, "")


static func _validate_round_result(payload: Dictionary) -> Dictionary:
	if not _shape(payload, ["series_id", "preparation_id", "rules_revision", "round_index",
			"winner", "score_one", "score_two", "wins_one", "wins_two", "ties", "finished",
			"series_winner", "next_round_index"]):
		return _verdict(false, "Résultat de manche incomplet.")
	if not _series_id(payload.get("series_id")) \
			or not _preparation_id(payload.get("preparation_id")) \
			or not _rules_revision(payload.get("rules_revision")) \
			or not _round_index(payload.get("round_index")):
		return _verdict(false, "Identifiants de résultat invalides.")
	var winner := _integer(payload.get("winner"))
	if winner == INVALID_INT or winner < GameState.PLAYER_NONE or winner > GameState.PLAYER_TWO:
		return _verdict(false, "Vainqueur de manche invalide.")
	for key in ["score_one", "score_two"]:
		if not _score(payload.get(key)):
			return _verdict(false, "Score de manche invalide.")
	for key in ["wins_one", "wins_two"]:
		var wins := _integer(payload.get(key))
		if wins == INVALID_INT or wins < 0 or wins > 3:
			return _verdict(false, "Victoire de série invalide.")
	var ties := _integer(payload.get("ties"))
	if ties == INVALID_INT or ties < 0:
		return _verdict(false, "Égalités invalides.")
	if not payload.get("finished") is bool:
		return _verdict(false, "Fin de série invalide.")
	var series_winner := _integer(payload.get("series_winner"))
	if series_winner == INVALID_INT or series_winner < GameState.PLAYER_NONE or series_winner > GameState.PLAYER_TWO:
		return _verdict(false, "Vainqueur de série invalide.")
	if not _round_index(payload.get("next_round_index")):
		return _verdict(false, "Manche suivante invalide.")
	return _verdict(true, "")


static func _validate_presence(payload: Dictionary) -> Dictionary:
	if not _shape(payload, ["presence"]):
		return _verdict(false, "Présence mal formée.")
	if not payload.get("presence") is String \
			or not PRESENCES.has(str(payload.get("presence", ""))):
		return _verdict(false, "Présence inconnue.")
	return _verdict(true, "")


static func _validate_series_state(payload: Dictionary) -> Dictionary:
	if not _shape(payload, ["series_id", "mode", "series", "rules_revision", "power_tier",
			"wins_one", "wins_two", "wins_needed", "max_rounds", "round_index", "ties",
			"finished", "winner", "seed", "keeps_loadouts"]):
		return _verdict(false, "État de série incomplet.")
	if not _series_id(payload.get("series_id")) \
			or not _mode(payload.get("mode")) or not _series_format(payload.get("series")) \
			or not _rules_revision(payload.get("rules_revision")) \
			or not _power_tier(payload.get("power_tier")):
		return _verdict(false, "Règles de série invalides.")
	for key in ["wins_one", "wins_two"]:
		var wins := _integer(payload.get(key))
		if wins == INVALID_INT or wins < 0 or wins > 3:
			return _verdict(false, "Victoires de série invalides.")
	var needed := _integer(payload.get("wins_needed"))
	if needed == INVALID_INT or needed < 1 or needed > 3:
		return _verdict(false, "Objectif de série invalide.")
	var maximum := _integer(payload.get("max_rounds"))
	if maximum == INVALID_INT or maximum < 1 or maximum > 5:
		return _verdict(false, "Maximum de manches invalide.")
	if not _round_index(payload.get("round_index")):
		return _verdict(false, "Manche de série invalide.")
	var ties := _integer(payload.get("ties"))
	if ties == INVALID_INT or ties < 0:
		return _verdict(false, "Égalités de série invalides.")
	if not payload.get("finished") is bool or not payload.get("keeps_loadouts") is bool:
		return _verdict(false, "État de série invalide.")
	if _integer(payload.get("seed")) == INVALID_INT:
		return _verdict(false, "Graine de série invalide.")
	var winner := _integer(payload.get("winner"))
	if winner == INVALID_INT or winner < GameState.PLAYER_NONE or winner > GameState.PLAYER_TWO:
		return _verdict(false, "Vainqueur de série invalide.")
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


static func _rules_revision(value: Variant) -> bool:
	var revision := _integer(value)
	return revision != INVALID_INT and revision >= 0


static func _series_id(value: Variant) -> bool:
	return _text(value, MAX_ID_LENGTH) and (value as String).length() >= 1


static func _preparation_id(value: Variant) -> bool:
	return _text(value, MAX_ID_LENGTH) and (value as String).length() >= 1


static func _optional_id(value: Variant, max_length: int) -> bool:
	return _text(value, max_length)


static func _round_index(value: Variant) -> bool:
	var index := _integer(value)
	return index != INVALID_INT and index >= 1


static func _deadline(value: Variant) -> bool:
	var deadline := _integer(value)
	return deadline != INVALID_INT and deadline >= 0


static func _offers(value: Variant) -> bool:
	if not value is Array or (value as Array).size() != 2:
		return false
	for entry in value:
		if not _text(entry, MAX_STONE_ID_LENGTH) or (entry as String).length() == 0:
			return false
	return true


static func _mode(value: Variant) -> bool:
	return value is String and MatchRules.MODES.has(value)


static func _series_format(value: Variant) -> bool:
	return value is String and MatchRules.SERIES_FORMATS.has(value)


static func _power_tier(value: Variant) -> bool:
	var tier := _integer(value)
	return tier != INVALID_INT and tier >= MatchRules.MIN_POWER_TIER and tier <= MatchRules.MAX_POWER_TIER


static func _phase(value: Variant) -> bool:
	return value is String and MatchRules.PHASES.has(value)


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
