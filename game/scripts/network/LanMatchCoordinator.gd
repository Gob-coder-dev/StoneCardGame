## LanMatchCoordinator.gd
## Pont entre le réseau et le moteur pendant un match PVP local.
##
## L'hôte est autoritaire : il vérifie l'expéditeur, le match, la séquence, le
## joueur actif, la phase, les coordonnées et la carte. Les deux moteurs
## appliquent ensuite la même commande validée, avec la même graine, puis
## comparent une empreinte canonique de leur état avant d'ouvrir le tour suivant.
##
## Ce fichier ne contient aucune règle de combat : la validation est fournie par
## l'appelant (`set_move_validator`), qui interroge PlacementRules et TurnManager.
class_name LanMatchCoordinator
extends RefCounted

signal command_accepted(command: Dictionary)
signal turn_confirmed(turn_sequence: int)
signal match_finished(winner: int, score_one: int, score_two: int)
## L'adversaire a demandé le lancement de la partie.
signal start_pending()
## L'hôte a confirmé le départ : les deux appareils ouvrent le plateau.
signal match_ready(config: Dictionary)
signal desync(reason: String)
signal aborted(message: String)
signal ready_changed(can_submit: bool)
signal move_rejected(reason: String)

const HOST_PEER: int = LanProtocol.SERVER_ID
const DUPLICATE_MESSAGE: String = "Coup déjà reçu."
const DESYNC_MESSAGE: String = "Désynchronisation détectée : la partie est arrêtée."

var _transport: LanTransportLink = null
var _is_host := false
var _local_side := GameState.PLAYER_ONE
var _local_peer := 0
var _client_peer := 0
var _match_id := ""
var _active_player := GameState.PLAYER_ONE
var _sequence := 0
var _can_submit := false
var _closed := false
var _started := false
var _desynced := false
var _finished := false
var _validator: Callable = Callable()
## Génère une nouvelle configuration (revanche) : la graine, le terrain et le
## premier joueur restent l'affaire de l'hôte, jamais du coordinateur.
var _start_builder: Callable = Callable()
## Configuration rejouée telle quelle (premier match, après le pile ou face).
var _start_config: Dictionary = {}
var _start_enabled := false
var _start_local := false
var _start_remote := false
var _last_command: Dictionary = {}
var _local_fingerprint := ""
var _remote_fingerprint := ""
var _pending_ack_sequence := -1
var _intent_pending := false
var _pending_result: Dictionary = {}


## Branche le coordinateur. `client_peer` n'est utile qu'à l'hôte.
func attach(transport: LanTransportLink, session_match_id: String, is_host: bool,
		local_side: int, client_peer: int = 0) -> void:
	close()
	_closed = false
	_transport = transport
	_match_id = session_match_id
	_is_host = is_host
	_local_side = local_side
	_client_peer = client_peer
	_local_peer = transport.local_peer_id()
	transport.message_received.connect(_on_message)
	transport.peer_left.connect(_on_peer_left)


func close() -> void:
	_closed = true
	_can_submit = false
	if _transport == null:
		return
	if _transport.message_received.is_connected(_on_message):
		_transport.message_received.disconnect(_on_message)
	if _transport.peer_left.is_connected(_on_peer_left):
		_transport.peer_left.disconnect(_on_peer_left)
	_transport = null


## Validation réelle fournie par le driver : joueur actif, phase, coordonnées,
## présence de la carte et PlacementRules. Signée
## (player: int, row: int, col: int, stone_id: String) -> bool.
func set_move_validator(validator: Callable) -> void:
	_validator = validator


## Génère la configuration d'une revanche. Signé () -> Dictionary.
func set_start_builder(builder: Callable) -> void:
	_start_builder = builder


## Arme la poignée de main de lancement. `config` est la configuration déjà
## validée et rejouée telle quelle (premier match) ; vide, l'hôte en fabrique
## une neuve avec le builder (revanche). L'écran d'avant-combat et l'écran de
## résultat créent chacun leur coordinateur, après la libération du précédent.
func enable_start(config: Dictionary = {}) -> void:
	_start_enabled = true
	_start_config = config.duplicate(true) if not config.is_empty() else {}
	_start_local = false
	_start_remote = false
	_set_can_submit(false)


## Ouvre le match au premier tour. Les deux côtés partent de la configuration
## validée par l'hôte, donc aucune confirmation supplémentaire n'est nécessaire.
func begin(starting_player: int) -> void:
	_started = true
	_closed = false
	_sequence = 0
	_pending_ack_sequence = -1
	_intent_pending = false
	_pending_result = {}
	_desynced = false
	_finished = false
	_active_player = starting_player
	_last_command = {}
	_local_fingerprint = ""
	_remote_fingerprint = ""
	_set_can_submit(true)


func sequence() -> int:
	return _sequence


func match_id() -> String:
	return _match_id


func can_submit() -> bool:
	return _can_submit and not _closed and not _desynced and not _finished


func active_player() -> int:
	return _active_player


func is_local_turn() -> bool:
	return _active_player == _local_side


## Demande de coup du joueur local. L'hôte valide et diffuse ; le client envoie
## une intention et attend la commande acceptée.
func request_move(row: int, col: int, stone_id: String) -> bool:
	if not can_submit() or not is_local_turn():
		return false
	var intent := {
		"match_id": _match_id,
		"player": _local_side,
		"row": row,
		"col": col,
		"stone_id": stone_id,
	}
	if _is_host:
		return _host_accept(intent)
	_intent_pending = true
	_set_can_submit(false)
	if not _transport.send_to(HOST_PEER, LanProtocol.KIND_MOVE_INTENT, intent):
		_intent_pending = false
		_set_can_submit(true)
		return false
	return true


## ─── Hôte ────────────────────────────────────────────────────────────────────

## Applique et diffuse une commande validée. Refuse les doublons par le silence.
func _host_accept(intent: Dictionary) -> bool:
	if not can_submit():
		return false
	if _is_duplicate(intent):
		return false
	var player := int(intent.get("player", GameState.PLAYER_NONE))
	var row := int(intent.get("row", -1))
	var col := int(intent.get("col", -1))
	var stone_id := str(intent.get("stone_id", ""))
	if player != _active_player or not _is_valid_move(player, row, col, stone_id):
		return false
	var command := {
		"match_id": _match_id,
		"sequence": _sequence + 1,
		"player": player,
		"row": row,
		"col": col,
		"stone_id": stone_id,
	}
	if not LanProtocol.validate(LanProtocol.KIND_MOVE_ACCEPTED, command)["ok"]:
		return false
	_accept(command)
	if _transport != null:
		_transport.broadcast(LanProtocol.KIND_MOVE_ACCEPTED, command)
	return true


func _accept(command: Dictionary) -> void:
	_intent_pending = false
	_sequence = int(command["sequence"])
	_last_command = {
		"player": int(command["player"]),
		"row": int(command["row"]),
		"col": int(command["col"]),
		"stone_id": str(command["stone_id"]),
	}
	_active_player = GameState.PLAYER_TWO if int(command["player"]) == GameState.PLAYER_ONE \
		else GameState.PLAYER_ONE
	_local_fingerprint = ""
	_remote_fingerprint = ""
	_pending_ack_sequence = _sequence
	_set_can_submit(false)
	command_accepted.emit(command)


func _on_turn_ack(from_peer: int, payload: Dictionary) -> void:
	if not _is_host or from_peer != _client_peer:
		return
	var turn_sequence := int(payload.get("sequence", -1))
	if turn_sequence != _sequence or turn_sequence != _pending_ack_sequence:
		return
	_remote_fingerprint = str(payload.get("fingerprint", ""))
	_confirm_if_ready()


## L'hôte compare les deux empreintes ; elles doivent être identiques.
func _confirm_if_ready() -> void:
	if _local_fingerprint == "" or _remote_fingerprint == "":
		return
	if _local_fingerprint != _remote_fingerprint:
		_fail_desync()
		return
	var fingerprint := _local_fingerprint
	_local_fingerprint = ""
	_remote_fingerprint = ""
	_pending_ack_sequence = -1
	_set_can_submit(true)
	if _transport != null:
		_transport.broadcast(LanProtocol.KIND_TURN_CONFIRMED, {
			"match_id": _match_id,
			"sequence": _sequence,
			"fingerprint": fingerprint,
		})
	turn_confirmed.emit(_sequence)
	_publish_result_if_ready()


func _fail_desync() -> void:
	if _desynced:
		return
	_desynced = true
	_pending_result = {}
	_set_can_submit(false)
	if _transport != null and _is_host:
		_transport.broadcast(LanProtocol.KIND_DESYNC, {
			"match_id": _match_id,
			"sequence": _sequence,
			"reason": DESYNC_MESSAGE,
		})
	desync.emit(DESYNC_MESSAGE)


## ─── Preuve d'état des deux appareils ───────────────────────────────────────

## Appelé par le driver après la résolution et la présentation du tour local.
func report_local_state(fingerprint: String, turn_sequence: int) -> void:
	if _closed or _desynced or not _started:
		return
	if turn_sequence != _sequence:
		return
	_local_fingerprint = fingerprint
	if _is_host:
		_confirm_if_ready()
	else:
		_transport.send_to(HOST_PEER, LanProtocol.KIND_TURN_ACK, {
			"match_id": _match_id,
			"sequence": turn_sequence,
			"fingerprint": fingerprint,
		})


## ─── Fin et erreurs ──────────────────────────────────────────────────────────

## Seul l'hôte décide du résultat et le diffuse.
func finish_match(winner: int, score_one: int, score_two: int) -> void:
	if _closed or _desynced or _finished:
		return
	if not _is_host:
		return
	var payload := {
		"match_id": _match_id,
		"winner": winner,
		"score_one": score_one,
		"score_two": score_two,
	}
	if not LanProtocol.validate(LanProtocol.KIND_MATCH_END, payload)["ok"]:
		return
	_pending_result = payload
	_publish_result_if_ready()


## Le dernier tour suit le même accord d'empreintes que tous les autres.
## Un verdict calculé localement reste en attente tant que son tour n'est pas confirmé.
func _publish_result_if_ready() -> void:
	if _pending_result.is_empty() or _pending_ack_sequence >= 0 \
			or _closed or _desynced or _finished:
		return
	var result := _pending_result
	_pending_result = {}
	_finished = true
	_set_can_submit(false)
	_transport.broadcast(LanProtocol.KIND_MATCH_END, result)
	match_finished.emit(int(result["winner"]), int(result["score_one"]), int(result["score_two"]))


## Chaque appareil doit toucher COMMENCER (ou REVANCHE) : l'hôte ne lance le
## plateau qu'une fois les deux accords reçus, et les deux appareils changent
## d'écran ensemble. Le premier qui demande attend l'autre.
func request_start() -> bool:
	if not _start_enabled or _closed or _desynced or _transport == null:
		return false
	if _start_local:
		return true
	_start_local = true
	if _is_host:
		_maybe_start()
	else:
		_transport.send_to(HOST_PEER, LanProtocol.KIND_START_REQUEST,
			{"match_id": _match_id})
	start_pending.emit()
	return true


func _maybe_start() -> void:
	if not _is_host or not _start_enabled or not _start_local or not _start_remote:
		return
	var config: Dictionary = _start_config
	if _start_builder.is_valid():
		config = _start_builder.call()
	if not LanProtocol.validate(LanProtocol.KIND_MATCH_START, config)["ok"]:
		return
	_match_id = str(config.get("match_id", ""))
	_start_config = config.duplicate(true)
	_start_enabled = false
	_start_local = false
	_start_remote = false
	if _transport == null:
		return
	_transport.broadcast(LanProtocol.KIND_MATCH_START, config)
	match_ready.emit(config)


func abort(message: String) -> void:
	if _closed:
		return
	_closed = true
	_pending_result = {}
	_can_submit = false
	aborted.emit(message)


## ─── Réception ───────────────────────────────────────────────────────────────

func _on_message(from_peer: int, kind: String, payload: Dictionary) -> void:
	if _closed or _desynced:
		return
	if not _is_from_expected_peer(from_peer):
		return
	if kind == LanProtocol.KIND_START_REQUEST:
		if _is_host:
			_on_start_request(from_peer, payload)
		return
	if kind == LanProtocol.KIND_MATCH_START:
		if not _is_host:
			_on_start_confirmed(from_peer, payload)
		return
	if _finished:
		return
	if kind == LanProtocol.KIND_MOVE_INTENT:
		if _is_host:
			_on_intent(from_peer, payload)
		return
	if str(payload.get("match_id", "")) != _match_id:
		return
	match kind:
		LanProtocol.KIND_MOVE_ACCEPTED:
			if not _is_host:
				_on_accepted(from_peer, payload)
		LanProtocol.KIND_MOVE_REJECTED:
			if not _is_host:
				_on_rejected(payload)
		LanProtocol.KIND_TURN_ACK:
			_on_turn_ack(from_peer, payload)
		LanProtocol.KIND_TURN_CONFIRMED:
			if not _is_host and from_peer == HOST_PEER:
				_on_turn_confirmed(payload)
		LanProtocol.KIND_DESYNC:
			_desynced = true
			_set_can_submit(false)
			desync.emit(str(payload.get("reason", DESYNC_MESSAGE)))
		LanProtocol.KIND_MATCH_END:
			if not _is_host and from_peer == HOST_PEER:
				_finished = true
				_can_submit = false
				match_finished.emit(int(payload.get("winner", GameState.PLAYER_NONE)),
					int(payload.get("score_one", 0)), int(payload.get("score_two", 0)))
		_:
			pass


func _on_intent(from_peer: int, payload: Dictionary) -> void:
	if from_peer != _client_peer:
		return
	if str(payload.get("match_id", "")) != _match_id:
		return
	if int(payload.get("player", 0)) != GameState.PLAYER_TWO:
		_reject(from_peer, "Camp invalide.")
		return
	if _is_duplicate(payload):
		return
	var row := int(payload.get("row", -1))
	var col := int(payload.get("col", -1))
	var stone_id := str(payload.get("stone_id", ""))
	if _active_player != GameState.PLAYER_TWO or not _is_valid_move(GameState.PLAYER_TWO, row, col, stone_id):
		_reject(from_peer, "Coup invalide.")
		return
	_host_accept(payload)


## Une commande acceptée doit suivre exactement la séquence locale et le joueur
## attendu ; sinon la partie est arrêtée plutôt que de diverger silencieusement.
func _on_accepted(from_peer: int, payload: Dictionary) -> void:
	if from_peer != HOST_PEER:
		return
	if int(payload.get("sequence", 0)) != _sequence + 1 or int(payload.get("player", 0)) != _active_player:
		_desynced = true
		_set_can_submit(false)
		desync.emit(DESYNC_MESSAGE)
		return
	_accept(payload)


func _on_turn_confirmed(payload: Dictionary) -> void:
	var turn_sequence := int(payload.get("sequence", -1))
	if turn_sequence != _sequence:
		return
	if str(payload.get("fingerprint", "")) != _local_fingerprint:
		_desynced = true
		_set_can_submit(false)
		desync.emit(DESYNC_MESSAGE)
		return
	_pending_ack_sequence = -1
	_set_can_submit(true)
	turn_confirmed.emit(turn_sequence)


func _on_rejected(payload: Dictionary) -> void:
	if not _intent_pending or int(payload.get("sequence", -1)) != _sequence:
		return
	_intent_pending = false
	_set_can_submit(true)
	move_rejected.emit(str(payload.get("reason", "Coup refusé.")))


func _on_start_request(from_peer: int, payload: Dictionary) -> void:
	if not _start_enabled or from_peer != _client_peer:
		return
	if str(payload.get("match_id", "")) != _match_id:
		return
	_start_remote = true
	start_pending.emit()
	_maybe_start()


## Le client n'ouvre le plateau que sur confirmation de l'hôte : il ne peut
## donc jamais jouer un coup avant que l'autre téléphone soit prêt.
func _on_start_confirmed(from_peer: int, payload: Dictionary) -> void:
	if not _start_enabled or from_peer != HOST_PEER:
		return
	if not LanProtocol.validate(LanProtocol.KIND_MATCH_START, payload)["ok"]:
		return
	_match_id = str(payload.get("match_id", ""))
	_start_enabled = false
	_start_local = false
	_start_remote = false
	match_ready.emit(payload)


func _on_peer_left(peer_id: int) -> void:
	if _closed:
		return
	var expected := _client_peer if _is_host else HOST_PEER
	if expected != 0 and peer_id != expected:
		return
	_can_submit = false
	aborted.emit("L'adversaire a quitté la partie.")


## ─── Contrôles internes ─────────────────────────────────────────────────────

func _is_from_expected_peer(from_peer: int) -> bool:
	if _is_host:
		return _client_peer != 0 and from_peer == _client_peer
	return from_peer == HOST_PEER


func _is_duplicate(intent: Dictionary) -> bool:
	return not _last_command.is_empty() \
		and int(_last_command["player"]) == int(intent.get("player", 0)) \
		and int(_last_command["row"]) == int(intent.get("row", -1)) \
		and int(_last_command["col"]) == int(intent.get("col", -1)) \
		and str(_last_command["stone_id"]) == str(intent.get("stone_id", ""))


func _is_valid_move(player: int, row: int, col: int, stone_id: String) -> bool:
	if not _validator.is_valid():
		return false
	return bool(_validator.call(player, row, col, stone_id))


func _reject(peer_id: int, reason: String) -> void:
	if _transport == null:
		return
	_transport.send_to(peer_id, LanProtocol.KIND_MOVE_REJECTED, {
		"match_id": _match_id,
		"sequence": _sequence,
		"reason": reason,
	})


func _set_can_submit(value: bool) -> void:
	if _can_submit == value:
		return
	_can_submit = value
	ready_changed.emit(value)
