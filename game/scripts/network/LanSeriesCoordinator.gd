## LanSeriesCoordinator.gd
## Orchestration réseau d'une série PVP : préparation autoritaire, draft,
## confirmation des loadouts, lancement des manches et score de série.
##
## L'hôte possède les graines, les générateurs, les offres, les choix validés,
## les loadouts et le score. Le client ne peut envoyer qu'un choix parmi les
## offres et sa confirmation de loadout. Aucun deck arbitraire n'est accepté.
##
## Les règles pures vivent dans MatchRules, LoadoutGenerator, DraftEngine et
## SeriesEngine ; ce fichier ne fait que les relier au transport et aux écrans.
class_name LanSeriesCoordinator
extends RefCounted

const DraftModel := preload("res://scripts/domain/DraftEngine.gd")
const SeriesEngineModel := preload("res://scripts/domain/SeriesEngine.gd")
const SeriesStateModel := preload("res://scripts/domain/SeriesState.gd")
const RulesModel := preload("res://scripts/domain/MatchRules.gd")
const LoadoutModel := preload("res://scripts/domain/Loadout.gd")
const LoadoutFactoryModel := preload("res://scripts/application/pvp/PvpLoadoutFactory.gd")
const StateProjector := preload("res://scripts/network/pvp/LanSeriesStateProjector.gd")

signal state_changed(state: Dictionary)
signal preparation_started(state: Dictionary)
signal loadout_revealed(state: Dictionary)
signal draft_updated(state: Dictionary)
signal round_ready(config: Dictionary)
signal round_finished(state: Dictionary)
signal series_finished(state: Dictionary)
signal failed(message: String)

var _transport: LanTransportLink = null
var _is_host := false
var _local_side := GameState.PLAYER_ONE
var _client_peer := 0
var _closed := false
var _rules: Dictionary = {}
var _series: SeriesState = null
var _phase := RulesModel.PHASE_RULES_READY
var _series_seed := 0
var _prep_id := ""
var _loadout_one: Loadout = null
var _loadout_two: Loadout = null
var _confirmed_one := false
var _confirmed_two := false
var _draft: DraftEngine = null
var _draft_deadline_ms := 0
var _client_draft: Dictionary = {}
var _client_chosen_step := -1
var _client_chosen := ""
var _local_profile: Dictionary = {}
var _remote_profile: Dictionary = {}
var _next_local := false
var _next_remote := false
var _rematch_local := false
var _rematch_remote := false
## Collaborateur conservé pour toute la série : ses index du catalogue sont
## réutilisés entre les manches au lieu d'être reconstruits à chaque fois.
var _loadout_factory: PvpLoadoutFactory = LoadoutFactoryModel.new()


## Branche la série sur la session déjà ouverte par le salon. `rules` doit être
## verrouillée par le salon ; le coordinateur ne modifie jamais la configuration.
func attach(transport: LanTransportLink, is_host: bool, local_side: int,
		client_peer: int, local_profile: Dictionary, remote_profile: Dictionary,
		rules: Dictionary, series_seed: int = 0) -> void:
	close()
	_closed = false
	_transport = transport
	_is_host = is_host
	_local_side = local_side
	_client_peer = client_peer
	_rules = RulesModel.normalized(rules)
	_rules["locked"] = true
	_series_seed = series_seed
	_local_profile = (local_profile as Dictionary).duplicate(true)
	_remote_profile = (remote_profile as Dictionary).duplicate(true)
	_transport.message_received.connect(_on_message)


## Destruction définitive : aucun état, aucun signal et aucune donnée de
## joueur ne doit rester derrière une sortie de série. Idempotent.
func close() -> void:
	_closed = true
	if _transport != null and _transport.message_received.is_connected(_on_message):
		_transport.message_received.disconnect(_on_message)
	_transport = null
	_series = null
	_phase = RulesModel.PHASE_RULES_READY
	_prep_id = ""
	_loadout_one = null
	_loadout_two = null
	_confirmed_one = false
	_confirmed_two = false
	_draft = null
	_draft_deadline_ms = 0
	_client_draft = {}
	_client_chosen_step = -1
	_client_chosen = ""
	_next_local = false
	_next_remote = false
	_rematch_local = false
	_rematch_remote = false
	_local_profile = {}
	_remote_profile = {}
	_rules = {}
	_series_seed = 0


## Abandonne la série courante mais conserve le transport, les profils et les
## règles : utilisé par une revanche ou un retour au salon connecté.
func reset_series() -> void:
	_series = null
	_phase = RulesModel.PHASE_RULES_READY
	_prep_id = ""
	_loadout_one = null
	_loadout_two = null
	_confirmed_one = false
	_confirmed_two = false
	_draft = null
	_draft_deadline_ms = 0
	_client_draft = {}
	_client_chosen_step = -1
	_client_chosen = ""
	_next_local = false
	_next_remote = false
	_rematch_local = false
	_rematch_remote = false


func rules() -> Dictionary:
	return _rules.duplicate(true)


func local_profile() -> Dictionary:
	return _local_profile.duplicate(true)


func remote_profile() -> Dictionary:
	return _remote_profile.duplicate(true)


func client_peer_id() -> int:
	return _client_peer


func is_host() -> bool:
	return _is_host


func local_side() -> int:
	return _local_side


func phase() -> String:
	return _phase


func series_id() -> String:
	return _series.series_id if _series != null else ""


func preparation_id() -> String:
	return _prep_id


func series() -> SeriesState:
	return _series


## ─── Hôte : démarrage et préparation ────────────────────────────────────────

func host_start_series() -> bool:
	if not _is_host or _transport == null or _series != null:
		return false
	var sid := "series-%d-%d" % [Time.get_ticks_usec(), _transport.local_peer_id()]
	_series = SeriesEngineModel.begin(sid, _rules, _series_seed if _series_seed != 0 else randi())
	_broadcast_series_state()
	return _prepare_round()


## L'hôte seul prépare la manche suivante, avec une nouvelle graine dérivée de
## la série et un nouvel identifiant de préparation.
func host_next_round() -> bool:
	if not _is_host or _series == null or _series.finished:
		return false
	if not _prepare_round():
		return false
	_next_local = false
	_next_remote = false
	return true


## Accord de manche suivante : les deux appareils doivent le demander. Le
## client envoie une demande au même format que le lancement de match ; l'hôte
## ne prépare rien tant que l'autre camp n'a pas confirmé.
func request_rematch() -> bool:
	if _series == null or _closed:
		return false
	if not _series.finished and _series.series_format != RulesModel.SERIES_FT1:
		return false
	if _rematch_local:
		return true
	_rematch_local = true
	if _is_host:
		if _rematch_remote:
			return host_rematch_series()
		return true
	if _transport == null:
		return false
	return _transport.send_to(LanProtocol.SERVER_ID, LanProtocol.KIND_START_REQUEST,
		{"match_id": "rematch-" + _series.series_id})


func request_next_round() -> bool:
	if _series == null or _series.finished or _closed:
		return false
	if _next_local:
		return true
	_next_local = true
	if _is_host:
		if _next_remote:
			return host_next_round()
		return true
	if _transport == null:
		return false
	return _transport.send_to(LanProtocol.SERVER_ID, LanProtocol.KIND_START_REQUEST,
		{"match_id": _series.series_id})


## Nouvelle série après une série terminée ou une égalité FT1. Les règles et
## les profils restent, mais l'identifiant de série et la graine changent.
## L'accord des deux camps est exigé via `request_rematch()`.
func host_rematch_series() -> bool:
	if not _is_host or _transport == null or _series == null:
		return false
	if not _series.finished and _series.series_format != RulesModel.SERIES_FT1:
		return false
	var sid := "series-%d-%d" % [Time.get_ticks_usec(), _transport.local_peer_id()]
	_series = SeriesEngineModel.begin(sid, _rules, randi())
	_rematch_local = false
	_rematch_remote = false
	_next_local = false
	_next_remote = false
	return _prepare_round()


func _prepare_round() -> bool:
	if _series == null:
		return false
	_confirmed_one = false
	_confirmed_two = false
	_loadout_one = null
	_loadout_two = null
	_draft = null
	_client_draft = {}
	_client_chosen_step = -1
	_client_chosen = ""
	_prep_id = "prep-%d-%d" % [_series.round_index, Time.get_ticks_usec()]
	_phase = RulesModel.PHASE_PREPARING
	match _series.mode:
		RulesModel.MODE_CLASSIC:
			_loadout_one = LoadoutFactoryModel.from_profile(
				_profile_for_side(GameState.PLAYER_ONE), GameState.PLAYER_ONE, _series, _prep_id)
			_loadout_two = LoadoutFactoryModel.from_profile(
				_profile_for_side(GameState.PLAYER_TWO), GameState.PLAYER_TWO, _series, _prep_id)
			if _loadout_one == null or _loadout_two == null:
				_fail("Le deck classique est invalide ou dépasse le budget.")
				return false
			SeriesEngineModel.remember_loadouts(_series, _loadout_one, _loadout_two)
			_prep_id = "prep-classic-%d" % _series.round_index
			# Le client doit d'abord créer son coordinateur et recevoir les
			# identifiants de série ; sans cela, son `round_start` serait rejeté.
			_send_prepare_start(0)
			_send_round_start()
			return true
		RulesModel.MODE_RANDOM:
			return _prepare_generated(false)
		RulesModel.MODE_MIRROR:
			return _prepare_generated(true)
		RulesModel.MODE_DRAFT:
			return _prepare_draft()
	return false


func _prepare_generated(mirror: bool) -> bool:
	var mode := RulesModel.MODE_MIRROR if mirror else RulesModel.MODE_RANDOM
	var result := _loadout_factory.generate(mode, _seed_for_round(), _series.power_tier)
	if not bool(result.get("ok", false)):
		_fail(str(result.get("reason", "Génération impossible.")))
		return false
	_loadout_one = LoadoutFactoryModel.wrap(result["loadout_one"], GameState.PLAYER_ONE,
		_series, _prep_id)
	_loadout_two = LoadoutFactoryModel.wrap(result["loadout_two"], GameState.PLAYER_TWO,
		_series, _prep_id)
	_phase = RulesModel.PHASE_LOADOUT_REVEAL
	_send_prepare_start(0)
	_send_loadout_to_side(GameState.PLAYER_ONE)
	_send_loadout_to_side(GameState.PLAYER_TWO)
	_emit_state()
	return true


func _prepare_draft() -> bool:
	var created := _loadout_factory.draft(_seed_for_round(), _series.power_tier,
		_profile_for_side(GameState.PLAYER_ONE), _profile_for_side(GameState.PLAYER_TWO),
		DraftModel.DEFAULT_DURATION_SECONDS)
	if not bool(created.get("ok", false)):
		_fail(str(created.get("reason", "Draft impossible.")))
		_draft = null
		return false
	_draft = created["draft"] as DraftEngine
	_phase = RulesModel.PHASE_PREPARING
	_draft_deadline_ms = _now_ms() + int(DraftModel.DEFAULT_DURATION_SECONDS * 1000.0)
	_send_prepare_start(_draft_deadline_ms)
	_send_draft_offers()
	_emit_state()
	return true


func _send_prepare_start(deadline_ms: int) -> void:
	var payload := {
		"series_id": _series.series_id,
		"preparation_id": _prep_id,
		"rules_revision": _series.rules_revision,
		"round_index": _series.round_index,
		"mode": _series.mode,
		"series": _series.series_format,
		"power_tier": _series.power_tier,
		"deadline_unix_ms": deadline_ms,
	}
	if _transport == null or not LanProtocol.validate(LanProtocol.KIND_PREPARE_START, payload)["ok"]:
		_fail("Message de préparation invalide.")
		return
	_transport.broadcast(LanProtocol.KIND_PREPARE_START, payload)
	preparation_started.emit(public_state())


func _send_loadout_to_side(side: int) -> void:
	var loadout := _loadout_for_side(side)
	if loadout == null:
		return
	if side == _local_side:
		# En draft, la première fin de deck ne doit pas faire passer la phase
		# globale en révélation : l'autre camp peut encore choisir.
		if _draft == null:
			_phase = RulesModel.PHASE_LOADOUT_REVEAL
		loadout_revealed.emit(public_state())
		_emit_state()
		return
	var payload := LoadoutFactoryModel.payload(loadout)
	var kind := LanProtocol.KIND_LOADOUT_REVEAL
	if _draft != null:
		kind = LanProtocol.KIND_DRAFT_FINISHED
	if _transport == null or not LanProtocol.validate(kind, payload)["ok"]:
		_fail("Loadout local invalide.")
		return
	_transport.send_to(_peer_for_side(side), kind, payload)


## Chaque destinataire reçoit les deux paires de **son** étape de draft. La
## progression réelle des deux camps reste dans le message, mais seules les
## offres projetées sont dévoilées : connaître la position adverse ne donne
## jamais accès à sa paire courante ni à son deck.
func _send_draft_offers() -> void:
	if not _is_host or _draft == null:
		return
	var remote_side := _remote_side()
	if not _draft.complete_for(remote_side):
		var payload := _draft_offers_payload(remote_side)
		if _transport == null \
				or not LanProtocol.validate(LanProtocol.KIND_DRAFT_OFFERS, payload)["ok"]:
			_fail("Offres de draft invalides.")
			return
		_transport.send_to(_peer_for_side(remote_side), LanProtocol.KIND_DRAFT_OFFERS, payload)
	draft_updated.emit(public_state())
	_emit_state()


func _draft_offers_payload(viewer_side: int) -> Dictionary:
	var view := _draft.public_state(viewer_side)
	return {
		"series_id": _series.series_id,
		"preparation_id": _prep_id,
		"rules_revision": _series.rules_revision,
		"round_index": _series.round_index,
		"step_one": _draft.step_for(GameState.PLAYER_ONE),
		"step_two": _draft.step_for(GameState.PLAYER_TWO),
		"complete_one": _draft.complete_for(GameState.PLAYER_ONE),
		"complete_two": _draft.complete_for(GameState.PLAYER_TWO),
		"viewer_side": viewer_side,
		"offers_step": int(view["offers_step"]),
		"offers_one": (view["offers_one"] as Array).duplicate(),
		"offers_two": (view["offers_two"] as Array).duplicate(),
		"deadline_unix_ms": _draft_deadline_ms,
	}


## Accusé privé : seul le camp concerné reçoit son deck en construction.
func _send_draft_progress(side: int) -> void:
	if _draft == null or side == _local_side or _transport == null:
		return
	var payload := _ids_payload()
	payload["own_step"] = _draft.step_for(side)
	payload["own_deck"] = _draft.deck(side)
	payload["own_complete"] = _draft.complete_for(side)
	if not LanProtocol.validate(LanProtocol.KIND_DRAFT_PROGRESS, payload)["ok"]:
		return
	_transport.send_to(_peer_for_side(side), LanProtocol.KIND_DRAFT_PROGRESS, payload)


## Construit le loadout d'un seul camp dès qu'il a terminé ses huit choix.
func _finish_draft_side(side: int) -> bool:
	if _draft == null or _loadout_for_side(side) != null:
		return _draft != null
	var god_id := str(_profile_for_side(side).get("god_id", ""))
	var loadout := LoadoutModel.create(god_id, _draft.deck(side), side,
		_series.series_id, _prep_id, _series.round_index, _series.rules_revision)
	if side == GameState.PLAYER_ONE:
		_loadout_one = loadout
	else:
		_loadout_two = loadout
	if _draft.is_complete():
		_phase = RulesModel.PHASE_LOADOUT_REVEAL
	_send_draft_progress(side)
	_send_loadout_to_side(side)
	_send_draft_offers()
	_emit_state()
	return true


## Fin autoritaire du temps : chaque camp est complété indépendamment. Un
## deck déjà terminé n'est jamais réinitialisé.
func _timeout_draft() -> void:
	if _draft == null:
		return
	for side in [GameState.PLAYER_ONE, GameState.PLAYER_TWO]:
		if _draft.complete_for(side):
			_finish_draft_side(side)
	if _draft.is_complete():
		_phase = RulesModel.PHASE_LOADOUT_REVEAL
	_send_draft_offers()
	_emit_state()


func _send_round_start() -> void:
	if _loadout_one == null or _loadout_two == null:
		_fail("Loadouts manquants.")
		return
	var config := _build_round_config()
	if not LanProtocol.validate(LanProtocol.KIND_ROUND_START, config)["ok"]:
		_fail("Configuration de manche invalide.")
		return
	_phase = RulesModel.PHASE_IN_MATCH
	if _transport != null:
		_transport.broadcast(LanProtocol.KIND_ROUND_START, config)
	round_ready.emit(config)
	_emit_state()


func _build_round_config() -> Dictionary:
	return {
		"match_id": "round-%s-%d" % [_series.series_id, _series.round_index],
		"seed": randi(),
		"blocked_cells": BoardSetupGenerator.generate(),
		"starting_player": BoardSetupGenerator.draw_first_player(),
		"participants": [
			{
				"peer_id": _peer_for_side(GameState.PLAYER_ONE),
				"side": GameState.PLAYER_ONE,
				"name": str(_profile_for_side(GameState.PLAYER_ONE).get("name", "Joueur 1")),
				"god_id": _loadout_one.god_id,
				"deck": _loadout_one.deck.duplicate(),
			},
			{
				"peer_id": _peer_for_side(GameState.PLAYER_TWO),
				"side": GameState.PLAYER_TWO,
				"name": str(_profile_for_side(GameState.PLAYER_TWO).get("name", "Joueur 2")),
				"god_id": _loadout_two.god_id,
				"deck": _loadout_two.deck.duplicate(),
			},
		],
		"series_id": _series.series_id,
		"rules_revision": _series.rules_revision,
		"preparation_id": _prep_id,
		"round_index": _series.round_index,
		"mode": _series.mode,
		"series": _series.series_format,
		"power_tier": _series.power_tier,
	}


## ─── Hôte : confirmations et choix ──────────────────────────────────────────

func _confirm_side(side: int) -> bool:
	if _phase != RulesModel.PHASE_PREPARING \
			and _phase != RulesModel.PHASE_LOADOUT_REVEAL \
			and _phase != RulesModel.PHASE_LOADOUT_READY:
		return false
	if _loadout_for_side(side) == null or _confirmed_for(side):
		return false
	_set_confirmed(side, true)
	if _transport != null:
		var payload := _ids_payload()
		payload["side"] = side
		payload["ready"] = true
		if LanProtocol.validate(LanProtocol.KIND_LOADOUT_READY, payload)["ok"]:
			_transport.broadcast(LanProtocol.KIND_LOADOUT_READY, payload)
	_emit_state()
	if _confirmed_for(GameState.PLAYER_ONE) and _confirmed_for(GameState.PLAYER_TWO):
		_phase = RulesModel.PHASE_LOADOUT_READY
		_send_round_start()
	return true


func _choose_side(side: int, stone_id: String) -> bool:
	if _draft == null or _draft.complete_for(side):
		return false
	var result := _draft.choose(side, stone_id)
	if not bool(result.get("ok", false)):
		return false
	if _draft.complete_for(side):
		return _finish_draft_side(side)
	_send_draft_progress(side)
	_send_draft_offers()
	return true


func host_record_round(winner: int, score_one: int, score_two: int) -> bool:
	if not _is_host or _series == null:
		return false
	if _phase != RulesModel.PHASE_IN_MATCH:
		return false
	var old_round := _series.round_index
	var result := SeriesEngineModel.record_round(_series, winner, score_one, score_two)
	if not bool(result.get("ok", false)):
		_fail(str(result.get("reason", "Résultat de manche invalide.")))
		return false
	_phase = RulesModel.PHASE_ROUND_RESULT
	var payload := {
		"series_id": _series.series_id,
		"preparation_id": _prep_id,
		"rules_revision": _series.rules_revision,
		"round_index": old_round,
		"winner": winner,
		"score_one": score_one,
		"score_two": score_two,
		"wins_one": _series.wins_one,
		"wins_two": _series.wins_two,
		"ties": _series.ties,
		"finished": _series.finished,
		"series_winner": _series.winner,
		"next_round_index": _series.round_index,
	}
	if _transport == null or not LanProtocol.validate(LanProtocol.KIND_ROUND_RESULT, payload)["ok"]:
		_fail("Résultat de série invalide.")
		return false
	_transport.broadcast(LanProtocol.KIND_ROUND_RESULT, payload)
	_broadcast_series_state()
	if _series.finished:
		_phase = RulesModel.PHASE_SERIES_COMPLETE
	round_finished.emit(public_state())
	if _series.finished:
		series_finished.emit(public_state())
	_emit_state()
	return true


## ─── API locale (identique pour l'hôte et le client) ────────────────────────

func confirm_local() -> bool:
	if _closed:
		return false
	if _is_host:
		return _confirm_side(_local_side)
	if _phase != RulesModel.PHASE_PREPARING \
			and _phase != RulesModel.PHASE_LOADOUT_REVEAL \
			and _phase != RulesModel.PHASE_LOADOUT_READY:
		return false
	if _loadout_for_side(_local_side) == null or _confirmed_for(_local_side):
		return false
	_set_confirmed(_local_side, true)
	if _transport == null or not _transport.send_to(LanProtocol.SERVER_ID,
			LanProtocol.KIND_LOADOUT_CONFIRM, _ids_payload()):
		return false
	_emit_state()
	return true


func choose_local(stone_id: String) -> bool:
	if _closed:
		return false
	if _is_host:
		return _choose_side(_local_side, stone_id)
	if _client_draft.is_empty() or bool(_client_draft.get("own_complete", false)):
		return false
	var step := int(_client_draft.get("own_step", -1))
	if _client_chosen_step == step:
		return false
	var offers := _offers_for_client(_local_side)
	if not offers.has(stone_id):
		return false
	var payload := _ids_payload()
	payload["own_step"] = step
	payload["stone_id"] = stone_id
	if _transport == null or not _transport.send_to(LanProtocol.SERVER_ID,
			LanProtocol.KIND_DRAFT_CHOICE, payload):
		return false
	_client_chosen_step = step
	_client_chosen = stone_id
	return true


## Le client reçoit la deadline autoritaire ; cette méthode ne sert qu'à
## l'affichage. La complétion réelle appartient au `poll()` de l'hôte.
func poll(delta: float) -> void:
	if not _is_host or _draft == null or _draft.is_complete():
		return
	if _draft.advance(delta):
		_timeout_draft()


## ─── Réception réseau ───────────────────────────────────────────────────────

func _on_message(from_peer: int, kind: String, payload: Dictionary) -> void:
	if _closed or _transport == null:
		return
	if _is_host:
		if from_peer != _client_peer:
			return
	else:
		if from_peer != LanProtocol.SERVER_ID:
			return
	if not LanProtocol.validate(kind, payload)["ok"]:
		return
	match kind:
		LanProtocol.KIND_PREPARE_START:
			if not _is_host:
				_on_prepare_start(payload)
		LanProtocol.KIND_LOADOUT_REVEAL:
			if not _is_host:
				_on_loadout(payload)
		LanProtocol.KIND_DRAFT_FINISHED:
			if not _is_host:
				_on_loadout(payload)
		LanProtocol.KIND_DRAFT_OFFERS:
			if not _is_host:
				_on_draft_offers(payload)
		LanProtocol.KIND_DRAFT_PROGRESS:
			if not _is_host:
				_on_draft_progress(payload)
		LanProtocol.KIND_LOADOUT_READY:
			if not _is_host:
				_on_loadout_ready(payload)
		LanProtocol.KIND_LOADOUT_CONFIRM:
			if _is_host:
				_on_confirm(payload)
		LanProtocol.KIND_DRAFT_CHOICE:
			if _is_host:
				_on_draft_choice(payload)
		LanProtocol.KIND_ROUND_START:
			if not _is_host:
				_on_round_start(payload)
		LanProtocol.KIND_ROUND_RESULT:
			if not _is_host:
				_on_round_result(payload)
		LanProtocol.KIND_SERIES_STATE:
			if not _is_host:
				_on_series_state(payload)
		LanProtocol.KIND_START_REQUEST:
			if _is_host:
				_on_next_request(payload)
		_:
			pass


func _on_prepare_start(payload: Dictionary) -> void:
	if _series != null and not _series_ids_match(payload):
		if not _accepts_new_series(payload):
			return
		_reset_for_new_series(payload)
	if _series == null:
		_reset_for_new_series(payload)
	_series.round_index = int(payload.get("round_index", 1))
	_series.rules_revision = int(payload.get("rules_revision", 0))
	_rules["revision"] = _series.rules_revision
	_prep_id = str(payload.get("preparation_id", ""))
	# L'échéance appartient à la préparation autoritaire. Le client doit la
	# conserver dès le premier message, avant même l'arrivée des offres.
	_draft_deadline_ms = int(payload.get("deadline_unix_ms", 0))
	# Une nouvelle préparation invalide les confirmations et les demandes de
	# manche précédentes : chaque manche exige un accord et deux confirmations.
	_confirmed_one = false
	_confirmed_two = false
	_next_local = false
	_next_remote = false
	_loadout_one = null
	_loadout_two = null
	_phase = RulesModel.PHASE_PREPARING
	preparation_started.emit(public_state())
	_emit_state()


func _on_loadout(payload: Dictionary) -> void:
	if not _ids_match(payload, false):
		return
	var side := _local_side
	var loadout := LoadoutFactoryModel.from_payload(payload, side)
	if loadout == null:
		return
	if side == GameState.PLAYER_ONE:
		_loadout_one = loadout
	else:
		_loadout_two = loadout
	if not _client_draft.is_empty():
		_client_draft["own_complete"] = true
		_client_draft["own_step"] = DeckRules.DECK_SIZE
		_client_draft["step"] = DeckRules.DECK_SIZE
		_client_draft["own_deck"] = loadout.deck.duplicate()
		_client_draft["complete"] = bool(_client_draft.get("complete_one", false)) \
			and bool(_client_draft.get("complete_two", false))
	if _draft == null:
		_phase = RulesModel.PHASE_LOADOUT_REVEAL
	else:
		_phase = RulesModel.PHASE_LOADOUT_REVEAL if _client_draft.get("complete", false) \
			else RulesModel.PHASE_PREPARING
	loadout_revealed.emit(public_state())
	_emit_state()


func _on_draft_offers(payload: Dictionary) -> void:
	if not _ids_match(payload, false):
		return
	if int(payload.get("viewer_side", 0)) != _local_side:
		return
	# Chaque nouvelle paire resynchronise le compte à rebours du client sans
	# nécessiter un paquet réseau par seconde.
	_draft_deadline_ms = int(payload.get("deadline_unix_ms", _draft_deadline_ms))
	var step_one := int(payload.get("step_one", 0))
	var step_two := int(payload.get("step_two", 0))
	var complete_one := bool(payload.get("complete_one", false))
	var complete_two := bool(payload.get("complete_two", false))
	var own_step := step_one if _local_side == GameState.PLAYER_ONE else step_two
	var other_step := step_two if _local_side == GameState.PLAYER_ONE else step_one
	var offers_step := int(payload.get("offers_step", -1))
	if offers_step != own_step:
		return
	if not _client_draft.is_empty() and own_step < int(_client_draft.get("own_step", 0)):
		return
	if own_step != _client_chosen_step:
		_client_chosen_step = -1
		_client_chosen = ""
	var own_deck: Array = []
	if not _client_draft.is_empty():
		own_deck = (_client_draft.get("own_deck", []) as Array).duplicate()
	_client_draft = {
		"started": true,
		"complete": complete_one and complete_two,
		"complete_one": complete_one,
		"complete_two": complete_two,
		"step_one": step_one,
		"step_two": step_two,
		"step": own_step,
		"own_step": own_step,
		"opponent_step": other_step,
		"offers_step": offers_step,
		"own_complete": complete_one if _local_side == GameState.PLAYER_ONE else complete_two,
		"opponent_complete": complete_two if _local_side == GameState.PLAYER_ONE else complete_one,
		"total_steps": DeckRules.DECK_SIZE,
		"cost_quarters": _offer_cost_from_payload(payload, _local_side),
		"offers_one": (payload.get("offers_one", []) as Array).duplicate(true),
		"offers_two": (payload.get("offers_two", []) as Array).duplicate(true),
		"own_deck": own_deck,
		"locked_one": false,
		"locked_two": false,
		"deadline_unix_ms": int(payload.get("deadline_unix_ms", 0)),
	}
	_phase = RulesModel.PHASE_LOADOUT_REVEAL if bool(_client_draft["complete"]) \
		else RulesModel.PHASE_PREPARING
	draft_updated.emit(public_state())
	_emit_state()


## Accusé privé du deck en construction : jamais diffusé à l'autre camp.
func _on_draft_progress(payload: Dictionary) -> void:
	if not _ids_match(payload, false) or _client_draft.is_empty():
		return
	var own_step := int(payload.get("own_step", -1))
	if own_step < int(_client_draft.get("own_step", 0)):
		return
	var deck: Array = (payload.get("own_deck", []) as Array).duplicate(true)
	if deck.size() != own_step:
		return
	_client_draft["own_step"] = own_step
	_client_draft["step"] = own_step
	_client_draft["own_deck"] = deck
	_client_draft["own_complete"] = bool(payload.get("own_complete", false))
	if own_step != _client_chosen_step:
		_client_chosen_step = -1
		_client_chosen = ""
	draft_updated.emit(public_state())
	_emit_state()


func _offer_cost_from_payload(payload: Dictionary, side: int) -> int:
	var offers: Variant = payload.get("offers_one") if side == GameState.PLAYER_ONE \
		else payload.get("offers_two")
	if not offers is Array or (offers as Array).is_empty():
		return 0
	var first := str((offers as Array)[0])
	return StoneLoader.get_stone(first).get("cost_q", 0)


func _on_loadout_ready(payload: Dictionary) -> void:
	if not _ids_match(payload, false):
		return
	_set_confirmed(int(payload.get("side", 0)), bool(payload.get("ready", false)))
	_emit_state()


func _on_confirm(payload: Dictionary) -> void:
	if not _ids_match(payload, false):
		return
	_confirm_side(_remote_side())


func _on_draft_choice(payload: Dictionary) -> void:
	if not _ids_match(payload, false):
		return
	var side := _remote_side()
	if _draft == null or int(payload.get("own_step", -1)) != _draft.step_for(side):
		return
	_choose_side(side, str(payload.get("stone_id", "")))


func _on_round_start(payload: Dictionary) -> void:
	if _series != null and str(payload.get("series_id", "")) != _series.series_id:
		if not _accepts_new_series(payload):
			return
		_reset_for_new_series(payload)
		_prep_id = str(payload.get("preparation_id", ""))
	if not _ids_match(payload, false):
		return
	_phase = RulesModel.PHASE_IN_MATCH
	round_ready.emit(payload.duplicate(true))
	_emit_state()


func _on_round_result(payload: Dictionary) -> void:
	if not _ids_match(payload, false):
		return
	if _series == null:
		return
	_series.wins_one = int(payload.get("wins_one", 0))
	_series.wins_two = int(payload.get("wins_two", 0))
	_series.ties = int(payload.get("ties", 0))
	_series.round_index = int(payload.get("next_round_index", _series.round_index))
	_series.finished = bool(payload.get("finished", false))
	_series.winner = int(payload.get("series_winner", GameState.PLAYER_NONE))
	_phase = RulesModel.PHASE_SERIES_COMPLETE if _series.finished else RulesModel.PHASE_ROUND_RESULT
	round_finished.emit(public_state())
	if _series.finished:
		series_finished.emit(public_state())
	_emit_state()


func _on_next_request(payload: Dictionary) -> void:
	if _series == null:
		return
	var requested := str(payload.get("match_id", ""))
	if requested == "rematch-" + _series.series_id:
		if not _series.finished and _series.series_format != RulesModel.SERIES_FT1:
			return
		_rematch_remote = true
		if _rematch_local:
			host_rematch_series()
		return
	if requested != _series.series_id:
		return
	_next_remote = true
	if _next_local:
		host_next_round()


## Le client n'accepte un nouvel identifiant de série que s'il a lui-même
## demandé la revanche et que l'ancienne série est finie (ou FT1, qui peut
## rejouer après une égalité). Un ancien `prepare_start` reste donc ignoré.
func _accepts_new_series(payload: Dictionary) -> bool:
	if _series == null:
		return true
	if str(payload.get("series_id", "")) == _series.series_id:
		return true
	if not _rematch_local:
		return false
	return _series.finished or _series.series_format == RulesModel.SERIES_FT1


func _reset_for_new_series(payload: Dictionary) -> void:
	var rules := RulesModel.normalized({
		"mode": str(payload.get("mode", RulesModel.MODE_CLASSIC)),
		"series": str(payload.get("series", RulesModel.SERIES_FT1)),
		"power_tier": int(payload.get("power_tier", RulesModel.DEFAULT_POWER_TIER)),
		"revision": int(payload.get("rules_revision", 0)),
		"locked": true,
	})
	_series = SeriesStateModel.create(str(payload.get("series_id", "")), rules, 0)
	_series.round_index = int(payload.get("round_index", 1))
	_series.rules_revision = int(payload.get("rules_revision", 0))
	_rules = rules
	_rules["revision"] = _series.rules_revision
	_prep_id = ""
	_loadout_one = null
	_loadout_two = null
	_confirmed_one = false
	_confirmed_two = false
	_draft = null
	_draft_deadline_ms = 0
	_client_draft = {}
	_client_chosen_step = -1
	_client_chosen = ""
	_next_local = false
	_next_remote = false
	_rematch_local = false
	_rematch_remote = false
	_phase = RulesModel.PHASE_PREPARING


func _on_series_state(payload: Dictionary) -> void:
	if _series != null and str(payload.get("series_id", "")) != _series.series_id:
		return
	var restored := SeriesStateModel.from_dict(payload)
	if restored == null:
		return
	_series = restored
	_rules["revision"] = _series.rules_revision
	_phase = RulesModel.PHASE_SERIES_COMPLETE if _series.finished \
		else (RulesModel.PHASE_ROUND_RESULT if _series.wins_one + _series.wins_two + _series.ties > 0
			else _phase)
	_emit_state()


## ─── Vues et utilitaires ────────────────────────────────────────────────────

func public_state() -> Dictionary:
	return StateProjector.build(_phase, _is_host, _local_side, _rules, _series,
		_prep_id, _loadout_one, _loadout_two, _confirmed_one, _confirmed_two,
		_draft if _is_host else null, _client_draft, _client_chosen,
		_draft_deadline_ms, _remaining_seconds())


## Valeur vivante destinée à l'affichage. Le contrôleur ne doit pas relire un
## ancien snapshot, sinon le texte ne change qu'au prochain événement réseau.
func remaining_seconds() -> float:
	return _remaining_seconds()


func _remaining_seconds() -> float:
	if _draft_deadline_ms <= 0:
		return 0.0
	if _is_host and _draft != null:
		return _draft.remaining_seconds()
	var remaining_ms := _draft_deadline_ms - _now_ms()
	return maxf(0.0, float(remaining_ms) / 1000.0)


func _ids_payload() -> Dictionary:
	return {
		"series_id": series_id(),
		"preparation_id": _prep_id,
		"rules_revision": int(_rules.get("revision", 0)),
		"round_index": _series.round_index if _series != null else 1,
	}


func _series_ids_match(payload: Dictionary) -> bool:
	if _series == null:
		return false
	return str(payload.get("series_id", "")) == _series.series_id \
		and int(payload.get("rules_revision", -1)) == _series.rules_revision \
		and int(payload.get("round_index", -1)) == _series.round_index


func _ids_match(payload: Dictionary, allow_new_series: bool) -> bool:
	var payload_series := str(payload.get("series_id", ""))
	if _series != null and payload_series != _series.series_id:
		return false
	if _series == null and not allow_new_series:
		return false
	if _series != null and int(payload.get("rules_revision", -1)) != _series.rules_revision:
		return false
	if _series != null and int(payload.get("round_index", -1)) != _series.round_index:
		return false
	if _series != null and str(payload.get("preparation_id", "")) != _prep_id:
		return false
	return true


func _broadcast_series_state() -> void:
	if _series == null or _transport == null:
		return
	var payload := SeriesEngineModel.public_state(_series)
	if LanProtocol.validate(LanProtocol.KIND_SERIES_STATE, payload)["ok"]:
		_transport.broadcast(LanProtocol.KIND_SERIES_STATE, payload)


func _profile_for_side(side: int) -> Dictionary:
	return _local_profile if side == _local_side else _remote_profile


func _loadout_for_side(side: int) -> Loadout:
	return _loadout_one if side == GameState.PLAYER_ONE else _loadout_two


func _remote_side() -> int:
	return GameState.PLAYER_TWO if _local_side == GameState.PLAYER_ONE else GameState.PLAYER_ONE


func _confirmed_for(side: int) -> bool:
	return _confirmed_one if side == GameState.PLAYER_ONE else _confirmed_two


func _set_confirmed(side: int, value: bool) -> void:
	if side == GameState.PLAYER_ONE:
		_confirmed_one = value
	elif side == GameState.PLAYER_TWO:
		_confirmed_two = value


func _peer_for_side(side: int) -> int:
	if _is_host:
		return LanProtocol.SERVER_ID if side == GameState.PLAYER_ONE else _client_peer
	return _transport.local_peer_id() if side == _local_side else LanProtocol.SERVER_ID


func _offers_for_client(side: int) -> Array:
	var offers: Variant = _client_draft.get("offers_one") if side == GameState.PLAYER_ONE \
		else _client_draft.get("offers_two")
	return (offers as Array).duplicate() if offers is Array else []


func _client_own_deck() -> Array:
	return (_client_draft.get("own_deck", []) as Array).duplicate(true) if not _client_draft.is_empty() else []


func _seed_for_round() -> int:
	return _series.seed + _series.round_index * 104729


func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


func _emit_state() -> void:
	state_changed.emit(public_state())


func _fail(message: String) -> void:
	failed.emit(message)
