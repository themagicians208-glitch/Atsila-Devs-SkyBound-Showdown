extends Control

## SkyBound Showdown — lobby.
##
## Replaces the old home menu with three Animal-Crossing-style screens that
## appear right after the loading screen:
##   1. Mode Select  — two pillowy cards (Single Player / Multiplayer)
##   2. Multiplayer  — pill buttons (blurred background)
##   3. Single Player— pill buttons (blurred background)
## plus the deeper menus (level select, character select, options, how to play,
## online room, local co-op), all in the same rounded pastel style.
##
## The background is layered art (sky, drifting clouds, bobbing islands, a
## flowing waterfall and flickering lightning) animated behind everything.

const FONT := preload("res://fonts/lilita_one_regular.ttf")
const ROSTER := preload("res://scripts/roster.gd")
const CARD_SHADER := preload("res://shaders/lobby_card.gdshader")
const BLUR_SHADER := preload("res://shaders/lobby_blur.gdshader")
const WATERFALL_SHADER := preload("res://shaders/lobby_waterfall.gdshader")

const LEVEL_NAMES := [
	"Forgotten Island", "The Whispering Woods", "Frozen Skies",
	"Rising Ruins", "Malakar's Fortress",
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

const BUBBLE_LINES := ["Ready for an adventure?", "Going solo?", "Bring your friends!", "The sky is waiting!"]

var world: Control
var blur: ColorRect
var screen_layer: Control
var bubble: Control
var bubble_label: Label
var notice: Label

var _cards: Array = []       # {node, base: Vector2, phase, hover, pressed, side}
var _clouds: Array = []      # {node, x0, speed}
var _bobbers: Array = []     # {node, y0, amp, speed, phase}
var _lightning: TextureRect

var _t := 0.0
var _bubble_index := 0
var _bubble_override := ""
var _bubble_timer := 0.0

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
	_build_logo()
	_build_blur()
	_build_notice()
	screen_layer = Control.new()
	screen_layer.name = "Screens"
	screen_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen_layer)
	_show_mode_select()

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

	var sky := _tex(world, "res://assets/generated/lobby_bg_sky.png", Rect2(0, 0, 1280, 720))
	sky.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE

	# Drifting clouds (x wraps around the screen).
	_add_cloud(Rect2(150, 110, 240, 120), 14.0)
	_add_cloud(Rect2(820, 80, 320, 160), -10.0)
	_add_cloud(Rect2(520, 230, 280, 140), 9.0)
	_add_cloud(Rect2(1040, 300, 220, 110), -12.0)

	# Center small islands.
	_bobber(_tex(world, "res://assets/generated/lobby_islands_center.png", Rect2(400, 350, 480, 240)), 5.0, 1.1)
	# Left lush island.
	_bobber(_tex(world, "res://assets/generated/lobby_island_tree.png", Rect2(10, 150, 440, 440)), 8.0, 0.9)
	# Waterfall under the left island's right lip (scrolls so the streaks flow).
	_lightning = null
	var fall := _tex(world, "res://assets/generated/lobby_waterfall.png", Rect2(360, 300, 150, 420))
	fall.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var fm := ShaderMaterial.new()
	fm.shader = WATERFALL_SHADER
	fall.material = fm
	# Right evil island.
	_bobber(_tex(world, "res://assets/generated/lobby_island_evil.png", Rect2(820, 130, 450, 450)), 6.0, 1.3)
	# Flickering lightning over the evil fortress.
	_lightning = _tex(world, "res://assets/generated/lobby_lightning.png", Rect2(1010, 150, 70, 150))
	_lightning.modulate.a = 0.0


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


func _build_logo() -> void:
	var top := _label("SkyBound Showdown", 62, BUTTER)
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.offset_left = -640
	top.offset_right = 640
	top.offset_top = 14
	top.offset_bottom = 96
	top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_theme_color_override("font_outline_color", INK)
	top.add_theme_constant_override("outline_size", 14)
	top.add_theme_color_override("font_shadow_color", Color(0.10, 0.06, 0.22, 0.85))
	top.add_theme_constant_override("shadow_offset_x", 0)
	top.add_theme_constant_override("shadow_offset_y", 7)
	add_child(top)

	var sub := _label("THE FALL OF THE SKY KINGDOM", 20, SKY)
	sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	sub.offset_left = -640
	sub.offset_right = 640
	sub.offset_top = 96
	sub.offset_bottom = 124
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_outline_color", INK)
	sub.add_theme_constant_override("outline_size", 5)
	sub.add_theme_color_override("font_shadow_color", Color(0.4, 0.2, 0.6, 0.8))
	add_child(sub)


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
		# Wrap within a wide band around the screen.
		x = fposmod(x + 300.0, 1880.0) - 300.0
		(c["node"] as Control).position.x = x

	# Lightning flicker.
	_flash_timer -= delta
	if _flash_timer <= 0.0:
		_flash_timer = randf_range(2.5, 5.5)
		_flash = 0.35
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		if _lightning:
			_lightning.modulate.a = clampf(_flash / 0.35, 0.0, 1.0)

	# Mode-select card float / hover / press.
	for c in _cards:
		var node: Control = c["node"]
		var lift := -10.0 if bool(c["hover"]) else 0.0
		var grow := 1.05 if bool(c["hover"]) else 1.0
		var sx := grow
		var sy := grow
		if bool(c["pressed"]):
			sx = 1.10
			sy = 0.90
		var tilt := 0.0
		if bool(c["hover"]):
			tilt = deg_to_rad(-2.0) if c["side"] == "left" else deg_to_rad(2.0)
		node.pivot_offset = node.size * 0.5
		node.position = Vector2(float(c["base"].x), float(c["base"].y) + lift + sin(_t * 1.4 + float(c["phase"])) * 6.0)
		node.scale = node.scale.lerp(Vector2(sx, sy), delta * 12.0)
		node.rotation = lerp_angle(node.rotation, tilt, delta * 12.0)

	# Speech bubble cycle.
	if bubble != null and bubble.visible:
		_bubble_timer += delta
		if _bubble_timer >= 3.0:
			_bubble_timer = 0.0
			if _bubble_override.is_empty():
				_bubble_index = (_bubble_index + 1) % BUBBLE_LINES.size()
		if not _bubble_override.is_empty():
			bubble_label.text = _bubble_override
		else:
			bubble_label.text = BUBBLE_LINES[_bubble_index]


# ------------------------------------------------------------------ screens --

func _clear_screen() -> void:
	for child in screen_layer.get_children():
		screen_layer.remove_child(child)
		child.queue_free()
	_cards.clear()
	bubble = null
	bubble_label = null


func _screen_button_parent(top: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	box.offset_left = -240
	box.offset_right = 240
	box.offset_top = top
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 20)
	screen_layer.add_child(box)
	return box


func _screen_title(text: String, subtitle: String) -> void:
	var t := _label(text, 46, Color.WHITE)
	t.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	t.offset_left = -500
	t.offset_right = 500
	t.offset_top = 150
	t.offset_bottom = 210
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_outline_color", INK)
	t.add_theme_constant_override("outline_size", 12)
	t.add_theme_color_override("font_shadow_color", Color(0.10, 0.06, 0.22, 0.8))
	t.add_theme_constant_override("shadow_offset_x", 0)
	t.add_theme_constant_override("shadow_offset_y", 6)
	screen_layer.add_child(t)
	if not subtitle.is_empty():
		var s := _label(subtitle, 22, SKY)
		s.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		s.offset_left = -500
		s.offset_right = 500
		s.offset_top = 210
		s.offset_bottom = 244
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.add_theme_color_override("font_outline_color", INK)
		s.add_theme_constant_override("outline_size", 5)
		screen_layer.add_child(s)


# ------------------------------------------------------------- screen 1 -----

func _show_mode_select() -> void:
	_clear_screen()
	blur.visible = false

	_build_bubble()

	var card_size := Vector2(340, 420)
	var left := _make_card(
		"SINGLE PLAYER", "Your own adventure", "res://assets/generated/lobby_icon_single.png",
		CREAM, MINT, Vector2(235, 250), card_size)
	left.pressed.connect(_show_single)
	_cards.append(_card_state(left, Vector2(235, 250), "left"))

	var right := _make_card(
		"MULTIPLAYER", "Adventure together", "res://assets/generated/lobby_icon_coop.png",
		CREAM, PEACH, Vector2(705, 250), card_size)
	right.pressed.connect(_show_multiplayer)
	_cards.append(_card_state(right, Vector2(705, 250), "right"))

	left.grab_focus()


func _card_state(node: Button, base: Vector2, side: String) -> Dictionary:
	return {"node": node, "base": base, "side": side, "phase": randf() * TAU, "hover": false, "pressed": false}


func _build_bubble() -> void:
	bubble = Control.new()
	bubble.position = Vector2(430, 138)
	bubble.size = Vector2(420, 96)
	screen_layer.add_child(bubble)

	var tail_navy := Polygon2D.new()
	tail_navy.polygon = PackedVector2Array([Vector2(190, 78), Vector2(232, 78), Vector2(211, 108)])
	tail_navy.color = INK
	bubble.add_child(tail_navy)
	var tail := Polygon2D.new()
	tail.polygon = PackedVector2Array([Vector2(196, 74), Vector2(228, 74), Vector2(211, 100)])
	tail.color = CREAM
	bubble.add_child(tail)

	var panel := Panel.new()
	panel.position = Vector2.ZERO
	panel.size = Vector2(420, 82)
	panel.add_theme_stylebox_override("panel", _bubble_style())
	bubble.add_child(panel)

	bubble_label = _label(BUBBLE_LINES[0], 24, INK)
	bubble_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bubble_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bubble.add_child(bubble_label)


func _bubble_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = CREAM
	s.border_color = INK
	s.set_border_width_all(4)
	s.set_corner_radius_all(26)
	s.shadow_color = Color(0.17, 0.11, 0.36, 0.45)
	s.shadow_size = 8
	s.shadow_offset = Vector2(0, 6)
	return s


func _make_card(title: String, subtitle: String, icon_path: String, top: Color, bottom: Color, pos: Vector2, card_size: Vector2) -> Button:
	var card := Button.new()
	card.flat = true
	card.position = pos
	card.size = card_size
	card.custom_minimum_size = card_size
	card.focus_mode = Control.FOCUS_ALL
	card.pivot_offset = card_size * 0.5
	screen_layer.add_child(card)

	# Thick navy drop shadow.
	var shadow := Panel.new()
	shadow.position = Vector2(2, 10)
	shadow.size = card_size
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color(0.17, 0.11, 0.36, 0.35)
	ss.set_corner_radius_all(36)
	shadow.add_theme_stylebox_override("panel", ss)
	card.add_child(shadow)

	# Pillowy face with gradient + navy border (shader).
	var face := ColorRect.new()
	face.position = Vector2.ZERO
	face.size = card_size
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = CARD_SHADER
	mat.set_shader_parameter("top_color", top)
	mat.set_shader_parameter("bottom_color", bottom)
	mat.set_shader_parameter("border_color", INK)
	mat.set_shader_parameter("radius", 32.0)
	mat.set_shader_parameter("border", 4.0)
	mat.set_shader_parameter("rect_size", card_size)
	mat.set_shader_parameter("glow", 0.0)
	face.material = mat
	card.add_child(face)
	card.set_meta("face_material", mat)

	var icon := TextureRect.new()
	icon.texture = load(icon_path)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2((card_size.x - 150.0) * 0.5, 44)
	icon.size = Vector2(150, 150)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(icon)

	var tl := _label(title, 30, INK)
	tl.position = Vector2(0, card_size.y - 130.0)
	tl.size = Vector2(card_size.x, 40)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(tl)

	var sl := _label(subtitle, 20, Color(INK.r, INK.g, INK.b, 0.8))
	sl.position = Vector2(0, card_size.y - 88.0)
	sl.size = Vector2(card_size.x, 32)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(sl)

	card.mouse_entered.connect(func() -> void: _card_hover(card, true))
	card.mouse_exited.connect(func() -> void: _card_hover(card, false))
	card.focus_entered.connect(func() -> void: _card_hover(card, true))
	card.focus_exited.connect(func() -> void: _card_hover(card, false))
	card.button_down.connect(func() -> void: _card_press(card, true))
	card.button_up.connect(func() -> void: _card_press(card, false))
	return card


func _find_card(node: Control) -> Dictionary:
	for c in _cards:
		if c["node"] == node:
			return c
	return {}


func _card_hover(node: Control, hover: bool) -> void:
	var c := _find_card(node)
	if c.is_empty():
		return
	c["hover"] = hover
	# Bubble reflects the hovered card.
	if hover:
		_bubble_override = "Going solo?" if c["side"] == "left" else "Bring your friends!"
	else:
		_bubble_override = ""
	var mat: ShaderMaterial = node.get_meta("face_material")
	if mat:
		mat.set_shader_parameter("glow", 1.0 if hover else 0.0)


func _card_press(node: Control, pressed: bool) -> void:
	var c := _find_card(node)
	if not c.is_empty():
		c["pressed"] = pressed


# ------------------------------------------------------------- screen 2 -----

func _show_multiplayer() -> void:
	_clear_screen()
	blur.visible = true
	_screen_title("MULTIPLAYER", "Adventure together")

	var box := _screen_button_parent(270)
	var local := _pill_button("LOCAL SPLIT SCREEN", MINT, INK)
	local.pressed.connect(_show_local)
	box.add_child(local)
	var online := _pill_button("ONLINE ROOM", SKY, INK)
	online.pressed.connect(_show_online)
	box.add_child(online)
	var back := _pill_button("BACK", LAVENDER, INK)
	back.pressed.connect(_show_mode_select)
	box.add_child(back)
	local.grab_focus()


# ------------------------------------------------------------- screen 3 -----

func _show_single() -> void:
	_clear_screen()
	blur.visible = true
	_screen_title("SINGLE PLAYER", "Your own adventure")

	var box := _screen_button_parent(270)
	var play := _pill_button("PLAY", BUTTER, INK)
	play.pressed.connect(func() -> void: _show_character_select(1, func() -> void: _begin_level(1, false)))
	box.add_child(play)
	var levels := _pill_button("LEVEL SELECT", MINT, INK)
	levels.pressed.connect(_show_level_select)
	box.add_child(levels)
	var character := _pill_button("CHARACTER", PINK, INK)
	character.pressed.connect(func() -> void: _show_character_select(1, _show_single))
	box.add_child(character)
	var back := _pill_button("BACK", LAVENDER, INK)
	back.pressed.connect(_show_mode_select)
	box.add_child(back)
	play.grab_focus()


func _show_level_select() -> void:
	_clear_screen()
	blur.visible = true
	_screen_title("LEVEL SELECT", "Pick a course")

	var box := _screen_button_parent(260)
	for i in LEVEL_NAMES.size():
		var level_number := i + 1
		var b := _pill_button("%d  •  %s" % [level_number, LEVEL_NAMES[i].to_upper()], _level_color(i), INK)
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(func() -> void: _begin_level(level_number, false))
		box.add_child(b)
	var back := _pill_button("BACK", LAVENDER, INK)
	back.pressed.connect(_show_single)
	box.add_child(back)
	(box.get_child(0) as Control).grab_focus()


func _level_color(i: int) -> Color:
	return [MINT, PEACH, SKY, LAVENDER, PINK, BUTTER][i % 6]


func _show_character_select(slots: int, on_done: Callable) -> void:
	_clear_screen()
	blur.visible = true
	if _p1_character.is_empty() or not ROSTER.has(_p1_character):
		_p1_character = ROSTER.default_id()
	get_tree().set_meta("p1_character", _p1_character)

	_screen_title("PICK A CHARACTER", "Who do you want to play as?" if slots < 2 else "One for each player")

	var grid := GridContainer.new()
	grid.columns = 3
	grid.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	grid.offset_left = -430
	grid.offset_right = 430
	grid.offset_top = 250
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	screen_layer.add_child(grid)

	for i in ROSTER.count():
		var id := ROSTER.id_at(i)
		var picked := id == _p1_character
		var b := _pill_button(id, BUTTER if picked else LAVENDER, INK)
		b.custom_minimum_size = Vector2(280, 54)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(func() -> void:
			_p1_character = id
			get_tree().set_meta("p1_character", id)
			_show_character_select(slots, on_done))
		grid.add_child(b)

	var cont := _pill_button("CONTINUE", MINT, INK)
	cont.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	cont.offset_left = -180
	cont.offset_right = 180
	cont.offset_top = 610
	cont.offset_bottom = 672
	cont.pressed.connect(on_done)
	screen_layer.add_child(cont)
	cont.grab_focus()


# ------------------------------------------------------- options / help -----

func _show_options() -> void:
	_clear_screen()
	blur.visible = true
	_screen_title("OPTIONS", "Tune the adventure")

	var settings := get_node_or_null("/root/Settings")
	var box := _screen_button_parent(250)
	box.add_theme_constant_override("separation", 10)
	if settings:
		box.add_child(_slider_row("MOUSE SENSITIVITY", 0.05, 0.6, 0.01, float(settings.mouse_sensitivity),
			func(v: float) -> String: return "%.2f" % v,
			func(v: float) -> void: settings.set_mouse_sensitivity(v)))
		box.add_child(_slider_row("MASTER VOLUME", 0.0, 1.0, 0.01, float(settings.master_volume),
			func(v: float) -> String: return "%d%%" % roundi(v * 100.0),
			func(v: float) -> void: settings.set_master_volume(v)))
		box.add_child(_graphics_row(settings))

	var help := _pill_button("HOW TO PLAY", SKY, INK)
	help.pressed.connect(_show_how_to_play)
	box.add_child(help)
	var back := _pill_button("BACK", LAVENDER, INK)
	back.pressed.connect(_show_mode_select)
	box.add_child(back)
	(box.get_child(box.get_child_count() - 1) as Control).grab_focus()


func _show_how_to_play() -> void:
	_clear_screen()
	blur.visible = true
	_screen_title("HOW TO PLAY", "")
	var lines := [
		"WASD / LEFT STICK   Move",
		"MOUSE / RIGHT STICK   Look around",
		"CLICK / SPACE / A   Jump",
		"SHIFT / Q   Dash  &  shift dimensions",
		"F / Y   Slow time",
		"E / X   Interact",
	]
	var box := _screen_button_parent(240)
	box.add_theme_constant_override("separation", 8)
	for line in lines:
		var l := _label(line, 22, Color.WHITE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_outline_color", INK)
		l.add_theme_constant_override("outline_size", 5)
		box.add_child(l)
	var back := _pill_button("BACK", LAVENDER, INK)
	back.pressed.connect(_show_options)
	box.add_child(back)
	back.grab_focus()


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


# ------------------------------------------------------------------ online --

func _show_online() -> void:
	_clear_screen()
	blur.visible = true
	_screen_title("ONLINE ROOM", "Create or join a room")

	var box := _screen_button_parent(250)
	box.add_theme_constant_override("separation", 12)

	var name_label := _label("YOUR NAME", 18, Color.WHITE)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_outline_color", INK)
	name_label.add_theme_constant_override("outline_size", 4)
	box.add_child(name_label)
	var name_edit := _line_field(_online_name, "name")
	name_edit.text_changed.connect(func(v: String) -> void: _online_name = v)
	box.add_child(name_edit)

	var create := _pill_button("CREATE ROOM", MINT, INK)
	create.pressed.connect(_online_create)
	box.add_child(create)

	var code_label := _label("HOST ADDRESS", 18, Color.WHITE)
	code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_label.add_theme_color_override("font_outline_color", INK)
	code_label.add_theme_constant_override("outline_size", 4)
	box.add_child(code_label)
	var code_edit := _line_field("", "e.g. 192.168.0.12")
	box.add_child(code_edit)

	var join := _pill_button("JOIN ROOM", SKY, INK)
	join.pressed.connect(func() -> void: _online_join(code_edit.text))
	box.add_child(join)

	var back := _pill_button("BACK", LAVENDER, INK)
	back.pressed.connect(_show_multiplayer)
	box.add_child(back)
	create.grab_focus()


func _online_create() -> void:
	var network := get_node_or_null("/root/Network")
	if network == null:
		_show_notice("Networking is unavailable.")
		return
	network.local_name = _clean_name(_online_name)
	if not network.host():
		_show_notice("Could not create the room. The port may be in use.")
		return
	_clear_screen()
	blur.visible = true
	_screen_title("ROOM CREATED", "Share this address with a friend")
	var box := _screen_button_parent(260)
	var addr := _label(network.get_local_address(), 34, SKY)
	addr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	addr.add_theme_color_override("font_outline_color", INK)
	addr.add_theme_constant_override("outline_size", 6)
	box.add_child(addr)
	var start := _pill_button("START GAME", BUTTER, INK)
	start.pressed.connect(func() -> void: _start_online())
	box.add_child(start)
	var close := _pill_button("CLOSE ROOM", LAVENDER, INK)
	close.pressed.connect(func() -> void:
		network.close()
		_show_online())
	box.add_child(close)
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
	_show_character_select(1, func() -> void:
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


# ------------------------------------------------------------------- local --

func _show_local() -> void:
	_clear_screen()
	blur.visible = true
	_screen_title("LOCAL SPLIT SCREEN", "Two players, one screen")

	var box := _screen_button_parent(260)
	for i in LEVEL_NAMES.size():
		var level_number := i + 1
		var b := _pill_button("%d  •  %s" % [level_number, LEVEL_NAMES[i].to_upper()], _level_color(i), INK)
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(func() -> void: _begin_level(level_number, true))
		box.add_child(b)
	var back := _pill_button("BACK", LAVENDER, INK)
	back.pressed.connect(_show_multiplayer)
	box.add_child(back)
	(box.get_child(0) as Control).grab_focus()


func _begin_level(level_number: int, local_coop: bool) -> void:
	get_tree().set_meta("local_coop", local_coop)
	if local_coop:
		get_tree().set_meta("local_p1_device", "keyboard")
		get_tree().set_meta("local_p2_device", "keyboard")
		get_tree().set_meta("local_p1_name", "Player 1")
		get_tree().set_meta("local_p2_name", "Player 2")
	else:
		get_tree().set_meta("local_coop", false)
	if _p1_character.is_empty():
		_p1_character = ROSTER.default_id()
	get_tree().set_meta("p1_character", _p1_character)
	get_tree().set_meta("p2_character", _p2_character if not _p2_character.is_empty() else ROSTER.default_id())
	get_tree().set_meta("level_number", level_number)
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://scenes/main.tscn")


# ------------------------------------------------------------------ widgets --

func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _pill_button(text: String, color: Color, text_color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(420, 62)
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
	normal.set_corner_radius_all(31)
	normal.shadow_color = Color(0.17, 0.11, 0.36, 0.45)
	normal.shadow_size = 8
	normal.shadow_offset = Vector2(0, 7)
	normal.content_margin_left = 28
	normal.content_margin_right = 28
	normal.content_margin_top = 12
	normal.content_margin_bottom = 12

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
	if event.is_action_pressed("ui_cancel"):
		# Step back one screen.
		if not _cards.is_empty():
			return
		_show_mode_select()
