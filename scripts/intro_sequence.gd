class_name IntroSequence
extends Node

signal finished

@export var ambience: AudioStreamPlayer
@export var ring_stream: AudioStream = preload("res://Assets/audio/ring.mp3")
@export_range(-60.0, 6.0) var ring_volume_db: float = -12.0
@export_range(0.0, 20.0) var black_duration: float = 4.0
@export_range(0.5, 20.0) var blur_duration: float = 5.0
@export_range(0.0, 20.0) var ambience_fade_duration: float = 6.0
@export var ambience_target_db: float = 16.0

@export var camera: Camera3D
@export_range(0.0, 60.0) var head_droop_degrees: float = 35.0
@export_range(0.0, 90.0) var look_left_degrees: float = 32.0
@export_range(0.0, 90.0) var look_right_degrees: float = 38.0
@export_range(0.0, 60.0) var look_up_degrees: float = 22.0
@export_range(0.3, 3.0) var head_speed: float = 1.0
@export_range(0.0, 3.0) var head_sway_degrees: float = 0.8

var is_finished: bool = false
var _rest_rotation := Quaternion.IDENTITY
var _material: ShaderMaterial
var _path: Array[Vector2] = []
var _path_times: Array[float] = []
var _path_total: float = 0.0
var _path_elapsed: float = 0.0
var _path_active: bool = false
var _skipped: bool = false
var _overlay_layer: CanvasLayer

signal _head_done

func _enter_tree() -> void:
	add_to_group("intro_sequence")

func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/eyes_open.gdshader")
	_material.set_shader_parameter("openness", 0.0)
	_material.set_shader_parameter("blur", 1.0)

	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_overlay_layer = layer
	var overlay := ColorRect.new()
	overlay.color = Color.BLACK
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.material = _material
	layer.add_child(overlay)
	if ambience != null:
		ambience.stop()
		ambience.volume_db = -60.0
	if camera != null:
		_rest_rotation = camera.quaternion
		_build_head_path()
	
		_apply_look(_path[0])
	set_process(false)
	_play()

func _input(event: InputEvent) -> void:
	if not is_finished and event is InputEventKey:
		get_viewport().set_input_as_handled()

## Jumps to the end of the opening (eyes open, camera at rest). Only works while the screen is
## still black, before the ring sounds; used by the ending test mode.
func skip() -> void:
	if is_finished or _skipped:
		return
	_skipped = true
	_path_active = false
	set_process(false)
	if camera != null:
		camera.quaternion = _rest_rotation
	if ambience != null:
		ambience.volume_db = ambience_target_db
		ambience.play()
	_overlay_layer.queue_free()
	is_finished = true
	finished.emit()

func _play() -> void:
	await get_tree().create_timer(black_duration).timeout
	if _skipped:
		return
	var ring := AudioStreamPlayer.new()
	ring.stream = ring_stream
	ring.volume_db = ring_volume_db
	add_child(ring)
	ring.play()
	if ambience != null:
		ambience.play()
		var fade := create_tween()
		fade.tween_property(ambience, "volume_db", ambience_target_db, ambience_fade_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var focus := create_tween()
	focus.tween_method(_set_blur, 1.0, 0.0, blur_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	var lids := create_tween().set_trans(Tween.TRANS_SINE)
	lids.tween_method(_set_openness, 0.0, 0.3, 0.9).set_ease(Tween.EASE_OUT)
	lids.tween_interval(0.3)
	lids.tween_method(_set_openness, 0.3, 0.08, 0.35).set_ease(Tween.EASE_IN)
	lids.tween_interval(0.25)
	lids.tween_method(_set_openness, 0.08, 1.0, 1.8).set_ease(Tween.EASE_OUT)
	if camera != null:
		_path_elapsed = 0.0
		_path_active = true
		set_process(true)
		await _head_done
	if lids.is_running():
		await lids.finished
	if focus.is_running():
		await focus.finished
	is_finished = true
	finished.emit()

func _build_head_path() -> void:
	var left := look_left_degrees
	var right := -look_right_degrees
	var up := look_up_degrees
	var droop := -head_droop_degrees
	var waypoints := [
		[0.0, droop, 0.0],
		[4.0, droop * 0.4, 1.4],
		[9.0, droop * 0.2, 0.9],
		[left * 0.9, -2.0, 1.0],
		[left, 1.5, 0.7],
		[left * 0.25, 2.0, 0.7],
		[right * 0.9, 2.5, 0.9],
		[right, 4.0, 0.7],
		[right * 0.35, up * 0.5, 0.9],
		[right * 0.05, up, 0.8],
		[-2.0, up * 0.9, 0.6],
		[0.0, 0.0, 1.1],
	]
	_path.clear()
	_path_times.clear()
	var time := 0.0
	for waypoint in waypoints:
		time += waypoint[2]
		_path.append(Vector2(deg_to_rad(waypoint[0]), deg_to_rad(waypoint[1])))
		_path_times.append(time)
	_path_total = time

func _process(delta: float) -> void:
	if not _path_active:
		return
	_path_elapsed += delta * head_speed
	var elapsed := minf(_path_elapsed, _path_total)
	var look := _sample_path(elapsed)

	var sway_weight := clampf((_path_total - elapsed) / 1.5, 0.0, 1.0) * deg_to_rad(head_sway_degrees)
	look += Vector2(
		sin(elapsed * 2.3) + 0.5 * sin(elapsed * 5.1 + 1.0),
		sin(elapsed * 1.9 + 2.0) + 0.5 * sin(elapsed * 4.3)
	) * sway_weight
	_apply_look(look)
	if _path_elapsed >= _path_total:
		_path_active = false
		set_process(false)
		camera.quaternion = _rest_rotation
		_head_done.emit()

# Catmull-Rom
func _sample_path(elapsed: float) -> Vector2:
	var last := _path.size() - 1
	var segment := 1
	while segment < last and elapsed > _path_times[segment]:
		segment += 1
	var from_index := segment - 1
	var start_time := _path_times[from_index]
	var end_time := _path_times[segment]
	var weight := clampf((elapsed - start_time) / maxf(end_time - start_time, 0.0001), 0.0, 1.0)
	var before := _path[maxi(from_index - 1, 0)]
	var after := _path[mini(segment + 1, last)]
	var duration := end_time - start_time
	var before_time := _path_times[from_index - 1] - start_time if from_index > 0 else -duration
	var after_time := _path_times[segment + 1] - start_time if segment < last else duration * 2.0
	return _path[from_index].cubic_interpolate_in_time(_path[segment], before, after, weight, duration, before_time, after_time)

func _apply_look(value: Vector2) -> void:
	camera.quaternion = Quaternion(Vector3.UP, value.x) * _rest_rotation * Quaternion(Vector3.RIGHT, value.y)

func _set_blur(value: float) -> void:
	_material.set_shader_parameter("blur", value)

func _set_openness(value: float) -> void:
	_material.set_shader_parameter("openness", value)
