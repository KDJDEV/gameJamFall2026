class_name CardDeckConfig
extends Resource

## Fill `sets` with CardSetDef resources (name, image, tint) to configure the real deck.
## While `sets` is empty, `placeholder_set_count` numbered sets are generated instead.
@export var sets: Array[CardSetDef] = []
@export_range(2, 6) var cards_per_set: int = 3
@export_range(1, 30) var placeholder_set_count: int = 10
@export var default_front_texture: Texture2D

func build_sets() -> Array[CardSetDef]:
	var result: Array[CardSetDef] = []
	if not sets.is_empty():
		for set_def in sets:
			result.append(set_def)
	else:
		for index in placeholder_set_count:
			var set_def := CardSetDef.new()
			set_def.set_number = index + 1
			result.append(set_def)
	for set_def in result:
		if set_def.front_texture == null:
			set_def.front_texture = default_front_texture
	return result
