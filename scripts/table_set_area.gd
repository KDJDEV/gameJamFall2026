class_name TableSetArea
extends Node3D

## A player's tabletop region. Local +Z points toward the owner, so cards lie face up
## and read upright for them. Completed sets are laid out in rows away from the owner,
## each set as a loose stack of overlapping cards. A new set takes the first free slot of the
## grid that does not overlap another player's sets, so sets from different players never
## land on top of each other.
@export_range(0.05, 0.6) var set_spacing: float = 0.125
@export_range(0.05, 0.4) var row_spacing: float = 0.15
@export_range(1, 6) var sets_per_row: int = 3
## How far each card in a stack is shifted from the one below it.
@export var stack_offset := Vector2(0.016, -0.012)
## Height added per card so the stack layers cleanly instead of z-fighting.
@export_range(0.0005, 0.01) var stack_lift: float = 0.002
## Random turn of each card (radians) so the stack looks casually placed.
@export_range(0.0, 0.3) var stack_sloppiness: float = 0.07
## Empty space kept between this area's sets and other players' sets (metres).
@export_range(0.0, 0.05) var clearance: float = 0.004
## How many rows the slot search may use before it gives up and accepts an overlap.
@export_range(1, 12) var max_rows: int = 8
## World-space (x, z) corners of the table top. Slots that would hang over the edge are
## skipped. Leave both at zero to disable.
@export var table_min := Vector2.ZERO
@export var table_max := Vector2.ZERO
## A round obstacle on the table (the candle) that sets keep clear of; radius 0 disables it.
@export var obstacle_center := Vector2.ZERO
@export_range(0.0, 0.3) var obstacle_radius: float = 0.0

# Half the size of a card's face in card-local units (the Front quad is 1.4 x 2).
const CARD_HALF := Vector2(0.7, 1.0)

var sets: Array[Array] = []
## How many sets had to be placed overlapping because no free slot was left (diagnostic).
var overlap_fallbacks: int = 0
var _used_slots: Dictionary = {}

func _enter_tree() -> void:
	add_to_group("table_set_area")

func get_set_count() -> int:
	return sets.size()

func receive_set(set_cards: Array) -> void:
	if set_cards.is_empty():
		return
	var card_scale := (set_cards[0] as Node3D).scale
	var choice := _choose_slot(set_cards.size(), card_scale)
	_used_slots[choice["slot"]] = true
	var poses: Array = choice["poses"]
	for index in set_cards.size():
		var card := set_cards[index] as Node3D
		card.reparent(self, true)
		var local_position: Vector3 = poses[index][0]
		var local_rotation: Vector3 = poses[index][1]
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

# Returns {slot, poses}: the first unused slot whose stack clears every other player's sets,
# the table edge and the obstacle (or the first unused slot if none does).
func _choose_slot(count: int, card_scale: Vector3) -> Dictionary:
	var rotations: Array[float] = []
	for index in count:
		rotations.append(randf_range(-stack_sloppiness, stack_sloppiness))
	var others := _other_polygons()
	var fallback: Dictionary = {}
	for slot in sets_per_row * max_rows:
		if _used_slots.has(slot):
			continue
		var poses := _stack_poses(slot / sets_per_row, slot % sets_per_row, count, rotations)
		var candidate := {"slot": slot, "poses": poses}
		if fallback.is_empty():
			fallback = candidate
		if not _overlaps_any(poses, card_scale, others):
			return candidate
	if fallback.is_empty():
		# Every slot in range is taken: keep stacking in rows past max_rows.
		var slot := sets_per_row * max_rows + _used_slots.size()
		fallback = {"slot": slot, "poses": _stack_poses(slot / sets_per_row, slot % sets_per_row, count, rotations)}
	overlap_fallbacks += 1
	push_warning("%s: no free slot left for a set, placing it overlapping." % name)
	return fallback

func _stack_poses(row: int, column: int, count: int, rotations: Array[float]) -> Array:
	var row_origin := Vector3((column - (sets_per_row - 1) * 0.5) * set_spacing, 0.0, -row * row_spacing)
	var middle := (count - 1) * 0.5
	var poses: Array = []
	for index in count:
		var shift := index - middle
		var local_position := row_origin + Vector3(shift * stack_offset.x, 0.0015 + index * stack_lift, shift * stack_offset.y)
		poses.append([local_position, Vector3(-PI * 0.5, rotations[index], 0.0)])
	return poses

func _overlaps_any(poses: Array, card_scale: Vector3, others: Array) -> bool:
	for pose in poses:
		var card_transform := global_transform * Transform3D(Basis.from_euler(pose[1]).scaled(card_scale), pose[0])
		var polygon := _inflated_polygon(card_transform)
		if _leaves_table(polygon) or _hits_obstacle(polygon):
			return true
		var bounds := _bounds(polygon)
		for other in others:
			if bounds.intersects(other[0]) and not Geometry2D.intersect_polygons(polygon, other[1]).is_empty():
				return true
	return false

func _leaves_table(polygon: PackedVector2Array) -> bool:
	if table_min == table_max:
		return false
	for point in polygon:
		if point.x < table_min.x or point.x > table_max.x or point.y < table_min.y or point.y > table_max.y:
			return true
	return false

func _hits_obstacle(polygon: PackedVector2Array) -> bool:
	if obstacle_radius <= 0.0:
		return false
	var grown := Geometry2D.offset_polygon(polygon, obstacle_radius)
	return not grown.is_empty() and Geometry2D.is_point_in_polygon(obstacle_center, grown[0])

# [bounds, polygon] for every card laid down by the other players.
func _other_polygons() -> Array:
	var result: Array = []
	for node in get_tree().get_nodes_in_group("table_set_area"):
		var area := node as TableSetArea
		if area == null or area == self:
			continue
		for set_cards in area.sets:
			for card in set_cards:
				if not is_instance_valid(card) or not card.has_method("get_target_global_transform"):
					continue
				var polygon := _inflated_polygon(card.get_target_global_transform())
				result.append([_bounds(polygon), polygon])
	return result

# The card's face as a polygon on the table plane (x, z), grown by `clearance`.
func _inflated_polygon(card_transform: Transform3D) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var world := card_transform * Vector3(corner.x * CARD_HALF.x, corner.y * CARD_HALF.y, 0.0)
		polygon.append(Vector2(world.x, world.z))
	if Geometry2D.is_polygon_clockwise(polygon):
		polygon.reverse()
	var grown := Geometry2D.offset_polygon(polygon, clearance)
	return grown[0] if not grown.is_empty() else polygon

func _bounds(polygon: PackedVector2Array) -> Rect2:
	var rect := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		rect = rect.expand(point)
	return rect
