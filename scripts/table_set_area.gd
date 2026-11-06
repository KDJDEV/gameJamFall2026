class_name TableSetArea
extends Node3D

## A player's tabletop region. Local +Z points toward the owner, so cards lie face up
## and read upright for them. Completed sets are laid out in rows away from the owner.
@export_range(0.05, 0.6) var card_spacing: float = 0.082
@export_range(0.1, 1.0) var set_spacing: float = 0.27
@export_range(0.05, 0.4) var row_spacing: float = 0.14
@export_range(1, 6) var sets_per_row: int = 2

var sets: Array[Array] = []

func get_set_count() -> int:
	return sets.size()

func receive_set(set_cards: Array) -> void:
	var set_index := sets.size()
	var row := set_index / sets_per_row
	var column := set_index % sets_per_row
	var row_origin := Vector3((column - (sets_per_row - 1) * 0.5) * set_spacing, 0.0, -row * row_spacing)
	for index in set_cards.size():
		var card := set_cards[index] as Node3D
		card.reparent(self, true)
		var offset := (index - (set_cards.size() - 1) * 0.5) * card_spacing
		var local_position := row_origin + Vector3(offset, 0.0015, 0.0)
		var local_rotation := Vector3(-PI * 0.5, 0.0, 0.0)
		if card.has_method("set_selected"):
			card.set_selected(false)
		if card.has_method("set_face_up"):
			card.set_face_up(true)
		if card.has_method("set_hand_pose"):
			card.set_hand_pose(local_position, local_rotation)
		else:
			card.position = local_position
			card.rotation = local_rotation
	sets.append(set_cards.duplicate())
