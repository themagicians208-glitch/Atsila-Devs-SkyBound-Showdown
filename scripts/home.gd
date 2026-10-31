extends Control

const UI_FONT = preload("res://fonts/lilita_one_regular.ttf")
const LEVEL_NAMES := ["Cloud Hop", "Switchback Sprint", "Moonflip Maze", "Rising Ruins", "Sky Crown", "Gimmick Gauntlet"]

var popup: ColorRect
var popup_title: Label
var popup_body: VBoxContainer
var back_button: Button
var default_button: Button

# Local co-op device selection ("keyboard" or "pad:<device id>").
var p1_device := "keyboard"
var p2_device := "keyboard"
var p1_name := "Player 1"
var p2_name := "Player 2"
var online_name := "Player"
var _p2_auto_assigned := false
var _showing_input_setup := false

# What the popup's single BACK button does on the current screen. When invalid,
# BACK closes the popup back to the main menu.
var _back_handler: Callable = Callable()
# Parallax references
var background: TextureRect
var shade: ColorRect
var margin: MarginContainer
var brand: Label

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.play_music("res://sounds/pixelland.mp3")
	_build_home()
	_build_popup()
	_run_entrance_sequence()
	# The game can start without window focus when launched from the editor,
	# and grab_focus() is unreliable inside _ready — so grab the window focus and
	# set the button focus deferred.
	if get_window():
		get_window().grab_focus()
	default_button.grab_focus.call_deferred()
	var network := get_node_or_null("/root/Network")
	if network and not network.connection_failed.is_connected(_on_network_failed):
		network.connection_failed.connect(_on_network_failed)
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)

func _run_entrance_sequence() -> void:
	background.modulate.a = 0.0
	shade.modulate.a = 0.0
	var bg_tween = create_tween().set_parallel(true)
	bg_tween.tween_property(background, "modulate:a", 1.0, 1.0)
	bg_tween.tween_property(shade, "modulate:a", 0.38, 1.0)
	var columns = margin.get_child(0)
	var content = columns.get_child(0).get_child(0)
	for child in content.get_children():
		child.modulate.a = 0.0
	var seq = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i in range(content.get_child_count()):
		seq.parallel().tween_property(content.get_child(i), "modulate:a", 1.0, 0.5).set_delay(0.3 + (i * 0.1))
	brand.modulate.a = 0.0
	create_tween().tween_property(brand, "modulate:a", 1.0, 0.8).set_delay(0.3)
	var feature_card = columns.get_child(1)
	feature_card.modulate.a = 0.0
	feature_card.scale = Vector2(0.9, 0.9)
	var ftween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	ftween.tween_property(feature_card, "modulate:a", 1.0, 0.8).set_delay(1.0)
	ftween.parallel().tween_property(feature_card, "scale", Vector2(1.0, 1.0), 0.8).set_delay(1.0)

func _process(_delta: float) -> void:
	var mouse_pos = get_viewport().get_mouse_position()
	var screen_size = get_viewport().get_visible_rect().size
	var target_offset = (mouse_pos / screen_size - Vector2(0.5, 0.5)) * 20.0
	background.position = background.position.lerp(-target_offset, 0.1)
	shade.position = shade.position.lerp(-target_offset * 0.5, 0.1)
	margin.position = margin.position.lerp(target_offset, 0.1)

func _exit_tree() -> void:
	var network := get_node_or_null("/root/Network")
	if network and network.connection_failed.is_connected(_on_network_failed):
		network.connection_failed.disconnect(_on_network_failed)
	if Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.disconnect(_on_joy_connection_changed)


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	# Re-detect devices live while the input screen is open, so a controller
	# plugged in after the screen appears is picked up automatically.
	if _showing_input_setup and popup != null and popup.visible:
		call_deferred("_show_local_options")


func _on_network_failed() -> void:
	_online_message("CONNECTION FAILED", "Could not connect.\nCheck the address and that the host is ready.")

func _build_home() -> void:
	background = TextureRect.new()
	background.name = "Background"
	background.texture = preload("res://sprites/skybox.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.offset_left = -50
	background.offset_top = -50
	background.offset_right = 50
	background.offset_bottom = 50
	add_child(background)

	shade = ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0.035, 0.075, 0.17, 0.38)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	brand = _label("SkyBound\nShowdown", 38, Color("#fff1a3"))
	brand.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	brand.offset_left = 34
	brand.offset_top = 24
	brand.offset_right = 300
	brand.offset_bottom = 112
	brand.add_theme_color_override("font_shadow_color", Color(0.05, 0.08, 0.2, 0.9))
	brand.add_theme_constant_override("shadow_offset_x", 3)
	brand.add_theme_constant_override("shadow_offset_y", 4)
	add_child(brand)
	var brand_line := ColorRect.new()
	brand_line.color = Color("#6fe7ef")
	brand_line.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	brand_line.offset_left = 36
	brand_line.offset_top = 112
	brand_line.offset_right = 190
	brand_line.offset_bottom = 115
	brand_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(brand_line)
	var brand_kicker := _label("DIMENSION HOPPER", 12, Color("#a6f4ff"))
	brand_kicker.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	brand_kicker.offset_left = 36
	brand_kicker.offset_top = 120
	brand_kicker.offset_right = 220
	brand_kicker.offset_bottom = 142
	add_child(brand_kicker)

	margin = MarginContainer.new()
	margin.name = "MainMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 86)
	margin.add_theme_constant_override("margin_right", 86)
	margin.add_theme_constant_override("margin_top", 54)
	margin.add_theme_constant_override("margin_bottom", 48)
	add_child(margin)

	var columns := HBoxContainer.new()
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.add_theme_constant_override("separation", 68)
	# Ensure columns doesn't squash children
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(columns)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	columns.add_child(scroll)

	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(520, 0)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 18)
	scroll.add_child(content)

	var tag := _label("A SKY-HOPPING ADVENTURE ACROSS SIX WILDS", 18, Color("#a6f4ff"))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(tag)

	var subtitle := _label("Bend gravity. Outsmart the impossible.\nThe sky is waiting.", 23, Color.WHITE)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	content.add_child(subtitle)

	var menu_hint := _label("READY TO MAKE YOUR MOVE?", 14, Color("#c7f0b9"))
	menu_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(menu_hint)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 2
	content.add_child(spacer)

	var play := _button("PLAY NOW", Color("#ffd451"), Color("#493600"))
	default_button = play
	play.pressed.connect(func(): _start_level(1))
	content.add_child(play)

	var levels := _button("EXPLORE LEVELS", Color("#315784"), Color.WHITE)
	levels.pressed.connect(_show_level_select)
	content.add_child(levels)

	var multiplayer_button := _multiplayer_button()
	content.add_child(multiplayer_button)

	var controls := _button("HOW TO PLAY", Color("#315784"), Color.WHITE)
	controls.pressed.connect(_show_controls)
	content.add_child(controls)

	var settings := _button("OPTIONS", Color("#315784"), Color.WHITE)
	settings.pressed.connect(_show_settings)
	content.add_child(settings)

	var quit := _button("EXIT TO DESKTOP", Color("#263e64"), Color("#d6e6ff"))
	quit.pressed.connect(func(): get_tree().quit())
	content.add_child(quit)

	var feature_card := PanelContainer.new()
	feature_card.custom_minimum_size = Vector2(350, 320)
	feature_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	feature_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var feature_style := _panel_style(Color(0.04, 0.11, 0.24, 0.72), Color("#6fe7ef"))
	feature_style.shadow_color = Color(0.02, 0.05, 0.12, 0.45)
	feature_style.shadow_size = 18
	feature_style.shadow_offset = Vector2(0, 8)
	feature_card.add_theme_stylebox_override("panel", feature_style)
	columns.add_child(feature_card)
	var feature_list := VBoxContainer.new()
	feature_list.alignment = BoxContainer.ALIGNMENT_CENTER
	feature_list.add_theme_constant_override("separation", 17)
	feature_card.add_child(feature_list)
	feature_list.add_child(_label("WHY YOU'LL LOVE THE SKY", 28, Color("#ffe078")))
	feature_list.add_child(_label("6 wild courses to master", 20, Color.WHITE))
	feature_list.add_child(_label("Flip between dimensions", 20, Color.WHITE))
	feature_list.add_child(_label("Freeze time. Change everything.", 20, Color.WHITE))
	feature_list.add_child(_label("Ride the anti-gravity current", 20, Color.WHITE))
	feature_list.add_child(_label("Crack switches. Open new paths", 20, Color.WHITE))
	feature_list.add_child(_label("Ice, fans, barrels & surprises", 17, Color("#c7f0b9")))
	for child in feature_list.get_children():
		child.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var footer := _label("v1.0  •  Atsila Devs", 14, Color("#eff8ff"))
	footer.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	footer.offset_left = -100
	footer.offset_top = -24
	footer.offset_right = 100
	footer.offset_bottom = -8
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(footer)

func _build_popup() -> void:
	popup = ColorRect.new()
	popup.color = Color(0.025, 0.045, 0.09, 0.78)
	popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup.visible = false
	add_child(popup)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(540, 0)
	panel.add_theme_stylebox_override("panel", _panel_style(Color("#17324f"), Color("#ffd66b")))
	center.add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	layout.add_theme_constant_override("margin_left", 32)
	layout.add_theme_constant_override("margin_right", 32)
	layout.add_theme_constant_override("margin_top", 28)
	layout.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(layout)
	popup_title = _label("", 34, Color("#ffe078"))
	popup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(popup_title)
	popup_body = VBoxContainer.new()
	popup_body.add_theme_constant_override("separation", 10)
	layout.add_child(popup_body)
	var back := _button("BACK", Color("#315784"), Color.WHITE)
	back_button = back
	back.pressed.connect(_on_back_pressed)
	layout.add_child(back)


func _on_back_pressed() -> void:
	if _back_handler.is_valid():
		_back_handler.call()
	else:
		_close_popup()

func _show_level_select() -> void:
	_back_handler = Callable()
	popup_title.text = "PICK YOUR COURSE"
	_clear_popup_body()
	for i in range(LEVEL_NAMES.size()):
		var level_number := i + 1
		var level_button := _button("LEVEL %d   •   %s" % [level_number, LEVEL_NAMES[i].to_upper()], Color("#27496f"), Color.WHITE)
		level_button.pressed.connect(_start_level.bind(level_number))
		popup_body.add_child(level_button)

	popup.visible = true
	popup.modulate.a = 0.0
	create_tween().tween_property(popup, "modulate:a", 1.0, 0.2)
	if popup_body.get_child_count() > 0:
		(popup_body.get_child(0) as Control).grab_focus()

func _show_controls() -> void:
	_back_handler = Callable()
	popup_title.text = "HOW TO PLAY"
	_clear_popup_body()
	for line in ["WASD / LEFT STICK   Move", "MOUSE / RIGHT STICK   Look around", "LEFT CLICK / SPACE / A   Jump", "RIGHT CLICK / Q / LEFT BUMPER   Shift dimensions", "F / Y   Slow time", "E / X   Activate the nearby switch", "MOUSE WHEEL / TRIGGERS   Zoom", "CLICK / A   Select     ESC / B   Back"]:
		var row := _label(line, 19, Color.WHITE)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		popup_body.add_child(row)
	popup.visible = true
	popup.modulate.a = 0.0
	create_tween().tween_property(popup, "modulate:a", 1.0, 0.2)
	back_button.grab_focus()

func _show_settings() -> void:
	var settings := get_node_or_null("/root/Settings")
	if settings == null:
		return
	_back_handler = Callable()
	popup_title.text = "SETTINGS"
	_clear_popup_body()
	popup_body.add_child(_slider_row(
		"MOUSE SENSITIVITY", 0.05, 0.6, 0.01, float(settings.mouse_sensitivity),
		func(value: float) -> String: return "%.2f" % value,
		func(value: float) -> void: settings.set_mouse_sensitivity(value)))
	popup_body.add_child(_slider_row(
		"MASTER VOLUME", 0.0, 1.0, 0.01, float(settings.master_volume),
		func(value: float) -> String: return "%d%%" % roundi(value * 100.0),
		func(value: float) -> void: settings.set_master_volume(value)))
	popup_body.add_child(_graphics_row(settings))
	popup.visible = true
	popup.modulate.a = 0.0
	create_tween().tween_property(popup, "modulate:a", 1.0, 0.2)
	back_button.grab_focus()

func _slider_row(caption: String, min_value: float, max_value: float, step: float, value: float, formatter: Callable, on_change: Callable) -> VBoxContainer:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var label := _label("%s   %s" % [caption, formatter.call(value)], 18, Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(440, 26)
	slider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(new_value: float) -> void:
		label.text = "%s   %s" % [caption, formatter.call(new_value)]
		on_change.call(new_value))
	row.add_child(slider)
	return row

func _graphics_row(settings: Node) -> VBoxContainer:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var label := _label("GRAPHICS QUALITY", 18, Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(label)
	var options := OptionButton.new()
	options.custom_minimum_size = Vector2(440, 38)
	options.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	options.add_theme_font_override("font", UI_FONT)
	options.add_theme_font_size_override("font_size", 18)
	options.add_item("LOW", 0)
	options.add_item("MEDIUM", 1)
	options.add_item("HIGH", 2)
	options.select(int(settings.graphics_quality))
	options.item_selected.connect(func(index: int) -> void: settings.set_graphics_quality(index))
	row.add_child(options)
	return row

func _unhandled_input(event: InputEvent) -> void:
	if popup.visible and event.is_action_pressed("ui_cancel"):
		_close_popup()

# --- Multiplayer lobby -------------------------------------------------------

func _show_multiplayer() -> void:
	_showing_input_setup = false
	_back_handler = Callable()
	popup_title.text = "MULTIPLAYER LOBBY"
	_clear_popup_body()
	var local := _button("LOCAL   •   SPLIT SCREEN", Color("#27496f"), Color.WHITE)
	local.pressed.connect(_show_local_options)
	popup_body.add_child(local)
	var online := _button("ONLINE   •   JOIN OR CREATE A ROOM", Color("#27496f"), Color.WHITE)
	online.pressed.connect(_show_online)
	popup_body.add_child(online)
	popup.visible = true
	local.grab_focus()


func _show_local_options() -> void:
	_showing_input_setup = true
	popup_title.text = "LOCAL CO-OP — CONTROLS"
	_clear_popup_body()

	var pads := Input.get_connected_joypads()

	# Drop controller selections whose controller was unplugged.
	if p1_device.begins_with("pad") and not pads.has(int(p1_device.split(":")[1])):
		p1_device = "keyboard"
	if p2_device.begins_with("pad") and not pads.has(int(p2_device.split(":")[1])):
		p2_device = "keyboard"
	# Put player 2 on a controller automatically the first time one is seen.
	if not _p2_auto_assigned and p2_device == "keyboard" and not pads.is_empty():
		p2_device = "pad:%d" % pads[0]
		_p2_auto_assigned = true

	var info := _label("Two players, one screen. Name each player and choose their device.", 17, Color("#cfe9ff"))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 460
	popup_body.add_child(info)

	popup_body.add_child(_label("PLAYER 1", 16, Color("#8fe0ff")))
	var p1_name_edit := _name_field(p1_name, func(value: String) -> void:
		p1_name = value)
	popup_body.add_child(p1_name_edit)
	var p1_option := _device_option(p1_device, func(value: String) -> void:
		p1_device = value)
	popup_body.add_child(p1_option)

	popup_body.add_child(_label("PLAYER 2", 16, Color("#8fe0ff")))
	var p2_name_edit := _name_field(p2_name, func(value: String) -> void:
		p2_name = value)
	popup_body.add_child(p2_name_edit)
	var p2_option := _device_option(p2_device, func(value: String) -> void:
		p2_device = value
		_p2_auto_assigned = true)
	popup_body.add_child(p2_option)

	var detected := "Keyboard" if pads.is_empty() else "Keyboard  +  %d controller%s" % [pads.size(), "" if pads.size() == 1 else "s"]
	var status := _label("Detected:  %s" % detected, 15, Color("#9fc4e8"))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup_body.add_child(status)

	var start := _button("START", Color("#ffd451"), Color("#493600"))
	start.pressed.connect(_local_start_pressed)
	popup_body.add_child(start)

	_back_handler = _show_multiplayer
	popup.visible = true
	start.grab_focus()


func _name_field(current: String, on_change: Callable) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = current
	edit.placeholder_text = "name"
	edit.max_length = 14
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.custom_minimum_size = Vector2(320, 40)
	edit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	edit.add_theme_font_override("font", UI_FONT)
	edit.add_theme_font_size_override("font_size", 20)
	edit.text_changed.connect(func(value: String) -> void:
		on_change.call(value))
	return edit


func _clean_name(value: String, fallback: String = "Player") -> String:
	var trimmed := value.strip_edges()
	return trimmed if not trimmed.is_empty() else fallback


func _device_option(current: String, on_change: Callable) -> OptionButton:
	var option := OptionButton.new()
	option.add_theme_font_override("font", UI_FONT)
	option.add_theme_font_size_override("font_size", 20)
	option.custom_minimum_size = Vector2(320, 44)
	option.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	option.add_item("Keyboard", -1)
	var pads := Input.get_connected_joypads()
	for i in range(pads.size()):
		option.add_item("Controller %d" % (i + 1), pads[i])
		if current == "pad:%d" % pads[i]:
			option.select(option.item_count - 1)
	option.item_selected.connect(func(index: int) -> void:
		var device_id := option.get_item_id(index)
		on_change.call("keyboard" if device_id == -1 else "pad:%d" % device_id))
	return option


func _local_start_pressed() -> void:
	if p1_device == p2_device:
		if p1_device.begins_with("pad"):
			_show_device_error()
		else:
			_ask_keyboard_share()
		return
	_show_local_levels()


func _ask_keyboard_share() -> void:
	_showing_input_setup = false
	popup_title.text = "SHARE THE KEYBOARD?"
	_clear_popup_body()
	var info := _label("Only the keyboard is available.\n\nPlayer 1:  WASD  +  mouse\nPlayer 2:  arrow keys  +  Enter\n\nShare it between both players?", 18, Color("#e6f3ff"))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 460
	popup_body.add_child(info)
	var yes := _button("YES, PLAY ON ONE KEYBOARD", Color("#ffd451"), Color("#493600"))
	yes.pressed.connect(_show_local_levels)
	popup_body.add_child(yes)
	_back_handler = _show_local_options
	popup.visible = true
	yes.grab_focus()


func _show_device_error() -> void:
	_showing_input_setup = false
	popup_title.text = "NEED ANOTHER DEVICE"
	_clear_popup_body()
	var info := _label("A single controller can't control two players.\n\nSet one player to the keyboard, or plug in a second controller.", 18, Color("#e6f3ff"))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 460
	popup_body.add_child(info)
	_back_handler = _show_local_options
	popup.visible = true
	back_button.grab_focus()


func _show_local_levels() -> void:
	_showing_input_setup = false
	popup_title.text = "LOCAL SPLIT SCREEN"
	_clear_popup_body()
	var info := _label("P1: %s      P2: %s" % [_local_device_name(p1_device), _local_device_name(p2_device)], 16, Color("#cfe9ff"))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup_body.add_child(info)
	for i in range(LEVEL_NAMES.size()):
		var level_number := i + 1
		var level_button := _button("LEVEL %d   •   %s" % [level_number, LEVEL_NAMES[i].to_upper()], Color("#27496f"), Color.WHITE)
		level_button.pressed.connect(_start_local.bind(level_number))
		popup_body.add_child(level_button)
	_back_handler = _show_local_options
	popup.visible = true
	if popup_body.get_child_count() > 1:
		(popup_body.get_child(1) as Control).grab_focus()


func _local_device_name(device: String) -> String:
	if device.begins_with("pad"):
		var pads := Input.get_connected_joypads()
		var index: int = pads.find(int(device.split(":")[1]))
		return "Controller %d" % (index + 1) if index >= 0 else "Controller"
	return "Keyboard"


func _show_online() -> void:
	_back_handler = _show_multiplayer
	popup_title.text = "ONLINE"
	_clear_popup_body()

	var name_label := _label("YOUR NAME", 16, Color("#cfe9ff"))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup_body.add_child(name_label)
	var name_edit := _name_field(online_name, func(value: String) -> void:
		online_name = value)
	popup_body.add_child(name_edit)

	var create := _button("CREATE ROOM", Color("#27496f"), Color.WHITE)
	create.pressed.connect(_online_create)
	popup_body.add_child(create)

	var code_label := _label("HOST ADDRESS", 16, Color("#cfe9ff"))
	code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup_body.add_child(code_label)
	var code_edit := LineEdit.new()
	code_edit.placeholder_text = "e.g. 192.168.0.12"
	code_edit.max_length = 32
	code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_edit.custom_minimum_size = Vector2(320, 40)
	code_edit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	code_edit.add_theme_font_override("font", UI_FONT)
	code_edit.add_theme_font_size_override("font_size", 20)
	popup_body.add_child(code_edit)

	var join := _button("JOIN ROOM", Color("#27496f"), Color.WHITE)
	join.pressed.connect(func() -> void: _online_join(code_edit.text))
	popup_body.add_child(join)

	var note := _label("Create a room and share your address,\nor join a friend on the same network.", 15, Color("#9fc4e8"))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup_body.add_child(note)
	popup.visible = true
	create.grab_focus()


func _online_message(title: String, body: String) -> void:
	popup_title.text = title
	_clear_popup_body()
	var line := _label(body, 18, Color("#e6f3ff"))
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size.x = 460
	popup_body.add_child(line)
	_back_handler = _show_multiplayer
	popup.visible = true
	back_button.grab_focus()


func _online_create() -> void:
	var network := get_node_or_null("/root/Network")
	if network == null:
		_online_message("CREATE ROOM", "Networking is unavailable.")
		return
	network.local_name = _clean_name(online_name)
	if not network.host():
		_online_message("CREATE ROOM", "Could not create the room.\nThe port may already be in use.")
		return
	popup_title.text = "ROOM CREATED"
	_clear_popup_body()
	popup_body.add_child(_label("Share this address with your friend:", 16, Color("#cfe9ff")))
	var address := _label(network.get_local_address(), 30, Color("#8fe0ff"))
	address.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup_body.add_child(address)
	popup_body.add_child(_label("They pick JOIN ROOM and type it in.\n(Same Wi-Fi / LAN works best.)", 15, Color("#9fc4e8")))
	var start := _button("START GAME", Color("#ffd451"), Color("#493600"))
	start.pressed.connect(_online_start_host)
	popup_body.add_child(start)
	var cancel := _button("CLOSE ROOM", Color("#315784"), Color.WHITE)
	cancel.pressed.connect(func() -> void:
		network.close()
		_show_online())
	popup_body.add_child(cancel)
	_back_handler = func() -> void:
		network.close()
		_show_online()
	popup.visible = true
	start.grab_focus()


func _online_start_host() -> void:
	var network := get_node_or_null("/root/Network")
	if network:
		# Tell the host's own client list (and any later joiner) to load level 1.
		network.start_game(1)
	get_tree().set_meta("online", true)
	get_tree().set_meta("local_coop", false)
	get_tree().set_meta("level_number", 1)
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _online_join(code: String) -> void:
	var network := get_node_or_null("/root/Network")
	if network == null:
		_online_message("JOIN ROOM", "Networking is unavailable.")
		return
	var address := code.strip_edges()
	if address.is_empty():
		_online_message("JOIN ROOM", "Enter the host's address first.")
		return
	network.local_name = _clean_name(online_name)
	if not network.join(address):
		_online_message("JOIN ROOM", "Could not start the connection to \"%s\"." % address)
		return
	_online_message("JOINING ROOM", "Connecting to %s ...\nThe host will start the level." % address)


func _start_local(level_number: int) -> void:
	get_tree().set_meta("local_coop", true)
	get_tree().set_meta("local_p1_device", p1_device)
	get_tree().set_meta("local_p2_device", p2_device)
	get_tree().set_meta("local_p1_name", _clean_name(p1_name, "Player 1"))
	get_tree().set_meta("local_p2_name", _clean_name(p2_name, "Player 2"))
	_begin_level(level_number)


func _start_level(level_number: int) -> void:
	get_tree().set_meta("local_coop", false)
	_begin_level(level_number)


func _begin_level(level_number: int) -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().set_meta("level_number", level_number)
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _close_popup() -> void:
	_back_handler = Callable()
	var tween = create_tween()
	tween.tween_property(popup, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func(): popup.visible = false)
	default_button.grab_focus()

func _clear_popup_body() -> void:
	for child in popup_body.get_children():
		popup_body.remove_child(child)
		child.queue_free()

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UI_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(text: String, color: Color, text_color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(390, 44)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_override("font", UI_FONT)
	button.add_theme_font_size_override("font_size", 21)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", Color.WHITE)

	var normal = StyleBoxFlat.new()
	normal.bg_color = color
	normal.border_color = color.lightened(0.14)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(16)
	normal.content_margin_left = 22
	normal.content_margin_right = 22
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10

	var hover = normal.duplicate()
	hover.bg_color = color.lightened(0.13)
	hover.border_color = Color("#ffe078")

	var pressed = normal.duplicate()
	pressed.bg_color = color.darkened(0.15)
	pressed.border_color = Color("#ffe078")

	var focus = normal.duplicate()
	focus.border_color = Color("#a6f4ff")

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", focus)
	return button

func _multiplayer_button() -> Button:
	var button := Button.new()
	button.text = "MULTIPLAYER LOBBY"
	button.icon = preload("res://assets/generated/icon_people.png")
	button.expand_icon = true
	button.custom_minimum_size = Vector2(390, 48)
	button.add_theme_font_override("font", UI_FONT)
	button.add_theme_font_size_override("font_size", 21)
	button.add_theme_constant_override("icon_max_width", 28)
	button.add_theme_constant_override("h_separation", 14)
	button.add_theme_color_override("font_color", Color("#dff3ff"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _glow_style(Color("#101d38"), Color("#3fb6ff")))
	button.add_theme_stylebox_override("hover", _glow_style(Color("#182c50"), Color("#8fe0ff")))
	button.add_theme_stylebox_override("pressed", _glow_style(Color("#0b1428"), Color("#8fe0ff")))
	button.add_theme_stylebox_override("focus", _glow_style(Color("#101d38"), Color("#c9f0ff")))
	button.pressed.connect(_show_multiplayer)
	return button


func _glow_style(color: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(3)
	style.set_corner_radius_all(16)
	style.shadow_color = Color(border.r, border.g, border.b, 0.5)
	style.shadow_size = 8
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	return style


func _panel_style(color: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	return style
