extends Area2D

signal clicked

@onready var sprite: Sprite2D = $Sprite2D

var current_state: String = "uncontrolled"
var is_selected: bool = false

func _ready() -> void:
	input_event.connect(_on_input_event)

func set_state(state: String) -> void:
	current_state = state
	_update_modulate()

func set_selected(selected: bool) -> void:
	is_selected = selected
	_update_modulate()

func _update_modulate() -> void:
	if is_selected:
		sprite.modulate = Color(1.8, 1.8, 0.6)
		return

	# Dim if uncontrolled (overrides identity)
	if current_state == "uncontrolled":
		sprite.modulate = Color(0.4, 0.4, 0.4)
		return

	match current_state:
		"source":
			sprite.modulate = Color(0.6, 1.8, 0.6)
		"target":
			sprite.modulate = Color(1.8, 0.6, 1.8)
		"transmitter":
			sprite.modulate = Color(0.7, 1.5, 1.8)
		"controlled":
			sprite.modulate = Color.WHITE
		_:
			sprite.modulate = Color.WHITE
			
func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit()
		get_viewport().set_input_as_handled()
