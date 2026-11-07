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
@export_range(0.5, 5.0) var drain_settle_time: float = 1.5

var round_number: int = 1
var _dealt: bool = false
var _shuffling: bool = false
var _dialogue_locked: bool = false
var _winding_down: bool = false
var _empty_time: float = 0.0

signal _drained

func _ready() -> void:
	if dialogue_manager != null:
		dialogue_manager.register_event("shuffle_deck", shuffle_deck)
		dialogue_manager.register_event("deal_hands", deal_hands)
		dialogue_manager.register_event("wait_for_drain", wait_for_drain)
		dialogue_manager.register_event("collect_and_deal", collect_and_deal)
		dialogue_manager.register_event("start_final_phase", start_final_phase)
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

func start_final_phase() -> void:
	for hand in hands:
		hand.final_phase = true

func _process(delta: float) -> void:
	if not _winding_down:
		return
	if _piles_are_empty():
		_empty_time += delta
	else:
		_empty_time = 0.0
	if _empty_time >= drain_settle_time:
		_winding_down = false
		set_process(false)
		_drained.emit()

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
