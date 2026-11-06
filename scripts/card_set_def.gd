class_name CardSetDef
extends Resource

## One collectible set. Every card of the set shows this definition.
@export var set_number: int = 1
@export var display_name: String = ""
@export var front_texture: Texture2D
@export var tint: Color = Color.WHITE
@export var label_color: Color = Color.BLACK

func get_label_text() -> String:
	if display_name.is_empty():
		return "Set %d" % set_number
	return display_name
