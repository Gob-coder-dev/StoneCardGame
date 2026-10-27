## Compte les erreurs et avertissements de Godot pendant les suites de tests.
## Un test qui provoque volontairement un message l'annonce avec expect() :
## ce message attendu ne compte pas, mais son absence devient un problème.
extends Logger

## Journal actif (une instance de ce script), renseigné par le lanceur des suites.
static var current = null

## Godot peut journaliser depuis d'autres fils d'exécution.
var _mutex := Mutex.new()
var _expected: Array[String] = []
var _unexpected: Array[String] = []


## Le prochain message contenant ce fragment est attendu et ne compte pas.
func expect(fragment: String) -> void:
	_mutex.lock()
	_expected.append(fragment)
	_mutex.unlock()


## Messages inattendus, puis messages annoncés qui ne sont jamais apparus.
func problems() -> Array[String]:
	_mutex.lock()
	var result: Array[String] = _unexpected.duplicate()
	for fragment in _expected:
		result.append("message attendu absent : " + fragment)
	_mutex.unlock()
	return result


func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	var message := rationale if rationale != "" else code
	_mutex.lock()
	var expected_index := -1
	for index in range(_expected.size()):
		if message.contains(_expected[index]):
			expected_index = index
			break
	if expected_index >= 0:
		_expected.remove_at(expected_index)
	else:
		_unexpected.append("%s (%s:%d)" % [message, file.get_file(), line])
	_mutex.unlock()
