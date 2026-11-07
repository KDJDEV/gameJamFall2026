extends "res://scripts/card_hand.gd"

signal set_completed(set_id: int, set_cards: Array)

@export var draw_pile: Node3D
@export var discard_target: Node3D
@export var set_area: TableSetArea
@export var controllable: bool = true
@export_range(-40.0, 12.0) var audio_volume_db: float = 6.0
@export_range(0.1, 2.0) var draw_duration: float = 0.55
@export_range(0.0, 0.5) var draw_arc_height: float = 0.12

@export var auto_play: bool = false
@export_range(0.5, 20.0) var auto_play_interval: float = 4.0
## The player's hand draws from its pile by itself whenever it is below its full size.
var auto_draw: bool = false
## Start with an empty hand and wait for the dealer to deal it (see Dealer).
@export var dealt_by_dealer: bool = false

## Where the selected card stays while the rest of the hand is tucked away. The hand
## rides on the camera, so this keeps the card above the table when the camera looks down.
@export var held_position := Vector3(0.0, 0.05, 0.25)
## Same, while peeking at another hand, so the held card doesn't cover their cards.
@export var peek_held_position := Vector3(-0.3, -0.1, 0.28)
@export_range(0.1, 1.0) var tuck_depth: float = 0.45
## Set by the player view: the lap and waypoint offsets below are relative to this node.
var lap_anchor: Node3D
## Just behind the table edge, above the table top.
@export var lap_waypoint_offset := Vector3(0.0, -0.08, -0.02)
## Below the table, in the player's lap.
@export var lap_offset := Vector3(0.0, -0.5, 0.15)
@export_range(0.05, 1.0) var lap_waypoint_time: float = 0.2

var draw_in_progress: bool = false
var held_mode: bool = false
var _held_peeking: bool = false
var _tuck_time: float = 0.0
var _return_time: float = 0.0
var _returning: bool = false
## Auto play and player input stay off until the dealer finishes dealing or reshuffling.
var play_enabled: bool = true:
	set(value):
		play_enabled = value
		# No card is shown as selected while the hand can't be played.
		_update_selection()
## True until the dealer has dealt the opening hands; no card is selected until then.
var awaiting_deal: bool = false
## Held still while the player peeks at this hand.
var frozen: bool = false
## Set once the final round starts: no more drawing, the hand just gets emptied.
var final_phase: bool = false
var _full_hand_size: int = 5
var _auto_timer: Timer
var initializing: bool = true
var card_audio: AudioStreamPlayer
var draw_sounds: Array[AudioStream] = [
	preload("res://Assets/audio/cardDraw1.mp3"),
	preload("res://Assets/audio/cardDraw2.mp3")
]
var discard_sounds: Array[AudioStream] = [
	preload("res://Assets/audio/cardDiscard1.mp3"),
	preload("res://Assets/audio/cardDiscard2.mp3"),
	preload("res://Assets/audio/cardDiscard3.mp3")
]
var swap_sounds: Array[AudioStream] = [
	preload("res://Assets/audio/swap1.mp3"),
	preload("res://Assets/audio/swap2.mp3")
]

func _ready() -> void:
	card_audio = AudioStreamPlayer.new()
	card_audio.name = "CardAudio"
	card_audio.volume_db = audio_volume_db
	add_child(card_audio)
	_full_hand_size = starting_hand_size
	auto_draw = controllable
	if dealt_by_dealer:
		starting_hand_size = 0
		play_enabled = false
		awaiting_deal = true
	super._ready()
	initializing = false
	_check_for_sets.call_deferred()
	if auto_play:
		_auto_timer = Timer.new()
		_auto_timer.wait_time = auto_play_interval * randf_range(0.8, 1.2)
		_auto_timer.timeout.connect(_auto_play_turn)
		add_child(_auto_timer)
		_auto_timer.start()

func _auto_play_turn() -> void:
	_auto_timer.wait_time = auto_play_interval * randf_range(0.8, 1.2)
	if draw_in_progress or not play_enabled or frozen:
		return
	if final_phase:
		# After the last card the AI only gets rid of what is left in its hand.
		if not cards.is_empty():
			selected_index = _choose_discard_index()
			discard_selected()
		return
	if cards.size() < _full_hand_size:
		draw_card()
		return
	selected_index = _choose_discard_index()
	discard_selected()
	draw_card()

# Always discards a card of the type (set) the hand holds the fewest of; ties are random.
func _choose_discard_index() -> int:
	var counts := {}
	for card in cards:
		var set_id: int = card.get("set_id")
		counts[set_id] = counts.get(set_id, 0) + 1
	var fewest: int = cards.size() + 1
	for set_id in counts:
		fewest = mini(fewest, counts[set_id])
	var candidates: Array[int] = []
	for index in cards.size():
		if counts[cards[index].get("set_id")] == fewest:
			candidates.append(index)
	return candidates.pick_random()

func _check_for_sets() -> void:
	if set_area == null or draw_in_progress:
		return
	var deck := CardDeck.find(get_tree())
	var set_size := deck.get_set_size() if deck != null else 3
	var groups := {}
	for card in cards:
		var set_id: int = card.get("set_id")
		if set_id < 0:
			continue
		if not groups.has(set_id):
			groups[set_id] = []
		groups[set_id].append(card)
	for set_id in groups:
		if groups[set_id].size() >= set_size:
			_lay_down_set(set_id, groups[set_id].slice(0, set_size))

func _lay_down_set(set_id: int, set_cards: Array) -> void:
	for card in set_cards:
		cards.erase(card)
	selected_index = clampi(selected_index, 0, maxi(cards.size() - 1, 0))
	_layout_hand()
	_update_selection()
	set_area.receive_set(set_cards)
	_play_card_sound(discard_sounds)
	set_completed.emit(set_id, set_cards)

func _play_card_sound(sounds: Array[AudioStream]) -> void:
	if sounds.is_empty() or card_audio == null:
		return
	card_audio.stream = sounds[randi_range(0, sounds.size() - 1)]
	card_audio.pitch_scale = randf_range(0.9, 1.2)
	card_audio.play()

func _unhandled_input(event: InputEvent) -> void:
	if not controllable or not play_enabled:
		return
	super._unhandled_input(event)

# Draws one card from the given pile instead of this hand's usual source.
func deal_from(source: Node3D) -> Node3D:
	var usual_pile := draw_pile
	draw_pile = source
	var card := draw_card()
	draw_pile = usual_pile
	return card

func draw_card() -> Node3D:
	if draw_in_progress or draw_pile == null or (not initializing and _draw_pile_is_empty()):
		return null
	var card := super.draw_card()
	if card == null:
		return null
	var deck := CardDeck.find(get_tree())
	if initializing:
		if deck != null:
			deck.apply_to_card(card, deck.deal_set_id())
		return card
	var drawn_set_id := -1
	if draw_pile.has_method("consume_top_card"):
		drawn_set_id = draw_pile.consume_top_card()
	if deck != null:
		deck.apply_to_card(card, drawn_set_id)
	_play_card_sound(draw_sounds)
	_animate_from_pile(card)
	return card

func _draw_pile_is_empty() -> bool:
	if draw_pile == null:
		return true
	if draw_pile.has_method("has_cards"):
		return not draw_pile.has_cards()
	return false

func discard_selected() -> Node3D:
	if draw_in_progress or cards.is_empty() or selected_index < 0 or selected_index >= cards.size():
		return null
	var card := cards[selected_index]
	cards.remove_at(selected_index)
	discard_pile.append(card)
	selected_index = clampi(selected_index, 0, cards.size() - 1)
	_layout_hand()
	_update_selection()
	if discard_target != null and discard_target.has_method("receive_card"):
		card.set_process(false)
		discard_target.receive_card(card)
	else:
		card.visible = false
	_play_card_sound(discard_sounds)
	card_discarded.emit(card)
	return card

func _selection_allowed() -> bool:
	return play_enabled and not awaiting_deal

## How many cards the hand is short of a full hand.
func cards_needed() -> int:
	return maxi(_full_hand_size - cards.size(), 0)

func finish_dealing() -> void:
	awaiting_deal = false
	_update_selection()

## Keeps only the selected card in view and tucks the rest of the hand away.
func set_held_mode(enabled: bool, peeking: bool = false) -> void:
	var was_held := held_mode
	held_mode = enabled
	_held_peeking = peeking
	if enabled and not was_held:
		_tuck_time = 0.0
		_returning = false
	elif not enabled and was_held:
		_return_time = 0.0
		_returning = lap_anchor != null
	_layout_hand()

func _process(delta: float) -> void:
	super._process(delta)
	if auto_draw and play_enabled and not final_phase and not held_mode and not _returning and not draw_in_progress \
			and cards.size() < _full_hand_size and not _draw_pile_is_empty():
		draw_card()
	if held_mode:
		_tuck_time += delta
		_layout_hand()
	elif _returning:
		_return_time += delta
		_returning = _return_time < lap_waypoint_time
		_layout_hand()

func _layout_hand() -> void:
	if not held_mode and not _returning:
		super._layout_hand()
		return
	var center := (cards.size() - 1) * 0.5
	for index in cards.size():
		var card := cards[index]
		var is_held_card := index == selected_index
		var pose := peek_held_position if _held_peeking else held_position
		if not is_held_card:
			pose = _lap_pose(float(index) - center)
			card.visible = _returning or _tuck_time < lap_waypoint_time + 0.4
		else:
			card.visible = true
		if card.has_method("set_hand_pose"):
			card.set_hand_pose(pose, Vector3.ZERO)

# Cards leave and return along an arc: first up over the table edge (the waypoint), then
# down to the lap, so they never cut through the table top.
func _lap_pose(offset: float) -> Vector3:
	if lap_anchor == null:
		return Vector3(offset * card_spacing, -tuck_depth, 0.0)
	var at_waypoint := _returning or _tuck_time < lap_waypoint_time
	var anchor_offset := lap_waypoint_offset if at_waypoint else lap_offset
	var world := lap_anchor.global_position + anchor_offset + lap_anchor.global_basis.x * offset * card_spacing
	return to_local(world)

## Trades one of this hand's cards for one of another hand's cards.
func swap_card_with(other: Node3D, my_index: int, their_index: int) -> void:
	var mine := cards[my_index]
	var theirs: Node3D = other.cards[their_index]
	cards[my_index] = theirs
	other.cards[their_index] = mine
	theirs.reparent(self, true)
	mine.reparent(other, true)
	mine.visible = true
	theirs.visible = true
	_update_selection()
	other._update_selection()
	_layout_hand()
	other._layout_hand()
	_play_card_sound(swap_sounds)
	_check_for_sets.call_deferred()
	other._check_for_sets.call_deferred()

func _set_draw_rotation(weight: float, card: Node3D, start_basis: Basis, target_basis: Basis) -> void:
	var card_transform: Transform3D = card.global_transform
	card_transform.basis = start_basis.slerp(target_basis, weight).scaled(card_transform.basis.get_scale())
	card.global_transform = card_transform

func _animate_from_pile(card: Node3D) -> void:
	draw_in_progress = true
	var target_transform := Transform3D.IDENTITY
	if card.has_method("get_target_global_transform"):
		target_transform = card.get_target_global_transform()
	else:
		target_transform = card.global_transform
	var target_position := target_transform.origin
	var target_basis := target_transform.basis.orthonormalized()
	var start_basis := target_basis.rotated(target_basis.x, PI * 0.5)
	var start_position := draw_pile.global_position + Vector3.UP * 0.08
	if draw_pile.has_method("get_draw_position"):
		start_position = draw_pile.get_draw_position()
	card.set_process(false)
	var start_transform: Transform3D = card.global_transform
	start_transform.origin = start_position
	start_transform.basis = start_basis.scaled(target_transform.basis.get_scale())
	card.global_transform = start_transform
	var midpoint := (start_position + target_position) * 0.5 + Vector3.UP * draw_arc_height
	var position_tween := create_tween()
	position_tween.tween_property(card, "global_position", midpoint, draw_duration * 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	position_tween.tween_property(card, "global_position", target_position, draw_duration * 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	var rotation_tween := create_tween()
	rotation_tween.tween_method(_set_draw_rotation.bind(card, start_basis, target_basis), 0.0, 1.0, draw_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await position_tween.finished
	card.global_transform = target_transform
	card.set_process(true)
	draw_in_progress = false
	_update_selection()
	_check_for_sets()
