## Capture locale du protocole de débogage pour contrôler les warnings dès le boot.
## Lancé dans un projet temporaire vide : aucun autoload du jeu dans le récepteur.
## Protocole Godot 4.7 : paquet Variant [nom, identifiant de thread, données].
extends SceneTree

var _listener := TCPServer.new()
var _channel := PacketPeerStream.new()
var _connection: StreamPeerTCP
var _messages: Array = []
var _started := Time.get_ticks_msec()
var _child_pid := -1
var _report_path := ""
var _connected := false
var _deadline_ms := 30000


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_report_path = args[2]
	_deadline_ms = int(args[4]) * 1000
	var port := int(args[0])
	var error := _listener.listen(port, "127.0.0.1")
	if error != OK:
		_finish(true)
		return
	_child_pid = OS.create_process(OS.get_executable_path(), ["--headless", "--debug",
		"--remote-debug", "tcp://127.0.0.1:%d" % port, "--path", args[1],
		"--log-file", args[3], "--fixed-fps", "60", "res://tests/StartupChecks.tscn"])
	if _child_pid <= 0:
		_finish(true)


func _process(_delta: float) -> bool:
	if _connection == null and _listener.is_connection_available():
		_connection = _listener.take_connection()
		_channel.stream_peer = _connection
		_connected = true
	if _connection != null:
		_connection.poll()
		while _channel.get_available_packet_count() > 0:
			var packet: Variant = _channel.get_var()
			if packet is Array and packet.size() == 3:
				_messages.append(packet)
				if packet[0] == "debug_enter":
					_channel.put_var(["continue", packet[1], []])
	if Time.get_ticks_msec() - _started > _deadline_ms:
		if _child_pid > 0 and OS.is_process_running(_child_pid):
			OS.kill(_child_pid)
		_finish(true)
	elif _child_pid > 0 and not OS.is_process_running(_child_pid):
		_finish(false)
	return false


func _finish(timed_out: bool) -> void:
	var report := {"connected": _connected, "timed_out": timed_out, "messages": _messages}
	var file := FileAccess.open(_report_path, FileAccess.WRITE)
	if file == null:
		quit(2)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	_listener.stop()
	quit(1 if timed_out else 0)
