extends PanelContainer

signal ability_chosen(ability: String)

@onready var foo_button: Button = $Buttons/FooButton
@onready var bar_button: Button = $Buttons/BarButton
@onready var baz_button: Button = $Buttons/BazButton

func _ready() -> void:
	foo_button.pressed.connect(func(): ability_chosen.emit("foo"))
	bar_button.pressed.connect(func(): ability_chosen.emit("bar"))
	baz_button.pressed.connect(func(): ability_chosen.emit("baz"))
	hide()

func show_near(screen_pos: Vector2, viewport_size: Vector2) -> void:
	# Position above and to the right of the given screen position
	position = screen_pos + Vector2(30, -80)
	# Clamp to stay on screen
	position.x = clamp(position.x, 10, viewport_size.x - size.x - 10)
	position.y = clamp(position.y, 10, viewport_size.y - size.y - 10)
	show()
