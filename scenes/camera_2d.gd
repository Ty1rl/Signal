extends Camera2D

var dragging: bool = false
var drag_start: Vector2

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		dragging = event.pressed
		drag_start = event.position
	elif event is InputEventMouseMotion and dragging:
		position -= event.relative / zoom.x
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom *= 1.1
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom /= 1.1
