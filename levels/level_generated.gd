extends LevelBase

const LEVEL_PATH: String = "res://level_data/level_01_seed_10.json"

var level_data: Dictionary = {}
var tower_id_to_index: Dictionary = {}
var edge_lookup: Dictionary = {}

func _ready() -> void:
	level_data = LevelLoader.load_level(LEVEL_PATH)
	if level_data.is_empty():
		push_error("Level data empty; aborting.")
		return
	
	grid_w = int(level_data.get("grid_w", 15))
	grid_h = int(level_data.get("grid_h", 15))
	
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
	
	for e in level_data.get("edges", []):
		var key := _edge_key(e["a_id"], e["b_id"])
		edge_lookup[key] = e
	
	starting_integrity = int(level_data.get("budget", 100))
	current_integrity = starting_integrity
	
	# Build grid, set tower roles, do all game setup
	super._ready()
	
	# Now override terrain for non-plain tiles from JSON
	_paint_terrain_from_data()

func _paint_terrain_from_data() -> void:
	for t in level_data.get("tiles", []):
		var coord := Vector2i(int(t["x"]), int(t["y"]))
		if not terrain_grid.has(coord):
			continue
		var tile: Tile = terrain_grid[coord]
		match t["terrain"]:
			"forest": tile.set_terrain(Tile.Terrain.FOREST)
			"wall":   tile.set_terrain(Tile.Terrain.WALL)
			_:         tile.set_terrain(Tile.Terrain.PLAIN)

func _edge_key(a_id: String, b_id: String) -> String:
	if a_id < b_id:
		return a_id + "|" + b_id
	return b_id + "|" + a_id
