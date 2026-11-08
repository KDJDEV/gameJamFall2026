class_name EndingSequence
extends Node

## The two endings, started by the dialogue (data/dialogue.json) through events:
##   begin_ending           decides which ending applies: unmatched cards left in the final pile, or
##                          every card matched
## Unmatched cards remain:
##   ending_cards_to_candle the dealer lifts the unmatched cards above the candle flame
##   ending_burn            the flame grows, the cards swirl into it, a roar, a white-out, then the
##                          game closes
## All cards matched:
##   ending_open_door       the player looks at the door, the red light comes in and it swings open
##   ending_fade_out        fade to black and close
##   ending_fade_white      fade to white and close (used when the player is caught cheating a third time)
##
## Test mode: tick `test_mode` on this node, pick `test_ending` and run the scene. It skips the
## opening, lays out a finished table and goes straight to the ending dialogue. Ignored in
## exported (non-debug) builds.

enum TestWinner { RANDOM, DEALER, LEFT_NPC, RIGHT_NPC, PLAYER }
enum TestEnding { UNMATCHED_CARDS, ALL_MATCHED }

const DEALER := &"dealer"
const LEFT_NPC := &"left_npc"
const RIGHT_NPC := &"right_npc"
const PLAYER := &"player"
const FLAME_SCENE := preload("res://Assets/flame/flame.tscn")

@export var dialogue_manager: DialogueManager
## The pile nobody draws from; whatever is left in it when the game ends is "unmatched".
@export var final_pile: CardPile
@export var draw_pile: CardPile
@export var dealer_set_area: TableSetArea
@export var left_set_area: TableSetArea
@export var right_set_area: TableSetArea
@export var player_set_area: TableSetArea
@export var flame: Node3D
## Candle lights that flicker (flicker.gd); their brightness and reach grow with the fire.
@export var flame_lights: Array[OmniLight3D] = []
@export var camera: Camera3D
## The player's view script (player_view.gd); its look_at_door() opens the door.
@export var player_view: Node

@export_group("Fire")
@export_range(1.0, 20.0) var flame_growth: float = 9.0
@export_range(0.5, 10.0) var peak_light_energy: float = 1.5
@export_range(1.0, 10.0) var peak_light_range: float = 2.5
@export_range(0.0, 0.1) var camera_shake: float = 0.02
@export var magic_color := Color(0.7, 0.25, 1.0)
@export var magic_core_color := Color(0.45, 0.1, 1.0)

@export_group("Timing")
@export_range(0.5, 5.0) var lift_duration: float = 2.0
## How long the cards take to reach full speed; they accelerate the whole time.
@export_range(0.5, 20.0) var swirl_duration: float = 7.0
@export_range(0.5, 10.0) var collapse_duration: float = 3.5
## Where in the build-up the screen starts to whiten, as a fraction of swirl_duration.
@export_range(0.0, 1.0) var whiteout_start_fraction: float = 0.3
## How white the screen is (0 to 1) by the end of the build-up; it goes fully white during the dive.
@export_range(0.0, 1.0) var semi_whiteout_alpha: float = 0.6
## How long the full white screen and the roar hold before the game closes.
@export_range(0.5, 10.0) var crash_duration: float = 4.0
## Top angular speed of the cards (radians per second).
@export_range(5.0, 80.0) var max_swirl_speed: float = 30.0
## How long the screen takes to fade to black in the all-matched ending, and how long it then rests.
@export_range(0.5, 10.0) var fade_out_duration: float = 3.0
@export_range(0.0, 10.0) var end_hold_duration: float = 1.5

@export_group("Audio")
## Plays when the cards start to rise.
@export var magic_stream: AudioStream = preload("res://Assets/audio/magic.wav")
## Fades in during the build-up and keeps going until the white-out cuts everything else off.
@export var roar_stream: AudioStream = preload("res://Assets/audio/roar.wav")
@export_range(-30.0, 12.0) var magic_volume_db: float = -8.0
@export_range(-30.0, 12.0) var roar_volume_db: float = -4.0
@export_range(-80.0, 0.0) var roar_fade_start_db: float = -38.0
## When the roar begins, as a fraction of the build-up (swirl_duration).
@export_range(0.0, 1.0) var roar_start_fraction: float = 0.15

@export_group("Test")
@export var test_mode: bool = false
@export var test_ending: TestEnding = TestEnding.UNMATCHED_CARDS
## Who wins; only used when test_ending is UNMATCHED_CARDS.
@export var test_winner: TestWinner = TestWinner.RANDOM
@export_range(0.0, 10.0) var test_start_delay: float = 1.0

class OrbitCard:
	var node: Node3D
	var start: Vector3
	var start_rotation: Vector3
	var base_scale: Vector3
	var angle: float
	var radius: float
	var height: float
	var speed: float
	var tilt: Vector3
	var order: float
	var phase: float
	var blend: float = 0.0

var _orbit_cards: Array[OrbitCard] = []
var _vortex: Node3D
var _fire_light: OmniLight3D
var _flash: ColorRect
var _fire_material: ShaderMaterial
var _magic_flame: Node3D
var _magic_material: ShaderMaterial
var _sparks: CPUParticles3D
var _roar_player: AudioStreamPlayer
var _flame_base_scale := Vector3.ONE
var _base_emission: float = 1.0
var _base_fire_color := Color.WHITE
var _light_bases: Array[Dictionary] = []

var _swirl: float = 0.0
var _collapse: float = 0.0
var _shake: float = 0.0
var _swirl_clock: float = 0.0

func _ready() -> void:
	set_process(false)
	if dialogue_manager != null:
		dialogue_manager.register_event("begin_ending", _begin_ending)
		dialogue_manager.register_event("ending_cards_to_candle", _lift_cards_above_candle)
		dialogue_manager.register_event("ending_burn", _burn)
		dialogue_manager.register_event("ending_open_door", _open_door)
		dialogue_manager.register_event("ending_fade_out", _fade_out)
		dialogue_manager.register_event("ending_fade_white", _fade_out.bind(Color.WHITE))
	if test_mode and OS.is_debug_build():
		_run_test()

func _areas() -> Dictionary:
	return {
		DEALER: dealer_set_area,
		LEFT_NPC: left_set_area,
		RIGHT_NPC: right_set_area,
		PLAYER: player_set_area,
	}

## The speaker id of whoever laid down the most sets. A tie goes to the dealer, then the left
## player, the right player and last the player (the order of the areas above).
func determine_winner() -> StringName:
	var areas := _areas()
	var winner := DEALER
	var best := -1
	for key in areas:
		var area := areas[key] as TableSetArea
		if area != null and area.get_set_count() > best:
			best = area.get_set_count()
			winner = key
	return winner

func _begin_ending() -> void:
	if final_pile == null or not final_pile.has_cards():
		dialogue_manager.play_sequence("ending_matched")
		return
	var winner := determine_winner()
	dialogue_manager.play_sequence("ending_win_%s" % winner)
	var questioners: Array[StringName] = [LEFT_NPC, RIGHT_NPC]
	questioners.erase(winner)
	dialogue_manager.play_sequence("ending_question_%s" % questioners.pick_random())
	dialogue_manager.play_sequence("ending_burn")

# ---------------------------------------------------------------------------------------------
# All cards matched: the door opens
# ---------------------------------------------------------------------------------------------

## The player looks at the door, the outside light turns on and the door swings open.
func _open_door() -> void:
	if player_view == null or not player_view.has_method("look_at_door"):
		push_warning("EndingSequence has no player view to open the door with.")
		return
	player_view.look_at_door()

func _fade_out(color: Color = Color.BLACK) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var cover := ColorRect.new()
	cover.color = Color(color, 0.0)
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(cover)
	var fade := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fade.tween_property(cover, "color:a", 1.0, fade_out_duration)
	fade.tween_method(_set_master_volume, 0.0, -60.0, fade_out_duration)
	await fade.finished
	await get_tree().create_timer(end_hold_duration).timeout
	get_tree().quit()

func _set_master_volume(db: float) -> void:
	AudioServer.set_bus_volume_db(0, db)

# ---------------------------------------------------------------------------------------------
# Unmatched cards: they float up above the candle
# ---------------------------------------------------------------------------------------------

func _lift_cards_above_candle() -> void:
	_prepare_fire()
	_vortex = Node3D.new()
	_vortex.name = "Vortex"
	add_child(_vortex)
	_vortex.global_position = flame.global_position if flame != null else final_pile.global_position + Vector3.UP * 0.1
	var cards := final_pile.cards.duplicate()
	final_pile.cards.clear()
	final_pile.count_changed.emit(0)
	for index in cards.size():
		var card := cards[index] as Node3D
		card.set_process(false)
		card.reparent(_vortex, true)
		var orbit := OrbitCard.new()
		orbit.node = card
		orbit.start = card.position
		orbit.start_rotation = card.rotation
		orbit.base_scale = card.scale
		orbit.angle = randf() * TAU
		orbit.radius = randf_range(0.04, 0.13)
		orbit.height = randf_range(0.12, 0.3)
		orbit.speed = randf_range(0.7, 1.25) * (1.0 if randf() > 0.15 else -1.0)
		orbit.tilt = Vector3(randf_range(-0.6, 0.6), randf() * TAU, randf_range(-0.6, 0.6))
		orbit.order = float(index) / maxf(cards.size() - 1, 1)
		orbit.phase = randf() * TAU
		_orbit_cards.append(orbit)
		var lift := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		lift.tween_interval(randf() * lift_duration * 0.5)
		lift.tween_property(orbit, "blend", 1.0, lift_duration * 0.5)
	set_process(true)
	_add_sparks()
	_play_sound(magic_stream, magic_volume_db)
	var kindle := create_tween()
	kindle.tween_method(_set_fire, 0.0, 0.12, lift_duration)
	await get_tree().create_timer(lift_duration + 0.5).timeout

# ---------------------------------------------------------------------------------------------
# Unmatched cards: fire, vortex, roar, white-out, close
# ---------------------------------------------------------------------------------------------

func _burn() -> void:
	if _vortex == null:
		await _lift_cards_above_candle()
	_build_flash()
	_start_roar()
	_start_whiteout()
	# The cards accelerate for the whole build-up while the fire keeps growing.
	var growth := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	growth.tween_method(_set_fire, 0.12, 0.8, swirl_duration)
	growth.tween_property(self, "_shake", 0.5, swirl_duration)
	growth.tween_property(self, "_swirl", 1.0, swirl_duration).set_trans(Tween.TRANS_LINEAR)
	await growth.finished

	var dive := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	dive.tween_method(_set_fire, 0.8, 1.0, collapse_duration)
	dive.tween_property(self, "_collapse", 1.0, collapse_duration)
	dive.tween_property(self, "_shake", 1.0, collapse_duration)
	dive.tween_property(_flash, "color:a", 1.0, collapse_duration)
	await dive.finished
	_crash()

## The screen starts to whiten partway through the build-up, so it is already half white when the
## roar gets loud, and goes fully white as the cards dive into the fire.
func _start_whiteout() -> void:
	await get_tree().create_timer(swirl_duration * whiteout_start_fraction).timeout
	var fade := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade.tween_property(_flash, "color:a", semi_whiteout_alpha, swirl_duration * (1.0 - whiteout_start_fraction))

## Starts early in the build-up, fades in quickly and keeps getting louder; loops until the white-out.
func _start_roar() -> void:
	if roar_stream == null:
		return
	var delay := swirl_duration * roar_start_fraction
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	var player := AudioStreamPlayer.new()
	_roar_player = player
	player.stream = roar_stream
	player.volume_db = roar_fade_start_db
	add_child(player)
	player.finished.connect(player.play)
	player.play()
	var fade := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	fade.tween_property(player, "volume_db", roar_volume_db, swirl_duration * 0.6)

func _play_sound(stream: AudioStream, volume_db: float) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	player.play()

func _crash() -> void:
	set_process(false)
	_vortex.visible = false
	if camera != null:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
	# Everything goes quiet except the roar, which keeps going over the white screen.
	for type in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for node in get_tree().root.find_children("*", type, true, false):
			if node != _roar_player:
				node.stop()
	await get_tree().create_timer(crash_duration).timeout
	get_tree().quit()

func _process(delta: float) -> void:
	_swirl_clock += delta
	for orbit in _orbit_cards:
		var fall := clampf(_collapse * 1.5 - orbit.order * 0.5, 0.0, 1.0)
		var turn := orbit.speed * (0.6 + max_swirl_speed * _swirl * _swirl) * (1.0 + fall * 1.5)
		orbit.angle += delta * turn
		var radius := orbit.radius * (1.0 + _swirl * 0.8) * (1.0 - fall)
		var height := orbit.height * (1.0 + _swirl * 0.5) + sin(_swirl_clock * 1.4 + orbit.phase) * 0.012
		height = lerpf(height, 0.03, fall * fall)
		var target := Vector3(cos(orbit.angle) * radius, height, sin(orbit.angle) * radius)
		orbit.node.position = orbit.start.lerp(target, orbit.blend)
		orbit.node.rotation = orbit.start_rotation.lerp(orbit.tilt + Vector3(orbit.angle * 0.6, -orbit.angle, 0.0), orbit.blend)
		orbit.node.scale = orbit.base_scale * (1.0 - fall)
		orbit.node.visible = fall < 1.0
	if camera != null and _shake > 0.0:
		camera.h_offset = randf_range(-1.0, 1.0) * _shake * camera_shake
		camera.v_offset = randf_range(-1.0, 1.0) * _shake * camera_shake

# 0 = the candle as it was, 1 = a roaring blaze. Called from tweens.
func _set_fire(value: float) -> void:
	if flame != null:
		var grown := lerpf(1.0, flame_growth, value)
		flame.scale = Vector3(_flame_base_scale.x * grown * 1.8, _flame_base_scale.y * grown, _flame_base_scale.z * grown * 1.8)
		if _magic_flame != null:
			# The purple fire towers over the candle's own flame.
			var magic := maxf(grown * 1.4, 0.01)
			_magic_flame.visible = value > 0.02
			_magic_flame.scale = Vector3(_flame_base_scale.x * magic * 1.8, _flame_base_scale.y * magic, _flame_base_scale.z * magic * 1.8)
	if _fire_material != null:
		_fire_material.set_shader_parameter("emission", lerpf(_base_emission, _base_emission * 1.6, value))
		_fire_material.set_shader_parameter("color", _base_fire_color.lerp(magic_color, minf(value * 3.0, 1.0)))
	if _magic_material != null:
		_magic_material.set_shader_parameter("emission", _base_emission * lerpf(0.8, 2.0, value))
	_fire_light.light_energy = peak_light_energy * value
	_fire_light.light_color = Color(1.0, 0.75, 0.45).lerp(magic_color, minf(value * 3.0, 1.0))
	if _sparks != null:
		_sparks.emitting = value > 0.05
		_sparks.speed_scale = lerpf(1.0, 3.0, value)
		_sparks.emission_sphere_radius = lerpf(0.03, 0.14, value)
	for entry in _light_bases:
		var light: OmniLight3D = entry["light"]
		light.set("min_energy", float(entry["min"]) * (1.0 + value * 2.0))
		light.set("max_energy", float(entry["max"]) * (1.0 + value * 2.0))
		light.omni_range = lerpf(float(entry["range"]), peak_light_range, value)
		light.light_color = (entry["color"] as Color).lerp(magic_color, minf(value * 3.0, 1.0))

func _prepare_fire() -> void:
	if _fire_light != null:
		return
	if flame != null:
		_flame_base_scale = flame.scale
		var particles := flame.get_node_or_null("GPUParticles3D") as GPUParticles3D
		if particles != null and particles.draw_pass_1 != null:
			_fire_material = particles.draw_pass_1.material as ShaderMaterial
		if _fire_material != null:
			_base_emission = float(_fire_material.get_shader_parameter("emission"))
			_base_fire_color = _fire_material.get_shader_parameter("color")
		_build_magic_flame()
	for light in flame_lights:
		if light != null:
			_light_bases.append({
				"light": light,
				"min": float(light.get("min_energy")),
				"max": float(light.get("max_energy")),
				"range": light.omni_range,
				"color": light.light_color,
			})
	_fire_light = OmniLight3D.new()
	_fire_light.light_color = Color(1.0, 0.75, 0.45)
	_fire_light.light_energy = 0.0
	_fire_light.omni_range = 8.0
	_fire_light.position = Vector3.UP * 0.15
	_fire_light.shadow_enabled = false
	add_child(_fire_light)
	if flame != null:
		_fire_light.global_position = flame.global_position + Vector3.UP * 0.15

# A second copy of the flame on top of the candle's, tinted purple, with its own material.
func _build_magic_flame() -> void:
	_magic_flame = FLAME_SCENE.instantiate() as Node3D
	flame.get_parent().add_child(_magic_flame)
	_magic_flame.transform = flame.transform
	_magic_flame.visible = false
	var particles := _magic_flame.get_node_or_null("GPUParticles3D") as GPUParticles3D
	if particles == null or particles.draw_pass_1 == null:
		return
	var mesh := particles.draw_pass_1.duplicate() as Mesh
	_magic_material = (mesh.material as ShaderMaterial).duplicate() as ShaderMaterial
	_magic_material.set_shader_parameter("color", magic_core_color)
	mesh.material = _magic_material
	particles.draw_pass_1 = mesh

# Purple embers that rise off the fire.
func _add_sparks() -> void:
	_sparks = CPUParticles3D.new()
	_sparks.emitting = false
	_sparks.amount = 90
	_sparks.lifetime = 1.6
	_sparks.local_coords = false
	_sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_sparks.emission_sphere_radius = 0.03
	_sparks.direction = Vector3.UP
	_sparks.spread = 30.0
	_sparks.initial_velocity_min = 0.15
	_sparks.initial_velocity_max = 0.6
	_sparks.gravity = Vector3(0.0, 0.2, 0.0)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.012
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = magic_color.lightened(0.3)
	quad.material = material
	_sparks.mesh = quad
	_vortex.add_child(_sparks)
	_sparks.position = Vector3.UP * 0.05

func _build_flash() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_flash = ColorRect.new()
	_flash.color = Color(1.0, 1.0, 1.0, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_flash)

# ---------------------------------------------------------------------------------------------
# Test mode
# ---------------------------------------------------------------------------------------------

func _run_test() -> void:
	dialogue_manager.mark_automatic_sequences_played()
	var intro := get_tree().get_first_node_in_group("intro_sequence") as IntroSequence
	if intro != null:
		intro.skip()
	# The draw pile builds its cards on the first frame.
	for frame in 3:
		await get_tree().process_frame
	await _stage_final_table()
	await get_tree().create_timer(test_start_delay).timeout
	_begin_ending()

## Lays the deck out as a finished game. Unmatched ending: complete sets on the tables (the winner
## gets 3 or 4, everyone else fewer) and everything else in the final pile. All-matched ending:
## every set on the tables and the final pile empty.
func _stage_final_table() -> void:
	var deck := CardDeck.find(get_tree())
	var set_size := deck.get_set_size() if deck != null else 3
	var groups := {}
	for card in draw_pile.cards:
		var set_id: int = card.get("set_id")
		if not groups.has(set_id):
			groups[set_id] = []
		groups[set_id].append(card)
	var complete: Array = []
	for set_id in groups:
		if groups[set_id].size() == set_size:
			complete.append(groups[set_id])
	complete.shuffle()

	var keys: Array = _areas().keys()
	if test_ending == TestEnding.ALL_MATCHED:
		for index in complete.size():
			var set_cards: Array = complete[index]
			for card in set_cards:
				draw_pile.cards.erase(card)
				card.set_process(true)
			(_areas()[keys[index % keys.size()]] as TableSetArea).receive_set(set_cards)
		print("Ending test: every card is matched (%d sets)." % complete.size())
		return
	var winner: StringName = keys.pick_random() if test_winner == TestWinner.RANDOM else keys[test_winner - 1]
	var winner_sets := randi_range(3, 4)
	for key in keys:
		var area := _areas()[key] as TableSetArea
		var wanted := winner_sets if key == winner else randi_range(0, winner_sets - 1)
		for index in wanted:
			if complete.is_empty():
				break
			var set_cards: Array = complete.pop_back()
			for card in set_cards:
				draw_pile.cards.erase(card)
				card.set_process(true)
			area.receive_set(set_cards)
	print("Ending test: winner is %s (%d sets)." % [winner, (_areas()[winner] as TableSetArea).get_set_count()])
	await final_pile.absorb_pile(draw_pile)
