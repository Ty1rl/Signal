extends PanelContainer

signal ability_chosen(ability: String)

@onready var wide_button: Button = $Buttons/WideButton
@onready var pulse_button: Button = $Buttons/PulseButton
@onready var skip_button: Button = $Buttons/SkipButton
@onready var off_button: Button = $Buttons/OffButton

const SHAPE_COSTS: Dictionary = {
	"Wide": 10,
	"Pulse": 15,
	"Skip": 25,
}

# Normal / selected style for each shape
var _normal_styles: Dictionary = {}
var _selected_styles: Dictionary = {}

var current_shape: String = ""
var current_integrity: int = 100

func _ready() -> void:
	# Cache the styles we set up in the tscn for toggling selected-state
	_normal_styles = {
		"Wide": wide_button.get_theme_stylebox("normal").duplicate(),
		"Pulse": pulse_button.get_theme_stylebox("normal").duplicate(),
		"Skip": skip_button.get_theme_stylebox("normal").duplicate(),
	}
	# Selected styles are auth'd by the tscn sub_resources; load them by name
	var scene := load("res://scenes/drawer.tscn")
	# Simpler: build selected styles programmatically
	for shape in ["Wide", "Pulse", "Skip"]:
		var style: StyleBoxFlat = _normal_styles[shape].duplicate()
		style.bg_color = style.bg_color.lightened(0.25)
		style.border_color = Color(1, 1, 0.8, 1)
		style.border_width_left = 3
		style.border_width_top = 3
		style.border_width_right = 3
		style.border_width_bottom = 3
		_selected_styles[shape] = style
	
	wide_button.pressed.connect(func(): _on_shape_pressed("Wide"))
	pulse_button.pressed.connect(func(): _on_shape_pressed("Pulse"))
	skip_button.pressed.connect(func(): _on_shape_pressed("Skip"))
	off_button.pressed.connect(_on_off_pressed)
	hide()

func _on_shape_pressed(shape: String) -> void:
	# Re-clicking same shape is a no-op (explicit Off required)
	if current_shape == shape:
		return
	if current_integrity < SHAPE_COSTS[shape]:
		return
	ability_chosen.emit(shape)

func _on_off_pressed() -> void:
	ability_chosen.emit("Off")

# --- Public API for level_base to configure drawer state ---

func show_near(screen_pos: Vector2, viewport_size: Vector2) -> void:
	position = screen_pos + Vector2(-size.x * 0.5, -size.y - 160)
	position.x = clamp(position.x, 10, viewport_size.x - size.x - 10)
	position.y = clamp(position.y, 10, viewport_size.y - size.y - 10)
	show()

func set_current_shape(shape: String) -> void:
	current_shape = shape
	_refresh_button_states()

func set_integrity(integrity: int) -> void:
	current_integrity = integrity
	_refresh_button_states()

# --- Visual refresh ---

func _refresh_button_states() -> void:
	_apply_button_state(wide_button, "Wide")
	_apply_button_state(pulse_button, "Pulse")
	_apply_button_state(skip_button, "Skip")

func _apply_button_state(btn: Button, shape: String) -> void:
	var cost: int = SHAPE_COSTS[shape]
	var affordable: bool = current_integrity >= cost
	var is_selected: bool = current_shape == shape
	
	btn.disabled = not affordable and not is_selected
	
	var style: StyleBoxFlat
	if is_selected:
		style = _selected_styles[shape]
	else:
		style = _normal_styles[shape]
	
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	
	# Dim text when unaffordable
	if not affordable and not is_selected:
		btn.modulate = Color(0.6, 0.6, 0.6)
	else:
		btn.modulate = Color.WHITE
