extends Node2D

@onready var drawer: PanelContainer = $UI/Drawer

var selected_node: int = -1   # -1 means nothing selected
var integrity: Array[float] = [1.0, 1.0, 1.0, 1.0, 1.0]
var controlled: Array[bool] = [false, false, false, false, false]
var nodes: Array[Vector2] = [
	Vector2(200, 200),
	Vector2(500, 150),
	Vector2(800, 250),
	Vector2(300, 450),
	Vector2(700, 500),
]

var edges: Array[Vector2i] = [
	Vector2i(0, 1),
	Vector2i(1, 2),
	Vector2i(0, 3),
	Vector2i(3, 4),
	Vector2i(1, 4),
	Vector2i(2, 4),
]

func _ready() -> void:
	drawer.ability_chosen.connect(_on_ability_chosen)

func _draw() -> void:
	for edge in edges:
		draw_line(nodes[edge.x], nodes[edge.y], Color.DIM_GRAY, 3.0)
	for i in nodes.size():
		var base_color := Color.GREEN if controlled[i] else Color.CYAN
		if i == selected_node:
			base_color = Color.YELLOW
		var radius := 12.0 + 12.0 * integrity[i]  # shrinks as integrity drops
		draw_circle(nodes[i], radius, base_color)
		
const CLICK_RADIUS: float = 25.0

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# If the click is on the drawer, ignore it here — let the button handle it
		if drawer.visible and drawer.get_global_rect().has_point(event.position):
			return

		for i in nodes.size():
			if nodes[i].distance_to(event.position) < CLICK_RADIUS:
				selected_node = i
				drawer.show()
				queue_redraw()
				return
		selected_node = -1
		drawer.hide()
		queue_redraw()
		
func _on_ability_chosen(ability: String) -> void:
	if selected_node == -1:
		return
	match ability:
		"foo":  # take control
			controlled[selected_node] = true
		"bar":  # boost integrity
			integrity[selected_node] = min(1.0, integrity[selected_node] + 0.25)
		"baz":  # drain neighbors, transfer integrity
			for edge in edges:
				var other := -1
				if edge.x == selected_node:
					other = edge.y
				elif edge.y == selected_node:
					other = edge.x
				if other != -1:
					integrity[other] = max(0.0, integrity[other] - 0.2)
					integrity[selected_node] = min(1.0, integrity[selected_node] + 0.1)
	queue_redraw()
