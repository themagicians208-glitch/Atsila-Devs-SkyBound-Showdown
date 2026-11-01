extends Node

## Does a mouse button bound in the InputMap actually drive the action state?
## Bypasses the settings file entirely: events are added straight to InputMap.

func _ready() -> void:
	for pair in [[MOUSE_BUTTON_MIDDLE, "probe_middle"], [MOUSE_BUTTON_WHEEL_UP, "probe_wheel"],
			[MOUSE_BUTTON_XBUTTON2, "probe_mouse5"], [MOUSE_BUTTON_LEFT, "probe_left"]]:
		var event := InputEventMouseButton.new()
		event.button_index = pair[0]
		event.device = -1
		InputMap.add_action(str(pair[1]))
		InputMap.action_add_event(str(pair[1]), event)

	for pair in [[MOUSE_BUTTON_MIDDLE, "probe_middle"], [MOUSE_BUTTON_WHEEL_UP, "probe_wheel"],
			[MOUSE_BUTTON_XBUTTON2, "probe_mouse5"], [MOUSE_BUTTON_LEFT, "probe_left"]]:
		var press := InputEventMouseButton.new()
		press.button_index = pair[0]
		press.pressed = true
		Input.parse_input_event(press)
		print("button %d -> '%s':  same frame %s   just_pressed %s" % [
			pair[0], pair[1], Input.is_action_pressed(str(pair[1])),
			Input.is_action_just_pressed(str(pair[1]))])
		await get_tree().physics_frame
		print("      after a frame: pressed %s   just_pressed %s" % [
			Input.is_action_pressed(str(pair[1])), Input.is_action_just_pressed(str(pair[1]))])
		await get_tree().physics_frame
		print("      after two:     pressed %s" % Input.is_action_pressed(str(pair[1])))
		var release := InputEventMouseButton.new()
		release.button_index = pair[0]
		release.pressed = false
		Input.parse_input_event(release)
		await get_tree().physics_frame
	get_tree().quit()
