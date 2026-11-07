class_name DialogueSpeaker
extends Marker3D


@export var speaker_id: StringName = &""
@export var display_name: String = ""
@export var icon_texture: Texture2D = preload("res://Assets/ui/audio_icon.svg")
@export_range(0.0001, 0.01) var icon_pixel_size: float = 0.0009
@export var voice_volume_db: float = 0.0
@export_range(16.0, 200.0) var edge_icon_size: float = 56.0
@export_range(0.0, 100.0) var edge_margin: float = 24.0

var _icon: Sprite3D
var _edge_icon: TextureRect
var _voice: AudioStreamPlayer3D
var _pulse_tween: Tween
var _pulse: float = 1.0
var _speaking: bool = false

func _enter_tree() -> void:
	add_to_group("dialogue_speaker")

func _ready() -> void:
	_icon = Sprite3D.new()
	_icon.name = "AudioIcon"
	_icon.texture = icon_texture
	_icon.pixel_size = icon_pixel_size
	_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_icon.shaded = false
	_icon.double_sided = true
	_icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_icon.modulate = Color(1.0, 1.0, 1.0, 0.85)
	_icon.visible = false
	add_child(_icon)
	# Above the opening blur (layer 5) and below the subtitles (layer 10).
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	_edge_icon = TextureRect.new()
	_edge_icon.name = "EdgeIcon"
	_edge_icon.texture = icon_texture
	_edge_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_edge_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_edge_icon.custom_minimum_size = Vector2.ONE * edge_icon_size
	_edge_icon.size = Vector2.ONE * edge_icon_size
	_edge_icon.pivot_offset = Vector2.ONE * edge_icon_size * 0.5
	_edge_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge_icon.modulate = Color(1.0, 1.0, 1.0, 0.85)
	_edge_icon.visible = false
	layer.add_child(_edge_icon)
	_voice = AudioStreamPlayer3D.new()
	_voice.name = "Voice"
	_voice.volume_db = voice_volume_db
	add_child(_voice)
	set_process(false)

func set_speaking(speaking: bool) -> void:
	if _icon == null:
		return
	_speaking = speaking
	if _pulse_tween != null:
		_pulse_tween.kill()
	_pulse = 1.0
	set_process(speaking)
	if speaking:
		_update_icon()
		_pulse_tween = create_tween().set_loops()
		_pulse_tween.tween_property(self, "_pulse", 1.15, 0.35).set_trans(Tween.TRANS_SINE)
		_pulse_tween.tween_property(self, "_pulse", 1.0, 0.35).set_trans(Tween.TRANS_SINE)
	else:
		_icon.visible = false
		_edge_icon.visible = false

func _process(_delta: float) -> void:
	_update_icon()

func _update_icon() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var screen := get_viewport().get_visible_rect().size
	var center := screen * 0.5
	var inset := edge_margin + edge_icon_size * 0.5
	var inner := Rect2(Vector2.ONE * inset, screen - Vector2.ONE * inset * 2.0)
	var behind := camera.is_position_behind(global_position)
	var point := camera.unproject_position(global_position)
	if not behind and inner.has_point(point):
		_icon.visible = true
		_icon.scale = Vector3.ONE * _pulse
		_edge_icon.visible = false
		return
	var pinned := point.clamp(inner.position, inner.end)
	if behind:
		var direction := center - point
		if direction.length() < 1.0:
			direction = Vector2.DOWN
		var half := inner.size * 0.5
		var scale_x := half.x / absf(direction.x) if direction.x != 0.0 else INF
		var scale_y := half.y / absf(direction.y) if direction.y != 0.0 else INF
		pinned = center + direction * minf(scale_x, scale_y)
	_icon.visible = false
	_edge_icon.visible = true
	_edge_icon.position = pinned - _edge_icon.size * 0.5
	_edge_icon.scale = Vector2.ONE * _pulse

func play_voice(stream: AudioStream) -> void:
	_voice.stream = stream
	_voice.play()

func stop_voice() -> void:
	if _voice != null:
		_voice.stop()
