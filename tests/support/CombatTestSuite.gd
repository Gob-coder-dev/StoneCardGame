## Fixtures et assertions communes aux suites autonomes, sans dépendance GUT.
extends Node
const BattleStoneModel := preload("res://scripts/engine/BattleStone.gd")
const CombatResolverModel := preload("res://scripts/engine/CombatResolver.gd")
const Symbols := preload("res://scripts/ui/StoneSymbols.gd")
const Timeline := preload("res://scripts/ui/combat/CombatTimeline.gd")
const TestLog := preload("res://tests/support/TestLog.gd")
const StoneEffects := preload("res://scripts/domain/StoneEffects.gd")
var _passed: int = 0
var _failed: int = 0

## Les anciennes suites de règles utilisent les mêmes assertions sans installer GUT.
func assert_true(value: bool, message: String = "") -> void:
	_check(value, message if message != "" else "assert_true")

func assert_false(value: bool, message: String = "") -> void:
	_check(not value, message if message != "" else "assert_false")

func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	_check(actual == expected, message if message != "" else "attendu %s, obtenu %s" % [str(expected), str(actual)])

func _register_test_stones() -> void:
	_register("fx_plain", 1, 1, 1, 1)
	_register("fx_attack2", 0, 0, 0, 2)
	_register("fx_wall", 1, 1, 1, 1, {"shields": {"top": 1, "bottom": 1, "left": 1, "right": 1}})
	_register("fx_ranged", 0, 0, 0, 2, {"long_blades": {"top": 0, "bottom": 0, "left": 0, "right": 1}})
	_register("fx_mixed_ranged", 0, 0, 0, 2, {"long_blades": {"top": 0, "bottom": 0, "left": 0, "right": 2}})
	_register("fx_strong_wall", 4, 4, 4, 4)
	_register("fx_ranged_target", 0, 0, 0, 0)
	_register("fx_target", 0, 0, 1, 0, {"shields": {"top": 0, "bottom": 0, "left": 1, "right": 0}})
	_register("fx_weaken_local", 0, 0, 0, 0, {"effects": [StoneEffects.WEAKEN_ADJACENT]})
	_register("fx_weaken_attack1", 0, 0, 0, 1, {"effects": [StoneEffects.WEAKEN_ADJACENT]})
	_register("fx_weaken_attack2", 0, 0, 0, 2, {"effects": [StoneEffects.WEAKEN_ADJACENT]})
	# Échec corrosif : 1 lame à droite, qui échoue contre une défense de 1.
	_register("fx_corrode", 0, 0, 0, 1, {"effects": [StoneEffects.WEAKEN_ON_FAILED_ATTACK]})
	# Attaque en haut (1 lame) et à droite (2 lames) : une réussite et un échec possibles.
	_register("fx_corrode_mixed", 1, 0, 0, 2, {"effects": [StoneEffects.WEAKEN_ON_FAILED_ATTACK]})
	_register("fx_corrode_ranged", 0, 0, 0, 0, {"effects": [StoneEffects.WEAKEN_ON_FAILED_ATTACK],
		"long_blades": {"top": 0, "bottom": 0, "left": 0, "right": 1}})
	_register("fx_swarm_a", 1, 1, 1, 1, {"effects": [StoneEffects.SWARM]})
	_register("fx_swarm_b", 1, 1, 1, 1, {"effects": [StoneEffects.SWARM]})
	_register("fx_swarm_c", 1, 1, 1, 1, {"effects": [StoneEffects.SWARM]})
	# Seule la face du bas a de la place : sa lame d'Essaim y pousse toujours.
	_register("fx_swarm_bottom", 4, 0, 4, 4, {"effects": [StoneEffects.SWARM]})
	_register("fx_thief", 3, 3, 3, 3, {"effects": [StoneEffects.SHIELD_THEFT]})
	# Seule la face droite a de la place : c'est aussi elle qui attaque.
	_register("fx_thief_right_open", 4, 4, 4, 2, {"effects": [StoneEffects.SHIELD_THEFT]})


func _register(id: String, top: int, bottom: int, left: int, right: int, extras: Dictionary = {}) -> void:
	var definition := {"god_id": "neutral", "effects": []}
	definition.merge(extras, true)
	StoneLoader.register_stone(id, top, bottom, left, right, definition)


func _state_with_hands(human: Array, ai: Array) -> GameState:
	var state := GameState.new()
	state.setup_hands(human, ai)
	state.set_random_seed(1)
	return state


func _force_instance(state: GameState, row: int, col: int, stone_id: String, owner: int) -> void:
	var stone: BattleStoneModel = BattleStoneModel.new()
	stone.configure(stone_id, StoneLoader.get_stone(stone_id), state.take_instance_id())
	var cell := state.get_cell(row, col)
	cell["stone_id"] = stone_id
	cell["stone"] = stone
	cell["owner"] = owner
	state.empty_playable_cells -= 1


func _sum(values: Dictionary) -> int:
	var total := 0
	for value in values.values():
		total += int(value)
	return total


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("PASS: ", label)
	else:
		_failed += 1
		# printerr : un échec est compté ici, pas comme une erreur Godot.
		printerr("FAIL: ", label)


## Annonce un message Godot que le test provoque volontairement.
func _expect_log(fragment: String) -> void:
	if TestLog.current != null:
		TestLog.current.expect(fragment)


func _animated_manager() -> TurnManager:
	var manager := TurnManager.new()
	add_child(manager)
	var board := BoardView.new()
	board.size = Vector2(900, 900)
	manager.add_child(board)
	board.build()
	manager.stone_placed.connect(func(_r, _c, _id, _owner): board.refresh(manager.get_state()))
	manager.presentation_requested.connect(func(step: CombatPresentation):
		if step.kind == CombatPresentation.Kind.EFFECTS:
			board.refresh(manager.get_state())
		board.animations.present(step))
	return manager
