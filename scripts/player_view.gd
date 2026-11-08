class_name PlayerView
extends Node3D

## Controls use the move_up / move_down / move_left / move_right / select input actions
## (Project Settings > Input Map), bound to every joystick and button key of the arcade cabinet.
## Up: look at the table (only the selected card stays in view); select there discards it and
## returns to your hand. From the table, left or right leans over to peek at the neighbouring
## player's hand: up/down pick one of their cards (up goes to the previous card, down to the next),
## select swaps it with your selected card. Leaning left, only right brings you back to the table
## view; leaning right, only left does.
## The longer you stay leaned over, the louder your heartbeat gets and the more the screen closes in.
enum ViewState { NORMAL, TABLE, PEEK }

## You leaned over to peek at this player's hand.
signal peek_started(hand_node: Node3D)
## You swapped one of your cards with a card from this player's hand.
signal swapped(hand_node: Node3D)

@export var camera: Camera3D
@export var hand: Node3D
@export var left_hand: Node3D
@export var right_hand: Node3D
@export_range(0.0, 90.0) var look_down_degrees: float = 30.0
@export var camera_lean_offset := Vector3(0.0, 0.0, -0.25)
@export_range(0.1, 2.0) var transition_time: float = 0.45
@export var peek_offset := Vector3(0.45, 0.5, 0.05)
@export_range(0.1, 2.0) var peek_transition_time: float = 0.6
## A small light that follows the card you are peeking at. It is dim, short-ranged and casts
## shadows, so only the cards are lit and the person holding them stays in the dark.
@export_range(0.0, 2.0) var peek_light_energy: float = 0.06
@export_range(0.1, 2.0) var peek_light_range: float = 0.4
## How far in front of the card (toward the camera) the light floats.
@export_range(0.0, 0.5) var peek_light_distance: float = 0.12
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
@export var test_door_look_delay: float = 0.0

@export_group("Peek tension")
## Looped while you are leaned over; it gets louder and faster the longer you stay.
@export var heartbeat_stream: AudioStream = preload("res://Assets/audio/heartbeat.wav")
@export_range(-60.0, 12.0) var heartbeat_min_db: float = -10.0
@export_range(-60.0, 24.0) var heartbeat_max_db: float = 14.0
## Playback speed of the heartbeat when you are calm and when the owner is about to look back down.
@export_range(0.5, 1.5) var heartbeat_calm_pitch: float = 0.85
@export_range(0.5, 2.0) var heartbeat_danger_pitch: float = 1.2
## Where the beats fall in the clip (seconds); the vignette pulses on them.
@export var heartbeat_beat_times: PackedFloat32Array = PackedFloat32Array([0.03, 0.29])
## How tense it is while you are leaned over and safe (0 to 1). It only climbs above this when the owner
## of the hand is about to stop staring at someone else and look back at their cards.
@export_range(0.0, 1.0) var calm_tension: float = 0.3
## How fast the tension rises when the danger grows (per second).
@export_range(0.1, 5.0) var tension_rise_speed: float = 1.5
@export_range(0.0, 1.0) var vignette_max_strength: float = 0.6
## How solid the red gets at the very edge of the screen, at full strength.
@export_range(0.0, 1.0) var vignette_max_alpha: float = 0.75
## The room is nearly black, so a dark red edge shows up far better than black.
@export var vignette_color := Color(0.5, 0.0, 0.03)

## Set every frame by the cheat watcher while you peek: 0 while the owner of the hand is staring at
## someone else, rising to 1 as they are about to look back down at their cards.
var peek_danger: float = 0.0
## 0 to 1: how tense you are while leaned over, which drives the heartbeat and the vignette.
var tension: float = 0.0

var view_state: ViewState = ViewState.NORMAL
var _looking_at_door: bool = false
var _camera_rest_quaternion: Quaternion
var _camera_rest_position: Vector3
var _tween: Tween
var _peek_hand: Node3D
var _peek_light: OmniLight3D
var _light_tween: Tween
var _hold_repeat := HoldRepeat.new(0.17, 0.17, &"move_up", &"move_down")
## 1 or -1: which way up/down scroll through the peeked hand, flipped for the hand on the right so the
## cards read in the same direction from where you lean.
var _peek_scroll_sign: int = 1
var _heartbeat: AudioStreamPlayer
var _vignette_material: ShaderMaterial

const VIGNETTE_CODE := """
shader_type canvas_item;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform float max_alpha : hint_range(0.0, 1.0) = 0.75;
uniform vec4 tint : source_color = vec4(0.5, 0.0, 0.03, 1.0);
void fragment() {
	// 0 at the middle of the screen, 1 in the corners.
	float d = length((UV - vec2(0.5)) * vec2(1.4, 1.0)) / 0.86;
	float edge = mix(0.8, 0.05, strength);
	float a = smoothstep(edge, edge + 0.5, d) * clamp(strength * 2.0, 0.0, 1.0) * max_alpha;
	a *= 0.75 + 0.25 * pulse;
	COLOR = vec4(tint.rgb, a);
}
"""

func _ready() -> void:
	_camera_rest_quaternion = camera.quaternion
	_camera_rest_position = camera.position
	hand.lap_anchor = self
	_build_tension_effects()
	_peek_light = OmniLight3D.new()
	_peek_light.top_level = true
	_peek_light.light_color = Color(1.0, 0.85, 0.6)
	_peek_light.light_energy = 0.0
	_peek_light.omni_range = peek_light_range
	_peek_light.shadow_enabled = true
	_peek_light.visible = false
	add_child(_peek_light)
	if test_door_look_delay > 0.0:
		if door_look_target == null:
			push_warning("Door look test is enabled but no door target is assigned.")
		else:
			get_tree().create_timer(test_door_look_delay).timeout.connect(look_at_door)

func _process(delta: float) -> void:
	_update_tension(delta)
	if view_state != ViewState.NORMAL and not _looking_at_door and not hand.play_enabled:
		_end_peek()
		_enter_normal_view()
	# Holding the joystick keeps scrolling through the peeked hand's cards.
	if view_state == ViewState.PEEK and _peek_hand != null and hand.play_enabled and not _looking_at_door:
		var direction := _hold_repeat.step(delta)
		if direction != 0:
			_peek_hand.move_selection(direction * _peek_scroll_sign)
		_follow_peeked_card(delta)
	else:
		_hold_repeat.reset()

func _unhandled_input(event: InputEvent) -> void:
	if _looking_at_door or not hand.play_enabled:
		return
	var handled := true
	match view_state:
		ViewState.NORMAL:
			if event.is_action_pressed("move_up"):
				_enter_table_view()
			else:
				handled = false
		ViewState.TABLE:
			if event.is_action_pressed("move_down"):
				_enter_normal_view()
			elif event.is_action_pressed("select"):
				_discard_from_table()
			elif event.is_action_pressed("move_left"):
				_start_peek(left_hand)
			elif event.is_action_pressed("move_right"):
				_start_peek(right_hand)
			else:
				handled = false
		ViewState.PEEK:
			if event.is_action_pressed("move_up"):
				_peek_hand.move_selection(-_peek_scroll_sign)
			elif event.is_action_pressed("move_down"):
				_peek_hand.move_selection(_peek_scroll_sign)
			# You leaned out to the left or right, so only the opposite direction brings you back.
			elif event.is_action_pressed("move_right" if _peek_hand == left_hand else "move_left"):
				_end_peek()
				_enter_table_view()
			elif event.is_action_pressed("move_left") or event.is_action_pressed("move_right"):
				pass
			elif event.is_action_pressed("select"):
				_swap_with_peeked_hand()
			else:
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
	_peek_scroll_sign = -1 if target == right_hand else 1
	target.frozen = true
	target.show_selection = true
	target.refresh_selection()
	hand.set_held_mode(true, true)
	_peek_light.global_position = _peek_light_target(target)
	_peek_light.visible = true
	_fade_peek_light(peek_light_energy, peek_transition_time)
	var side := signf(target.to_local(global_position).x)
	if side == 0.0:
		side = 1.0
	var camera_world := target.to_global(Vector3(peek_offset.x * side, peek_offset.y, peek_offset.z))
	target.set_peek_view(camera_world)
	var peek_transform := global_transform.affine_inverse() * Transform3D(Basis.IDENTITY, camera_world).looking_at(target.global_position, Vector3.UP)
	_move_camera(peek_transform.origin, peek_transform.basis.get_rotation_quaternion(), peek_transition_time)
	peek_started.emit(target)

## The hand you are leaning over to look at, or null.
func get_peeked_hand() -> Node3D:
	return _peek_hand

## True while the camera is looking at the door (the endings), when you cannot do anything.
func is_looking_at_door() -> bool:
	return _looking_at_door

## Throws you back to your own hand, e.g. when you were caught.
func abort_peek() -> void:
	_end_peek()
	_enter_normal_view()

func _end_peek() -> void:
	if _peek_light.visible:
		_fade_peek_light(0.0, peek_transition_time)
	if _peek_hand == null:
		return
	_peek_hand.clear_peek_view()
	_peek_hand.show_selection = false
	_peek_hand.refresh_selection()
	_peek_hand.frozen = false
	_peek_hand = null

func _discard_from_table() -> void:
	if not hand.play_enabled or hand.draw_in_progress or hand.cards.is_empty():
		return
	_enter_normal_view()
	hand.discard_selected()

func _swap_with_peeked_hand() -> void:
	if _peek_hand == null or _peek_hand.cards.is_empty() or hand.cards.is_empty():
		return
	var victim := _peek_hand
	hand.swap_card_with(_peek_hand, hand.selected_index, _peek_hand.selected_index)
	_end_peek()
	_enter_normal_view()
	swapped.emit(victim)

func _update_tension(delta: float) -> void:
	var peeking := view_state == ViewState.PEEK and _peek_hand != null and not _looking_at_door
	if peeking:
		# Steady while the owner is staring at someone else; it only climbs as they are about to look back.
		var target := calm_tension + (1.0 - calm_tension) * clampf(peek_danger, 0.0, 1.0)
		var speed := tension_rise_speed if target > tension else tension_rise_speed * 0.5
		tension = move_toward(tension, target, speed * delta)
	else:
		tension = maxf(tension - delta * 1.5, 0.0)
	_vignette_material.set_shader_parameter("strength", tension * vignette_max_strength)
	_vignette_material.set_shader_parameter("tint", vignette_color)
	_vignette_material.set_shader_parameter("max_alpha", vignette_max_alpha)
	if tension <= 0.0:
		_vignette_material.set_shader_parameter("pulse", 0.0)
		if _heartbeat.playing:
			_heartbeat.stop()
		return
	if not _heartbeat.playing:
		_heartbeat.play()
	_heartbeat.volume_db = lerpf(heartbeat_min_db, heartbeat_max_db, tension)
	_heartbeat.pitch_scale = lerpf(heartbeat_calm_pitch, heartbeat_danger_pitch, clampf((tension - calm_tension) / maxf(1.0 - calm_tension, 0.01), 0.0, 1.0))
	_vignette_material.set_shader_parameter("pulse", _beat_pulse(_heartbeat.get_playback_position()))

# 1 right on a beat, fading away quickly after it.
func _beat_pulse(position_in_clip: float) -> float:
	var pulse := 0.0
	for beat_time in heartbeat_beat_times:
		if position_in_clip >= beat_time:
			pulse = maxf(pulse, exp(-(position_in_clip - beat_time) * 9.0))
	return pulse

func _build_tension_effects() -> void:
	_heartbeat = AudioStreamPlayer.new()
	_heartbeat.name = "Heartbeat"
	_heartbeat.stream = _looping(heartbeat_stream)
	_heartbeat.volume_db = heartbeat_min_db
	# Backup in case the clip does not loop by itself: start it again as soon as it ends.
	_heartbeat.finished.connect(func() -> void:
		if tension > 0.0:
			_heartbeat.play())
	add_child(_heartbeat)
	# Above the scene, below the opening blur (5), the speaker icons (6) and the subtitles (10).
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	var shader := Shader.new()
	shader.code = VIGNETTE_CODE
	_vignette_material = ShaderMaterial.new()
	_vignette_material.shader = shader
	_vignette_material.set_shader_parameter("strength", 0.0)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = _vignette_material
	layer.add_child(rect)

# Plays the clip over and over without a gap.
func _looping(stream: AudioStream) -> AudioStream:
	var wav := stream as AudioStreamWAV
	if wav == null:
		return stream
	wav = wav.duplicate() as AudioStreamWAV
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	var bytes_per_frame := (2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if wav.stereo else 1)
	wav.loop_end = wav.data.size() / bytes_per_frame
	return wav

func _peek_light_target(hand_node: Node3D) -> Vector3:
	if hand_node.cards.is_empty():
		return hand_node.global_position
	var card: Node3D = hand_node.cards[clampi(hand_node.selected_index, 0, hand_node.cards.size() - 1)]
	var toward_camera := (camera.global_position - card.global_position).normalized()
	return card.global_position + toward_camera * peek_light_distance

func _follow_peeked_card(delta: float) -> void:
	var weight := 1.0 - exp(-12.0 * delta)
	_peek_light.global_position = _peek_light.global_position.lerp(_peek_light_target(_peek_hand), weight)

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
