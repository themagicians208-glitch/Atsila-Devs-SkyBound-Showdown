extends Node

## Persistent player settings: mouse sensitivity, master volume and graphics
## quality. Saved to user://settings.cfg and applied on startup.

const CONFIG_PATH := "user://settings.cfg"
const DEFAULT_SENSITIVITY := 0.22
const DEFAULT_VOLUME := 1.0
const DEFAULT_GRAPHICS := 2
# Mouse buttons share the bind table with keys. A mouse bind is stored as
# MOUSE_BIND_BASE + the MouseButton index, which is far above every Key value.
const MOUSE_BIND_BASE := 1 << 25

var mouse_sensitivity := DEFAULT_SENSITIVITY
var master_volume := DEFAULT_VOLUME
var graphics_quality := DEFAULT_GRAPHICS
# Rebound keys, action name -> key code. Actions that are not in here use the
# bindings the game sets up itself.
var key_binds: Dictionary = {}


func _ready() -> void:
	load_settings()
	apply_all()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	mouse_sensitivity = clampf(float(config.get_value("controls", "mouse_sensitivity", DEFAULT_SENSITIVITY)), 0.02, 1.0)
	master_volume = clampf(float(config.get_value("audio", "master_volume", DEFAULT_VOLUME)), 0.0, 1.0)
	graphics_quality = clampi(int(config.get_value("video", "graphics_quality", DEFAULT_GRAPHICS)), 0, 2)
	key_binds.clear()
	if config.has_section("input"):
		for key in config.get_section_keys("input"):
			if str(key).begins_with("bind_"):
				key_binds[str(key).substr(5)] = int(config.get_value("input", key))


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("video", "graphics_quality", graphics_quality)
	for action in key_binds.keys():
		config.set_value("input", "bind_" + str(action), int(key_binds[action]))
	config.save(CONFIG_PATH)


func get_key_bind(action: String) -> int:
	return int(key_binds.get(action, 0))


func set_key_bind(action: String, key_code: int) -> void:
	if key_code <= 0:
		key_binds.erase(action)
	else:
		key_binds[action] = key_code
	save_settings()


func clear_key_binds() -> void:
	key_binds.clear()
	save_settings()


## --- Mouse-button binds ---------------------------------------------------------
# Keyboard keys and mouse buttons are stored in the same table, so both can be
# listed, rebind and checked for clashes the same way.

func is_mouse_bind(code: int) -> bool:
	return code >= MOUSE_BIND_BASE


func mouse_bind_for(button: int) -> int:
	return MOUSE_BIND_BASE + button


func mouse_button_of(code: int) -> int:
	return code - MOUSE_BIND_BASE if code >= MOUSE_BIND_BASE else 0


## "Left Click", "Wheel Up", "Mouse 4" ... for a MouseButton index.
func mouse_button_caption(button: int) -> String:
	match button:
		MOUSE_BUTTON_LEFT:
			return "Left Click"
		MOUSE_BUTTON_RIGHT:
			return "Right Click"
		MOUSE_BUTTON_MIDDLE:
			return "Middle Click"
		MOUSE_BUTTON_WHEEL_UP:
			return "Wheel Up"
		MOUSE_BUTTON_WHEEL_DOWN:
			return "Wheel Down"
		MOUSE_BUTTON_WHEEL_LEFT:
			return "Wheel Left"
		MOUSE_BUTTON_WHEEL_RIGHT:
			return "Wheel Right"
		MOUSE_BUTTON_XBUTTON1:
			return "Mouse 4"
		MOUSE_BUTTON_XBUTTON2:
			return "Mouse 5"
	return "Mouse %d" % button


## Display name for a stored bind, whichever kind it is.
func bind_caption(code: int) -> String:
	if is_mouse_bind(code):
		return mouse_button_caption(mouse_button_of(code))
	return OS.get_keycode_string(code)


func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(value, 0.02, 1.0)
	save_settings()


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	apply_audio()
	save_settings()


func set_graphics_quality(value: int) -> void:
	graphics_quality = clampi(value, 0, 2)
	apply_graphics()
	save_settings()


func apply_all() -> void:
	apply_audio()
	apply_graphics()


func apply_audio() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus < 0:
		bus = 0
	if master_volume <= 0.001:
		AudioServer.set_bus_mute(bus, true)
	else:
		AudioServer.set_bus_mute(bus, false)
		AudioServer.set_bus_volume_db(bus, linear_to_db(master_volume))


func apply_graphics() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var root_viewport: Window = tree.root
	match graphics_quality:
		0:
			root_viewport.scaling_3d_scale = 0.55
			root_viewport.msaa_3d = Viewport.MSAA_DISABLED
			root_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		1:
			root_viewport.scaling_3d_scale = 0.77
			root_viewport.msaa_3d = Viewport.MSAA_DISABLED
			root_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		_:
			root_viewport.scaling_3d_scale = 1.0
			root_viewport.msaa_3d = Viewport.MSAA_2X
			root_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA