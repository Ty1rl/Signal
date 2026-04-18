extends Node2D

@onready var gameplay_layer: TileMapLayer = $GameplayTileMapLayer
@onready var drawer: PanelContainer = $UI/Drawer

const TOWER_SCENE := preload("res://scenes/tower.tscn")

var towers: Array[Area2D] = []
var selected_tower: int = -1

#var tower_positions: Array[Vector2i] = [
	#Vector2i(0, 0),
	#Vector2i(0, 1),
	#Vector2i(0, 0),
	#Vector2i(0, 0),
	#Vector2i(5, 5),
#]
var tower_positions: Array[Vector2i] = []

func _ready() -> void:
	for x in 10:
		for y in 10:
			tower_positions.append(Vector2i(x, y))
	drawer.ability_chosen.connect(_on_ability_chosen)
	_spawn_towers()

#func _ready() -> void:
	#print("level _ready running")
	#drawer.ability_chosen.connect(_on_ability_chosen)
	#_spawn_towers()

func _spawn_towers() -> void:
	for i in tower_positions.size():
		var tower: Area2D = TOWER_SCENE.instantiate()
		tower.position = gameplay_layer.map_to_local(tower_positions[i])
		tower.clicked.connect(_on_tower_clicked.bind(i))
		add_child(tower)
		towers.append(tower)

func _on_tower_clicked(tower_idx: int) -> void:
	if selected_tower != -1:
		towers[selected_tower].set_selected(false)
	selected_tower = tower_idx
	towers[tower_idx].set_selected(true)
	drawer.show()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Click landed on empty space (towers consumed their own clicks)
		if selected_tower != -1:
			towers[selected_tower].set_selected(false)
			selected_tower = -1
		drawer.hide()

func _on_ability_chosen(ability: String) -> void:
	if selected_tower == -1:
		return
	print("ability ", ability, " on tower ", selected_tower, " at tile ", tower_positions[selected_tower])

func _process(_delta: float) -> void:
	if selected_tower == -1:
		return
	var screen_pos: Vector2 = towers[selected_tower].get_global_transform_with_canvas().origin
	var viewport_size: Vector2 = get_viewport_rect().size

	# Hide drawer if tower is off-screen
	if screen_pos.x < 0 or screen_pos.x > viewport_size.x or screen_pos.y < 0 or screen_pos.y > viewport_size.y:
		drawer.hide()
		return

	drawer.show()
	drawer.position = screen_pos + Vector2(30, -80)
	drawer.position.x = clamp(drawer.position.x, 10, viewport_size.x - drawer.size.x - 10)
	drawer.position.y = clamp(drawer.position.y, 10, viewport_size.y - drawer.size.y - 10)
