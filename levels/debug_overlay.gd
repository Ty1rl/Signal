extends Node2D

const ENABLED: bool = true

var tile_map_layer: TileMapLayer
var towers_ref: Array = []
var tower_positions_ref: Array = []
var grid_w: int = 15
var grid_h: int = 15

var source_index: int = -1

func setup(tml: TileMapLayer, towers: Array, positions: Array, w: int, h: int, src: int) -> void:
	tile_map_layer = tml
	towers_ref = towers
	tower_positions_ref = positions
	grid_w = w
	grid_h = h
	source_index = src
	queue_redraw()

func _draw() -> void:
	if not ENABLED or tile_map_layer == null:
		return
	
	# Draw every tile position as a small dot (teal)
	for x in grid_w:
		for y in grid_h:
			var p: Vector2 = tile_map_layer.map_to_local(Vector2i(x, y))
			draw_circle(p, 1.5, Color(0.1, 0.8, 0.8, 0.6))
	
	# Draw tower positions as larger dots (red)
	for i in tower_positions_ref.size():
		var p: Vector2 = tile_map_layer.map_to_local(tower_positions_ref[i])
		draw_circle(p, 3.0, Color(1.0, 0.2, 0.2, 1.0))
	
	# Draw tower actual positions (where they're drawn) as crosses (yellow)
	for t in towers_ref:
		var p: Vector2 = t.position
		draw_line(p + Vector2(-4, 0), p + Vector2(4, 0), Color.YELLOW, 1.0)
		draw_line(p + Vector2(0, -4), p + Vector2(0, 4), Color.YELLOW, 1.0)
	
	# Outline the grid edges with the diamond of the extreme tiles
	#_draw_tile_diamond(Vector2i(0, 0), Color(0.3, 1.0, 0.3, 0.8))
	#_draw_tile_diamond(Vector2i(grid_w - 1, 0), Color(0.3, 1.0, 0.3, 0.8))
	#_draw_tile_diamond(Vector2i(0, grid_h - 1), Color(0.3, 1.0, 0.3, 0.8))
	#_draw_tile_diamond(Vector2i(grid_w - 1, grid_h - 1), Color(0.3, 1.0, 0.3, 0.8))
	# Outline every tile diamond in white
	for x in grid_w:
		for y in grid_h:
			_draw_tile_diamond(Vector2i(x, y), Color(1.0, 1.0, 1.0, 0.5))	
			
	# Source tower base in red
	if source_index >= 0 and source_index < tower_positions_ref.size():
		_draw_tile_diamond(tower_positions_ref[source_index], Color(1.0, 0.2, 0.2, 1.0))

func _draw_tile_diamond(tile: Vector2i, color: Color) -> void:
	var c: Vector2 = tile_map_layer.map_to_local(tile)
	var ts: Vector2i = tile_map_layer.tile_set.tile_size
	var w := ts.x * 0.5
	var h := ts.y * 0.5
	var pts := PackedVector2Array([
		c + Vector2(0, -h),
		c + Vector2(w, 0),
		c + Vector2(0, h),
		c + Vector2(-w, 0),
		c + Vector2(0, -h),  # close
	])
	for i in pts.size() - 1:
		draw_line(pts[i], pts[i + 1], color, 1.0)
