extends LevelBase

const LEVEL_PATH: String = "res://level_data/level_01_seed_10.json"

var level_data: Dictionary = {}

# Maps from JSON tower id -> index into `towers` array
var tower_id_to_index: Dictionary = {}

# Edges indexed by (a_id, b_id) tuple -> edge dict from JSON
var edge_lookup: Dictionary = {}

func _ready() -> void:
	level_data = LevelLoader.load_level(LEVEL_PATH)
	if level_data.is_empty():
		push_error("Level data empty; aborting.")
		return

	# Populate tower_positions from JSON so base's _spawn_towers does the right thing
	tower_positions.clear()
	var json_towers: Array = level_data.get("towers", [])
	for i in json_towers.size():
		var t: Dictionary = json_towers[i]
		tower_positions.append(Vector2i(int(t["x"]), int(t["y"])))
		tower_id_to_index[t["id"]] = i
		if t.get("is_source", false):
			source_index = i
		if t.get("is_target", false):
			target_index = i

	# Build edge lookup for later use (control propagation will use this)
	for e in level_data.get("edges", []):
		var key := _edge_key(e["a_id"], e["b_id"])
		edge_lookup[key] = e

	# Call base ready to do drawer wiring, spawn towers, etc.
	starting_integrity = int(level_data.get("budget", 100))
	current_integrity = starting_integrity
	super._ready()

	# After towers are spawned, paint tiles from JSON
	_paint_tiles_from_data()
	
	print("tower[0] pos: ", towers[0].position, " y_sort_enabled: ", towers[0].y_sort_enabled)
	print("terrain_layer y_sort_enabled: ", terrain_layer.y_sort_enabled)
	print("terrain_layer child count: ", terrain_layer.get_child_count())	


func _paint_tiles_from_data() -> void:
	# Tiles JSON only ships non-plain tiles; plain is the default floor.
	# First paint a full plain floor for the grid, then overlay the non-plain.
	var bg: TileMapLayer = $TerrainLayer
	var grid_w: int = int(level_data.get("grid_w", 15))
	var grid_h: int = int(level_data.get("grid_h", 15))

	# Flat floor fill
	for x in grid_w:
		for y in grid_h:
			bg.set_cell(Vector2i(x, y), FLOOR_SOURCE_ID, FLOOR_ATLAS_COORDS)

	# Overlay non-plain tiles
	for t in level_data.get("tiles", []):
		var pos := Vector2i(int(t["x"]), int(t["y"]))
		var terrain: String = t["terrain"]
		var source_id: int = FLOOR_SOURCE_ID
		var atlas_coords: Vector2i = FLOOR_ATLAS_COORDS
		match terrain:
			"forest":
				source_id = FOREST_SOURCE_ID
				atlas_coords = FOREST_ATLAS_COORDS
			"wall":
				source_id = WALL_SOURCE_ID
				atlas_coords = WALL_ATLAS_COORDS
		bg.set_cell(pos, source_id, atlas_coords)
		
	print("Tile at (5,14) source_id: ", bg.get_cell_source_id(Vector2i(5, 14)))
	print("Tile at (1,13) source_id: ", bg.get_cell_source_id(Vector2i(1, 13)))
	print("TerrainLayer z_index: ", bg.z_index)
	print("TerrainLayer z_as_relative: ", bg.z_as_relative)		


func _edge_key(a_id: String, b_id: String) -> String:
	# Canonical key: sort alphabetically so (a,b) and (b,a) collide
	if a_id < b_id:
		return a_id + "|" + b_id
	return b_id + "|" + a_id
