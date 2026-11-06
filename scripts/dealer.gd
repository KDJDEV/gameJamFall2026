class_name Dealer
extends Node

## Runs the dealer's table actions. They are started by dialogue lines (the "event"
## field in data/dialogue.json), so the dealer acts while talking:
##   shuffle_deck - shuffles the draw pile; once it is empty, shuffles the discard pile
##                  the dealer draws from and turns it into the new draw pile (round 2).
##   deal_hands   - deals cards_per_hand cards to every hand, in `hands` order.
signal deal_finished
signal shuffle_finished

@export var dialogue_manager: DialogueManager
@export var draw_pile: CardPile
## The discard pile that feeds the dealer's draw pile when the deck runs out.
@export var reshuffle_source: CardPile
## Hands in dealing order (clockwise from the dealer's left).
@export var hands: Array[Node3D] = []
@export_range(1, 10) var cards_per_hand: int = 5
@export_range(0.0, 1.0) var deal_gap: float = 0.1
@export_range(1, 4) var shuffle_passes: int = 2

var _dealt: bool = false
var _reshuffled: bool = false

func _ready() -> void:
	if dialogue_manager != null:
		dialogue_manager.register_event("shuffle_deck", shuffle_deck)
		dialogue_manager.register_event("deal_hands", deal_hands)
	if draw_pile != null:
		draw_pile.count_changed.connect(_on_draw_pile_count_changed)

func shuffle_deck() -> void:
	if draw_pile.has_cards():
		await draw_pile.shuffle(shuffle_passes)
	elif not _reshuffled and reshuffle_source != null and reshuffle_source.has_cards():
		_reshuffled = true
		await reshuffle_source.shuffle(shuffle_passes)
		await draw_pile.absorb_pile(reshuffle_source)
	if _dealt:
		_set_hands_playing(true)
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
	_set_hands_playing(true)
	if dialogue_manager != null:
		dialogue_manager.set_draw_baseline()
	deal_finished.emit()

# Play stops while the deck is empty and resumes once the dealer has reshuffled.
# The reshuffle only happens once; after it the game is waiting for its ending.
func _on_draw_pile_count_changed(count: int) -> void:
	if count == 0 and _dealt and not _reshuffled:
		_set_hands_playing(false)

func _set_hands_playing(enabled: bool) -> void:
	for hand in hands:
		hand.play_enabled = enabled
