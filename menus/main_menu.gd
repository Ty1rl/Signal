extends Control

@onready var title_menu: Control = $TitleMenu
@onready var options_menu: Control = $OptionsMenu
@onready var level_select: Control = $LevelSelect

func _on_play_button_pressed() -> void:
	title_menu.hide()
	level_select.show()

func _on_options_button_pressed() -> void:
	title_menu.hide()
	options_menu.show()

func _on_back_button_pressed() -> void:
	options_menu.hide()
	title_menu.show()
