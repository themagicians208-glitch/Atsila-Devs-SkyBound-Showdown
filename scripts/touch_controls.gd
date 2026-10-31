extends CanvasLayer

## On-screen touch controls for phones and tablets. They feed the SAME input
## actions the keyboard and controller use, so gameplay code stays unchanged:
##   - Left half drag  -> a virtual stick driving move_left/right/forward/back
##   - Right half drag -> turns the camera (look)
##   - Buttons         -> jump, dash, shift dimension, freeze, interact
## The layer only appears during gameplay on touch devices (or when forced on
## in Options), so desktop and console players never see it.

const BUTTON_LAYOUT := [
	{"action": "jump", "label": "JUMP", "radius": 66.0, "offset": Vector2(-104.0, -108.0)},
	{"action": "dash", "label": "DASH", "radius": 50.0, "offset": Vector2(-256.0, -80.0)},
	{"action": "shift_dimension", "label": "SHIFT", "radius": 48.0, "offset": Vector2(-108.0, -256.0)},
	{"action": "time_freeze", "label": "FREEZE", "radius": 46.0, "offset": Vector2(-252.0, -224.0)},
	{"action": "interact", "label": "USE", "radius": 42.0, "offset": Vector2(-346.0, -334.0)},
]

const STICK_RADIUS := 96.0
const KNOB_RADIUS := 44.0
const MOVE_ACTIONS := ["move_left", "move_right", "move_forward", "move_back"]

var _root: Control
var _shown := false
var _stick_index := -1
var _stick_center := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _look_index := -1
var _look_last := Vector2.ZERO
var _held: Dictionary = {}          # touch index -> action name (buttons)
var _button_targets: Array = []     # [{action, label, center, radius}]


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = "TouchRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	_root.draw.connect(_draw_controls)
	add_child(_root)


func _process(_delta: float) -> void:
	var want := _should_show()
	if want != _shown:
		_shown = want
		_root.visible = want
		if not want:
			_release_all()
	if want:
		_root.queue_redraw()


func _touch_enabled() -> bool:
	var settings := get_node_or_null("/root/Settings")
	var mode := "auto"
	if settings != null and settings.get("touch_controls_mode") != null:
		mode = str(settings.touch_controls_mode)
	if mode == "off":
		return false
	if mode == "on":
		return true
	return DisplayServer.is_touchscreen_available()


func _should_show() -> bool:
	if not _touch_enabled() or get_tree().paused:
		return false
	var scene := get_tree().current_scene
	return scene != null and scene.has_node("Player")


func _viewport_size() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2(1280, 720)
	return vp.get_visible_rect().size


func _relayout() -> void:
	_button_targets.clear()
	var size := _viewport_size()
	for b in BUTTON_LAYOUT:
		_button_targets.append({
			"action": b["action"],
			"label": b["label"],
			"center": size + (b["offset"] as Vector2),
			"radius": b["radius"],
		})


func _input(event: InputEvent) -> void:
	if not _shown:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	_relayout()
	if event.pressed:
		for b in _button_targets:
			if event.position.distance_to(b["center"]) <= b["radius"]:
				_press_action(b["action"])
				_held[event.index] = b["action"]
				_root.queue_redraw()
				return
		if event.position.x < _viewport_size().x * 0.5 and _stick_index == -1:
			_stick_index = event.index
			_stick_center = event.position
			_stick_pos = event.position
			_apply_move(Vector2.ZERO)
			_root.queue_redraw()
			return
		if _look_index == -1:
			_look_index = event.index
			_look_last = event.position
		return

	if _held.has(event.index):
		_release_action(_held[event.index])
		_held.erase(event.index)
	elif event.index == _stick_index:
		_stick_index = -1
		_release_move()
	elif event.index == _look_index:
		_look_index = -1
	_root.queue_redraw()


func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index == _stick_index:
		var stick_offset := event.position - _stick_center
		if stick_offset.length() > STICK_RADIUS:
			stick_offset = stick_offset.normalized() * STICK_RADIUS
		_stick_pos = _stick_center + stick_offset
		_apply_move(stick_offset / STICK_RADIUS)
		_root.queue_redraw()
	elif event.index == _look_index:
		_look(event.position - _look_last)
		_look_last = event.position


func _apply_move(v: Vector2) -> void:
	_set_axis("move_right", maxf(v.x, 0.0))
	_set_axis("move_left", maxf(-v.x, 0.0))
	_set_axis("move_back", maxf(v.y, 0.0))
	_set_axis("move_forward", maxf(-v.y, 0.0))


func _set_axis(action: String, strength: float) -> void:
	if not InputMap.has_action(action):
		return
	if strength > 0.02:
		Input.action_press(action, strength)
	elif Input.is_action_pressed(action):
		Input.action_release(action)


func _release_move() -> void:
	for action in MOVE_ACTIONS:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			Input.action_release(action)


func _press_action(action: String) -> void:
	if InputMap.has_action(action):
		Input.action_press(action)


func _release_action(action: String) -> void:
	if InputMap.has_action(action):
		Input.action_release(action)


func _release_all() -> void:
	for action in _held.values():
		_release_action(action)
	_held.clear()
	_stick_index = -1
	_look_index = -1
	_release_move()


func _look(delta: Vector2) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var view := scene.get_node_or_null("View")
	if view != null and view.has_method("add_look"):
		view.add_look(delta)


func _draw_controls() -> void:
	_relayout()
	var font := ThemeDB.fallback_font
	var size := _viewport_size()

	var base := _stick_center if _stick_index != -1 else Vector2(size.x * 0.22, size.y - 150.0)
	var knob := _stick_pos if _stick_index != -1 else base
	_root.draw_circle(base, STICK_RADIUS, Color(1, 1, 1, 0.10))
	_root.draw_arc(base, STICK_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 2.0, true)
	_root.draw_circle(knob, KNOB_RADIUS, Color(1, 1, 1, 0.22))
	_root.draw_arc(knob, KNOB_RADIUS, 0.0, TAU, 32, Color(1, 1, 1, 0.5), 2.0, true)

	for b in _button_targets:
		var lit: bool = InputMap.has_action(b["action"]) and Input.is_action_pressed(b["action"])
		var fill := Color(1.0, 0.82, 0.25, 0.5) if lit else Color(1, 1, 1, 0.16)
		_root.draw_circle(b["center"], b["radius"], fill)
		_root.draw_arc(b["center"], b["radius"], 0.0, TAU, 40, Color(1, 1, 1, 0.5), 2.0, true)
		var label: String = b["label"]
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		_root.draw_string(font, b["center"] + Vector2(-width * 0.5, 6.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.92))