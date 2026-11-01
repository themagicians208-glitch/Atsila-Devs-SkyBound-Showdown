extends Node

## Rebinds through the real OPTIONS > KEY BINDS screen - once with a key and once
## with mouse buttons - checks clashes are refused, checks the bindings reach the
## game's input map, and puts the player's own settings back exactly as they were.

var _home: Node
var _settings: Node
var _saved: Dictionary = {}


func _ready() -> void:
	_settings = get_node("/root/Settings")
	# Whatever the player has bound stays bound: this test puts it all back.
	_saved = (_settings.get("key_binds") as Dictionary).duplicate()
	_home = load("res://scenes/home.tscn").instantiate()
	add_child(_home)
	await get_tree().process_frame
	await get_tree().process_frame
	_home.call("_show_key_binds")
	await get_tree().process_frame

	print("player's own binds: %s" % (_saved if not _saved.is_empty() else "none"))
	print("rows shown: %d" % (_home.get("_bind_buttons") as Dictionary).size())
	var rows: Array[String] = []
	for action in (_home.get("_bind_buttons") as Dictionary).keys():
		rows.append("%s = %s" % [action, (_home.get("_bind_buttons")[action] as Button).text])
	print("bound now: %s" % " | ".join(rows))

	# --- a key ---------------------------------------------------------------
	await _rebind("attack", _key(KEY_L))
	print("\nafter pressing L: attack row reads '%s'   note: %s" % [
		_row("attack"), _home.get("_bind_note").text])

	# --- a mouse button that is already taken --------------------------------
	# Right click is Shift dimension's, so this must be refused.
	await _rebind("attack", _click(MOUSE_BUTTON_RIGHT))
	print("right click on \"Slash attack\": %s" % _home.get("_bind_note").text)
	print("   attack is still %s" % _row("attack"))

	# --- free mouse buttons --------------------------------------------------
	await _rebind("attack", _click(MOUSE_BUTTON_MIDDLE))
	print("middle click on \"Slash attack\": %s" % _home.get("_bind_note").text)
	print("   row reads '%s'   stored as %d (mouse base + %d)" % [
		_row("attack"), int(_settings.call("get_key_bind", "attack")),
		int(_settings.call("mouse_button_of", int(_settings.call("get_key_bind", "attack"))))])
	await _rebind("dash", _click(MOUSE_BUTTON_MIDDLE))
	print("middle click on \"Dash\" too: %s" % _home.get("_bind_note").text)
	await _rebind("dash", _click(MOUSE_BUTTON_XBUTTON2))
	print("mouse 5 on \"Dash\": %s" % _home.get("_bind_note").text)
	await _rebind("inventory", _click(MOUSE_BUTTON_WHEEL_UP))
	print("wheel up on \"Inventory\": %s" % _home.get("_bind_note").text)
	await _rebind("interact", _click(MOUSE_BUTTON_XBUTTON1))
	print("mouse 4 on \"Interact\": %s" % _home.get("_bind_note").text)
	await _rebind("move_forward", _click(MOUSE_BUTTON_RIGHT))
	print("right click on \"Move forward\": %s" % _home.get("_bind_note").text)

	# --- ESC still cancels ---------------------------------------------------
	_home.call("_start_rebind", "jump")
	_home.call("_input", _key(KEY_ESCAPE))
	await get_tree().process_frame
	print("ESC on \"Jump\": row reads '%s'   note cleared: %s" % [
		_row("jump"), _home.get("_bind_note").text == ""])

	# --- does the game use them? --------------------------------------------
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(0.6).timeout
	for action in ["attack", "dash", "inventory", "interact", "move_forward", "jump"]:
		print("in the level, '%s' is bound to: %s" % [action, _events(action)])
	var player: CharacterBody3D = main.get_node("Player")
	# Each button is pressed, checked in that frame, then released - a synthetic
	# button left held down would swallow the next press.
	for pair in [[MOUSE_BUTTON_XBUTTON2, "dash"], [MOUSE_BUTTON_MIDDLE, "attack"]]:
		var button: int = pair[0]
		var action: String = pair[1]
		Input.parse_input_event(_click(button))
		await get_tree().physics_frame
		await get_tree().physics_frame
		print("mouse %d pressed -> '%s' is down: %s" % [button, action, Input.is_action_pressed(action)])
		Input.parse_input_event(_release(button))
		await get_tree().physics_frame
		await get_tree().create_timer(0.2).timeout
	print("   dash while mouse 5 was held reached the player: %s" % player.get("is_dashing"))
	print("   left click  -> still bound to jump:  %s" % _has_mouse("jump", MOUSE_BUTTON_LEFT))
	print("   right click -> still Shift dimension: %s" % _has_mouse("shift_dimension", MOUSE_BUTTON_RIGHT))

	# --- give the player their settings back ---------------------------------
	_settings.call("clear_key_binds")
	for action in _saved.keys():
		_settings.call("set_key_bind", str(action), int(_saved[action]))
	print("\nrestored: %s" % (_settings.get("key_binds") if not _saved.is_empty() else "no binds, as before"))
	get_tree().quit()


func _rebind(action: String, event: InputEvent) -> void:
	_home.call("_start_rebind", action)
	_home.call("_input", event)
	await get_tree().process_frame
	# Let the button back up: a synthetic mouse button left held down swallows
	# the next press of that button.
	if event is InputEventMouseButton:
		_home.call("_input", _release((event as InputEventMouseButton).button_index))


func _row(action: String) -> String:
	return (_home.get("_bind_buttons")[action] as Button).text


func _events(action: String) -> String:
	var names: Array[String] = []
	for event in InputMap.action_get_events(action):
		if event is InputEventMouseButton:
			names.append("mouse %d" % (event as InputEventMouseButton).button_index)
		elif event is InputEventKey:
			names.append(OS.get_keycode_string((event as InputEventKey).physical_keycode))
	return ", ".join(names)


func _has_mouse(action: String, button: int) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == button:
			return true
	return false


func _key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


func _click(button: int) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	return event


func _release(button: int) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = false
	return event
