extends Area2D

signal clicked

@onready var polygon: Polygon2D = $Polygon2D

func _ready() -> void:
	input_event.connect(_on_input_event)

func set_selected(is_selected: bool) -> void:
	polygon.color = Color.YELLOW if is_selected else Color.CYAN

func _on_input_event(_viewport, event, _shape_idx) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit()
		get_viewport().set_input_as_handled()
