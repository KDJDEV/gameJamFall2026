class_name AvailableIcons
extends TextureRect

## Shows what you can do right now as a row of pictures on top of this background. The background grows
## and shrinks to fit the pictures. The picture for the button you press pops and lights up. Nothing is
## shown while you are not expected to play (the opening, dealing, shuffling, dialogue that locks play,
## the endings), while the game is paused, or once the second round has started.
##
## Joystick pictures: select_card = left/right chooses a card, look_up / look_down = joystick up / down
## (stacked in one column when both are available), peek_left / peek_right = lean toward that player
## (also stacked); swap_* = the button swaps with that player's card; discard = the button discards.

const ICONS := {
	&"select_card": preload("res://Assets/textures/availableMoveIcons/icon_select_card.png"),
	&"discard": preload("res://Assets/textures/availableMoveIcons/icon_discard.png"),
	&"look_up": preload("res://Assets/textures/availableMoveIcons/icon_look_up.png"),
	&"look_down": preload("res://Assets/textures/availableMoveIcons/icon_look_down.png"),
	&"peek_left": preload("res://Assets/textures/availableMoveIcons/icon_peek_left.png"),
	&"peek_right": preload("res://Assets/textures/availableMoveIcons/icon_peek_right.png"),
	&"swap_left": preload("res://Assets/textures/availableMoveIcons/icon_swap_left.png"),
	&"swap_right": preload("res://Assets/textures/availableMoveIcons/icon_swap_right.png"),
}
const WATCHED_ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down", &"select"]
## Pictures of the same kind that are shown together are stacked on top of each other.
const STACKED_GROUPS: Array = [
	[&"look_up", &"look_down"],
	[&"peek_left", &"peek_right"],
]

@export var player_view: PlayerView
## The pictures stop showing once this dealer has started the second round.
@export var dealer: Dealer
## Space between the edge of the background and the pictures.
@export_range(0.0, 60.0) var padding: float = 12.0
@export_range(0.0, 60.0) var spacing: float = 14.0
## Space between pictures that are stacked in one column.
@export_range(0.0, 30.0) var stack_spacing: float = 6.0
## Height of every picture. 0 uses the height of the background in the scene, minus the padding.
@export_range(0.0, 300.0) var icon_height: float = 70.0
@export_range(0.0, 1.0) var fade_time: float = 0.15
## The tint of a picture while its button is pressed.
@export var highlight_color := Color(1.0, 0.85, 0.35)

var actions: Array[StringName] = []

var _row: HBoxContainer
var _pictures: Dictionary = {}
var _cropped: Dictionary = {}
var _fade_tween: Tween
var _height: float = 0.0
var _bottom: float = 0.0
var _shown: bool = false

func _ready() -> void:
	# Keeps running while the game is paused so the pictures can disappear.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Only the background is see-through; the pictures stay solid.
	self_modulate.a = modulate.a
	modulate.a = 0.0
	visible = false
	_height = icon_height if icon_height > 0.0 else maxf(size.y - padding * 2.0, 16.0)
	# The panel sits on the bottom edge you placed it at and grows upward.
	_bottom = position.y + size.y
	_row = HBoxContainer.new()
	_row.position = Vector2(padding, padding)
	_row.add_theme_constant_override("separation", int(spacing))
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	for key in ICONS:
		_cropped[key] = _crop(ICONS[key])

func _process(_delta: float) -> void:
	if player_view == null:
		return
	var now := available_actions()
	if now != actions:
		_set_actions(now)
	var wanted := not actions.is_empty()
	if wanted == _shown:
		return
	_shown = wanted
	if wanted:
		visible = true
		_fade_to(1.0, false)
	else:
		_fade_to(0.0, true)

func _input(event: InputEvent) -> void:
	if player_view == null or actions.is_empty():
		return
	for action in WATCHED_ACTIONS:
		if event.is_action_pressed(action):
			var key := _icon_for(action)
			if _pictures.has(key):
				_pulse(_pictures[key])
			return

## What you can do right now, in the order the pictures are shown. Nothing while the game is paused,
## whenever you are not expected to play, or from the second round on.
func available_actions() -> Array[StringName]:
	var result: Array[StringName] = []
	if get_tree().paused:
		return result
	if dealer != null and dealer.round_number >= 2:
		return result
	var intro := get_tree().get_first_node_in_group("intro_sequence") as IntroSequence
	if intro != null and not intro.is_finished:
		return result
	var hand := player_view.hand
	if hand == null or not hand.play_enabled or player_view.is_looking_at_door():
		return result
	var has_cards: bool = not hand.cards.is_empty()
	match player_view.view_state:
		PlayerView.ViewState.NORMAL:
			if hand.cards.size() > 1:
				result.append(&"select_card")
			if has_cards:
				result.append(&"discard")
			result.append(&"look_up")
		PlayerView.ViewState.TABLE:
			if has_cards:
				result.append(&"discard")
			if _can_peek(player_view.left_hand):
				result.append(&"peek_left")
			if _can_peek(player_view.right_hand):
				result.append(&"peek_right")
		PlayerView.ViewState.PEEK:
			var peeked := player_view.get_peeked_hand()
			if peeked == null:
				return result
			if peeked.cards.size() > 1:
				result.append(&"look_up")
				result.append(&"look_down")
			if not peeked.cards.is_empty() and has_cards:
				result.append(&"swap_left" if peeked == player_view.left_hand else &"swap_right")
	return result

func _can_peek(other: Node3D) -> bool:
	return other != null and not other.cards.is_empty() and not player_view.hand.cards.is_empty()

# Which picture belongs to a button in the current view.
func _icon_for(action: StringName) -> StringName:
	match player_view.view_state:
		PlayerView.ViewState.NORMAL:
			if action == &"move_left" or action == &"move_right":
				return &"select_card"
			if action == &"move_up":
				return &"look_up"
			if action == &"select":
				return &"discard"
		PlayerView.ViewState.TABLE:
			if action == &"move_left":
				return &"peek_left"
			if action == &"move_right":
				return &"peek_right"
			if action == &"select":
				return &"discard"
		PlayerView.ViewState.PEEK:
			if action == &"move_up":
				return &"look_up"
			if action == &"move_down":
				return &"look_down"
			if action == &"select":
				return &"swap_left" if player_view.get_peeked_hand() == player_view.left_hand else &"swap_right"
	return &""

func _set_actions(new_actions: Array[StringName]) -> void:
	actions = new_actions
	_pictures.clear()
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	if actions.is_empty():
		return
	var columns := _columns(actions)
	var total_width := 0.0
	for column in columns:
		# Related pictures share a column, each half as tall, so they take up less room.
		var stacked: bool = column.size() > 1
		var picture_height := (_height - stack_spacing) * 0.5 if stacked else _height
		var holder := VBoxContainer.new()
		holder.add_theme_constant_override("separation", int(stack_spacing))
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_row.add_child(holder)
		var column_width := 0.0
		for key in column:
			var texture: Texture2D = _cropped[key]
			var aspect := texture.get_width() / maxf(texture.get_height(), 1.0)
			var picture := TextureRect.new()
			picture.texture = texture
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			picture.custom_minimum_size = Vector2(picture_height * aspect, picture_height)
			picture.pivot_offset = picture.custom_minimum_size * 0.5
			picture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(picture)
			_pictures[key] = picture
			column_width = maxf(column_width, picture_height * aspect)
		total_width += column_width
	total_width += spacing * (columns.size() - 1)
	size = Vector2(total_width + padding * 2.0, _height + padding * 2.0)
	position.y = _bottom - size.y

# Groups the actions into columns: pictures of the same kind that are available together (up and down,
# left and right) are stacked in one column; everything else stands alone.
func _columns(shown: Array[StringName]) -> Array:
	var columns: Array = []
	var used: Array[StringName] = []
	for key in shown:
		if used.has(key):
			continue
		var column: Array[StringName] = [key]
		for group in STACKED_GROUPS:
			if group.has(key):
				column.clear()
				for member in group:
					if shown.has(member):
						column.append(member)
				break
		used.append_array(column)
		columns.append(column)
	return columns

func _fade_to(alpha: float, hide_afterwards: bool) -> void:
	if _fade_tween != null:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", alpha, fade_time)
	if hide_afterwards:
		_fade_tween.tween_callback(set_visible.bind(false))

# The picture grows a little and lights up, then settles back.
func _pulse(picture: TextureRect) -> void:
	var pop := create_tween().set_parallel(true)
	pop.tween_property(picture, "scale", Vector2.ONE * 1.18, 0.08)
	pop.tween_property(picture, "modulate", highlight_color, 0.08)
	pop.chain().tween_property(picture, "scale", Vector2.ONE, 0.2)
	pop.parallel().tween_property(picture, "modulate", Color.WHITE, 0.2)

# Trims the empty margin around a picture so every picture is shown at the same height.
func _crop(texture: Texture2D) -> Texture2D:
	var image := texture.get_image()
	if image == null or image.is_empty():
		return texture
	if image.is_compressed():
		image.decompress()
	var used := image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return texture
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(used.grow(6).intersection(Rect2i(Vector2i.ZERO, image.get_size())))
	return atlas
