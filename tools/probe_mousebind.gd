extends Node

func _ready() -> void:
	var settings := get_node("/root/Settings")
	var home: Node = load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await get_tree().process_frame
	home.call("_show_key_binds")
	await get_tree().process_frame
	print("MOUSE_DEFAULTS = %s" % home.get("MOUSE_DEFAULTS"))
	for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		var code: int = int(settings.call("mouse_bind_for", button))
		print("button %d -> code %d   owner=%s   shift_dimension bound mouse=%s   jump bound mouse=%s" % [
			button, code, home.call("_action_using", code),
			home.call("_bound_mouse", "shift_dimension"), home.call("_bound_mouse", "jump")])
	get_tree().quit()
