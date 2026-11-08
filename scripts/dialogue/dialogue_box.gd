class_name DialogueBox
extends CanvasLayer

@export var font_size: int = 30
@export_range(0.1, 1.0) var max_width_fraction: float = 0.6
@export_range(0.0, 1.0) var fade_time: float = 0.2
@export var bottom_margin: float = 50.0
@export var padding := Vector2(16.0, 8.0)

var _panel: PanelContainer
var _label: RichTextLabel
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
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("normal_font_size", font_size)
	_label.add_theme_font_size_override("bold_font_size", font_size)
	_label.add_theme_color_override("default_color", Color.WHITE)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)
	var bold := FontVariation.new()
	bold.base_font = _label.get_theme_font("normal_font")
	bold.variation_embolden = 0.9
	_label.add_theme_font_override("bold_font", bold)

## Text between asterisks is shown in bold: "their *eyes* are on you".
func show_line(text: String) -> void:
	var plain := text.replace("*", "")
	_label.text = "[center]%s[/center]" % _to_bbcode(text)
	var max_width := get_viewport().get_visible_rect().size.x * max_width_fraction
	var text_width := _label.get_theme_font("normal_font").get_string_size(plain, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	# A little extra room, since bold letters are wider.
	_label.custom_minimum_size.x = minf(text_width * 1.06 + 8.0, max_width)
	_fade_to(1.0)

func _to_bbcode(text: String) -> String:
	var escaped := text.replace("[", "[lb]")
	var bold_marks := RegEx.create_from_string("\\*(.+?)\\*")
	return bold_marks.sub(escaped, "[b]$1[/b]", true)

func hide_line() -> void:
	_fade_to(0.0)

func _fade_to(alpha: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_panel, "modulate:a", alpha, fade_time)
