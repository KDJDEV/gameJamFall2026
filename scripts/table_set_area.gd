class_name TableSetArea
extends Node3D

## A player's tabletop region. Local +Z points toward the owner, so cards lie face up
## and read upright for them. Completed sets are laid out in rows away from the owner,
## each set as a loose stack of overlapping cards.
@export_range(0.05, 0.6) var set_spacing: float = 0.17
@export_range(0.05, 0.4) var row_spacing: float = 0.16
@export_range(1, 6) var sets_per_row: int = 3
## How far each card in a stack is shifted from the one below it.
@export var stack_offset := Vector2(0.016, -0.012)
## Height added per card so the stack layers cleanly instead of z-fighting.
@export_range(0.0005, 0.01) var stack_lift: float = 0.002
## Random turn of each card (radians) so the stack looks casually placed.
@export_range(0.0, 0.3) var stack_sloppiness: float = 0.07

var sets: Array[Array] = []

func get_set_count() -> int:
	return sets.size()

func receive_set(set_cards: Array) -> void:
	var set_index := sets.size()
	var row := set_index / sets_per_row
	var column := set_index % sets_per_row
	var row_origin := Vector3((column - (sets_per_row - 1) * 0.5) * set_spacing, 0.0, -row * row_spacing)
	var middle := (set_cards.size() - 1) * 0.5
	for index in set_cards.size():
		var card := set_cards[index] as Node3D
		card.reparent(self, true)
		var shift := (index - middle)
		var local_position := row_origin + Vector3(shift * stack_offset.x, 0.0015 + index * stack_lift, shift * stack_offset.y)
		var local_rotation := Vector3(-PI * 0.5, randf_range(-stack_sloppiness, stack_sloppiness), 0.0)
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
