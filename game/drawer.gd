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
