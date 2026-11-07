class_name DialogueBox
extends CanvasLayer

@export var font_size: int = 30
@export_range(0.1, 1.0) var max_width_fraction: float = 0.6
@export_range(0.0, 1.0) var fade_time: float = 0.2
@export var bottom_margin: float = 50.0
@export var padding := Vector2(16.0, 8.0)

var _panel: PanelContainer
var _label: Label
var _tween: Tween

func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# Containers keep the box centred and bottom-aligned however large the text makes it.
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_bottom", int(bottom_margin))
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(margin)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_END
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)
	_panel = PanelContainer.new()
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color.BLACK
	style.content_margin_left = padding.x
	style.content_margin_right = padding.x
	style.content_margin_top = padding.y
	style.content_margin_bottom = padding.y
	_panel.add_theme_stylebox_override("panel", style)
	_panel.modulate.a = 0.0
	column.add_child(_panel)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", font_size)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)

func show_line(text: String) -> void:
	_label.text = text
	var max_width := get_viewport().get_visible_rect().size.x * max_width_fraction
	var text_width := _label.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_label.custom_minimum_size.x = minf(text_width + 2.0, max_width)
	_fade_to(1.0)

func hide_line() -> void:
	_fade_to(0.0)

func _fade_to(alpha: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_panel, "modulate:a", alpha, fade_time)
