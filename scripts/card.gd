class_name GameCard
extends Node3D

@export var card_id: String = "card"
@export var suit: String = "unknown"
@export var rank: String = "unknown"
@export var is_face_up: bool = true
@export_range(1.0, 30.0) var motion_smoothing: float = 14.0

@export_group("Card layout")
## Where the art and the name go, in pixels of the background image (Front in card.tscn). The default
## suits Assets/cardTextures/blank.png (125 x 190): the name box is the strip at the top and the art
## fills the big area below it.
@export var background_size := Vector2(125.0, 190.0)
@export var art_rect := Rect2(6.0, 34.0, 113.0, 150.0)
@export var name_rect := Rect2(6.0, 5.0, 113.0, 26.0)
## Empty space left around the art inside its area (fraction of the area).
@export_range(0.0, 0.3) var art_padding: float = 0.04
## Largest size of the name; longer names are shrunk to fit the box.
@export_range(8, 128) var name_font_size: int = 36
## How strongly the card's colours are pushed away from mid-grey (1 = the pictures as drawn).
@export_range(0.5, 3.0) var contrast: float = 1.5

const ART_SHADER := preload("res://shaders/card_art.gdshader")
# The card face in card units (the Front quad in card.tscn).
const FACE_SIZE := Vector2(1.4, 2.0)
const ART_DEPTH := 0.0212
const NAME_DEPTH := 0.0222

# One quad mesh and material per set, shared by every card of that set.
static var _art_cache: Dictionary = {}

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
	if label != null:
		label.text = "?" if set_def == null else set_def.get_label_text()
		if set_def != null:
			label.modulate = set_def.label_color
		_fit_name(label)
	_apply_art()
	_apply_background_contrast()

func _apply_background_contrast() -> void:
	var front := get_node_or_null("Front") as MeshInstance3D
	if front == null:
		return
	var material := front.get_surface_override_material(0) as ShaderMaterial
	if material != null:
		material.set_shader_parameter("contrast", contrast)
# The art sits on top of the background (Front), inside the area below the name box.
func _apply_art() -> void:
	var art := get_node_or_null("Art") as MeshInstance3D
	if set_def == null or set_def.art_texture == null:
		if art != null:
			art.visible = false
		return
	if art == null:
		art = MeshInstance3D.new()
		art.name = "Art"
		art.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(art)
	var cached := _art_for(set_def)
	art.mesh = cached["mesh"]
	art.visible = true
	var area := _to_face(art_rect)
	art.position = Vector3(area.get_center().x, area.get_center().y, ART_DEPTH)

func _art_for(def: CardSetDef) -> Dictionary:
	var texture := def.art_texture
	var texture_key := texture.resource_path if not texture.resource_path.is_empty() else str(texture.get_instance_id())
	var key := "%s|%s|%s|%s|%s|%s" % [texture_key, str(def.tint), str(background_size), str(art_rect), str(art_padding), str(contrast)]
	if _art_cache.has(key):
		return _art_cache[key]
	var area := _to_face(art_rect)
	var max_size := area.size * (1.0 - art_padding * 2.0)
	# Fit the visible part of the picture (its empty margins are cropped off) inside the area,
	# keeping its proportions, so every creature fills the card about equally.
	var tex_size := Vector2(texture.get_width(), texture.get_height())
	var visible_rect := Rect2(Vector2.ZERO, tex_size)
	var image := texture.get_image()
	if image != null:
		if image.is_compressed():
			image.decompress()
		var used := image.get_used_rect()
		if used.has_area():
			visible_rect = Rect2(used)
	var scale_to_fit := minf(max_size.x / visible_rect.size.x, max_size.y / visible_rect.size.y)
	var quad := QuadMesh.new()
	quad.size = visible_rect.size * scale_to_fit
	var visible_rect_scale := Vector2(visible_rect.size.x / tex_size.x, visible_rect.size.y / tex_size.y)
	var material := ShaderMaterial.new()
	material.shader = ART_SHADER
	material.set_shader_parameter("albedo_texture", texture)
	material.set_shader_parameter("tint", def.tint)
	material.set_shader_parameter("contrast", contrast)
	material.set_shader_parameter("uv_scale", visible_rect_scale)
	material.set_shader_parameter("uv_offset", Vector2(visible_rect.position.x / tex_size.x, visible_rect.position.y / tex_size.y))
	quad.material = material
	var entry := {"mesh": quad}
	_art_cache[key] = entry
	return entry

# Puts the name in the middle of the name box and shrinks it until it fits.
func _fit_name(label: Label3D) -> void:
	var box := _to_face(name_rect)
	label.position = Vector3(box.get_center().x, box.get_center().y, NAME_DEPTH)
	label.font_size = name_font_size
	var font := label.font if label.font != null else ThemeDB.fallback_font
	var max_width := box.size.x * 0.94 / label.pixel_size
	var max_height := box.size.y * 0.9 / label.pixel_size
	var measured := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_font_size)
	var shrink := minf(1.0, minf(max_width / maxf(measured.x, 1.0), max_height / maxf(measured.y, 1.0)))
	label.font_size = maxi(int(name_font_size * shrink), 6)

# Converts a rectangle in background-image pixels to card units (centred on the card, +Y up).
func _to_face(pixels: Rect2) -> Rect2:
	var unit := FACE_SIZE / background_size
	var top_left := Vector2((pixels.position.x - background_size.x * 0.5) * unit.x, (background_size.y * 0.5 - pixels.end.y) * unit.y)
	return Rect2(top_left, pixels.size * unit)

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
