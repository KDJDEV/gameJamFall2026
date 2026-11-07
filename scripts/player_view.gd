extends Node3D

## Up arrow: look at the table (only the selected card stays in view); Space there discards
## it and returns to your hand. From the table, Left or Right leans over to peek at the
## neighbouring player's hand: Left/Right pick one of their cards, Space swaps it with your
## selected card, Up or Down steps back to the table view.
enum ViewState { NORMAL, TABLE, PEEK }

@export var camera: Camera3D
@export var hand: Node3D
## Hands you can peek at and swap with (not the dealer across the table).
@export var left_hand: Node3D
@export var right_hand: Node3D
@export_range(0.0, 90.0) var look_down_degrees: float = 30.0
@export var camera_lean_offset := Vector3(0.0, 0.0, -0.25)
@export_range(0.1, 2.0) var transition_time: float = 0.45
## Camera position when peeking, in the peeked hand's space: X is toward your own side of
## it (mirrored automatically), Y up, Z toward the hand's owner. Small values keep you
## leaning from your seat rather than standing behind them.
@export var peek_offset := Vector3(0.45, 0.5, 0.05)
@export_range(0.1, 2.0) var peek_transition_time: float = 0.6
@export_range(0.0, 3.0) var peek_light_energy: float = 0.6
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

var view_state: ViewState = ViewState.NORMAL
var _looking_at_door: bool = false
var _camera_rest_quaternion: Quaternion
var _camera_rest_position: Vector3
var _tween: Tween
var _peek_hand: Node3D
var _peek_hand_was_playing: bool = true
var _peek_light: OmniLight3D
var _light_tween: Tween

func _ready() -> void:
	_camera_rest_quaternion = camera.quaternion
	_camera_rest_position = camera.position
	hand.lap_anchor = self
	# A dim light so the cards can be read when leaning into the dark corners of the table.
	_peek_light = OmniLight3D.new()
	_peek_light.light_energy = peek_light_energy
	_peek_light.light_color = Color(1.0, 0.85, 0.6)
	_peek_light.omni_range = 1.4
	_peek_light.visible = false
	camera.add_child(_peek_light)
	if test_door_look_delay > 0.0:
		if door_look_target == null:
			push_warning("Door look test is enabled but no door target is assigned.")
		else:
			get_tree().create_timer(test_door_look_delay).timeout.connect(look_at_door)

func _unhandled_input(event: InputEvent) -> void:
	if _looking_at_door or hand.awaiting_deal:
		return
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var handled := true
	match view_state:
		ViewState.NORMAL:
			if key_event.keycode == KEY_UP:
				_enter_table_view()
			else:
				handled = false
		ViewState.TABLE:
			match key_event.keycode:
				KEY_DOWN:
					_enter_normal_view()
				KEY_SPACE:
					_discard_from_table()
				KEY_LEFT:
					_start_peek(left_hand)
				KEY_RIGHT:
					_start_peek(right_hand)
				_:
					handled = false
		ViewState.PEEK:
			match key_event.keycode:
				KEY_LEFT:
					_peek_hand.move_selection(-1)
				KEY_RIGHT:
					_peek_hand.move_selection(1)
				KEY_DOWN, KEY_UP:
					_end_peek()
					_enter_table_view()
				KEY_SPACE:
					_swap_with_peeked_hand()
				_:
					handled = false
	if handled:
		get_viewport().set_input_as_handled()

func look_at_door() -> void:
	if _looking_at_door:
		return
	if door_look_target == null:
		push_warning("Cannot look at the door: no door target is assigned.")
		return
	_looking_at_door = true
	_end_peek()
	hand.set_held_mode(false)
	if _tween != null:
		_tween.kill()
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

func _enter_normal_view() -> void:
	view_state = ViewState.NORMAL
	hand.set_held_mode(false)
	hand.controllable = true
	_move_camera(_camera_rest_position, _camera_rest_quaternion, transition_time)

func _enter_table_view() -> void:
	view_state = ViewState.TABLE
	hand.controllable = false
	hand.set_held_mode(true)
	var table_rotation := Quaternion(Vector3.RIGHT, -deg_to_rad(look_down_degrees)) * _camera_rest_quaternion
	_move_camera(_camera_rest_position + camera_lean_offset, table_rotation, transition_time)

func _start_peek(target: Node3D) -> void:
	if target == null or target.cards.is_empty() or hand.cards.is_empty():
		return
	view_state = ViewState.PEEK
	_peek_hand = target
	# Their hand holds still and shows its selection while you choose a card.
	_peek_hand_was_playing = target.play_enabled
	target.play_enabled = false
	target.show_selection = true
	target.refresh_selection()
	hand.set_held_mode(true, true)
	_peek_light.light_energy = 0.0
	_peek_light.visible = true
	_fade_peek_light(peek_light_energy, peek_transition_time)
	var side := signf(target.to_local(global_position).x)
	if side == 0.0:
		side = 1.0
	var camera_world := target.to_global(Vector3(peek_offset.x * side, peek_offset.y, peek_offset.z))
	target.face_toward(camera_world)
	var peek_transform := global_transform.affine_inverse() * Transform3D(Basis.IDENTITY, camera_world).looking_at(target.global_position, Vector3.UP)
	_move_camera(peek_transform.origin, peek_transform.basis.get_rotation_quaternion(), peek_transition_time)

func _end_peek() -> void:
	if _peek_light.visible:
		_fade_peek_light(0.0, peek_transition_time)
	if _peek_hand == null:
		return
	_peek_hand.restore_facing()
	_peek_hand.show_selection = false
	_peek_hand.refresh_selection()
	_peek_hand.play_enabled = _peek_hand_was_playing
	_peek_hand = null

func _discard_from_table() -> void:
	if not hand.play_enabled or hand.draw_in_progress or hand.cards.is_empty():
		return
	# Leave the leaned position first so the rest of the hand comes back before the card goes.
	_enter_normal_view()
	hand.discard_selected()

func _swap_with_peeked_hand() -> void:
	if _peek_hand == null or _peek_hand.cards.is_empty() or hand.cards.is_empty():
		return
	hand.swap_card_with(_peek_hand, hand.selected_index, _peek_hand.selected_index)
	_end_peek()
	_enter_normal_view()

func _fade_peek_light(target_energy: float, duration: float) -> void:
	if _light_tween != null:
		_light_tween.kill()
	_light_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_light_tween.tween_property(_peek_light, "light_energy", target_energy, duration)
	if target_energy <= 0.0:
		_light_tween.tween_callback(_peek_light.set_visible.bind(false))

func _move_camera(target_position: Vector3, target_rotation: Quaternion, duration: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(camera, "position", target_position, duration)
	_tween.tween_property(camera, "quaternion", target_rotation, duration)
