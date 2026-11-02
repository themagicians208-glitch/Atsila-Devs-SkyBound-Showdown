extends Control
## SkyBound Showdown loading screen (Godot 4.x)
## Root node: a plain Control. Everything else is built in code.
## The runner on the progress tube is Jamal the raccoon (2D sprite).

signal continue_pressed

## Scene to load in the background. Leave empty to run a fake 15 second demo.
@export_file("*.tscn") var next_scene: String = ""
## Kept for compatibility (the runner is a 2D sprite now).
@export var jamal_model: PackedScene
## Jamal's sprite. Defaults to the raccoon art.
@export var runner_texture: Texture2D
@export var runner_path: String = "res://assets/generated/loading_character.png"
## Optional: drop Lilita One (.ttf) here for the chunky title look.
@export var title_font: Font
@export var simulate_seconds: float = 15.0

const INK := Color("2a2350")
const SKY := Color("7fd8e8")
const SUN := Color("ffd54f")
const PINK := Color("e0527f")
const TEAL := Color("2b8fa8")
const TUBE_H := 38.0
const TUBE_SIDE := 80.0
const TUBE_BOTTOM := 60.0
const RUN_SIZE := Vector2(180, 160)

const STRIPE_SHADER := """
shader_type canvas_item;
uniform vec2 px = vec2(100.0, 30.0);
void fragment() {
	float s = step(0.5, fract((UV.x * px.x + UV.y * px.y) / 28.0 - TIME * 1.2));
	COLOR.rgb = mix(COLOR.rgb, vec3(1.0, 0.89, 0.53), s);
}
"""

var _t := 0.0
var _shown := 0.0
var _target := 0.0
var _manual := false
var _ready_to_go := false
var _gone := false
var _letters: Array[Control] = []
var _title_box: VBoxContainer
var _sub: Label
var _prompt: Label
var _pct: Label
var _tube: Panel
var _fill: Panel
var _fill_mat: ShaderMaterial
var _runner: TextureRect


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color.WHITE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_title()
	_build_tube()
	_build_runner()
	if next_scene != "":
		ResourceLoader.load_threaded_request(next_scene)


## Call this yourself (0.0 to 1.0) if you load things manually instead of using next_scene.
func set_progress(p: float) -> void:
	_manual = true
	_target = clampf(p, 0.0, 1.0)


# ---------------------------------------------------------------- title
func _build_title() -> void:
	_title_box = VBoxContainer.new()
	_title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_title_box.add_theme_constant_override("separation", 6)
	_title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_box)
	for word in ["SkyBound", "Showdown"]:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 2)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_title_box.add_child(row)
		for ch in word:
			var cell := _make_letter(ch, _letters.size())
			row.add_child(cell)
			_letters.append(cell)
	_sub = _label("Packing the sky…", 26, INK)
	_title_box.add_child(_sub)
	_prompt = _label("Press Esc to continue", 32, INK)
	_prompt.modulate.a = 0.0
	_prompt.mouse_filter = Control.MOUSE_FILTER_STOP
	_prompt.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_continue())
	_title_box.add_child(_prompt)
	_title_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_title_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_title_box.grow_vertical = Control.GROW_DIRECTION_BOTH


func _label(t: String, px: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := LabelSettings.new()
	s.font_size = px
	s.font_color = col
	if title_font:
		s.font = title_font
	l.label_settings = s
	return l


# One letter = hollow white face + coloured outline, stacked teal copies behind it for depth.
func _make_letter(ch: String, i: int) -> Control:
	var px := 100
	var f: Font = title_font if title_font else ThemeDB.fallback_font
	var cell := Control.new()
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + 14.0
	cell.custom_minimum_size = Vector2(w, px * 1.3)
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(holder)
	var depth := 7
	holder.add_child(_glyph(ch, px, f, INK, INK, Vector2(depth + 2, depth + 4)))
	for d in range(depth, 0, -1):
		holder.add_child(_glyph(ch, px, f, SKY, SKY, Vector2(d, d)))
	var edge: Color = [INK, PINK, TEAL][i % 3]
	holder.add_child(_glyph(ch, px, f, Color.WHITE, edge, Vector2.ZERO))
	return cell


func _glyph(ch: String, px: int, f: Font, fill: Color, edge: Color, off: Vector2) -> Label:
	var l := Label.new()
	l.text = ch
	l.position = off
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := LabelSettings.new()
	s.font = f
	s.font_size = px
	s.font_color = fill
	s.outline_size = 12
	s.outline_color = edge
	l.label_settings = s
	return l


# ---------------------------------------------------------------- tube
func _build_tube() -> void:
	_tube = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("eef9fc")
	sb.set_corner_radius_all(30)
	sb.set_border_width_all(4)
	sb.border_color = INK
	sb.shadow_color = SKY
	sb.shadow_size = 1
	sb.shadow_offset = Vector2(0, 6)
	_tube.add_theme_stylebox_override("panel", sb)
	_tube.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tube)
	_tube.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_tube.offset_left = TUBE_SIDE
	_tube.offset_right = -TUBE_SIDE
	_tube.offset_bottom = -TUBE_BOTTOM
	_tube.offset_top = -TUBE_BOTTOM - TUBE_H

	_fill = Panel.new()
	var fb := StyleBoxFlat.new()
	fb.bg_color = SUN
	fb.set_corner_radius_all(30)
	_fill.add_theme_stylebox_override("panel", fb)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = STRIPE_SHADER
	_fill_mat = ShaderMaterial.new()
	_fill_mat.shader = sh
	_fill.material = _fill_mat
	_tube.add_child(_fill)
	_fill.position = Vector2(4, 4)

	_pct = _label("0%", 26, INK)
	_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_pct)
	_pct.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_pct.offset_right = -TUBE_SIDE - 6
	_pct.offset_left = _pct.offset_right - 80
	_pct.offset_bottom = -TUBE_BOTTOM - TUBE_H - 4
	_pct.offset_top = _pct.offset_bottom - 36


# ---------------------------------------------------------------- Jamal
func _build_runner() -> void:
	_runner = TextureRect.new()
	var tex := runner_texture
	if tex == null:
		tex = load(runner_path) as Texture2D
	_runner.texture = tex
	_runner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_runner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_runner.size = RUN_SIZE
	_runner.custom_minimum_size = RUN_SIZE
	_runner.pivot_offset = RUN_SIZE * 0.5
	_runner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_runner)
	if tex == null:
		push_warning("Jamal sprite not found at " + runner_path)


# ---------------------------------------------------------------- loop
func _process(delta: float) -> void:
	_t += delta
	_update_progress()
	_shown = lerpf(_shown, _target, 1.0 - exp(-8.0 * delta))
	if not _ready_to_go and _target >= 1.0 and _shown > 0.995:
		_ready_to_go = true
		create_tween().tween_property(_prompt, "modulate:a", 1.0, 0.4)

	# tube + percent + status text
	var inner_w := _tube.size.x - 8.0
	_fill.size = Vector2(maxf(30.0, inner_w * _shown), TUBE_H - 8.0)
	_fill_mat.set_shader_parameter("px", _fill.size)
	_pct.text = "%d%%" % int(_shown * 100.0)
	if _ready_to_go:
		_sub.text = "Ready to hop!"
		_prompt.pivot_offset = _prompt.size * 0.5
		_prompt.scale = Vector2.ONE * (1.0 + 0.04 * sin(_t * 4.0))
	else:
		_sub.text = ["Packing the sky…", "Waking Jamal up…", "Bending gravity…"][mini(2, int(_shown * 3.0))]

	# title letters hop in a wave
	for i in _letters.size():
		var k := fposmod(_t * 0.625 - i * 0.09, 1.0)
		var up := sin(PI * clampf(k / 0.5, 0.0, 1.0)) * 14.0
		(_letters[i].get_child(0) as Control).position.y = -up

	# Jamal the raccoon rides the front edge of the fill.
	var tp := _tube.global_position
	var cx := tp.x + 4.0 + inner_w * _shown
	var base_y := tp.y - RUN_SIZE.y + 20.0
	if _ready_to_go:
		_runner.position = Vector2(cx - RUN_SIZE.x * 0.5, base_y - absf(sin(_t * 5.0)) * 16.0)
		_runner.rotation = sin(_t * 3.0) * 0.16
		_runner.scale = Vector2.ONE
	else:
		_runner.position = Vector2(cx - RUN_SIZE.x * 0.5, base_y - absf(sin(_t * 13.0)) * 7.0)
		_runner.rotation = -0.06 + sin(_t * 13.0) * 0.04
		_runner.scale = Vector2(1.0, 1.0 + 0.03 * sin(_t * 13.0))


func _update_progress() -> void:
	if _manual:
		return
	if next_scene == "":
		_target = clampf(_t / simulate_seconds, 0.0, 1.0)
		return
	var prog: Array = []
	var st := ResourceLoader.load_threaded_get_status(next_scene, prog)
	if prog.size() > 0:
		_target = clampf(prog[0], 0.0, 1.0)
	if st == ResourceLoader.THREAD_LOAD_LOADED:
		_target = 1.0
	elif st == ResourceLoader.THREAD_LOAD_FAILED:
		push_error("Could not load " + next_scene)


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		_continue()


func _continue() -> void:
	if not _ready_to_go or _gone:
		return
	_gone = true
	continue_pressed.emit()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.5)
	await tw.finished
	if next_scene != "":
		var res := ResourceLoader.load_threaded_get(next_scene) as PackedScene
		if res:
			get_tree().change_scene_to_packed(res)
	else:
		get_tree().reload_current_scene()  # demo mode: just loop