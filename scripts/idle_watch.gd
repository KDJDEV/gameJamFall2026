class_name IdleWatch
extends Node

## Nags the player when they take too long to play a card. Each time `idle_seconds` pass with no card
## played, Melanie says one of the taking_too_long_0..2 lines (picked at random). Doing something resets
## the count; being nagged `strikes_to_end` times in a row plays caught_3, the same ending as being
## caught cheating three times (this also keeps an arcade machine from sitting on a stuck game).
##
## The clock only runs while you are expected to play: not during dialogue that stops play, not while
## you are peeking or looking at the door, and not once your hand is empty.

@export var dialogue_manager: DialogueManager
@export var player_view: PlayerView
## The player's hand.
@export var hand: Node3D
## Who nags you and who "alright, you're done" is attributed to (speaker id).
@export var nagger_id: StringName = &"left_npc"
@export_range(3.0, 120.0) var idle_seconds: float = 25.0
@export_range(1, 10) var strikes_to_end: int = 3
@export var ending_sequence: String = "caught_3_melanie"
@export var nag_sequence_prefix: String = "taking_too_long_"
@export_range(1, 10) var nag_variants: int = 3

var strikes: int = 0

var _idle_time: float = 0.0
var _hand_signature: int = 0
var _finished: bool = false

func _ready() -> void:
	if dialogue_manager == null or player_view == null or hand == null:
		push_warning("IdleWatch needs a dialogue manager, a player view and the player's hand.")
		set_process(false)
		return
	dialogue_manager.sequence_started.connect(_on_sequence_started)

func _on_sequence_started(sequence_id: String) -> void:
	# Any third-strike ending (from cheating or from this script) ends the game.
	if sequence_id.begins_with("caught_3"):
		_finished = true

func _process(delta: float) -> void:
	if _finished:
		return
	var signature := _signature()
	if signature != _hand_signature:
		_hand_signature = signature
		_idle_time = 0.0
		strikes = 0
		return
	if not _expected_to_play():
		_idle_time = 0.0
		return
	_idle_time += delta
	if _idle_time >= idle_seconds:
		_idle_time = 0.0
		_take_too_long()

func _expected_to_play() -> bool:
	if not hand.play_enabled or hand.awaiting_deal or hand.draw_in_progress or hand.cards.is_empty():
		return false
	if player_view.view_state == PlayerView.ViewState.PEEK or player_view.is_looking_at_door():
		return false
	return true

# Changes whenever a card enters or leaves the hand.
func _signature() -> int:
	var ids: Array[int] = []
	for card in hand.cards:
		ids.append(card.get_instance_id())
	return ids.hash()

func _take_too_long() -> void:
	strikes += 1
	if strikes >= strikes_to_end:
		_finished = true
		dialogue_manager.set_variable("complainer", String(nagger_id))
		if dialogue_manager.has_sequence(ending_sequence):
			dialogue_manager.play_urgent(ending_sequence)
		return
	var nag := "%s%d" % [nag_sequence_prefix, randi() % nag_variants]
	if dialogue_manager.has_sequence(nag):
		dialogue_manager.replay_sequence(nag)
