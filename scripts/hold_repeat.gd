class_name HoldRepeat
extends RefCounted

var first_delay: float
var interval: float
var _negative_action: StringName
var _positive_action: StringName
var _direction: int = 0
var _countdown: float = 0.0

## The two actions that scroll one way and the other; left/right unless told otherwise.
func _init(first_delay_seconds: float = 0.17, interval_seconds: float = 0.17, negative_action: StringName = &"move_left", positive_action: StringName = &"move_right") -> void:
	first_delay = first_delay_seconds
	interval = interval_seconds
	_negative_action = negative_action
	_positive_action = positive_action

func reset() -> void:
	_direction = 0
	_countdown = 0.0

func step(delta: float) -> int:
	var left := Input.is_action_pressed(_negative_action)
	var right := Input.is_action_pressed(_positive_action)
	var direction := 0
	if left and not right:
		direction = -1
	elif right and not left:
		direction = 1
	if direction == 0:
		reset()
		return 0
	if direction != _direction:
		_direction = direction
		_countdown = first_delay
		return 0
	_countdown -= delta
	if _countdown > 0.0:
		return 0
	_countdown += interval
	return direction
