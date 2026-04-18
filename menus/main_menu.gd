extends Control

@onready var title_menu: Control = $TitleMenu
@onready var options_menu: Control = $OptionsMenu

func _on_options_button_pressed() -> void:
	title_menu.hide()
	options_menu.show()

func _on_back_button_pressed() -> void:
	options_menu.hide()
	title_menu.show()
