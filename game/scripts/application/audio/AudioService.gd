## Service audio unique du jeu.
##
## Il possède les bus, le pool de lectures courtes, les deux lecteurs de
## musique et le branchement automatique des boutons. Les écrans ne parlent
## jamais directement à AudioServer : ils demandent un identifiant du
## catalogue, ou posent une métadonnée sur un bouton.
##
## La musique suit la scène courante sans qu'aucun écran n'ait à l'annoncer.
extends Node

const Catalog := preload("res://scripts/application/audio/AudioCatalog.gd")

const SFX_POOL_SIZE := 10
const MUSIC_FADE_SECONDS := 0.8
const SILENT_DB := -80.0
const META_BOUND := "_audio_bound"

var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _music_players: Array[AudioStreamPlayer] = []
var _music_active := 0
var _music_id := ""
var _music_tween: Tween = null
var _streams: Dictionary = {}
var _warned_paths: Dictionary = {}
var _current_scene: Node = null
var _last_scene_path := ""


func _ready() -> void:
	_ensure_buses()
	_create_sfx_pool()
	_create_music_players()
	get_tree().node_added.connect(_on_node_added)
	_bind_existing_buttons(get_tree().root)


## La scène courante est le seul signal de navigation dont la musique a besoin.
## Un changement de scène libère l'ancienne avant d'installer la nouvelle : le
## passage par `null` ne doit pas couper la piste en cours.
func _process(_delta: float) -> void:
	var scene := get_tree().current_scene
	if scene == _current_scene:
		return
	_current_scene = scene
	if scene == null:
		return
	_sync_scene_music()


## ─── Bus ─────────────────────────────────────────────────────────────────────

func _ensure_buses() -> void:
	_ensure_bus("Music", "Master")
	_ensure_bus("SFX", "Master")


func _ensure_bus(bus_name: String, send: String) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		index = AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, send)


## ─── Effets sonores ──────────────────────────────────────────────────────────

func play_sfx(id: String) -> void:
	var path := Catalog.sfx_path(id)
	if path == "":
		push_warning("Audio: effet sonore inconnu '%s'." % id)
		return
	var stream := _load_stream(path, false)
	if stream == null:
		return
	var player := _free_sfx_player()
	player.stream = stream
	player.play()


## Un lecteur déjà terminé est toujours préféré : deux captures du même coup ne
## doivent pas se couper l'une l'autre. Si les dix jouent, le tourniquet évite
## de toujours sacrifier le même.
func _free_sfx_player() -> AudioStreamPlayer:
	for player in _sfx_players:
		if not player.playing:
			return player
	var player := _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	return player


func _create_sfx_pool() -> void:
	for index in range(SFX_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.name = "SfxPlayer%d" % index
		player.bus = &"SFX"
		add_child(player)
		_sfx_players.append(player)


## ─── Musique ─────────────────────────────────────────────────────────────────

func current_music_id() -> String:
	return _music_id


func play_music(id: String) -> void:
	if id == "":
		return
	var path := Catalog.music_path(id)
	if path == "":
		push_warning("Audio: musique inconnue '%s'." % id)
		return
	if id == _music_id and not _music_players.is_empty() \
			and _music_players[_music_active].playing:
		return
	var stream := _load_stream(path, true)
	if stream == null:
		return
	var next_index := 1 - _music_active
	var next := _music_players[next_index]
	var previous := _music_players[_music_active]
	next.stream = stream
	next.volume_db = SILENT_DB
	next.play()
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.set_parallel(true)
	_music_tween.tween_property(next, "volume_db", 0.0, MUSIC_FADE_SECONDS)
	if previous.playing:
		_music_tween.tween_property(previous, "volume_db", SILENT_DB,
			MUSIC_FADE_SECONDS)
	_music_tween.set_parallel(false)
	_music_tween.tween_callback(previous.stop)
	_music_active = next_index
	_music_id = id


func _create_music_players() -> void:
	for index in range(2):
		var player := AudioStreamPlayer.new()
		player.name = "MusicPlayer%d" % index
		player.bus = &"Music"
		add_child(player)
		_music_players.append(player)


func _sync_scene_music() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var path := scene.scene_file_path
	if path == "":
		return
	if path == _last_scene_path and _music_id != "":
		return
	_last_scene_path = path
	play_music(Catalog.music_for_scene(path))


## ─── Boutons ─────────────────────────────────────────────────────────────────

## Tout BaseButton reçoit le son de sélection par défaut. Un écran peut changer
## ce son avec `set_button_sfx`, ou le taire avec `set_button_silent` quand le
## geste déclenche déjà un son propre (sceau et carte de Rituel).
func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_bind_button(node as BaseButton)


func _bind_existing_buttons(node: Node) -> void:
	if node is BaseButton:
		_bind_button(node as BaseButton)
	for child in node.get_children():
		_bind_existing_buttons(child)


func _bind_button(button: BaseButton) -> void:
	if button.has_meta(META_BOUND):
		return
	button.set_meta(META_BOUND, true)
	button.pressed.connect(_on_button_pressed.bind(button))


func _on_button_pressed(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	if bool(button.get_meta(Catalog.META_SILENT, false)):
		return
	play_sfx(str(button.get_meta(Catalog.META_SFX, Catalog.SFX_BUTTON)))


func set_button_sfx(button: BaseButton, id: String) -> void:
	if is_instance_valid(button):
		button.set_meta(Catalog.META_SFX, id)


func set_button_silent(button: BaseButton) -> void:
	if is_instance_valid(button):
		button.set_meta(Catalog.META_SILENT, true)


## ─── Chargement ──────────────────────────────────────────────────────────────

func _load_stream(path: String, loop: bool) -> AudioStream:
	if _streams.has(path):
		var cached: AudioStream = _streams[path]
		if loop:
			_set_loop(cached, true)
		return cached
	if not ResourceLoader.exists(path):
		_warn_missing(path)
		return null
	var stream := load(path) as AudioStream
	if stream == null:
		_warn_missing(path)
		return null
	if loop:
		_set_loop(stream, true)
	_streams[path] = stream
	return stream


func _set_loop(stream: AudioStream, enabled: bool) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = enabled
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = enabled
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = (AudioStreamWAV.LOOP_FORWARD if enabled
			else AudioStreamWAV.LOOP_DISABLED)
		# Un WAV importé sans fin de boucle valide ne bouclerait que sur zéro
		# échantillon. On referme la boucle sur la durée réelle du flux.
		if enabled and wav.loop_end <= wav.loop_begin:
			wav.loop_end = int(round(wav.get_length() * float(wav.mix_rate)))


func _warn_missing(path: String) -> void:
	if _warned_paths.has(path):
		return
	_warned_paths[path] = true
	push_warning("Audio: fichier introuvable '%s'." % path)
