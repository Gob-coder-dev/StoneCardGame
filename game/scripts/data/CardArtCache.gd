## Charge les illustrations de cartes hors du thread principal et conserve
## seulement le groupe utile à l'écran courant. Les vues demandent une texture
## sans jamais bloquer : elles sont prévenues lorsqu'elle devient disponible.
extends Node

signal texture_ready(path: String, texture: Texture2D)
signal warmup_progress(god_id: String, loaded: int, total: int)
signal warmup_finished(god_id: String)

const MAX_PARALLEL_LOADS := 2

var _textures: Dictionary = {}
var _failed: Dictionary = {}
var _queue: Array[String] = []
var _queued: Dictionary = {}
var _pending: Dictionary = {}
var _active_paths: Dictionary = {}
var _direct_paths: Dictionary = {}
var _persistent_paths: Dictionary = {}
var _warmup_paths: Dictionary = {}
var _active_god_id := ""


func _ready() -> void:
	set_process(false)


## ResourceLoader ne propose pas d'annulation d'une requête déjà lancée. À la
## fermeture seulement, récupérer les deux requêtes en vol évite de laisser des
## ressources de thread orphelines dans ObjectDB.
func _exit_tree() -> void:
	for raw_path in _pending.keys():
		var path := str(raw_path)
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS \
				or status == ResourceLoader.THREAD_LOAD_LOADED:
			ResourceLoader.load_threaded_get(path)
	_pending.clear()


## Prépare la collection visible et les éventuelles formes déjà équipées.
## Changer de groupe libère nos références fortes aux anciennes illustrations.
func activate_god(god_id: String, preview_level: int = 1, deck: Array = []) -> void:
	_active_god_id = god_id
	_direct_paths.clear()
	_warmup_paths = _paths_for_god(god_id, preview_level)
	for stone_id in deck:
		var path := _asset_path(StoneLoader.get_stone(str(stone_id)))
		if not path.is_empty():
			_warmup_paths[path] = true
	_active_paths = _persistent_paths.duplicate()
	for path in _warmup_paths:
		_active_paths[path] = true
	_prune_unused_textures()
	_prune_obsolete_queue()
	for path in _warmup_paths:
		_request(path, true)
	_emit_warmup_progress()


## Les six portraits sont petits en nombre, présents dans plusieurs écrans et
## conservés pour toute la session. Ils ne font pas partie de la progression
## des cartes du dieu actif.
func preload_god_portraits() -> void:
	for god in StoneLoader.get_all_gods():
		var path := str(god.get("asset", ""))
		if path.is_empty():
			continue
		_persistent_paths[path] = true
		_active_paths[path] = true
		_request(path, true)


## Demande non bloquante utilisée par StoneCard. Une texture déjà chargée est
## rendue immédiatement ; sinon la carte recevra texture_ready plus tard.
func texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	_direct_paths[path] = true
	if _textures.has(path):
		return _textures[path] as Texture2D
	var cached := ResourceLoader.get_cached_ref(path) as Texture2D
	if cached != null:
		_store(path, cached)
		return cached
	_request(path, true)
	# En headless, `_request` charge directement et émet `texture_ready` avant
	# de revenir. Renvoyer la texture stockée évite que l'appelant l'écrase
	# avec un `null` alors que le signal synchrone l'a déjà fournie.
	return _textures.get(path) as Texture2D


func preload_stones(stone_ids: Array) -> void:
	for stone_id in stone_ids:
		var path := _asset_path(StoneLoader.get_stone(str(stone_id)))
		if path.is_empty():
			continue
		_active_paths[path] = true
		_request(path, true)


func progress_for_god(god_id: String) -> Vector2i:
	if god_id != _active_god_id:
		return Vector2i.ZERO
	return Vector2i(_completed_warmup_count(), _warmup_paths.size())


func is_warm_for_god(god_id: String) -> bool:
	var progress := progress_for_god(god_id)
	return progress.y > 0 and progress.x >= progress.y


func _process(_delta: float) -> void:
	_complete_finished_requests()
	_start_queued_requests()
	if _queue.is_empty() and _pending.is_empty():
		set_process(false)


func _request(path: String, prioritize: bool) -> void:
	if path.is_empty() or _textures.has(path) or _failed.has(path) \
			or _queued.has(path) or _pending.has(path):
		return
	if not ResourceLoader.exists(path, "Texture2D"):
		_failed[path] = true
		_emit_warmup_progress()
		return
	var cached := ResourceLoader.get_cached_ref(path) as Texture2D
	if cached != null:
		_store(path, cached)
		return
	# Le renderer factice de `--headless` ne possède pas de stockage de
	# textures thread-safe. Un chargement direct rend les tests déterministes ;
	# les exports Android et desktop gardent la file asynchrone ci-dessous.
	if DisplayServer.get_name() == "headless":
		var loaded := ResourceLoader.load(path, "Texture2D") as Texture2D
		if loaded != null:
			_store(path, loaded)
		else:
			_failed[path] = true
			_emit_warmup_progress()
		return
	if prioritize:
		_queue.push_front(path)
	else:
		_queue.append(path)
	_queued[path] = true
	set_process(true)


func _start_queued_requests() -> void:
	while _pending.size() < MAX_PARALLEL_LOADS and not _queue.is_empty():
		var path: String = _queue.pop_front()
		_queued.erase(path)
		if not _should_keep_request(path):
			continue
		var error := ResourceLoader.load_threaded_request(
			path, "Texture2D", false, ResourceLoader.CACHE_MODE_REUSE
		)
		if error == OK:
			_pending[path] = true
		else:
			_failed[path] = true
			_emit_warmup_progress()


func _complete_finished_requests() -> void:
	for raw_path in _pending.keys():
		var path := str(raw_path)
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		_pending.erase(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var loaded := ResourceLoader.load_threaded_get(path) as Texture2D
			if loaded != null:
				_store(path, loaded)
				continue
		_failed[path] = true
		_emit_warmup_progress()


func _store(path: String, loaded: Texture2D) -> void:
	# Une ancienne requête peut finir après un changement de dieu. Elle réveille
	# encore une éventuelle carte vivante, mais n'est pas retenue inutilement.
	if _active_paths.has(path) or _direct_paths.has(path):
		_textures[path] = loaded
	_failed.erase(path)
	texture_ready.emit(path, loaded)
	_emit_warmup_progress()


func _emit_warmup_progress() -> void:
	if _active_god_id.is_empty():
		return
	var loaded := _completed_warmup_count()
	var total := _warmup_paths.size()
	warmup_progress.emit(_active_god_id, loaded, total)
	if total > 0 and loaded >= total:
		warmup_finished.emit(_active_god_id)


func _completed_warmup_count() -> int:
	var completed := 0
	for path in _warmup_paths:
		if _textures.has(path) or _failed.has(path):
			completed += 1
	return completed


func _paths_for_god(god_id: String, preview_level: int) -> Dictionary:
	var paths := {}
	for base in StoneLoader.get_lineages_for_god(god_id):
		var stone_id := StoneLoader.preview_variant(str(base["id"]), preview_level)
		var path := _asset_path(StoneLoader.get_stone(stone_id))
		if not path.is_empty():
			paths[path] = true
	return paths


static func _asset_path(stone: Dictionary) -> String:
	return str(stone.get("asset", ""))


func _prune_unused_textures() -> void:
	for path in _textures.keys():
		if not _active_paths.has(path):
			_textures.erase(path)


func _prune_obsolete_queue() -> void:
	var retained: Array[String] = []
	_queued.clear()
	for path in _queue:
		if _should_keep_request(path):
			retained.append(path)
			_queued[path] = true
	_queue = retained


func _should_keep_request(path: String) -> bool:
	return _active_paths.has(path) or _direct_paths.has(path)
