class_name LevelBase
extends Node2D

const TILE_SCENE := preload("res://scenes/tile.tscn")
const TILE_SIZE := Vector2i(32, 16)

const SHAPES: Dictionary = {
	"Wide":  {"range": 3, "cost": 10, "passes": ["plain", "forest"]},
	"Pulse": {"range": 5, "cost": 15, "passes": ["plain"]},
	"Skip":  {"range": 2, "cost": 25, "passes": ["plain", "forest", "wall"]},
}

const SHAPE_COLORS: Dictionary = {
	"Wide":  Color(0.3, 0.9, 0.4, 0.4),
	"Pulse": Color(0.3, 0.6, 1.0, 0.4),
	"Skip":  Color(1.0, 0.5, 0.2, 0.4),
}

@onready var terrain_grid_node: Node2D = $TerrainGrid
@onready var drawer: PanelContainer = $UI/Drawer
@onready var quit_button: Button = $UI/QuitButton
@onready var quit_confirm: ConfirmationDialog = $UI/QuitConfirm
@onready var integrity_label: Label = $UI/IntegrityLabel
@onready var win_dialog: ConfirmationDialog = $UI/WinDialog

var win_shown: bool = false

var starting_integrity: int = 100
var current_integrity: int = 100
var controlled_tiles: Dictionary = {}
var controlled_tile_shapes: Dictionary = {}  # Vector2i -> Array[String]
var transmitter_shape: Dictionary = {}

var grid_w: int = 15
var grid_h: int = 15
var tower_positions: Array[Vector2i] = []
var source_index: int = -1
var target_index: int = -1

var terrain_grid: Dictionary = {}
var tower_coords: Array[Vector2i] = []
var source_coord: Vector2i = Vector2i(-1, -1)
var target_coord: Vector2i = Vector2i(-1, -1)
var transmitters: Dictionary = {}
var selected_coord: Vector2i = Vector2i(-1, -1)

func _ready() -> void:
	drawer.ability_chosen.connect(_on_ability_chosen)
	quit_button.pressed.connect(_on_quit_pressed)
	quit_confirm.confirmed.connect(_on_quit_confirmed)
	win_dialog.confirmed.connect(_on_win_confirmed)
	
	_build_grid()
	_apply_tower_roles()
	_recompute_control()
	_refresh_all_tiles()
	_update_integrity_label()

func tile_to_local(tile: Vector2i) -> Vector2:
	var hw: float = TILE_SIZE.x * 0.5
	var hh: float = TILE_SIZE.y * 0.5
	return Vector2((tile.x - tile.y) * hw, (tile.x + tile.y) * hh)

func _build_grid() -> void:
	for x in grid_w:
		for y in grid_h:
			var coord := Vector2i(x, y)
			var tile: Tile = TILE_SCENE.instantiate()
			tile.tile_coord = coord
			tile.position = tile_to_local(coord)
			terrain_grid_node.add_child(tile)
			terrain_grid[coord] = tile

func _apply_tower_roles() -> void:
	tower_coords.clear()
	for i in tower_positions.size():
		var coord: Vector2i = tower_positions[i]
		if not terrain_grid.has(coord):
			push_warning("Tower position %s has no tile" % coord)
			continue
		var tile: Tile = terrain_grid[coord]
		tower_coords.append(coord)
		if i == source_index:
			tile.set_tower_role(Tile.TowerRole.SOURCE)
			source_coord = coord
		elif i == target_index:
			tile.set_tower_role(Tile.TowerRole.TARGET)
			target_coord = coord
		else:
			tile.set_tower_role(Tile.TowerRole.NORMAL)

func _tile_terrain(tile: Vector2i) -> String:
	if not terrain_grid.has(tile):
		return "plain"
	var t: Tile = terrain_grid[tile]
	match t.terrain:
		Tile.Terrain.FOREST: return "forest"
		Tile.Terrain.WALL:   return "wall"
		_:                    return "plain"

func _recompute_control() -> void:
	controlled_tiles.clear()
	controlled_tile_shapes.clear()
	
	if source_coord != Vector2i(-1, -1):
		controlled_tiles[source_coord] = true
	
	var changed := true
	while changed:
		changed = false
		for coord in transmitters.keys():
			if not controlled_tiles.has(coord) and coord != source_coord:
				continue
			var shape_name: String = transmitter_shape.get(coord, "Wide")
			var before_size: int = controlled_tiles.size()
			_flood_from(coord, shape_name)
			if controlled_tiles.size() > before_size:
				changed = true

func _flood_from(origin: Vector2i, shape_name: String) -> void:
	var shape: Dictionary = SHAPES[shape_name]
	var max_range: int = shape["range"]
	var passes: Array = shape["passes"]
	
	var queue: Array = [origin]
	var visited: Dictionary = {origin: 0}
	while not queue.is_empty():
		var tile: Vector2i = queue.pop_front()
		var d: int = visited[tile]
		controlled_tiles[tile] = true
		if not controlled_tile_shapes.has(tile):
			controlled_tile_shapes[tile] = []
		if shape_name not in controlled_tile_shapes[tile]:
			controlled_tile_shapes[tile].append(shape_name)
		if d >= max_range:
			continue
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				var nb := Vector2i(tile.x + dx, tile.y + dy)
				if visited.has(nb):
					continue
				var terrain: String = _tile_terrain(nb)
				if terrain not in passes:
					continue
				visited[nb] = d + 1
				queue.append(nb)

func _refresh_all_tiles() -> void:
	for coord in terrain_grid.keys():
		var tile: Tile = terrain_grid[coord]
		tile.clear_transient_states()
		if controlled_tiles.has(coord):
			var shape_list: Array = controlled_tile_shapes.get(coord, ["Wide"])
			var colors: Array = []
			for s in shape_list:
				colors.append(SHAPE_COLORS.get(s, Color(0.3, 0.8, 1.0, 0.4)))
			tile.set_highlight_colors(colors)
			tile.add_state(Tile.State.REACHABLE)
		if transmitters.has(coord):
			tile.set_tower_shape(transmitter_shape.get(coord, ""))
			tile.add_state(Tile.State.BROADCASTING)
		else:
			tile.set_tower_shape("")
		if coord == selected_coord:
			tile.add_state(Tile.State.SELECTED)

func _update_integrity_label() -> void:
	integrity_label.text = "Integrity: %d" % current_integrity
	if current_integrity < 0:
		integrity_label.add_theme_color_override("font_color", Color.RED)
	else:
		integrity_label.remove_theme_color_override("font_color")

func _on_tile_clicked(coord: Vector2i) -> void:
	if not terrain_grid.has(coord):
		return
	if not controlled_tiles.has(coord):
		return
	var tile: Tile = terrain_grid[coord]
	if tile.tower_role == Tile.TowerRole.NONE:
		return
	
	if selected_coord != Vector2i(-1, -1) and terrain_grid.has(selected_coord):
		terrain_grid[selected_coord].remove_state(Tile.State.SELECTED)
	selected_coord = coord
	tile.add_state(Tile.State.SELECTED)
	
	drawer.set_current_shape(transmitter_shape.get(coord, ""))
	drawer.set_integrity(current_integrity)
	drawer.show()

func _on_ability_chosen(ability: String) -> void:
	if selected_coord == Vector2i(-1, -1):
		return
	if not controlled_tiles.has(selected_coord):
		return
	
	if ability == "Off":
		if transmitters.has(selected_coord):
			var old: String = transmitter_shape.get(selected_coord, "")
			if old != "":
				current_integrity += SHAPES[old]["cost"]
			transmitters.erase(selected_coord)
			transmitter_shape.erase(selected_coord)
	else:
		var shape_cost: int = SHAPES[ability]["cost"]
		if transmitters.has(selected_coord):
			var old_shape: String = transmitter_shape.get(selected_coord, "")
			if old_shape != "":
				current_integrity += SHAPES[old_shape]["cost"]
			transmitter_shape[selected_coord] = ability
			current_integrity -= shape_cost
		else:
			transmitters[selected_coord] = true
			transmitter_shape[selected_coord] = ability
			current_integrity -= shape_cost
	
	_recompute_control()
	_refresh_all_tiles()
	_update_integrity_label()
	
	drawer.set_current_shape(transmitter_shape.get(selected_coord, ""))
	drawer.set_integrity(current_integrity)
	
	_check_win()

#func _on_ability_chosen(ability: String) -> void:
	#if selected_coord == Vector2i(-1, -1):
		#return
	#if not controlled_tiles.has(selected_coord):
		#return
#
	#if ability == "Off":
		#if transmitters.has(selected_coord):
			#var old: String = transmitter_shape.get(selected_coord, "")
			#if old != "":
				#current_integrity += SHAPES[old]["cost"]
			#transmitters.erase(selected_coord)
			#transmitter_shape.erase(selected_coord)
			#_recompute_control()
			#_refresh_all_tiles()
			#_update_integrity_label()
			#_check_win()
		#return
		#
	#var shape_cost: int = SHAPES[ability]["cost"]
	#
	#if transmitters.has(selected_coord) and transmitter_shape.get(selected_coord) == ability:
		#transmitters.erase(selected_coord)
		#transmitter_shape.erase(selected_coord)
		#current_integrity += shape_cost
	#elif transmitters.has(selected_coord):
		#var old_shape: String = transmitter_shape.get(selected_coord, "")
		#if old_shape != "":
			#current_integrity += SHAPES[old_shape]["cost"]
		#transmitter_shape[selected_coord] = ability
		#current_integrity -= shape_cost
	#else:
		#transmitters[selected_coord] = true
		#transmitter_shape[selected_coord] = ability
		#current_integrity -= shape_cost
	#
	#_recompute_control()
	#_refresh_all_tiles()
	#_update_integrity_label()
	#_check_win()

func _check_win() -> void:
	if win_shown:
		return
	if target_coord == Vector2i(-1, -1):
		return
	if not controlled_tiles.has(target_coord):
		return
	if current_integrity < 0:
		return
	win_shown = true
	win_dialog.dialog_text = "Signal   Integrity   remaining:   %d\n\n" % current_integrity
	win_dialog.popup_centered()

func _on_win_confirmed() -> void:
	get_tree().change_scene_to_file("res://menus/level_select.tscn")

func _process(_delta: float) -> void:
	if selected_coord == Vector2i(-1, -1):
		return
	if not terrain_grid.has(selected_coord):
		return
	var tile: Tile = terrain_grid[selected_coord]
	var screen_pos: Vector2 = tile.get_global_transform_with_canvas().origin
	var viewport_size: Vector2 = get_viewport_rect().size
	if screen_pos.x < 0 or screen_pos.x > viewport_size.x or screen_pos.y < 0 or screen_pos.y > viewport_size.y:
		drawer.hide()
		return
	drawer.show()
	drawer.position = screen_pos + Vector2(-drawer.size.x * 0.5, -drawer.size.y - 160)
	drawer.position.x = clamp(drawer.position.x, 10, viewport_size.x - drawer.size.x - 10)
	drawer.position.y = clamp(drawer.position.y, 10, viewport_size.y - drawer.size.y - 10)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if drawer.visible and drawer.get_global_rect().has_point(event.position):
			return
		
		var picked := _pick_tile_at(event.position)
		print("CLICK at ", event.position, " picked=", picked)
		if picked != Vector2i(-1, -1):
			_on_tile_clicked(picked)
			return
		
		if selected_coord != Vector2i(-1, -1) and terrain_grid.has(selected_coord):
			terrain_grid[selected_coord].remove_state(Tile.State.SELECTED)
			selected_coord = Vector2i(-1, -1)
		drawer.hide()

func _pick_tile_at(screen_pos: Vector2) -> Vector2i:
	var best_coord := Vector2i(-1, -1)
	var best_depth: int = -1
	for coord in terrain_grid.keys():
		var tile: Tile = terrain_grid[coord]
		if tile.tower_role == Tile.TowerRole.NONE:
			continue
		if not tile.has_state(Tile.State.REACHABLE):
			continue
		
		var polys: Array = tile.active_collisions()
		if polys.is_empty():
			continue
		
		var local: Vector2 = tile.get_global_transform_with_canvas().affine_inverse() * screen_pos
		
		var hit: bool = false
		for p in polys:
			var poly: CollisionPolygon2D = p
			var offset: Vector2 = poly.position
			var shifted: PackedVector2Array = PackedVector2Array()
			for pt in poly.polygon:
				shifted.append(pt + offset)
			if shifted.size() < 3:
				continue
			if Geometry2D.is_point_in_polygon(local, shifted):
				hit = true
				break
		
		if not hit:
			continue
		
		var depth: int = coord.x + coord.y
		if depth > best_depth:
			best_depth = depth
			best_coord = coord
	return best_coord

func _on_quit_pressed() -> void:
	quit_confirm.popup_centered()

func _on_quit_confirmed() -> void:
	get_tree().change_scene_to_file("res://menus/level_select.tscn")
