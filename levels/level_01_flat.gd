extends LevelBase

func _ready() -> void:
	tower_positions = [
		Vector2i(1, 1),    # 0: source
		Vector2i(3, 4),    # dist from source: 3 ✓ (reachable)
		Vector2i(6, 5),    # dist from [1]: 3 ✓
		Vector2i(8, 8),    # dist from [2]: 3 ✓
		Vector2i(5, 9),    # 4: target, dist from [3]: 3 ✓
	]
	source_index = 0
	target_index = 4
	_draw_floor_around_towers()
	super._ready()

func _draw_floor_around_towers() -> void:
	if tower_positions.is_empty():
		return

	var min_x: int = tower_positions[0].x
	var max_x: int = tower_positions[0].x
	var min_y: int = tower_positions[0].y
	var max_y: int = tower_positions[0].y
	for pos in tower_positions:
		min_x = min(min_x, pos.x)
		max_x = max(max_x, pos.x)
		min_y = min(min_y, pos.y)
		max_y = max(max_y, pos.y)

	min_x -= 1; max_x += 1
	min_y -= 1; max_y += 1
	# Then also pad bottom specifically for visual overhang
	max_y += 1

	var background_layer: TileMapLayer = $BackgroundTileMapLayer
	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			background_layer.set_cell(Vector2i(x, y), FLOOR_SOURCE_ID, FLOOR_ATLAS_COORDS)

#const FLOOR_SOURCE_ID: int = 21                      # replace with real value
#const FLOOR_ATLAS_COORDS: Vector2i = Vector2i(8, 0)  # replace with real value
