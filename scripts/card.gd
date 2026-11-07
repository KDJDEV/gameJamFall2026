class_name GameCard
extends Node3D

@export var card_id: String = "card"
@export var suit: String = "unknown"
@export var rank: String = "unknown"
@export var is_face_up: bool = true
@export_range(1.0, 30.0) var motion_smoothing: float = 14.0

var set_id: int = -1
var set_def: CardSetDef
var hand_index: int = -1
var is_selected: bool = false
var base_position := Vector3.ZERO
var base_rotation := Vector3.ZERO
var target_position := Vector3.ZERO
var target_rotation := Vector3.ZERO
var _look_point: Variant = null

func _ready() -> void:
	base_position = position
	base_rotation = rotation
	target_position = position
	target_rotation = rotation

func _process(delta: float) -> void:
	var weight := 1.0 - exp(-motion_smoothing * delta)
	position = position.lerp(target_position, weight)
	rotation = rotation.lerp(target_rotation, weight)

func configure(new_id: String, new_suit: String, new_rank: String) -> void:
	card_id = new_id
	suit = new_suit
	rank = new_rank

func assign_set(new_set_id: int, new_set_def: CardSetDef) -> void:
	set_id = new_set_id
	set_def = new_set_def
	var label := get_node_or_null("Label") as Label3D
	var front := get_node_or_null("Front") as MeshInstance3D
	if label != null:
		label.text = "?" if set_def == null else set_def.get_label_text()
		if set_def != null:
			label.modulate = set_def.label_color
	if front != null and set_def != null:
		var material := StandardMaterial3D.new()
		material.albedo_texture = set_def.front_texture
		material.albedo_color = set_def.tint
		front.set_surface_override_material(0, material)

func set_hand_pose(new_position: Vector3, new_rotation: Vector3) -> void:
	base_position = new_position
	base_rotation = new_rotation
	_refresh_target()

func get_target_global_transform() -> Transform3D:
	var saved_position := position
	var saved_rotation := rotation
	position = target_position
	rotation = target_rotation
	var result := global_transform
	position = saved_position
	rotation = saved_rotation
	return result

func set_static_pose(new_position: Vector3, new_rotation: Vector3, face_up: bool) -> void:
	is_selected = false
	is_face_up = face_up
	base_position = new_position
	base_rotation = new_rotation
	_refresh_target()
	position = target_position
	rotation = target_rotation

func set_selected(selected: bool) -> void:
	is_selected = selected
	_refresh_target()

func set_face_up(face_up: bool) -> void:
	is_face_up = face_up
	_refresh_target()

func _refresh_target() -> void:
	target_position = base_position + Vector3.UP * (0.08 if is_selected else 0.0)
	target_rotation = base_rotation
	if is_selected and _look_point != null:
		target_rotation = _rotation_facing(_look_point)
	if not is_face_up:
		target_rotation.y += PI

## Turns the card's face toward a world point (null to stop) while it is selected.
func set_look_target(world_point: Variant) -> void:
	_look_point = world_point

func _rotation_facing(world_point: Vector3) -> Vector3:
	var parent := get_parent() as Node3D
	if parent == null:
		return base_rotation
	var direction := parent.global_transform.basis.inverse() * (world_point - parent.to_global(target_position))
	if direction.length_squared() < 0.0001:
		return base_rotation
	# The card's face is its +Z side, so aim -Z away from the point.
	return Basis.looking_at(-direction.normalized(), Vector3.UP).get_euler()
