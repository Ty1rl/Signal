class_name LevelBase
extends Node2D

@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var drawer: PanelContainer = $UI/Drawer
@onready var quit_button: Button = $UI/QuitButton
@onready var quit_confirm: ConfirmationDialog = $UI/QuitConfirm
@onready var glow_overlay: Node2D = $GlowOverlay

@onready var integrity_label: Label = $UI/IntegrityLabel
@onready var win_dialog: ConfirmationDialog = $UI/WinDialog

#const FLOOR_SOURCE_ID: int = 1                   
#const FLOOR_ATLAS_COORDS: Vector2i = Vector2i(0, 0)  
#
#const FOREST_SOURCE_ID: int = 0
#const FOREST_ATLAS_COORDS: Vector2i = Vector2i(0, 0)
#
#const WALL_SOURCE_ID: int = 2
#const WALL_ATLAS_COORDS: Vector2i = Vector2i(0, 0)

const FLOOR_SOURCE_ID: int = 8
const FLOOR_ATLAS_COORDS: Vector2i = Vector2i(0, 0)
const FOREST_SOURCE_ID: int = 8
const FOREST_ATLAS_COORDS: Vector2i = Vector2i(1, 0)  # second rock
const WALL_SOURCE_ID: int = 8
const WALL_ATLAS_COORDS: Vector2i = Vector2i(2, 0)    # third rock

const TOWER_SCENE := preload("res://scenes/tower.tscn")
#const TRANSMIT_RANGE_TILES: int = 3
# Shape rules — must match JSON
const SHAPES: Dictionary = {
	"Wide":  {"range": 3, "cost": 10, "passes": ["plain", "forest"]},
	"Pulse": {"range": 5, "cost": 15, "passes": ["plain"]},
	"Skip":  {"range": 2, "cost": 25, "passes": ["plain", "forest", "wall"]},
}
var starting_integrity: int = 100   # set from JSON
var current_integrity: int = 100    # decreases/increases as transmitters toggle
var controlled_tiles: Dictionary = {}  # Vector2i -> true
var transmitter_shape: Dictionary = {} # tower_idx -> shape_name
# Levels override these
var tower_positions: Array[Vector2i] = []
var source_index: int = -1
var target_index: int = -1

# Runtime state
var towers: Array[Area2D] = []
var transmitters: Array[bool] = []
var controlled: Array[bool] = []
var selected_tower: int = -1

func _ready() -> void:
	drawer.ability_chosen.connect(_on_ability_chosen)
	quit_button.pressed.connect(_on_quit_pressed)
	quit_confirm.confirmed.connect(_on_quit_confirmed)
	win_dialog.confirmed.connect(_on_win_confirmed)
	_spawn_towers()
	
	######################
	var debug_overlay: Node2D = $DebugOverlay
	var grid_w: int = 15  # or read from level_data if available
	var grid_h: int = 15
	debug_overlay.setup(terrain_layer, towers, tower_positions, grid_w, grid_h, source_index)
	######################
	# Inspect what's going on with sort
	print("--- Sort diagnosis ---")
	print("TerrainLayer y_sort_enabled: ", terrain_layer.y_sort_enabled)
	print("TerrainLayer z_index: ", terrain_layer.z_index)
	print("TerrainLayer z_as_relative: ", terrain_layer.z_as_relative)

	var tower0 = towers[0]
	print("Tower[0] y_sort_enabled: ", tower0.y_sort_enabled)
	print("Tower[0] z_index: ", tower0.z_index)
	print("Tower[0] z_as_relative: ", tower0.z_as_relative)
	print("Tower[0] position: ", tower0.position)
	print("Tower[0] global_position: ", tower0.global_position)
	print("Tower[0] parent: ", tower0.get_parent().name)

	# Check if terrain_layer has tiles at tower positions
	var tile_at_tower = terrain_layer.get_cell_source_id(tower_positions[0])
	print("Tile at tower[0]'s cell (source_id): ", tile_at_tower)

	# Visual child check
	var visual = tower0.get_node_or_null("Visual")
	if visual:
		print("Visual y_sort_enabled: ", visual.y_sort_enabled)
		print("Visual position: ", visual.position)
		print("Visual children count: ", visual.get_child_count())
		for child in visual.get_children():
			print("  - ", child.name, " pos=", child.position, " type=", child.get_class())
		####
	
	glow_overlay.tile_size = terrain_layer.tile_set.tile_size
	glow_overlay.tile_origin_local = terrain_layer.map_to_local
	_update_glow()
	_update_integrity_label()

func _update_integrity_label() -> void:
	integrity_label.text = "Integrity: %d" % current_integrity
	if current_integrity < 0:
		integrity_label.add_theme_color_override("font_color", Color.RED)
	else:
		integrity_label.remove_theme_color_override("font_color")

func _spawn_towers() -> void:
	for i in tower_positions.size():
		var tower: Area2D = TOWER_SCENE.instantiate()
		tower.position = terrain_layer.map_to_local(tower_positions[i])
		#tower.z_index = tower_positions[i].x + tower_positions[i].y + 1
		tower.clicked.connect(_on_tower_clicked.bind(i))
		terrain_layer.add_child(tower)
		towers.append(tower)
		transmitters.append(false)
		controlled.append(false)
	
	if source_index >= 0:
		controlled[source_index] = true
	_recompute_control()
	_update_tower_visuals()

#func _spawn_towers() -> void:
	#var sort_order = range(tower_positions.size())
	#sort_order.sort_custom(func(a, b):
		#if tower_positions[a].y != tower_positions[b].y:
			#return tower_positions[a].y < tower_positions[b].y
		#return tower_positions[a].x < tower_positions[b].x
	#)
	#
	## Remember what source/target were before sorting
	#var original_source_pos: Vector2i = tower_positions[source_index] if source_index >= 0 else Vector2i(-1, -1)
	#var original_target_pos: Vector2i = tower_positions[target_index] if target_index >= 0 else Vector2i(-1, -1)
	#
	## Reorder tower_positions to match spawn order
	#var new_positions: Array[Vector2i] = []
	#for i in sort_order:
		#new_positions.append(tower_positions[i])
	#tower_positions = new_positions
	#
	## Find new indices for source and target
	#source_index = -1
	#target_index = -1
	#for i in tower_positions.size():
		#if tower_positions[i] == original_source_pos:
			#source_index = i
		#if tower_positions[i] == original_target_pos:
			#target_index = i
	#
	## Now spawn in the (already sorted) tower_positions order
	#for i in tower_positions.size():
		#var tower: Area2D = TOWER_SCENE.instantiate()
		#tower.position = terrain_layer.map_to_local(tower_positions[i])
		#tower.z_index = tower_positions[i].x + tower_positions[i].y + 1 
		#tower.clicked.connect(_on_tower_clicked.bind(i))
		##add_child(tower)
		#terrain_layer.add_child(tower)
		#towers.append(tower)
		#transmitters.append(false)
		#controlled.append(false)
	#
	#if source_index >= 0:
		#controlled[source_index] = true
	#_recompute_control()
	#_update_tower_visuals()


func _recompute_control() -> void:
	# Clear
	controlled_tiles.clear()
	for i in controlled.size():
		controlled[i] = false

	# Iteratively flood from each transmitter. Propagation loop: newly
	# controlled towers that are transmitters also flood.
	var changed := true
	while changed:
		changed = false
		for i in towers.size():
			if not transmitters[i]:
				continue
			var tower_tile: Vector2i = tower_positions[i]
			if not controlled_tiles.has(tower_tile) and i != source_index:
				# this transmitter isn't reachable yet
				continue
			# Flood from this transmitter using its chosen shape
			var shape_name: String = transmitter_shape.get(i, "Wide")
			_flood_from(tower_tile, shape_name)
			# Source is special: always controlled
			controlled_tiles[tower_tile] = true
			# Check if any uncontrolled towers got their tile lit up
			for j in towers.size():
				if controlled[j]:
					continue
				if controlled_tiles.has(tower_positions[j]):
					controlled[j] = true
					changed = true

	# Source is always controlled
	if source_index >= 0:
		controlled[source_index] = true


func _flood_from(origin: Vector2i, shape_name: String) -> void:
	var shape: Dictionary = SHAPES[shape_name]
	var max_range: int = shape["range"]
	var passes: Array = shape["passes"]
	print("Flood from ", origin, " shape=", shape_name, " range=", max_range, " passes=", passes)
	
	var queue := [origin]
	var visited := {origin: 0}
	var tiles_added := 0
	while not queue.is_empty():
		var tile: Vector2i = queue.pop_front()
		var d: int = visited[tile]
		controlled_tiles[tile] = true
		tiles_added += 1
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
					print("  blocked at ", nb, " terrain=", terrain)
					continue
				visited[nb] = d + 1
				queue.append(nb)
	print("  added ", tiles_added, " tiles. controlled_tiles now has ", controlled_tiles.size())


func _tile_terrain(tile: Vector2i) -> String:
	# Lookup the tile's terrain by checking the background tilemap
	var bg: TileMapLayer = $TerrainLayer
	var source_id := bg.get_cell_source_id(tile)
	var atlas := bg.get_cell_atlas_coords(tile)
	if source_id == -1:
		return "plain"  # no tile = treat as out of bounds, but plain-ish
	# Match against our known tile constants
	if source_id == FOREST_SOURCE_ID and atlas == FOREST_ATLAS_COORDS:
		return "forest"
	if source_id == WALL_SOURCE_ID and atlas == WALL_ATLAS_COORDS:
		return "wall"
	return "plain"

func _update_tower_visuals() -> void:
	for i in towers.size():
		var state := "uncontrolled"
		if i == source_index:
			state = "source"
		elif i == target_index and controlled[i]:
			state = "target"
		elif transmitters[i]:
			state = "transmitter"
		elif controlled[i]:
			state = "controlled"
		towers[i].set_state(state)


func _update_glow() -> void:
	var tiles: Array[Vector2i] = []
	for tile in controlled_tiles:
		tiles.append(tile)
	glow_overlay.set_tiles(tiles)


func _on_tower_clicked(tower_idx: int) -> void:
	if not controlled[tower_idx]:
		return
	if selected_tower != -1:
		towers[selected_tower].set_selected(false)
	selected_tower = tower_idx
	towers[tower_idx].set_selected(true)
	drawer.show()

func _on_ability_chosen(ability: String) -> void:
	if selected_tower == -1:
		return
	if not controlled[selected_tower]:
		return

	var shape_cost: int = SHAPES[ability]["cost"]

	# Toggle: same shape already active = refund and turn off
	if transmitters[selected_tower] and transmitter_shape.get(selected_tower) == ability:
		transmitters[selected_tower] = false
		transmitter_shape.erase(selected_tower)
		current_integrity += shape_cost
	# Switching shape on an active transmitter = refund old, charge new
	elif transmitters[selected_tower]:
		var old_shape: String = transmitter_shape.get(selected_tower, "")
		if old_shape != "":
			current_integrity += SHAPES[old_shape]["cost"]
		transmitter_shape[selected_tower] = ability
		current_integrity -= shape_cost
	# Activating new transmitter
	else:
		transmitters[selected_tower] = true
		transmitter_shape[selected_tower] = ability
		current_integrity -= shape_cost

	_recompute_control()
	_update_tower_visuals()
	_update_glow()
	_update_integrity_label()
	_check_win()

func _check_win() -> void:
	if target_index < 0:
		return
	if not controlled[target_index]:
		return
	if current_integrity < 0:
		print("REACHED TARGET BUT OVERDRAWN — integrity ", current_integrity)
		return
	# Win!
	win_dialog.dialog_text = "You connected the signal.\nIntegrity remaining: %d" % current_integrity
	win_dialog.popup_centered()


func _on_win_confirmed() -> void:
	get_tree().change_scene_to_file("res://menus/level_select.tscn")
		
func _process(_delta: float) -> void:
	if selected_tower == -1:
		return
	var screen_pos: Vector2 = towers[selected_tower].get_global_transform_with_canvas().origin
	var viewport_size: Vector2 = get_viewport_rect().size
	if screen_pos.x < 0 or screen_pos.x > viewport_size.x or screen_pos.y < 0 or screen_pos.y > viewport_size.y:
		drawer.hide()
		return
	drawer.show()
	drawer.position = screen_pos + Vector2(30, -80)
	drawer.position.x = clamp(drawer.position.x, 10, viewport_size.x - drawer.size.x - 10)
	drawer.position.y = clamp(drawer.position.y, 10, viewport_size.y - drawer.size.y - 10)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if drawer.visible and drawer.get_global_rect().has_point(event.position):
			return
		if selected_tower != -1:
			towers[selected_tower].set_selected(false)
			selected_tower = -1
		drawer.hide()


func _on_quit_pressed() -> void:
	quit_confirm.popup_centered()


func _on_quit_confirmed() -> void:
	get_tree().change_scene_to_file("res://menus/level_select.tscn")


func _tile_distance(a: Vector2i, b: Vector2i) -> int:
	return max(abs(a.x - b.x), abs(a.y - b.y))
