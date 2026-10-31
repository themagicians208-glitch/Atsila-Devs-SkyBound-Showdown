extends Node

## Persistent player settings: mouse sensitivity, master volume and graphics
## quality. Saved to user://settings.cfg and applied on startup.

const CONFIG_PATH := "user://settings.cfg"
const SAVE_PATH := "user://save.cfg"
const DEFAULT_SENSITIVITY := 0.22
const DEFAULT_VOLUME := 1.0
const DEFAULT_GRAPHICS := 2
const DEFAULT_TOUCH := "auto"

var mouse_sensitivity := DEFAULT_SENSITIVITY
var master_volume := DEFAULT_VOLUME
var graphics_quality := DEFAULT_GRAPHICS
var touch_controls_mode := DEFAULT_TOUCH


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
	touch_controls_mode = str(config.get_value("controls", "touch_controls_mode", DEFAULT_TOUCH))


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("video", "graphics_quality", graphics_quality)
	config.set_value("controls", "touch_controls_mode", touch_controls_mode)
	config.save(CONFIG_PATH)


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


func set_touch_controls_mode(value: String) -> void:
	touch_controls_mode = value if value in ["auto", "on", "off"] else "auto"
	save_settings()

func get_save_data() -> Dictionary:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return {}

	var data = {}
	if config.has_section("save"):
		for key in config.get_section_keys("save"):
			data[key] = config.get_value("save", key)
	return data


func get_saved_level() -> int:
	## The furthest level the player has reached, or 0 when there is no save yet.
	var data := get_save_data()
	if data.has("level"):
		return maxi(int(data["level"]), 0)
	return 0


func save_progress(level: int, position: Vector3 = Vector3.ZERO, rotation_y: float = 0.0) -> void:
	## Stores the level and the exact spot the player is standing on, so CONTINUE
	## PROGRESS resumes precisely there. A zero position means "the level start".
	level = maxi(level, 1)
	var config := ConfigFile.new()
	config.set_value("save", "level", level)
	config.set_value("save", "position", position)
	config.set_value("save", "rotation_y", rotation_y)
	config.save(SAVE_PATH)


func get_saved_position() -> Vector3:
	var data := get_save_data()
	if data.has("position"):
		return data["position"]
	return Vector3.ZERO


func get_saved_rotation_y() -> float:
	return float(get_save_data().get("rotation_y", 0.0))


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