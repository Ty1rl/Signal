extends Control

@onready var level_01_button: Button = $Center/Buttons/Level01Button
@onready var back_button: Button = $Center/Buttons/BackButton

func _ready() -> void:
	level_01_button.pressed.connect(_on_level_01_pressed)
	back_button.pressed.connect(_on_back_pressed)

func _on_level_01_pressed() -> void:
	get_tree().change_scene_to_file("res://levels/level_generated.tscn")

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://menus/main_menu.tscn")
