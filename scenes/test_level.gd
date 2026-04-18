extends Node2D

@onready var gameplay_layer: TileMapLayer = $GameplayTileMapLayer
@onready var drawer: PanelContainer = $UI/Drawer

const TOWER_SCENE := preload("res://scenes/tower.tscn")

var towers: Array = []
var selected_tower: int = -1

var tower_positions: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(2, 1),
	Vector2i(1, 3),
]

func _ready() -> void:
	drawer.ability_chosen.connect(_on_ability_chosen)
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
		if drawer.visible and drawer.get_global_rect().has_point(event.position):
			return
		if selected_tower != -1:
			towers[selected_tower].set_selected(false)
			selected_tower = -1
		drawer.hide()

func _on_ability_chosen(ability: String) -> void:
	if selected_tower == -1:
		return
	print("ability ", ability, " on tower ", selected_tower, " at ", tower_positions[selected_tower])
