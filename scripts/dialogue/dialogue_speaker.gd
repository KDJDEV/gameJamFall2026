class_name DialogueSpeaker
extends Marker3D

## Place this marker above a character's head. It shows an audio icon while that
## character speaks and plays their voice clips positionally. Lines in
## data/dialogue.json refer to it by speaker_id.
@export var speaker_id: StringName = &""
@export var display_name: String = ""
@export var icon_texture: Texture2D = preload("res://Assets/ui/audio_icon.svg")
@export_range(0.0001, 0.01) var icon_pixel_size: float = 0.0009
@export var voice_volume_db: float = 0.0

var _icon: Sprite3D
var _voice: AudioStreamPlayer3D
var _pulse_tween: Tween

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
	_voice = AudioStreamPlayer3D.new()
	_voice.name = "Voice"
	_voice.volume_db = voice_volume_db
	add_child(_voice)

func set_speaking(speaking: bool) -> void:
	if _icon == null:
		return
	if _pulse_tween != null:
		_pulse_tween.kill()
	_icon.visible = speaking
	_icon.scale = Vector3.ONE
	if speaking:
		_pulse_tween = create_tween().set_loops()
		_pulse_tween.tween_property(_icon, "scale", Vector3.ONE * 1.15, 0.35).set_trans(Tween.TRANS_SINE)
		_pulse_tween.tween_property(_icon, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_SINE)

func play_voice(stream: AudioStream) -> void:
	_voice.stream = stream
	_voice.play()

func stop_voice() -> void:
	if _voice != null:
		_voice.stop()
