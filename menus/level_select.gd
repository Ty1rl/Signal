extends Control

@onready var back_button: Button = $Center/Buttons/BackButton

var LEVELS = [
	{"label": "1.   Wide",     "path": "res://level_data/level_tutorial_1_wide.json"},
	{"label": "2.   Pulse",    "path": "res://level_data/level_tutorial_2_pulse.json"},
	{"label": "3.   Skip",     "path": "res://level_data/level_tutorial_3_skip.json"},
	{"label": "4.   Chain",    "path": "res://level_data/level_tutorial_4_chain.json"},
	{"label": "5.   Arc",      "path": "res://level_data/level_arc.json"},
	{"label": "6.   Zigzag",   "path": "res://level_data/level_zigzag.json"},
	{"label": "7.   Gauntlet", "path": "res://level_data/level_gauntlet.json"},
]

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	for lvl in LEVELS:
		var btn = Button.new()
		btn.text = lvl["label"]
		btn.pressed.connect(_load_level.bind(lvl["path"]))
		$Center/Buttons.add_child(btn)
	# Move BackButton to the end of the list
	$Center/Buttons.move_child(back_button, -1)
	# Remove the old hardcoded Level01Button from your scene tree (or hide it)
	if has_node("Center/Buttons/Level01Button"):
		$Center/Buttons/Level01Button.queue_free()

func _load_level(path: String) -> void:
	Globals.current_level_path = path
	get_tree().change_scene_to_file("res://levels/level_generated.tscn")

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://menus/main_menu.tscn")
