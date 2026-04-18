extends Control

const TEST_LEVEL: PackedScene = preload("uid://btp7inee50k1p")

func _on_play_button_pressed() -> void:
	get_tree().change_scene_to_file("res://menus/level_select.tscn")

func _on_exit_button_pressed() -> void:
	get_tree().quit()
