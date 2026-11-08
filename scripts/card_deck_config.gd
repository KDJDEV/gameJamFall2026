class_name CardDeckConfig
extends Resource

## Which sets are in the deck. Add CardSetDef resources to `sets` to choose them by hand; otherwise
## every picture in `art_folder` becomes one set, named after its file (Apep.png -> "Apep"). Drop a new
## picture in the folder to add a set.
@export var sets: Array[CardSetDef] = []
@export_dir var art_folder: String = "res://Assets/cardTextures/creatures"
@export_range(2, 6) var cards_per_set: int = 3
## Used only when there are no sets and no pictures: plain "Set N" cards.
@export_range(1, 30) var placeholder_set_count: int = 10

func build_sets() -> Array[CardSetDef]:
	var result: Array[CardSetDef] = []
	if not sets.is_empty():
		for set_def in sets:
			result.append(set_def)
		return result
	result = _sets_from_folder()
	if not result.is_empty():
		return result
	for index in placeholder_set_count:
		var set_def := CardSetDef.new()
		set_def.set_number = index + 1
		result.append(set_def)
	return result

func _sets_from_folder() -> Array[CardSetDef]:
	var result: Array[CardSetDef] = []
	if art_folder.is_empty():
		return result
	var file_names: Array[String] = []
	for file_name in DirAccess.get_files_at(art_folder):
		# In an exported game the files are listed as "name.png.import" or "name.png.remap".
		var clean := file_name.trim_suffix(".import").trim_suffix(".remap")
		if clean.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"] and not file_names.has(clean):
			file_names.append(clean)
	file_names.sort()
	for file_name in file_names:
		var texture := load(art_folder.path_join(file_name)) as Texture2D
		if texture == null:
			continue
		var set_def := CardSetDef.new()
		set_def.set_number = result.size() + 1
		set_def.display_name = file_name.get_basename()
		set_def.art_texture = texture
		result.append(set_def)
	return result
