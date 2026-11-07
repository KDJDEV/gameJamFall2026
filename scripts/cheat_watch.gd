class_name CheatWatch
extends Node

## Turns peeking and swapping into cheating. The owner of the hand you are leaning over to look at
## catches you only while they are looking down at their own cards. You are safe while they are staring
## at someone else (or at you, for that matter). Three strikes and you are thrown out.
##
## Dialogue sequences it plays (data/dialogue.json):
##   cheat_first_peek, cheat_first_swap   your inner voice the first time you peek / swap
##   got_away_1, got_away_2, ...          your inner voice after each swap nobody noticed
##   caught_1, caught_2, caught_3         the reactions to each strike; "$complainer" in those lines is
##                                        the owner of the hand you were looking at

@export var player_view: PlayerView
@export var dialogue_manager: DialogueManager
## Who owns the hand on your left and the hand on your right (speaker ids).
@export var left_speaker_id: StringName = &"left_npc"
@export var right_speaker_id: StringName = &"right_npc"
## How long the owner has to keep noticing you, while you are leaned over, before you are caught.
@export_range(0.1, 5.0) var catch_reaction: float = 0.8
## The heartbeat and vignette only build up in the last this many seconds before the owner stops
## staring at someone else and looks back down at their cards.
@export_range(0.5, 10.0) var danger_window: float = 4.0
@export_range(1, 3) var max_strikes: int = 3

var strikes: int = 0
var peeks: int = 0
var swaps: int = 0
var got_away_count: int = 0

var _watched_time: float = 0.0
var _game_over: bool = false

func _ready() -> void:
	if player_view == null or dialogue_manager == null:
		push_warning("CheatWatch needs a player view and a dialogue manager.")
		set_process(false)
		return
	player_view.peek_started.connect(_on_peek_started)
	player_view.swapped.connect(_on_swapped)

func _process(delta: float) -> void:
	var peeking := player_view.view_state == PlayerView.ViewState.PEEK and player_view.get_peeked_hand() != null
	if not peeking or _game_over:
		_watched_time = 0.0
		player_view.peek_danger = 0.0
		return
	var face := _owner_face(player_view.get_peeked_hand())
	var watched := face != null and face.is_looking_at_cards()
	# 0 while they stare at someone else, rising to 1 as they are about to look back at their cards.
	player_view.peek_danger = 0.0 if face == null else 1.0 - clampf(face.seconds_until_looks_down() / danger_window, 0.0, 1.0)
	if watched:
		_watched_time += delta
	else:
		_watched_time = maxf(_watched_time - delta * 2.0, 0.0)
	if _watched_time >= catch_reaction:
		_catch()

# The owner of the peeked hand only sees you while they are looking down at their own cards, which are
# the cards you are looking at. While they stare at someone else, or at you, you are safe.
func _owner_face(hand_node: Node3D) -> CharacterFace:
	var owner_id := _owner_of(hand_node)
	for node in get_tree().get_nodes_in_group("character_face"):
		var face := node as CharacterFace
		if face != null and face.speaker_id == owner_id:
			return face
	return null

func _on_peek_started(_hand: Node3D) -> void:
	peeks += 1
	if peeks == 1:
		_play_if_exists("cheat_first_peek")

func _on_swapped(_hand: Node3D) -> void:
	swaps += 1
	if swaps == 1:
		_play_if_exists("cheat_first_swap")
	got_away_count += 1
	_play_if_exists("got_away_%d" % got_away_count)

func _catch() -> void:
	var victim := _owner_of(player_view.get_peeked_hand())
	_watched_time = 0.0
	player_view.peek_danger = 0.0
	strikes += 1
	dialogue_manager.set_variable("complainer", String(victim))
	player_view.abort_peek()
	if strikes >= max_strikes:
		_game_over = true
	# Urgent: the reaction must play now, not after whatever else is going on (like the round ending).
	var caught_id := "caught_%d" % mini(strikes, max_strikes)
	if dialogue_manager.has_sequence(caught_id):
		dialogue_manager.play_urgent(caught_id)

func _owner_of(hand_node: Node3D) -> StringName:
	return left_speaker_id if hand_node == player_view.left_hand else right_speaker_id

func _play_if_exists(sequence_id: String) -> void:
	if dialogue_manager.has_sequence(sequence_id):
		dialogue_manager.play_sequence(sequence_id)
