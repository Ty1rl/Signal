class_name LevelBase
extends Node2D

@onready var gameplay_layer: TileMapLayer = $GameplayTileMapLayer
@onready var drawer: PanelContainer = $UI/Drawer
@onready var quit_button: Button = $UI/QuitButton
@onready var quit_confirm: ConfirmationDialog = $UI/QuitConfirm
@onready var glow_overlay: Node2D = $GlowOverlay

const TOWER_SCENE := preload("res://scenes/tower.tscn")
const TRANSMIT_RANGE_TILES: int = 3

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
	_spawn_towers()
	glow_overlay.tile_size = gameplay_layer.tile_set.tile_size
	glow_overlay.tile_origin_local = gameplay_layer.map_to_local
	_update_glow()


func _spawn_towers() -> void:
	for i in tower_positions.size():
		var tower: Area2D = TOWER_SCENE.instantiate()
		tower.position = gameplay_layer.map_to_local(tower_positions[i])
		tower.clicked.connect(_on_tower_clicked.bind(i))
		add_child(tower)
		towers.append(tower)
		transmitters.append(false)
		controlled.append(false)

	if source_index >= 0:
		controlled[source_index] = true
		transmitters[source_index] = true

	_recompute_control()
	_update_tower_visuals()


func _recompute_control() -> void:
	for i in controlled.size():
		if i != source_index:
			controlled[i] = false

	var changed := true
	while changed:
		changed = false
		for i in towers.size():
			if not (transmitters[i] and controlled[i]):
				continue
			for j in towers.size():
				if controlled[j]:
					continue
				var dist: int = _tile_distance(tower_positions[i], tower_positions[j])
				if dist <= TRANSMIT_RANGE_TILES:
					controlled[j] = true
					changed = true

	if target_index >= 0 and controlled[target_index]:
		print("TARGET REACHED — level complete")


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
	var seen: Dictionary = {}
	for i in towers.size():
		if not transmitters[i]:
			continue
		var origin: Vector2i = tower_positions[i]
		for dx in range(-TRANSMIT_RANGE_TILES, TRANSMIT_RANGE_TILES + 1):
			for dy in range(-TRANSMIT_RANGE_TILES, TRANSMIT_RANGE_TILES + 1):
				if max(abs(dx), abs(dy)) > TRANSMIT_RANGE_TILES:
					continue
				var t := Vector2i(origin.x + dx, origin.y + dy)
				if seen.has(t):
					continue
				seen[t] = true
				tiles.append(t)
	glow_overlay.set_tiles(tiles)


func _on_tower_clicked(tower_idx: int) -> void:
	if not controlled[tower_idx]:
		return
	if selected_tower != -1:
		towers[selected_tower].set_selected(false)
	selected_tower = tower_idx
	towers[tower_idx].set_selected(true)
	drawer.show()


func _on_ability_chosen(_ability: String) -> void:
	if selected_tower == -1:
		return
	if not controlled[selected_tower]:
		return
	if selected_tower == source_index:
		# Source can't toggle off
		return
	transmitters[selected_tower] = not transmitters[selected_tower]
	_recompute_control()
	_update_tower_visuals()
	_update_glow()


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
