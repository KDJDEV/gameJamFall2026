class_name CardHand
extends Node3D

signal hand_changed(cards: Array[Node3D], selected_index: int)
signal card_drawn(card: Node3D)
signal card_discarded(card: Node3D)

@export var card_scene: PackedScene
@export_range(1, 10) var hand_limit: int = 5
@export_range(0.1, 2.0) var card_spacing: float = 0.3
@export_range(0.0, 1.5) var fan_width: float = 0.9
@export_range(0.0, 0.5) var fan_height: float = 0.06
@export_range(0.0, 0.6) var fan_rotation: float = 0.12
## Depth between neighbouring cards (toward the viewer, later cards on top) so overlapping
## cards never sit in the same plane and flicker (z-fight).
@export_range(0.0, 0.02) var card_depth_step: float = 0.003
@export var starting_hand_size: int = 5
@export_range(0.0, 0.1) var bob_height: float = 0.012
@export_range(0.0, 0.1) var bob_sway: float = 0.008
@export_range(0.1, 3.0) var bob_speed: float = 0.7
@export_range(1.0, 20.0) var bob_smoothing: float = 6.0

@export var show_selection: bool = true

var cards: Array[Node3D] = []
var discard_pile: Array[Node3D] = []
var selected_index: int = 0
var draw_count: int = 0
var _bob_time: float = randf() * 100.0
var _bob_phases := Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
var _bob_rate: float = randf_range(0.75, 1.3)
var _rest_position := Vector3.ZERO
var _rest_rotation := Vector3.ZERO
var _facing_saved: bool = false
var _saved_yaw: float = 0.0

func _ready() -> void:
	_rest_position = position
	_rest_rotation = rotation
	if card_scene == null:
		card_scene = preload("res://card.tscn")
	for index in range(min(starting_hand_size, hand_limit)):
		draw_card()
	_update_selection()
	_layout_hand()

func _process(delta: float) -> void:
	_bob_time += delta * bob_speed * _bob_rate
	var bob_offset := Vector3(
		sin(_bob_time * 1.1 + _bob_phases.x) * bob_sway,
		sin(_bob_time * 0.8 + _bob_phases.y) * bob_height,
		cos(_bob_time * 0.9 + _bob_phases.z) * bob_sway * 0.35
	)
	var target_position := _rest_position + bob_offset
	var target_rotation := _rest_rotation + Vector3(
		sin(_bob_time * 0.7 + _bob_phases.y) * bob_sway * 0.5,
		sin(_bob_time * 0.6 + _bob_phases.z) * bob_sway * 0.5,
		sin(_bob_time * 0.5 + _bob_phases.x) * bob_sway * 0.25
	)
	var weight := 1.0 - exp(-bob_smoothing * delta)
	position = position.lerp(target_position, weight)
	rotation = rotation.lerp(target_rotation, weight)

## Left/right move the selection and select discards it (move_left / move_right / select
## input actions, bound to every joystick and button key of the arcade cabinet).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("move_left"):
		_move_selection(-1)
	elif event.is_action_pressed("move_right"):
		_move_selection(1)
	elif event.is_action_pressed("select"):
		discard_selected()

func move_selection(direction: int) -> void:
	_move_selection(direction)

func face_toward(world_point: Vector3) -> void:
	if not _facing_saved:
		_saved_yaw = _rest_rotation.y
		_facing_saved = true
	var direction := world_point - global_position
	_rest_rotation.y = lerp_angle(_rest_rotation.y, atan2(direction.x, direction.z), 1.0)

func restore_facing() -> void:
	if _facing_saved:
		_rest_rotation.y = _saved_yaw
		_facing_saved = false

func refresh_selection() -> void:
	_update_selection()

func _move_selection(direction: int) -> void:
	if cards.is_empty():
		return
	selected_index = wrapi(selected_index + direction, 0, cards.size())
	_update_selection()

func draw_card() -> Node3D:
	if cards.size() >= hand_limit or card_scene == null:
		return null
	var card := card_scene.instantiate() as Node3D
	if card == null:
		return null
	add_child(card)
	cards.append(card)
	draw_count += 1
	if card.has_method("configure"):
		card.configure("card_%02d" % draw_count, "unknown", "unknown")
	card_drawn.emit(card)
	selected_index = cards.size() - 1
	_layout_hand()
	_update_selection()
	return card

func discard_selected() -> Node3D:
	if cards.is_empty() or selected_index < 0 or selected_index >= cards.size():
		return null
	var card := cards[selected_index]
	cards.remove_at(selected_index)
	discard_pile.append(card)
	card.visible = false
	card_discarded.emit(card)
	selected_index = clampi(selected_index, 0, cards.size() - 1)
	_layout_hand()
	_update_selection()
	return card

func _selection_allowed() -> bool:
	return true

func _update_selection() -> void:
	for index in cards.size():
		var card := cards[index]
		card.set_meta("hand_index", index)
		if card.has_method("set_selected"):
			card.set_selected(show_selection and _selection_allowed() and index == selected_index)
	hand_changed.emit(cards, selected_index)

func _layout_hand() -> void:
	var count := cards.size()
	if count == 0:
		return
	var center := (count - 1) * 0.5
	for index in count:
		var card := cards[index]
		var offset := float(index) - center
		var card_position := Vector3(offset * card_spacing, -abs(offset) * fan_height, abs(offset) * 0.025 + index * card_depth_step)
		var card_rotation := Vector3(0.0, 0.0, -offset * fan_rotation)
		if card.has_method("set_hand_pose"):
			card.set_hand_pose(card_position, card_rotation)
		else:
			card.position = card_position
			card.rotation = card_rotation
		card.visible = true
