extends Camera2D

const ZOOM_STEP: float = 1.1
const ZOOM_MIN: float = 0.3
const ZOOM_MAX: float = 3.0

var dragging: bool = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(event.position, ZOOM_STEP)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(event.position, 1.0 / ZOOM_STEP)
	elif event is InputEventMouseMotion and dragging:
		position -= event.relative / zoom.x

func _zoom_at(_screen_pos: Vector2, factor: float) -> void:
	var world_before: Vector2 = get_global_mouse_position()
	zoom = (zoom * factor).clamp(Vector2(ZOOM_MIN, ZOOM_MIN), Vector2(ZOOM_MAX, ZOOM_MAX))
	var world_after: Vector2 = get_global_mouse_position()
	position += world_before - world_after
