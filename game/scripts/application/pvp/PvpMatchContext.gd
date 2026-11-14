## PvpMatchContext.gd — AutoLoad applicatif
## Données transitoires du match PVP local. Rien n'est sauvegardé ici : aucun
## champ du profil du joueur n'est lu pour écrire, et aucune statistique de
## campagne n'est enregistrée par ce mode.
##
## Un seul match vit à la fois ; `clear()` le termine. Le contexte est rempli
## par le salon après validation complète de la configuration de l'hôte.
extends Node

## Cycle de vie explicite : une scène ne devine plus l'écran à afficher à
## partir d'un dictionnaire résiduel. `LOBBY_RETURN` couvre uniquement le
## retour connecté au salon, avec le lien et les profils conservés.
enum Stage { NONE, PREPARATION, MATCH, RESULT, LOBBY_RETURN }
var stage: Stage = Stage.NONE
## Règles verrouillées de la partie, conservées pour un retour au salon.
var match_rules: Dictionary = {}
## Données transitoires du retour connecté, consommées une seule fois par le
## salon. Elles ne survivent jamais à une nouvelle entrée ordinaire.
var lobby_resume: Dictionary = {}

## Configuration validée du match en cours.
var match_id: String = ""
var generation_seed: int = 1
var blocked_cells: Array = []
var starting_player: int = GameState.PLAYER_ONE
var participants: Array = []
## Association peer_id -> PLAYER_ONE / PLAYER_TWO.
var peer_sides: Dictionary = {}
## Configuration brute validée : rejouée telle quelle quand les deux appareils
## confirment le lancement après le pile ou face.
var raw_config: Dictionary = {}
## Camp de cet appareil et identifiant réseau local.
var local_side: int = GameState.PLAYER_ONE
var local_peer_id: int = 0
## Profils échangés pendant la poignée de main (pseudo, dieu et deck).
## Les snapshots du salon restent immuables pendant la série. Les champs
## `local_*` et `remote_*` ci-dessous décrivent, eux, le loadout autoritaire de
## la manche courante et peuvent donc contenir un dieu ou un deck généré.
var _lobby_local_profile: Dictionary = {}
var _lobby_remote_profile: Dictionary = {}
var local_name: String = ""
var local_god_id: String = ""
var local_deck: Array = []
var remote_name: String = ""
var remote_god_id: String = ""
var remote_deck: Array = []
## Suivi de partie : mis à jour par le coordinateur réseau, jamais sauvegardé.
var turn_number: int = 0
var last_result: Dictionary = {}
## Série en cours : score public, loadout local et objets de session gardés
## vivants entre le salon, les manches et l'écran de résultat.
var series_public: Dictionary = {}
var local_loadout: Dictionary = {}
var preparation_id: String = ""
var round_index: int = 1
var series_flow: RefCounted = null
var series_link: RefCounted = null
## Présence PVP persistante : elle survit aux changements de scène et au
## nettoyage de la série tant que la connexion ENet reste ouverte.
var _presence_session := PvpPresenceSession.new()
var presence: RefCounted:
	get: return _presence_session.value
	set(value): _presence_session.adopt(value)


func is_active() -> bool:
	return match_id != ""


## Remplit le contexte depuis la configuration validée de l'hôte.
func begin(match_config: Dictionary, side: int, peer_id: int,
		local_snapshot: Dictionary, remote_snapshot: Dictionary,
		preserve_series: bool = false, rules: Dictionary = {}) -> void:
	var saved_lobby_local := _lobby_local_profile.duplicate(true) if preserve_series else {}
	var saved_lobby_remote := _lobby_remote_profile.duplicate(true) if preserve_series else {}
	if saved_lobby_local.is_empty():
		saved_lobby_local = _profile_snapshot(local_snapshot)
	if saved_lobby_remote.is_empty():
		saved_lobby_remote = _profile_snapshot(remote_snapshot)
	var saved_series := series_public.duplicate(true) if preserve_series else {}
	var saved_loadout := local_loadout.duplicate(true) if preserve_series else {}
	var saved_preparation := preparation_id if preserve_series else ""
	var saved_round := round_index if preserve_series else 1
	var saved_flow: RefCounted = series_flow if preserve_series else null
	var saved_link: RefCounted = series_link if preserve_series else null
	var saved_rules := match_rules.duplicate(true) if preserve_series else {}
	clear()
	stage = Stage.MATCH
	_set_lobby_profiles(saved_lobby_local, saved_lobby_remote)
	match_rules = rules.duplicate(true) if not rules.is_empty() else saved_rules
	series_public = saved_series
	local_loadout = saved_loadout
	preparation_id = saved_preparation
	round_index = saved_round
	series_flow = saved_flow
	series_link = saved_link
	raw_config = match_config.duplicate(true)
	match_id = str(match_config.get("match_id", ""))
	generation_seed = int(match_config.get("seed", 1))
	blocked_cells = (match_config.get("blocked_cells", []) as Array).duplicate()
	starting_player = int(match_config.get("starting_player", GameState.PLAYER_ONE))
	local_side = side
	local_peer_id = peer_id
	participants = []
	peer_sides = {}
	for entry in match_config.get("participants", []):
		var participant: Dictionary = (entry as Dictionary).duplicate(true)
		participants.append(participant)
		peer_sides[int(participant.get("peer_id", 0))] = int(participant.get("side", 0))
	# La configuration de manche est autoritaire : en Aléatoire et Miroir, ses
	# participants portent le dieu et le deck générés. Les profils du salon ne
	# sont que des replis pour les anciennes configurations sans participants.
	var configured_local := participant_for_side(local_side)
	var configured_remote := participant_for_side(remote_side())
	_apply_profiles(
		configured_local if not configured_local.is_empty() else local_snapshot,
		configured_remote if not configured_remote.is_empty() else remote_snapshot
	)
	turn_number = 0
	last_result = {}


## Entre dans la scène de préparation avant qu'un match ne soit configuré :
## les deux profils, le camp et le lien ENet restent vivants. Aucun deck
## adverse n'est copié dans la vue locale ; il ne sert qu'à configurer le camp.
func begin_preparation(flow: RefCounted, link: RefCounted, side: int,
		local_peer: int, remote_peer: int, local_snapshot: Dictionary,
		remote_snapshot: Dictionary, rules: Dictionary, state: Dictionary) -> void:
	clear()
	stage = Stage.PREPARATION
	_set_lobby_profiles(local_snapshot, remote_snapshot)
	series_flow = flow
	series_link = link
	local_side = side
	local_peer_id = local_peer
	local_name = str(local_snapshot.get("name", "Joueur"))
	local_god_id = str(local_snapshot.get("god_id", ""))
	local_deck = (local_snapshot.get("deck", []) as Array).duplicate()
	remote_name = str(remote_snapshot.get("name", "Adversaire"))
	remote_god_id = str(remote_snapshot.get("god_id", ""))
	remote_deck = (remote_snapshot.get("deck", []) as Array).duplicate()
	match_id = str(state.get("series_id", ""))
	match_rules = rules.duplicate(true)
	participants = [
		_participant(local_peer, side, local_snapshot),
		_participant(remote_peer, remote_side(), remote_snapshot),
	]
	peer_sides = {local_peer: side, remote_peer: remote_side()}
	set_series(state)


static func _participant(peer_id: int, side: int, profile: Dictionary) -> Dictionary:
	return {
		"peer_id": peer_id,
		"side": side,
		"name": str(profile.get("name", "Joueur")),
		"god_id": str(profile.get("god_id", "")),
		"deck": (profile.get("deck", []) as Array).duplicate(),
	}


func _apply_profiles(local_snapshot: Dictionary, remote_snapshot: Dictionary) -> void:
	local_name = str(local_snapshot.get("name", "Joueur"))
	local_god_id = str(local_snapshot.get("god_id", ""))
	local_deck = (local_snapshot.get("deck", []) as Array).duplicate()
	remote_name = str(remote_snapshot.get("name", "Adversaire"))
	remote_god_id = str(remote_snapshot.get("god_id", ""))
	remote_deck = (remote_snapshot.get("deck", []) as Array).duplicate()


func _set_lobby_profiles(local_snapshot: Dictionary, remote_snapshot: Dictionary) -> void:
	_lobby_local_profile = _profile_snapshot(local_snapshot)
	_lobby_remote_profile = _profile_snapshot(remote_snapshot)


static func _profile_snapshot(profile: Dictionary) -> Dictionary:
	if profile.is_empty():
		return {}
	return {
		"name": str(profile.get("name", "Joueur")),
		"god_id": str(profile.get("god_id", "")),
		"deck": (profile.get("deck", []) as Array).duplicate(true),
	}


## Termine les données de match mais conserve volontairement la présence :
## c'est elle qui porte le statut EN PARTIE pendant un retour au salon
## individuel. `close_presence()` est réservé à une vraie fermeture de session.
func clear() -> void:
	raw_config = {}
	match_id = ""
	generation_seed = 1
	blocked_cells = []
	starting_player = GameState.PLAYER_ONE
	participants = []
	peer_sides = {}
	_lobby_local_profile = {}
	_lobby_remote_profile = {}
	local_side = GameState.PLAYER_ONE
	local_peer_id = 0
	local_name = ""
	local_god_id = ""
	local_deck = []
	remote_name = ""
	remote_god_id = ""
	remote_deck = []
	turn_number = 0
	last_result = {}
	series_public = {}
	local_loadout = {}
	preparation_id = ""
	round_index = 1
	series_flow = null
	series_link = null
	stage = Stage.NONE
	match_rules = {}
	lobby_resume = {}


## Conserve la série et le lien réseau au-delà du salon. Le flux de série
## possède déjà son propre branchement au transport ; le contexte en garde une
## référence pour l'écran de résultat et les manches suivantes.
func keep_series(flow: RefCounted, link: RefCounted) -> void:
	series_flow = flow
	series_link = link


func set_series(state: Dictionary) -> void:
	series_public = (state.get("series", {}) as Dictionary).duplicate(true)
	local_loadout = (state.get("own_loadout", {}) as Dictionary).duplicate(true)
	preparation_id = str(state.get("preparation_id", ""))
	round_index = int(state.get("round_index", 1))
	var phase := str(state.get("phase", ""))
	if phase == MatchRules.PHASE_PREPARING or phase == MatchRules.PHASE_LOADOUT_REVEAL \
			or phase == MatchRules.PHASE_LOADOUT_READY:
		stage = Stage.PREPARATION
	elif phase == MatchRules.PHASE_IN_MATCH:
		stage = Stage.MATCH
	elif phase == MatchRules.PHASE_ROUND_RESULT or phase == MatchRules.PHASE_SERIES_COMPLETE:
		stage = Stage.RESULT


## Marque le résultat sans dépendre d'un dictionnaire de série non vide.
func mark_result() -> void:
	stage = Stage.RESULT


## Données du retour connecté au salon. Le lien ENet reste le même ; le salon
## le reprendra avec un coordinateur neuf, sans recréer de session.
func set_lobby_resume(data: Dictionary) -> void:
	lobby_resume = data.duplicate(true)
	stage = Stage.LOBBY_RETURN


## Installe ou réutilise la présence sur le lien conservé. Le pair distant est
## toujours connu par le salon ou par la série ; le contexte ne le devine pas.
func ensure_presence(link: RefCounted, remote_peer: int) -> RefCounted:
	return _presence_session.ensure(link, remote_peer)


func set_presence(value: String) -> bool:
	return _presence_session.set_local(value)


func close_presence() -> void:
	_presence_session.close()


## Consomme le retour une seule fois : un ancien état ne peut pas rouvrir un
## salon déjà quitté.
func take_lobby_resume() -> Dictionary:
	var data := lobby_resume.duplicate(true)
	lobby_resume = {}
	return data


func has_series() -> bool:
	return not series_public.is_empty() and series_flow != null


func is_simple_result() -> bool:
	return series_public.is_empty() or str(series_public.get("series", "")) == MatchRules.SERIES_FT1


func series_finished() -> bool:
	return bool(series_public.get("finished", false))


func series_mode() -> String:
	return str(series_public.get("mode", ""))


func series_format() -> String:
	return str(series_public.get("series", ""))


func series_wins(side: int) -> int:
	return int(series_public.get("wins_one" if side == GameState.PLAYER_ONE else "wins_two", 0))


func release_series() -> Dictionary:
	var released := {"flow": series_flow, "link": series_link}
	series_flow = null
	series_link = null
	return released


## La configuration validée, prête à être rediffusée sur `match_start`.
func config() -> Dictionary:
	return raw_config.duplicate(true)


func side_of_peer(peer_id: int) -> int:
	return int(peer_sides.get(peer_id, GameState.PLAYER_NONE))


func peer_of_side(side: int) -> int:
	for peer_id in peer_sides:
		if int(peer_sides[peer_id]) == side:
			return int(peer_id)
	return 0


func remote_side() -> int:
	return GameState.PLAYER_TWO if local_side == GameState.PLAYER_ONE else GameState.PLAYER_ONE


func participant_for_side(side: int) -> Dictionary:
	for entry in participants:
		if int((entry as Dictionary).get("side", 0)) == side:
			return (entry as Dictionary).duplicate(true)
	return {}


func deck_of_side(side: int) -> Array:
	var participant := participant_for_side(side)
	return (participant.get("deck", []) as Array).duplicate()


func local_profile() -> Dictionary:
	return {"name": local_name, "god_id": local_god_id, "deck": local_deck.duplicate()}


func remote_profile() -> Dictionary:
	return {"name": remote_name, "god_id": remote_god_id, "deck": remote_deck.duplicate()}


## Profils originaux de la connexion au salon. Ces accès ne retournent jamais
## les participants générés d'une manche Aléatoire, Miroir ou Sélection.
func lobby_local_profile() -> Dictionary:
	return _lobby_local_profile.duplicate(true)


func lobby_remote_profile() -> Dictionary:
	return _lobby_remote_profile.duplicate(true)


func record_result(winner: int, score_one: int, score_two: int) -> void:
	last_result = {"winner": winner, "score_one": score_one, "score_two": score_two}
