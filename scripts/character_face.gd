class_name CharacterFace
extends Node3D

## Mostly the character looks down at their cards and blinks now and then. Once in a while they raise
## and turn their head to stare at someone else (another character or you) for ten seconds or more.
## Dialogue lines can make a speaker look at a listener (see "look_at" in data/dialogue.json).
##
## Opening: everyone stares at you while you wake up, then keeps looking at the others instead of at
## their cards until the dealer has given them their first card.
##
## Other code can ask who is watching: is_looking_at(&"player") is true while this character's eyes
## are on you.

signal gaze_changed(face: CharacterFace, target_id: StringName)

const PLAYER := &"player"

## Matches the "speaker" ids in data/dialogue.json and the DialogueSpeaker nodes.
@export var speaker_id: StringName = &""
## Leave empty to use the default faces.
@export var faces: FaceSet
## Found automatically (the first Decal child) when left empty.
@export var decal: Decal
## Found through the "dialogue_manager" group when left empty.
@export var dialogue_manager: DialogueManager
## This character's hand. Until it receives its first card the character does not look down.
@export var hand: Node3D

@export_group("Looking around")
## Time spent reading their cards between stares (never less than the minimum).
@export_range(0.5, 120.0) var look_up_interval_min: float = 13.0
@export_range(0.5, 120.0) var look_up_interval_max: float = 30.0
## How long a stare at someone lasts (never less than the minimum).
@export_range(0.3, 60.0) var look_up_duration_min: float = 13.0
@export_range(0.3, 60.0) var look_up_duration_max: float = 18.0
## How likely the player is picked compared with each other character (which count 1).
@export_range(0.0, 3.0) var player_weight: float = 0.6

@export_group("Opening")
## After you wake up, how long they keep staring at you before looking at each other.
@export_range(0.0, 20.0) var opening_stare_min: float = 2.5
@export_range(0.0, 20.0) var opening_stare_max: float = 5.0
## Until they get a card, how long they look at one person before moving on to another.
@export_range(1.0, 30.0) var waiting_look_min: float = 5.0
@export_range(1.0, 30.0) var waiting_look_max: float = 10.0

@export_group("Blinking")
@export_range(0.5, 15.0) var blink_interval_min: float = 2.0
@export_range(0.5, 15.0) var blink_interval_max: float = 6.0
@export_range(0.05, 0.5) var blink_duration: float = 0.14
@export_range(0.0, 1.0) var double_blink_chance: float = 0.15

@export_group("Head")
@export_range(10.0, 120.0) var max_yaw_degrees: float = 70.0
## Head tilt while reading their cards (positive looks down).
@export_range(-20.0, 40.0) var reading_pitch_degrees: float = 12.0
@export_range(1.0, 20.0) var turn_speed: float = 7.0

## Who this character is looking at right now: a speaker id, "player", or empty when reading.
var gaze_target: StringName = &""

var _rest_rotation := Vector3.ZERO
var _look_timer: float = 0.0
var _blink_timer: float = 0.0
var _blink_left: float = 0.0
var _queued_blinks: int = 0
var _last_target: StringName = &""
var _override_target: StringName = &""
var _override_delay: float = 0.0
var _override_time: float = 0.0
var _pose: FaceSet.Pose = FaceSet.Pose.DOWN
var _target_yaw: float = 0.0
var _target_pitch: float = 0.0
var _shown: Texture2D
var _waiting_for_cards: bool = false
var _intro: IntroSequence

func _enter_tree() -> void:
	add_to_group("character_face")

func _ready() -> void:
	if faces == null:
		faces = FaceSet.new()
	if decal == null:
		for child in get_children():
			if child is Decal:
				decal = child
				break
	_rest_rotation = rotation
	_target_pitch = deg_to_rad(reading_pitch_degrees)
	_look_timer = randf_range(look_up_interval_min, look_up_interval_max)
	_blink_timer = randf_range(blink_interval_min, blink_interval_max)
	if dialogue_manager == null:
		dialogue_manager = get_tree().get_first_node_in_group("dialogue_manager") as DialogueManager
	if dialogue_manager != null:
		dialogue_manager.look_requested.connect(_on_look_requested)
	_begin_opening()
	_show_face()

# Staring at the player while they wake up, then at each other, until the first card arrives.
func _begin_opening() -> void:
	if hand == null or not hand.get("cards").is_empty():
		return
	_waiting_for_cards = true
	hand.card_drawn.connect(_on_card_received, CONNECT_ONE_SHOT)
	gaze_target = PLAYER
	_intro = get_tree().get_first_node_in_group("intro_sequence") as IntroSequence
	if _intro != null and not _intro.is_finished:
		_intro.finished.connect(_on_intro_finished, CONNECT_ONE_SHOT)
		_look_timer = INF
	else:
		_look_timer = randf_range(opening_stare_min, opening_stare_max)

func _on_intro_finished() -> void:
	_look_timer = randf_range(opening_stare_min, opening_stare_max)

func _on_card_received(_card: Node3D) -> void:
	_waiting_for_cards = false
	_set_gaze(&"")
	_look_timer = randf_range(look_up_interval_min, look_up_interval_max)

## True while the character is looking down at their own cards: not staring at anyone and with the
## head lowered and settled (so not while it is still coming back down from a stare).
func is_looking_at_cards() -> bool:
	if _waiting_for_cards or gaze_target != &"":
		return false
	var yaw_off := absf(wrapf(rotation.y - _rest_rotation.y, -PI, PI))
	var pitch_off := absf(rotation.x - (_rest_rotation.x + deg_to_rad(reading_pitch_degrees)))
	return yaw_off < 0.2 and pitch_off < 0.15

## How long until this character stops staring and looks back down at their cards: 0 if they already
## are, INF while there is no end in sight (before their first card).
func seconds_until_looks_down() -> float:
	if _waiting_for_cards:
		return INF
	if gaze_target == &"":
		return 0.0
	if _override_time > 0.0 and _override_delay <= 0.0:
		return _override_time
	return maxf(_look_timer, 0.0)

func is_looking_at(target_id: StringName) -> bool:
	return gaze_target == target_id

## Look at someone for a while, overriding the idle behaviour. Used by the dialogue.
func look_at_for(target_id: StringName, duration: float, delay: float = 0.0) -> void:
	_override_target = target_id
	_override_delay = delay
	_override_time = duration

func _on_look_requested(speaker: StringName, target: StringName, duration: float, look_back: bool) -> void:
	if speaker_id == &"":
		return
	if speaker == speaker_id:
		look_at_for(target, duration)
	elif look_back and target == speaker_id:
		look_at_for(speaker, maxf(duration * 0.7, 0.8), randf_range(0.4, 0.9))

func _process(delta: float) -> void:
	_update_blink(delta)
	_update_gaze(delta)
	_update_head(delta)
	_show_face()

func _update_blink(delta: float) -> void:
	if _blink_left > 0.0:
		_blink_left -= delta
		if _blink_left <= 0.0 and _queued_blinks > 0:
			_queued_blinks -= 1
			_blink_timer = blink_duration
		return
	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink_left = blink_duration
		_queued_blinks = 1 if randf() < double_blink_chance else 0
		_blink_timer = randf_range(blink_interval_min, blink_interval_max)

func _update_gaze(delta: float) -> void:
	if _override_time > 0.0:
		if _override_delay > 0.0:
			_override_delay -= delta
			return
		if gaze_target != _override_target:
			_set_gaze(_override_target)
		_override_time -= delta
		if _override_time <= 0.0:
			if _waiting_for_cards:
				_look_at_someone_while_waiting()
			else:
				_set_gaze(&"")
				_look_timer = randf_range(look_up_interval_min, look_up_interval_max)
		return
	_look_timer -= delta
	if _look_timer > 0.0:
		return
	if _waiting_for_cards:
		_look_at_someone_while_waiting()
		return
	if gaze_target == &"":
		var target := _pick_target()
		if target == &"":
			_look_timer = look_up_interval_min
			return
		_last_target = target
		_set_gaze(target)
		_look_timer = randf_range(look_up_duration_min, look_up_duration_max)
	else:
		_set_gaze(&"")
		_look_timer = randf_range(look_up_interval_min, look_up_interval_max)

func _look_at_someone_while_waiting() -> void:
	var target := _pick_target(false)
	if target != &"":
		_last_target = target
		_set_gaze(target)
	_look_timer = randf_range(waiting_look_min, waiting_look_max)

func _set_gaze(target: StringName) -> void:
	var changed := target != gaze_target
	gaze_target = target
	if changed:
		gaze_changed.emit(self, target)

# Someone other than the character we looked at last time, with the player counting by player_weight.
func _pick_target(include_player: bool = true) -> StringName:
	var options: Array[StringName] = []
	var weights := PackedFloat32Array()
	for node in get_tree().get_nodes_in_group("character_face"):
		var other := node as CharacterFace
		if other != null and other != self and other.speaker_id != &"":
			options.append(other.speaker_id)
			weights.append(0.0 if other.speaker_id == _last_target else 1.0)
	if include_player:
		options.append(PLAYER)
		weights.append(0.0 if _last_target == PLAYER else player_weight)
	var total := 0.0
	for weight in weights:
		total += weight
	if total <= 0.0:
		return options.pick_random() if not options.is_empty() else &""
	return options[RandomNumberGenerator.new().rand_weighted(weights)]

func _target_position(target_id: StringName) -> Variant:
	if target_id == PLAYER:
		var camera := get_viewport().get_camera_3d()
		return camera.global_position if camera != null else null
	for node in get_tree().get_nodes_in_group("character_face"):
		var other := node as CharacterFace
		if other != null and other.speaker_id == target_id:
			return other.global_position
	# Anyone else with a speaker marker, e.g. the knight.
	for node in get_tree().get_nodes_in_group("dialogue_speaker"):
		var speaker := node as DialogueSpeaker
		if speaker != null and speaker.speaker_id == target_id:
			return speaker.global_position
	return null

# Works out which texture to show and where the head should point.
func _update_head(delta: float) -> void:
	var reading_pitch := deg_to_rad(reading_pitch_degrees)
	_pose = FaceSet.Pose.DOWN
	_target_yaw = 0.0
	_target_pitch = reading_pitch
	var point: Variant = _target_position(gaze_target) if gaze_target != &"" else null
	var parent := get_parent() as Node3D
	if point != null and parent != null:
		var local: Vector3 = parent.to_local(point as Vector3) - position
		var yaw := wrapf(atan2(local.x, local.z) - _rest_rotation.y, -PI, PI)
		var limit := deg_to_rad(max_yaw_degrees)
		var horizontal := Vector2(local.x, local.z).length()
		_target_pitch = clampf(atan2(-local.y, maxf(horizontal, 0.001)), -0.35, 0.35)
		_target_yaw = clampf(yaw, -limit, limit)
		_pose = FaceSet.Pose.FORWARD
	var weight := 1.0 - exp(-turn_speed * delta)
	rotation.y = lerp_angle(rotation.y, _rest_rotation.y + _target_yaw, weight)
	rotation.x = lerp_angle(rotation.x, _rest_rotation.x + _target_pitch, weight)

func _show_face() -> void:
	if decal == null or faces == null:
		return
	var texture := faces.get_texture(_pose, _blink_left > 0.0)
	if texture != _shown:
		_shown = texture
		decal.texture_albedo = texture
