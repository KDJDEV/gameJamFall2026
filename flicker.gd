extends OmniLight3D

@export var noise: NoiseTexture3D
@export var flicker_speed: float = 25.0 
@export var min_energy: float = 0.75   
@export var max_energy: float = 1.15 

var time_past: float = 0.0
var fast_noise: FastNoiseLite

func _ready() -> void:
	if noise:
		fast_noise = noise.noise as FastNoiseLite

func _process(delta: float) -> void:
	if noise:
		time_past += delta * flicker_speed
		
		var raw_noise = fast_noise.get_noise_1d(time_past)
		
		var normalized_noise = (raw_noise + 1.0) / 2.0
		
		light_energy = lerp(min_energy, max_energy, normalized_noise)
