class_name LevelLoader
extends RefCounted

# Static utility for reading level JSON files.

static func load_level(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Level file not found: " + path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	var content := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(content)
	if parsed == null:
		push_error("Failed to parse JSON: " + path)
		return {}

	return parsed
