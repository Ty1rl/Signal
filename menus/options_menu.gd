extends Control

@onready var master_bus_index: int = AudioServer.get_bus_index("Master")

func _on_volume_slider_value_changed(value: float) -> void:
	AudioServer.set_bus_volume_linear(master_bus_index, value)
