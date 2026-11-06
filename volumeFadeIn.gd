extends AudioStreamPlayer

@export var fade_duration: float = 3.0
var target_volume: float = 10     

func _ready() -> void:
	volume_db = -60.0
	
	var tween = create_tween()
	
	tween.tween_property(self, "volume_db", target_volume, fade_duration)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
