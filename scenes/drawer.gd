extends PanelContainer

signal ability_chosen(ability: String)

@onready var wide_button: Button = $Buttons/WideButton
@onready var pulse_button: Button = $Buttons/PulseButton
@onready var skip_button: Button = $Buttons/SkipButton
@onready var off_button: Button = $Buttons/OffButton

func _ready() -> void:
	wide_button.pressed.connect(func(): ability_chosen.emit("Wide"))
	pulse_button.pressed.connect(func(): ability_chosen.emit("Pulse"))
	skip_button.pressed.connect(func(): ability_chosen.emit("Skip"))
	off_button.pressed.connect(func(): ability_chosen.emit("Off")) 
	hide()

func show_near(screen_pos: Vector2, viewport_size: Vector2) -> void:
	position = screen_pos + Vector2(30, -80)
	position.x = clamp(position.x, 10, viewport_size.x - size.x - 10)
	position.y = clamp(position.y, 10, viewport_size.y - size.y - 10)
	show()
