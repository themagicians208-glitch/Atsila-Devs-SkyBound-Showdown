extends Node

## Binds a mouse button straight into the running game's InputMap and watches
## whether the action state and the player's swing react. Writes no settings.

func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(0.8).timeout
	var player: CharacterBody3D = main.get_node("Player")
	print("mouse mode captured: %s" % (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED))

	for button in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_LEFT]:
		for event in InputMap.action_get_events("attack"):
			InputMap.action_erase_event("attack", event)
		var bound := InputEventMouseButton.new()
		bound.button_index = button
		bound.device = -1
		InputMap.action_add_event("attack", bound)

		var press := InputEventMouseButton.new()
		press.button_index = button
		press.pressed = true
		Input.parse_input_event(press)
		await get_tree().physics_frame
		print("button %d -> attack down: %s   just_pressed: %s   cooldown: %.2f" % [
			button, Input.is_action_pressed("attack"), Input.is_action_just_pressed("attack"),
			float(player.get("attack_cooldown_left"))])
		var release := InputEventMouseButton.new()
		release.button_index = button
		release.pressed = false
		Input.parse_input_event(release)
		await get_tree().physics_frame
		await get_tree().create_timer(0.5).timeout
	get_tree().quit()
