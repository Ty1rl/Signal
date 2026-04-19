extends Node2D

var tiles_to_draw: Array[Vector2i] = []
var tile_size: Vector2 = Vector2(128, 64)
var tile_origin_local: Callable

func set_tiles(tiles: Array[Vector2i]) -> void:
	tiles_to_draw = tiles
	queue_redraw()

func _draw() -> void:
	if tile_origin_local.is_null():
		return
	for tile in tiles_to_draw:
		var c: Vector2 = tile_origin_local.call(tile) + Vector2(0, tile_size.y * 0.5)
		c.y -= 8
		var w := tile_size.x * 0.5
		var h := tile_size.y * 0.5
		var diamond := PackedVector2Array([
			c + Vector2(0, -h),
			c + Vector2(w, 0),
			c + Vector2(0, h),
			c + Vector2(-w, 0),
		])
		draw_colored_polygon(diamond, Color(0.3, 0.8, 1.0, 0.3))
