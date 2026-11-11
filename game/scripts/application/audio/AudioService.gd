## Service audio unique du jeu.
##
## Il possède les bus, le pool de lectures courtes, le lecteur de musique et
## le branchement automatique des boutons. Les écrans ne parlent jamais
## directement à AudioServer : ils demandent un identifiant du catalogue, ou
## posent une métadonnée sur un bouton.
##
## La musique suit la scène courante sans qu'aucun écran n'ait à l'annoncer.
extends Node

signal volume_changed(bus_name: StringName, percent: float)

const Catalog := preload("res://scripts/application/audio/AudioCatalog.gd")

const SFX_POOL_SIZE := 10
const META_BOUND := "_audio_bound"
const SETTINGS_PATH := "user://audio_settings.cfg"
const SETTINGS_SECTION := "audio"
const DEFAULT_VOLUME_PERCENT := 70.0
const SETTINGS_SAVE_DELAY := 0.25
const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"

var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _music_player: AudioStreamPlayer = null
var _music_id := ""
var _jingle_player: AudioStreamPlayer = null
var _jingle_scene: Node = null
var _streams: Dictionary = {}
var _warned_paths: Dictionary = {}
var _current_scene: Node = null
var _volume_percent: Dictionary = {
	MUSIC_BUS: DEFAULT_VOLUME_PERCENT,
	SFX_BUS: DEFAULT_VOLUME_PERCENT,
}
var _settings_save_timer: Timer = null


func _ready() -> void:
	_ensure_buses()
	_create_settings_save_timer()
	_load_volume_settings()
	_apply_all_bus_volumes()
	_create_sfx_pool()
	_create_music_player()
	_create_jingle_player()
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
	_ensure_bus(MUSIC_BUS, &"Master")
	_ensure_bus(SFX_BUS, &"Master")


func _ensure_bus(bus_name: StringName, send: StringName) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		index = AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, send)


## ─── Préférences de volume ───────────────────────────────────────────────

func music_volume_percent() -> float:
	return volume_percent(MUSIC_BUS)


func sfx_volume_percent() -> float:
	return volume_percent(SFX_BUS)


func volume_percent(bus_name: StringName) -> float:
	return float(_volume_percent.get(bus_name, DEFAULT_VOLUME_PERCENT))


func set_music_volume_percent(percent: float, persist: bool = true) -> void:
	_set_volume_percent(MUSIC_BUS, percent, persist)


func set_sfx_volume_percent(percent: float, persist: bool = true) -> void:
	_set_volume_percent(SFX_BUS, percent, persist)


func _set_volume_percent(bus_name: StringName, percent: float,
		persist: bool) -> void:
	var normalized := clampf(roundf(percent), 0.0, 100.0)
	if is_equal_approx(volume_percent(bus_name), normalized):
		return
	_volume_percent[bus_name] = normalized
	_apply_bus_volume(bus_name)
	volume_changed.emit(bus_name, normalized)
	if persist:
		_schedule_settings_save()


## Le bus est réellement muet à zéro. Aux autres valeurs, une conversion en
## décibels conserve une progression perceptive naturelle pour l'oreille.
func _apply_bus_volume(bus_name: StringName) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	var percent := volume_percent(bus_name)
	AudioServer.set_bus_mute(index, is_zero_approx(percent))
	if percent > 0.0:
		AudioServer.set_bus_volume_db(index, linear_to_db(percent / 100.0))


func _apply_all_bus_volumes() -> void:
	_apply_bus_volume(MUSIC_BUS)
	_apply_bus_volume(SFX_BUS)


func _load_volume_settings() -> void:
	var config := ConfigFile.new()
	var error := config.load(SETTINGS_PATH)
	if error != OK:
		if error != ERR_FILE_NOT_FOUND:
			push_warning("Audio: réglages illisibles (%s), valeurs par défaut utilisées." % error)
		return
	_volume_percent[MUSIC_BUS] = _stored_percent(config, "music")
	_volume_percent[SFX_BUS] = _stored_percent(config, "sfx")


func _stored_percent(config: ConfigFile, key: String) -> float:
	return clampf(roundf(float(config.get_value(
		SETTINGS_SECTION, key, DEFAULT_VOLUME_PERCENT))), 0.0, 100.0)


func _create_settings_save_timer() -> void:
	_settings_save_timer = Timer.new()
	_settings_save_timer.name = "SettingsSaveTimer"
	_settings_save_timer.one_shot = true
	_settings_save_timer.wait_time = SETTINGS_SAVE_DELAY
	_settings_save_timer.timeout.connect(_save_volume_settings)
	add_child(_settings_save_timer)


## Le curseur peut émettre plusieurs dizaines de valeurs pendant un glissement.
## Le délai regroupe ces changements en une seule écriture sur le stockage.
func _schedule_settings_save() -> void:
	_settings_save_timer.start()


func flush_volume_settings() -> void:
	if _settings_save_timer == null or _settings_save_timer.is_stopped():
		return
	_settings_save_timer.stop()
	_save_volume_settings()


func _save_volume_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(SETTINGS_SECTION, "music", music_volume_percent())
	config.set_value(SETTINGS_SECTION, "sfx", sfx_volume_percent())
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Audio: impossible d'enregistrer les réglages (%s)." % error)


## ─── Effets sonores ──────────────────────────────────────────────────────────

func play_sfx(id: String) -> void:
	# Un jingle de résultat est un morceau complet : il passe par le lecteur
	# dédié pour couper la musique, même si l'appelant utilise play_sfx.
	if Catalog.is_jingle(id):
		play_jingle(id)
		return
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
	# La musique reprend toujours la main : un jingle encore en cours est coupé.
	_stop_jingle()
	if id == _music_id and _music_player != null and _music_player.playing:
		return
	var stream := _load_stream(path, true)
	if stream == null:
		return
	# Changement franc : l'ancienne piste s'arrête, la nouvelle démarre
	# immédiatement. Aucun fondu ne vient chevaucher les deux morceaux.
	_music_player.stop()
	_music_player.stream = stream
	_music_player.play()
	_music_id = id


func _create_music_player() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = &"Music"
	add_child(_music_player)


## Les sons de résultat (victoire, défaite, égalité, manche) sont des morceaux
## complets. Ils prennent la place de la musique : la piste de fond s'arrête, le
## jingle joue seul, puis la musique de l'écran reprend à la fin.
func play_jingle(id: String) -> void:
	var path := Catalog.sfx_path(id)
	if path == "":
		push_warning("Audio: jingle inconnu '%s'." % id)
		return
	var stream := _load_stream(path, false)
	if stream == null:
		return
	_stop_jingle()
	_jingle_scene = get_tree().current_scene
	_jingle_player.stream = stream
	_jingle_player.play()
	_music_player.stop()


func _create_jingle_player() -> void:
	_jingle_player = AudioStreamPlayer.new()
	_jingle_player.name = "JinglePlayer"
	_jingle_player.bus = &"SFX"
	add_child(_jingle_player)
	_jingle_player.finished.connect(_on_jingle_finished)


## Coupe le jingle en cours. La piste de fond n'est pas relancée ici : c'est
## l'appelant qui décide de la suite (reprise de la scène ou nouvelle scène).
func _stop_jingle() -> void:
	# Vider la scène avant `stop()` évite qu'un `finished` synchrone ne
	# relance la musique alors qu'on vient justement de couper le jingle.
	_jingle_scene = null
	if _jingle_player != null:
		_jingle_player.stop()


func _on_jingle_finished() -> void:
	if _jingle_scene == null:
		return
	_jingle_scene = null
	_resume_scene_music()


## La musique de l'écran reprend après un jingle, même si c'est la même piste
## que celle qui a été interrompue : elle redémarre du début.
func _resume_scene_music() -> void:
	var path := _current_scene_path()
	if path == "":
		return
	play_music(Catalog.music_for_scene(path))


func _current_scene_path() -> String:
	var scene := get_tree().current_scene
	return scene.scene_file_path if scene != null else ""


func _sync_scene_music() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var path := scene.scene_file_path
	if path == "":
		return
	# Un jingle lancé par cet écran garde la place de la musique. Si la scène a
	# changé (même vers le même fichier), le jingle est coupé.
	if _jingle_player.playing:
		if is_instance_valid(_jingle_scene) and scene == _jingle_scene:
			return
		_stop_jingle()
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
