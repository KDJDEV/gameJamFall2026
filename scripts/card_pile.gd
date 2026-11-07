class_name CardPile
extends Node3D

signal count_changed(count: int)

@export var card_scene: PackedScene
@export_range(0, 52) var visible_cards: int = 6
@export var face_down: bool = true
@export var fill_from_deck: bool = false
@export var stack_offset: float = 0.003
@export_range(0.1, 2.0) var receive_duration: float = 0.45
@export_range(0.02, 0.3) var shuffle_split_distance: float = 0.09
@export_range(0.0, 0.1) var shuffle_lift: float = 0.025

var cards: Array[Node3D] = []
var _shuffle_audio: AudioStreamPlayer3D
var _shuffle_sounds: Array[AudioStream] = [
	preload("res://Assets/audio/cardDraw1.mp3"),
	preload("res://Assets/audio/cardDraw2.mp3")
]

func has_cards() -> bool:
	return not cards.is_empty()

func consume_top_card() -> int:
	if cards.is_empty():
		return -1
	var card: Node3D = cards.pop_back()
	var set_id: int = card.get("set_id") if card.get("set_id") != null else -1
	card.queue_free()
	count_changed.emit(cards.size())
	return set_id

func _ready() -> void:
	if card_scene == null:
		card_scene = preload("res://card.tscn")
	if fill_from_deck:
		_build_visual_stack.call_deferred()
	else:
		_build_visual_stack()

func _build_visual_stack() -> void:
	var deck := CardDeck.find(get_tree())
	var count := visible_cards
	if fill_from_deck and deck != null:
		count = deck.remaining()
	for index in count:
		var card := card_scene.instantiate() as Node3D
		if card == null:
			continue
		add_child(card)
		if deck != null:
			deck.apply_to_card(card, deck.deal_set_id())
		_set_card_in_stack(card, index)
		cards.append(card)
	count_changed.emit(cards.size())

func _set_card_in_stack(card: Node3D, index: int) -> void:
	var stack_position := Vector3(0.0, 0.0, -index * stack_offset)
	if card.has_method("set_static_pose"):
		card.set_static_pose(stack_position, Vector3.ZERO, face_down)
	else:
		card.position = stack_position
		card.rotation = Vector3.ZERO
		if card.has_method("set_face_up"):
			card.set_face_up(face_down)
	card.set_meta("pile_index", index)
	card.set_process(false)

func _stack_position(index: int) -> Vector3:
	return Vector3(0.0, 0.0, -index * stack_offset)

func _play_shuffle_sound() -> void:
	if _shuffle_audio == null:
		_shuffle_audio = AudioStreamPlayer3D.new()
		_shuffle_audio.volume_db = 0.0
		add_child(_shuffle_audio)
	_shuffle_audio.stream = _shuffle_sounds.pick_random()
	_shuffle_audio.pitch_scale = randf_range(1.0, 1.4)
	_shuffle_audio.play()

func shuffle(passes: int = 2) -> void:
	if cards.size() < 2:
		return
	for pass_index in passes:
		await _shuffle_pass()

func _shuffle_pass() -> void:
	var half := cards.size() / 2
	var split_tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for index in cards.size():
		var is_top_half := index >= half
		var side := 1.0 if is_top_half else -1.0
		var lift := -shuffle_lift if is_top_half else 0.0
		var apart := _stack_position(index) + Vector3(side * shuffle_split_distance, 0.0, lift)
		split_tween.tween_property(cards[index], "position", apart, 0.3)
	_play_shuffle_sound()
	await split_tween.finished
	cards.shuffle()
	var drop_tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var drop_delay := 0.025
	for index in cards.size():
		var card := cards[index]
		drop_tween.tween_property(card, "position", _stack_position(index), 0.2).set_delay(index * drop_delay)
		if index % 4 == 0:
			drop_tween.tween_callback(_play_shuffle_sound).set_delay(index * drop_delay)
	await drop_tween.finished
	_snap_cards_to_stack()

func _snap_cards_to_stack() -> void:
	for index in cards.size():
		_set_card_in_stack(cards[index], index)

func absorb_pile(other: CardPile) -> void:
	var moving := other.cards.duplicate()
	other.cards.clear()
	other.count_changed.emit(0)
	var last_tween: Tween
	var order := 0
	for card in moving:
		var index := cards.size()
		cards.append(card)
		card.reparent(self, true)
		var target := _stack_position(index)
		var midpoint: Vector3 = (card.position + target) * 0.5 + Vector3(0.0, 0.0, -0.1)
		var delay := order * 0.03
		order += 1
		last_tween = create_tween()
		last_tween.tween_interval(delay)
		last_tween.tween_property(card, "position", midpoint, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		last_tween.tween_property(card, "position", target, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		var rotation_tween := create_tween()
		rotation_tween.tween_interval(delay)
		rotation_tween.tween_property(card, "rotation", Vector3.ZERO, 0.45)
	if last_tween != null:
		await last_tween.finished
	_snap_cards_to_stack()
	count_changed.emit(cards.size())

func get_draw_position() -> Vector3:
	return to_global(Vector3(0.0, 0.0, -cards.size() * stack_offset)) + Vector3.UP * 0.04

func receive_card(card: Node3D) -> void:
	if card == null:
		return
	var target_index := cards.size()
	var start_position := card.global_position
	var start_rotation := card.global_rotation
	card.set_process(false)
	card.reparent(self, true)
	card.visible = true
	var target_position := to_global(Vector3(0.0, 0.0, -target_index * stack_offset))
	var target_rotation := global_rotation
	var midpoint := (start_position + target_position) * 0.5 + Vector3.UP * 0.08
	var position_tween := create_tween()
	position_tween.tween_property(card, "global_position", midpoint, receive_duration * 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	position_tween.tween_property(card, "global_position", target_position, receive_duration * 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	var rotation_tween := create_tween()
	rotation_tween.tween_property(card, "global_rotation", target_rotation, receive_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await position_tween.finished
	card.global_position = target_position
	card.global_rotation = target_rotation
	var local_position := Vector3(0.0, 0.0, -target_index * stack_offset)
	if card.has_method("set_static_pose"):
		card.set_static_pose(local_position, Vector3.ZERO, face_down)
	else:
		_set_card_in_stack(card, target_index)
	card.set_meta("pile_index", target_index)
	cards.append(card)
	count_changed.emit(cards.size())
