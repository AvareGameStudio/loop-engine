extends Node
## Boot composition root. Scenes stay independently editable.

func _ready() -> void:
	randomize()
	Engine.max_fps = 60
	DisplayServer.window_set_title("Loop Engine")
