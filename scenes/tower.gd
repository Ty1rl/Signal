extends Area2D

signal clicked

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	input_event.connect(_on_input_event)

func set_selected(is_selected: bool) -> void:
	sprite.modulate = Color(1.8, 1.8, 0.6) if is_selected else Color.WHITE

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit()
		get_viewport().set_input_as_handled()
