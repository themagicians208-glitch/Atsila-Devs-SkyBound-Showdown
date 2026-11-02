extends Control

## SkyBound Showdown — lobby (rebuilt fresh).
##
## The menu shown right after the loading screen. A layered, animated sky
## background (drifting clouds, bobbing islands, a flowing waterfall and
## flickering lightning) sits behind clean, rounded pastel menus.
##
## Screens: Main, Levels, Multiplayer, Local Co-op, Online Room, Character
## Select, Options, How To Play. Every screen shares one header + pill style.

const FONT := preload("res://fonts/lilita_one_regular.ttf")
const ROSTER := preload("res://scripts/roster.gd")
const BLUR_SHADER := preload("res://shaders/lobby_blur.gdshader")
const WATERFALL_SHADER := preload("res://shaders/lobby_waterfall.gdshader")

const LEVEL_NAMES := [
	"Forgotten Island", "The Whispering Woods", "Frozen Skies",
	"Rising Ruins", "Malakar's Fortress", "Gimmick Gauntlet",
]

# Palette (all outlines and text use ink navy).
const INK := Color("#2b1d5c")
const BUTTER := Color("#ffe58a")
const CREAM := Color("#fff8e6")
const MINT := Color("#bff0c8")
const PEACH := Color("#ffd2b8")
const SKY := Color("#bfe3ff")
const PINK := Color("#ffc6dc")
const LAVENDER := Color("#e6dcff")

const TIPS := ["Ready for an adventure?", "Bring your friends!", "The sky is waiting!", "Pick your hero!"]

const BTN := Vector2(360, 54)
const ROW_SEP := 12

var world: Control
var blur: ColorRect
var screen_layer: Control
var notice: Label

var _clouds: Array = []      # {node, x0, speed}
var _bobbers: Array = []     # {node, y0, amp, speed, phase}
var _lightning: TextureRect
var _tip_label: Label

var _t := 0.0
var _screen := "main"
var _tip_index := 0
var _tip_timer := 0.0

var _p1_character := ""
var _p2_character := ""
var _online_name := "Player"

var _flash_timer := 3.0
var _flash := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.play_music("res://sounds/pixelland.mp3")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_world()
	_build_blur()
	_build_notice()
	screen_layer = Control.new()
	screen_layer.name = "Screens"
	screen_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen_layer)
	show_main()

	var network := get_node_or_null("/root/Network")
	if network and not network.connection_failed.is_connected(_on_network_failed):
		network.connection_failed.connect(_on_network_failed)


# --------------------------------------------------------------------- world --

func _build_world() -> void:
	world = Control.new()
	world.name = "World"
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(world)

	var sky := _tex(world, "res://sprites/skybox.png", Rect2(0, 0, 1280, 720))
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0.035, 0.075, 0.17, 0.38)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(shade)


func _tex(parent: Node, path: String, rect: Rect2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = _load_texture(path)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.position = rect.position
	t.size = rect.size
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	return t


## Load an image, importing it on the fly when the editor has not imported the
## freshly-generated PNG yet.
func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	var img := Image.load_from_file(path)
	return ImageTexture.create_from_image(img) if img != null else null


func _add_cloud(rect: Rect2, speed: float) -> void:
	var c := _tex(world, "res://assets/generated/lobby_cloud.png", rect)
	_clouds.append({"node": c, "x0": rect.position.x, "speed": speed})


func _bobber(node: Control, amp: float, speed: float) -> void:
	_bobbers.append({"node": node, "y0": node.position.y, "amp": amp, "speed": speed, "phase": randf() * TAU})


func _build_blur() -> void:
	blur = ColorRect.new()
	blur.name = "Blur"
	blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = BLUR_SHADER
	m.set_shader_parameter("radius", 2.5)
	m.set_shader_parameter("darkness", 0.22)
	blur.material = m
	blur.visible = false
	add_child(blur)


func _build_notice() -> void:
	notice = _label("", 18, BUTTER)
	notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	notice.offset_left = -420
	notice.offset_right = 420
	notice.offset_top = -46
	notice.offset_bottom = -14
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.add_theme_color_override("font_outline_color", INK)
	notice.add_theme_constant_override("outline_size", 5)
	notice.visible = false
	add_child(notice)


func _show_notice(text: String) -> void:
	notice.text = text
	notice.modulate.a = 1.0
	notice.visible = true
	var tw := create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(notice, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func() -> void: notice.visible = false)


func _on_network_failed() -> void:
	_show_notice("Could not connect. Check the address and that the host is ready.")


# -------------------------------------------------------------------- anim --

func _process(delta: float) -> void:
	_t += delta

	for b in _bobbers:
		b["node"].position.y = float(b["y0"]) + sin(_t * float(b["speed"]) + float(b["phase"])) * float(b["amp"])

	for c in _clouds:
		var x: float = float(c["x0"]) + _t * float(c["speed"])
		x = fposmod(x + 300.0, 1880.0) - 300.0
		(c["node"] as Control).position.x = x

	_flash_timer -= delta
	if _flash_timer <= 0.0:
		_flash_timer = randf_range(2.5, 5.5)
		_flash = 0.35
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		if _lightning:
			_lightning.modulate.a = clampf(_flash / 0.35, 0.0, 1.0)

	if _tip_label != null:
		_tip_timer += delta
		if _tip_timer >= 3.0:
			_tip_timer = 0.0
			_tip_index = (_tip_index + 1) % TIPS.size()
		_tip_label.text = TIPS[_tip_index]


# ------------------------------------------------------------------ screens --

func _clear() -> void:
	for child in screen_layer.get_children():
		screen_layer.remove_child(child)
		child.queue_free()
	_tip_label = null


func _set_screen(name: String) -> void:
	_screen = name


## Centered column of menu buttons under the title.
func _menu_column(top: float, width: float = BTN.x) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	box.offset_left = -width * 0.5
	box.offset_right = width * 0.5
	box.offset_top = top
	box.offset_bottom = top + 560.0
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", ROW_SEP)
	screen_layer.add_child(box)
	return box


func _header(title: String, subtitle: String, on_back: Callable) -> void:
	var t := _label(title, 50, Color.WHITE)
	t.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	t.offset_left = -500
	t.offset_right = 500
	t.offset_top = 40
	t.offset_bottom = 104
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_outline_color", INK)
	t.add_theme_constant_override("outline_size", 12)
	t.add_theme_color_override("font_shadow_color", Color(0.10, 0.06, 0.22, 0.8))
	t.add_theme_constant_override("shadow_offset_x", 0)
	t.add_theme_constant_override("shadow_offset_y", 6)
	screen_layer.add_child(t)

	if not subtitle.is_empty():
		var s := _label(subtitle, 20, SKY)
		s.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		s.offset_left = -500
		s.offset_right = 500
		s.offset_top = 104
		s.offset_bottom = 132
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.add_theme_color_override("font_outline_color", INK)
		s.add_theme_constant_override("outline_size", 5)
		screen_layer.add_child(s)

	if on_back.is_valid():
		var back := _pill_button("BACK", LAVENDER, INK, Vector2(170, 50))
		back.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		back.offset_left = 32
		back.offset_top = 32
		back.offset_right = 202
		back.offset_bottom = 82
		back.pressed.connect(on_back)
		screen_layer.add_child(back)


# ------------------------------------------------------------- main menu -----

func show_main() -> void:
	_clear()
	blur.visible = false
	_set_screen("main")

	var logo := _label("SkyBound Showdown", 60, BUTTER)
	logo.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	logo.offset_left = -640
	logo.offset_right = 640
	logo.offset_top = 26
	logo.offset_bottom = 100
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.add_theme_color_override("font_outline_color", INK)
	logo.add_theme_constant_override("outline_size", 14)
	logo.add_theme_color_override("font_shadow_color", Color(0.10, 0.06, 0.22, 0.85))
	logo.add_theme_constant_override("shadow_offset_x", 0)
	logo.add_theme_constant_override("shadow_offset_y", 7)
	screen_layer.add_child(logo)

	var sub := _label("THE FALL OF THE SKY KINGDOM", 18, SKY)
	sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	sub.offset_left = -640
	sub.offset_right = 640
	sub.offset_top = 100
	sub.offset_bottom = 126
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_outline_color", INK)
	sub.add_theme_constant_override("outline_size", 5)
	screen_layer.add_child(sub)

	# Cream card holding the menu, so the art behind never fights the text.
	var panel_rect := Rect2(420, 200, 440, 470)
	var panel := Panel.new()
	panel.position = panel_rect.position
	panel.size = panel_rect.size
	panel.add_theme_stylebox_override("panel", _panel_style())
	screen_layer.add_child(panel)

	_tip_label = _label(TIPS[_tip_index], 20, INK)
	_tip_label.position = Vector2(panel_rect.position.x + 20, panel_rect.position.y + 14)
	_tip_label.size = Vector2(panel_rect.size.x - 40, 30)
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	screen_layer.add_child(_tip_label)

	var box := VBoxContainer.new()
	box.position = Vector2(panel_rect.position.x + 40, panel_rect.position.y + 54)
	box.size = Vector2(panel_rect.size.x - 80, panel_rect.size.y - 74)
	box.add_theme_constant_override("separation", ROW_SEP)
	screen_layer.add_child(box)

	_menu(box, "PLAY", BUTTER, func() -> void: _pick_character(1, func() -> void: _begin_level(1, false)))
	_menu(box, "LEVELS", SKY, show_levels)
	_menu(box, "MULTIPLAYER", MINT, show_multiplayer)
	_menu(box, "CHARACTERS", PINK, func() -> void: _pick_character(1, show_main))
	_menu(box, "OPTIONS", LAVENDER, show_options)
	_menu(box, "HOW TO PLAY", CREAM, show_howto)

	(box.get_child(0) as Control).grab_focus()


func _menu(box: VBoxContainer, text: String, color: Color, cb: Callable) -> Button:
	var b := _pill_button(text, color, INK)
	b.pressed.connect(cb)
	box.add_child(b)
	return b


# ----------------------------------------------------------- multiplayer -----

func show_multiplayer() -> void:
	_clear()
	blur.visible = true
	_set_screen("multiplayer")
	_header("MULTIPLAYER", "Adventure together", show_main)

	var box := _menu_column(220)
	_menu(box, "LOCAL SPLIT SCREEN", MINT, show_local)
	_menu(box, "ONLINE ROOM", SKY, show_online)
	_menu(box, "BACK", LAVENDER, show_main)
	(box.get_child(0) as Control).grab_focus()


# --------------------------------------------------------------- levels ------

func show_levels() -> void:
	_clear()
	blur.visible = true
	_set_screen("levels")
	_header("LEVELS", "Pick a course", show_main)

	var box := _menu_column(200)
	for i in LEVEL_NAMES.size():
		var level_number := i + 1
		var b := _menu(box, "%d  •  %s" % [level_number, LEVEL_NAMES[i].to_upper()], _level_color(i),
			func() -> void: _pick_character(1, func() -> void: _begin_level(level_number, false)))
		b.add_theme_font_size_override("font_size", 22)
	_menu(box, "BACK", LAVENDER, show_main)
	(box.get_child(0) as Control).grab_focus()


func _level_color(i: int) -> Color:
	return [MINT, PEACH, SKY, LAVENDER, PINK, BUTTER][i % 6]


# ---------------------------------------------------------------- local ------

func show_local() -> void:
	_clear()
	blur.visible = true
	_set_screen("local")
	_header("LOCAL SPLIT SCREEN", "Two players, one screen", show_multiplayer)

	var box := _menu_column(200)
	for i in LEVEL_NAMES.size():
		var level_number := i + 1
		var b := _menu(box, "%d  •  %s" % [level_number, LEVEL_NAMES[i].to_upper()], _level_color(i),
			func() -> void: _begin_level(level_number, true))
		b.add_theme_font_size_override("font_size", 22)
	_menu(box, "BACK", LAVENDER, show_multiplayer)
	(box.get_child(0) as Control).grab_focus()


# ---------------------------------------------------------- character pick ---

func _pick_character(slots: int, on_done: Callable) -> void:
	_clear()
	blur.visible = true
	_set_screen("characters")
	if _p1_character.is_empty() or not ROSTER.has(_p1_character):
		_p1_character = ROSTER.default_id()
	get_tree().set_meta("p1_character", _p1_character)

	_header("PICK A CHARACTER", "Who do you want to play as?" if slots < 2 else "One for each player", show_main)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	grid.offset_left = -430
	grid.offset_right = 430
	grid.offset_top = 200
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	screen_layer.add_child(grid)

	for i in ROSTER.count():
		var id := ROSTER.id_at(i)
		var picked := id == _p1_character
		var b := _pill_button(id, BUTTER if picked else LAVENDER, INK, Vector2(280, 54))
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(func() -> void:
			_p1_character = id
			get_tree().set_meta("p1_character", id)
			_pick_character(slots, on_done))
		grid.add_child(b)

	var cont := _pill_button("CONTINUE", MINT, INK, Vector2(360, 58))
	cont.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	cont.offset_left = -180
	cont.offset_right = 180
	cont.offset_top = 560
	cont.offset_bottom = 618
	cont.pressed.connect(on_done)
	screen_layer.add_child(cont)
	cont.grab_focus()


# -------------------------------------------------------------- options ------

func show_options() -> void:
	_clear()
	blur.visible = true
	_set_screen("options")
	_header("OPTIONS", "Tune the adventure", show_main)

	var settings := get_node_or_null("/root/Settings")
	var box := _menu_column(200)
	box.add_theme_constant_override("separation", 10)
	if settings:
		box.add_child(_slider_row("MOUSE SENSITIVITY", 0.05, 0.6, 0.01, float(settings.mouse_sensitivity),
			func(v: float) -> String: return "%.2f" % v,
			func(v: float) -> void: settings.set_mouse_sensitivity(v)))
		box.add_child(_slider_row("MASTER VOLUME", 0.0, 1.0, 0.01, float(settings.master_volume),
			func(v: float) -> String: return "%d%%" % roundi(v * 100.0),
			func(v: float) -> void: settings.set_master_volume(v)))
		box.add_child(_graphics_row(settings))

	_menu(box, "HOW TO PLAY", SKY, show_howto)
	_menu(box, "BACK", LAVENDER, show_main)
	(box.get_child(box.get_child_count() - 1) as Control).grab_focus()


func show_howto() -> void:
	_clear()
	blur.visible = true
	_set_screen("howto")
	_header("HOW TO PLAY", "", show_main)

	var lines := [
		"WASD / LEFT STICK   Move",
		"MOUSE / RIGHT STICK   Look around",
		"CLICK / SPACE / A   Jump",
		"SHIFT / Q   Dash  &  shift dimensions",
		"F / Y   Slow time",
		"E / X   Interact",
	]
	var box := _menu_column(220)
	box.add_theme_constant_override("separation", 8)
	for line in lines:
		var l := _label(line, 22, Color.WHITE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_outline_color", INK)
		l.add_theme_constant_override("outline_size", 5)
		box.add_child(l)
	_menu(box, "BACK", LAVENDER, show_main)
	(box.get_child(box.get_child_count() - 1) as Control).grab_focus()


func _slider_row(caption: String, vmin: float, vmax: float, step: float, value: float, fmt: Callable, on_change: Callable) -> VBoxContainer:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var l := _label("%s   %s" % [caption, fmt.call(value)], 20, Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", 4)
	row.add_child(l)
	var slider := HSlider.new()
	slider.min_value = vmin
	slider.max_value = vmax
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(440, 24)
	slider.value_changed.connect(func(v: float) -> void:
		l.text = "%s   %s" % [caption, fmt.call(v)]
		on_change.call(v))
	row.add_child(slider)
	return row


func _graphics_row(settings: Node) -> VBoxContainer:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var l := _label("GRAPHICS QUALITY", 20, Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", 4)
	row.add_child(l)
	var options := OptionButton.new()
	options.custom_minimum_size = Vector2(440, 40)
	options.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	options.add_theme_font_override("font", FONT)
	options.add_theme_font_size_override("font_size", 20)
	options.add_item("LOW", 0)
	options.add_item("MEDIUM", 1)
	options.add_item("HIGH", 2)
	options.select(int(settings.graphics_quality))
	options.item_selected.connect(func(index: int) -> void: settings.set_graphics_quality(index))
	row.add_child(options)
	return row


# --------------------------------------------------------------- online ------

func show_online() -> void:
	_clear()
	blur.visible = true
	_set_screen("online")
	_header("ONLINE ROOM", "Create or join a room", show_multiplayer)

	var box := _menu_column(200)
	box.add_theme_constant_override("separation", 12)

	box.add_child(_caption("YOUR NAME"))
	var name_edit := _line_field(_online_name, "name")
	name_edit.text_changed.connect(func(v: String) -> void: _online_name = v)
	box.add_child(name_edit)

	var create := _menu(box, "CREATE ROOM", MINT, _online_create)

	box.add_child(_caption("HOST ADDRESS"))
	var code_edit := _line_field("", "e.g. 192.168.0.12")
	box.add_child(code_edit)

	_menu(box, "JOIN ROOM", SKY, func() -> void: _online_join(code_edit.text))
	_menu(box, "BACK", LAVENDER, show_multiplayer)
	create.grab_focus()


func _caption(text: String) -> Label:
	var l := _label(text, 18, Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", 4)
	return l


func _online_create() -> void:
	var network := get_node_or_null("/root/Network")
	if network == null:
		_show_notice("Networking is unavailable.")
		return
	network.local_name = _clean_name(_online_name)
	if not network.host():
		_show_notice("Could not create the room. The port may be in use.")
		return
	_clear()
	blur.visible = true
	_set_screen("online")
	_header("ROOM CREATED", "Share this address with a friend", show_online)
	var box := _menu_column(230)
	var addr := _label(network.get_local_address(), 34, SKY)
	addr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	addr.add_theme_color_override("font_outline_color", INK)
	addr.add_theme_constant_override("outline_size", 6)
	box.add_child(addr)
	var start := _menu(box, "START GAME", BUTTER, _start_online)
	_menu(box, "CLOSE ROOM", LAVENDER, func() -> void:
		network.close()
		show_online())
	start.grab_focus()


func _online_join(address: String) -> void:
	var network := get_node_or_null("/root/Network")
	if network == null:
		_show_notice("Networking is unavailable.")
		return
	var addr := address.strip_edges()
	if addr.is_empty():
		_show_notice("Enter the host's address first.")
		return
	network.local_name = _clean_name(_online_name)
	if not network.join(addr):
		_show_notice("Could not start the connection to \"%s\"." % addr)
		return
	_pick_character(1, func() -> void:
		var net := get_node_or_null("/root/Network")
		if net:
			net.local_character = _p1_character
			net.announce_profile()
		_show_notice("Connected. Waiting for the host to start."))


func _start_online() -> void:
	var network := get_node_or_null("/root/Network")
	get_tree().set_meta("online", true)
	get_tree().set_meta("local_coop", false)
	get_tree().set_meta("level_number", 1)
	get_tree().set_meta("p1_character", _p1_character)
	if network:
		network.local_character = _p1_character
		network.start_game(1)
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://scenes/main.tscn")


# --------------------------------------------------------------- launch ------

func _begin_level(level_number: int, local_coop: bool) -> void:
	get_tree().set_meta("online", false)
	get_tree().set_meta("local_coop", local_coop)
	if local_coop:
		get_tree().set_meta("local_p1_device", "keyboard")
		get_tree().set_meta("local_p2_device", "keyboard")
		get_tree().set_meta("local_p1_name", "Player 1")
		get_tree().set_meta("local_p2_name", "Player 2")
	if _p1_character.is_empty():
		_p1_character = ROSTER.default_id()
	get_tree().set_meta("p1_character", _p1_character)
	get_tree().set_meta("p2_character", _p2_character if not _p2_character.is_empty() else ROSTER.default_id())
	get_tree().set_meta("level_number", level_number)
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://scenes/main.tscn")


# ---------------------------------------------------------------- widgets ----

func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(CREAM.r, CREAM.g, CREAM.b, 0.94)
	s.border_color = INK
	s.set_border_width_all(5)
	s.set_corner_radius_all(34)
	s.shadow_color = Color(0.17, 0.11, 0.36, 0.45)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 8)
	return s


func _pill_button(text: String, color: Color, text_color: Color, size: Vector2 = BTN) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_override("font", FONT)
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_color_override("font_color", text_color)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_focus_color", text_color)

	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	normal.border_color = INK
	normal.set_border_width_all(4)
	normal.set_corner_radius_all(27)
	normal.shadow_color = Color(0.17, 0.11, 0.36, 0.45)
	normal.shadow_size = 8
	normal.shadow_offset = Vector2(0, 7)
	normal.content_margin_left = 28
	normal.content_margin_right = 28
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10

	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = color.lightened(0.12)
	hover.border_color = BUTTER

	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = color.darkened(0.12)
	pressed.shadow_size = 3
	pressed.shadow_offset = Vector2(0, 3)

	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", hover)
	return b


func _line_field(current: String, placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = current
	e.placeholder_text = placeholder
	e.max_length = 24
	e.alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.custom_minimum_size = Vector2(380, 46)
	e.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	e.add_theme_font_override("font", FONT)
	e.add_theme_font_size_override("font_size", 22)
	return e


func _clean_name(value: String) -> String:
	var s := value.strip_edges()
	return s if not s.is_empty() else "Player"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _screen != "main":
		show_main()