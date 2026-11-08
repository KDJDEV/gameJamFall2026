class_name Dealer
extends Node

signal deal_finished
signal shuffle_finished

@export var dialogue_manager: DialogueManager
@export var draw_pile: CardPile
@export var reshuffle_source: CardPile
@export var wind_down_piles: Array[CardPile] = []
@export var hands: Array[Node3D] = []
@export_range(1, 10) var cards_per_hand: int = 5
@export_range(0.0, 1.0) var deal_gap: float = 0.1
@export_range(1, 4) var shuffle_passes: int = 2
## The computer-controlled players start playing this many times faster (see the speed_up_npcs event).
@export_range(1.0, 10.0) var npc_speed_multiplier: float = 5.0
@export_range(0.5, 5.0) var drain_settle_time: float = 1.5

var round_number: int = 1
var _dealt: bool = false
var _shuffling: bool = false
var _dialogue_locked: bool = false
var _winding_down: bool = false
var _empty_time: float = 0.0
var _awaiting_game_end: bool = false
var _clear_time: float = 0.0

signal _drained
signal _game_ended

func _ready() -> void:
	if dialogue_manager != null:
		dialogue_manager.register_event("shuffle_deck", shuffle_deck)
		dialogue_manager.register_event("deal_hands", deal_hands)
		dialogue_manager.register_event("wait_for_drain", wait_for_drain)
		dialogue_manager.register_event("collect_and_deal", collect_and_deal)
		dialogue_manager.register_event("start_final_phase", start_final_phase)
		dialogue_manager.register_event("wait_for_game_end", wait_for_game_end)
		dialogue_manager.register_event("put_cards_down", put_cards_down)
		dialogue_manager.register_event("speed_up_npcs", speed_up_npcs)
		dialogue_manager.register_event("slow_down_npcs", slow_down_npcs)
		dialogue_manager.play_lock_changed.connect(_on_play_lock_changed)
	set_process(false)

func shuffle_deck() -> void:
	_shuffling = true
	_apply_play_state()
	if draw_pile.has_cards():
		await draw_pile.shuffle(shuffle_passes)
	_shuffling = false
	_apply_play_state()
	shuffle_finished.emit()

func deal_hands() -> void:
	for round_index in cards_per_hand:
		for hand in hands:
			if not draw_pile.has_cards():
				break
			if hand.deal_from(draw_pile) == null:
				continue
			while hand.draw_in_progress:
				await get_tree().process_frame
			await get_tree().create_timer(deal_gap).timeout
	_dealt = true
	for hand in hands:
		hand.finish_dealing()
	_apply_play_state()
	if dialogue_manager != null:
		dialogue_manager.set_draw_baseline()
	deal_finished.emit()

func wait_for_drain() -> void:
	_winding_down = true
	_empty_time = 0.0
	set_process(true)
	await _drained

## Waits for the last round to play out: every hand is empty (sets laid down, the rest
## discarded) and every pile except the final one has run dry.
func wait_for_game_end() -> void:
	_awaiting_game_end = true
	_clear_time = 0.0
	set_process(true)
	await _game_ended

func collect_and_deal() -> void:
	_shuffling = true
	_apply_play_state()
	if reshuffle_source != null and reshuffle_source.has_cards():
		await reshuffle_source.shuffle(shuffle_passes)
		await draw_pile.absorb_pile(reshuffle_source)
	await _top_up_hands()
	round_number = 2
	if dialogue_manager != null:
		dialogue_manager.set_round(2)
	_shuffling = false
	_apply_play_state()
	shuffle_finished.emit()

## Everyone, you included, lays their cards face down on the table and stops playing.
func put_cards_down() -> void:
	for hand in hands:
		hand.put_cards_down()
		await get_tree().create_timer(0.15).timeout

func speed_up_npcs() -> void:
	for hand in hands:
		if hand.auto_play:
			hand.speed_multiplier = npc_speed_multiplier

func slow_down_npcs() -> void:
	for hand in hands:
		if hand.auto_play:
			hand.speed_multiplier = 1.0

func start_final_phase() -> void:
	for hand in hands:
		hand.final_phase = true

func _process(delta: float) -> void:
	if _winding_down:
		if _piles_are_empty():
			_empty_time += delta
		else:
			_empty_time = 0.0
		if _empty_time >= drain_settle_time:
			_winding_down = false
			_drained.emit()
	if _awaiting_game_end:
		if _piles_are_empty() and _hands_are_empty():
			_clear_time += delta
		else:
			_clear_time = 0.0
		if _clear_time >= drain_settle_time:
			_awaiting_game_end = false
			_game_ended.emit()
	if not _winding_down and not _awaiting_game_end:
		set_process(false)

func _hands_are_empty() -> bool:
	for hand in hands:
		if not hand.cards.is_empty():
			return false
	return true

func _piles_are_empty() -> bool:
	for pile in wind_down_piles:
		if pile.has_cards():
			return false
	for hand in hands:
		if hand.draw_in_progress:
			return false
	return true

func _top_up_hands() -> void:
	var dealt_any := true
	while dealt_any and draw_pile.has_cards():
		dealt_any = false
		for hand in hands:
			if hand.cards_needed() <= 0 or not draw_pile.has_cards():
				continue
			if hand.deal_from(draw_pile) == null:
				continue
			dealt_any = true
			while hand.draw_in_progress:
				await get_tree().process_frame
			await get_tree().create_timer(deal_gap).timeout

func _on_play_lock_changed(locked: bool) -> void:
	_dialogue_locked = locked
	_apply_play_state()

func _apply_play_state() -> void:
	var enabled := _dealt and not _shuffling and not _dialogue_locked
	for hand in hands:
		hand.play_enabled = enabled
