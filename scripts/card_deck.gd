class_name CardDeck
extends Node

## Owns the shuffled deck. Cards keep their set id for the whole game, so piles,
## hands and the table always hold the same fixed set of cards.
@export var config: CardDeckConfig

var set_defs: Array[CardSetDef] = []
var _draw_order: Array[int] = []
var _built: bool = false

func _enter_tree() -> void:
	add_to_group("card_deck")

static func find(tree: SceneTree) -> CardDeck:
	return tree.get_first_node_in_group("card_deck") as CardDeck

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	if config == null:
		config = CardDeckConfig.new()
	set_defs = config.build_sets()
	for set_id in set_defs.size():
		for copy in config.cards_per_set:
			_draw_order.append(set_id)
	_draw_order.shuffle()

func get_set_size() -> int:
	_ensure_built()
	return config.cards_per_set

func remaining() -> int:
	_ensure_built()
	return _draw_order.size()

func deal_set_id() -> int:
	_ensure_built()
	if _draw_order.is_empty():
		return -1
	return _draw_order.pop_back()

func get_set_def(set_id: int) -> CardSetDef:
	_ensure_built()
	if set_id < 0 or set_id >= set_defs.size():
		return null
	return set_defs[set_id]

func apply_to_card(card: Node, set_id: int) -> void:
	if card != null and card.has_method("assign_set"):
		card.assign_set(set_id, get_set_def(set_id))
