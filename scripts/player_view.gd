extends Node3D

## Down arrow: lower the hand and look down at the table. Up arrow: return to normal.
@export var camera: Camera3D
@export var hand: Node3D
@export_range(0.0, 90.0) var look_down_degrees: float = 30.0
## World-space offset from the player where the hand is tucked: below the table top and behind its edge.
@export var hand_tucked_offset := Vector3(0.0, -0.5, 0.15)
## Intermediate point just behind the table edge, still above the table top.
@export var hand_clear_offset := Vector3(0.0, -0.08, -0.02)
@export_range(0.05, 1.0) var hand_retract_time: float = 0.12
@export var camera_lean_offset := Vector3(0.0, 0.0, -0.25)
@export_range(0.1, 2.0) var transition_time: float = 0.45
@export var door_look_target: Node3D
@export var door: Node3D
@export var outside_light: Light3D
@export var ambience_audio: AudioStreamPlayer
@export var door_audio: AudioStreamPlayer3D
@export var door_open_y_degrees: float = 150.3
@export var outside_light_open_energy: float = 3.0
@export var door_camera_rise: float = 0.18
@export_range(0.0, 5.0) var door_camera_delay: float = 0.6
@export_range(0.1, 10.0) var door_camera_duration: float = 3.5
@export_range(0.1, 10.0) var outside_light_duration: float = 0.45
@export_range(0.1, 30.0) var door_open_duration: float = 12.4
@export_range(0.0, 5.0) var door_open_pause: float = 0.2
@export_range(0.0, 5.0) var door_audio_lead: float = 2.5
## Temporary test trigger; set to 0 to disable.
@export var test_door_look_delay: float = 0.0

var looking_down: bool = false
var _looking_at_door: bool = false
var _camera_rest_x: float
var _camera_rest_position: Vector3
var _hand_rest_position: Vector3
var _tween: Tween
var _hand_tween: Tween

func _ready() -> void:
	_camera_rest_x = camera.rotation.x
	_camera_rest_position = camera.position
	_hand_rest_position = hand._rest_position
	if test_door_look_delay > 0.0:
		if door_look_target == null:
			push_warning("Door look test is enabled but no door target is assigned.")
		else:
			get_tree().create_timer(test_door_look_delay).timeout.connect(look_at_door)

func _unhandled_input(event: InputEvent) -> void:
	if _looking_at_door:
		return
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_DOWN and not looking_down:
		_set_looking_down(true)
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_UP and looking_down:
		_set_looking_down(false)
		get_viewport().set_input_as_handled()

func look_at_door() -> void:
	if _looking_at_door:
		return
	if door_look_target == null:
		push_warning("Cannot look at the door: no door target is assigned.")
		return
	_looking_at_door = true
	if _tween != null:
		_tween.kill()
	if _hand_tween != null:
		_hand_tween.kill()
	var target_position := camera.position + Vector3.UP * door_camera_rise
	var target_transform := global_transform * Transform3D(camera.basis, target_position)
	target_transform = target_transform.looking_at(door_look_target.global_position)
	var target_basis := (global_transform.affine_inverse() * target_transform).basis
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(camera, "position", target_position, door_camera_duration).set_delay(door_camera_delay)
	_tween.tween_property(camera, "quaternion", target_basis.get_rotation_quaternion(), door_camera_duration).set_delay(door_camera_delay)
	if outside_light != null:
		_tween.tween_property(outside_light, "light_energy", outside_light_open_energy, outside_light_duration)
		if ambience_audio != null and ambience_audio.stream != null:
			_tween.tween_callback(ambience_audio.play)
		else:
			push_warning("Cannot play ambience: no audio player or stream is assigned.")
	else:
		push_warning("Cannot brighten the outside light: no light is assigned.")
	if door != null:
		var audio_delay := outside_light_duration + door_open_pause
		_tween.tween_property(door, "rotation:y", deg_to_rad(door_open_y_degrees), door_open_duration).set_delay(audio_delay + door_audio_lead)
		if door_audio != null and door_audio.stream != null:
			_tween.tween_callback(door_audio.play).set_delay(audio_delay)
		else:
			push_warning("Cannot play the door sound: no audio player or stream is assigned.")
	else:
		push_warning("Cannot open the door: no door is assigned.")

func _set_looking_down(value: bool) -> void:
	looking_down = value
	hand.controllable = not value
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var target_x := _camera_rest_x - deg_to_rad(look_down_degrees) if value else _camera_rest_x
	var target_position := _camera_rest_position + camera_lean_offset if value else _camera_rest_position
	_tween.tween_property(camera, "rotation:x", target_x, transition_time)
	_tween.tween_property(camera, "position", target_position, transition_time)
	if _hand_tween != null:
		_hand_tween.kill()
	# The hand is a child of the moving camera, so its path is built in world space
	# (back past the table edge, then down) and converted to camera space every frame.
	var rest_camera := global_transform * Transform3D(Basis(Vector3.RIGHT, _camera_rest_x), _camera_rest_position)
	var rest_world := rest_camera * _hand_rest_position
	var start_world := camera.to_global(hand._rest_position)
	var clear_world := global_position + hand_clear_offset
	var end_world := global_position + hand_tucked_offset if value else rest_world
	var duration := hand_retract_time if value else transition_time
	_hand_tween = create_tween()
	_hand_tween.tween_method(_move_hand.bind(start_world, clear_world, end_world, value), 0.0, 1.0, duration)

func _move_hand(t: float, start_world: Vector3, clear_world: Vector3, end_world: Vector3, tucking: bool) -> void:
	var eased := smoothstep(0.0, 1.0, t)
	var world: Vector3
	if eased < 0.5:
		world = start_world.lerp(clear_world, eased * 2.0)
	else:
		world = clear_world.lerp(end_world, (eased - 0.5) * 2.0)
	hand._rest_position = camera.to_local(world) if t < 1.0 or tucking else _hand_rest_position
