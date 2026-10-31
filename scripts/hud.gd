extends Control

const UI_FONT = preload("res://fonts/lilita_one_regular.ttf")

@onready var coins_label: Label = $Coins

var coin_goal := 0
var finish_message: Label
var victory_overlay: ColorRect
var level_heading: Label
var victory_heading: Label
var victory_subtitle: Label
var replay_button: Button
var controls_hint: Label
var objective_hint: Label
var controls_tween: Tween
var shift_timer_label: Label
signal continue_pressed
signal retry_pressed
signal menu_pressed
signal save_pressed
var death_overlay: ColorRect
var death_heading: Label
var death_subtitle: Label
var retry_button: Button
var menu_button: Button

var pause_overlay: ColorRect
var pause_heading: Label
var pause_retry_button: Button
var pause_menu_button: Button
var pause_resume_button: Button
var pause_save_button: Button
var pause_status: Label

func _ready() -> void:
	_build_game_hud()
	_build_victory_overlay()
	_build_death_overlay()
	_build_pause_menu()
	_update_coin_counter(0)

func set_coin_goal(amount: int) -> void:
	coin_goal = amount
	_update_coin_counter(0)

func _on_coin_collected(coins):
	_update_coin_counter(coins)

func show_finish_message(message: String) -> void:
	finish_message.text = message
	finish_message.visible = true
	finish_message.scale = Vector2(0.5, 0.5)
	var tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(finish_message, "scale", Vector2(1.0, 1.0), 0.4)

	var timer := get_tree().create_timer(2.5)
	timer.timeout.connect(func(): finish_message.visible = false)

func show_victory(level_number: int, total_levels: int) -> void:
	victory_heading.text = ("ALL %d LEVELS COMPLETE!" % total_levels) if level_number == total_levels else "LEVEL %d COMPLETE!" % level_number
	victory_subtitle.text = "You conquered %s!" % level_heading.text.get_slice("•", 1).strip_edges().capitalize()
	replay_button.text = "PLAY AGAIN" if level_number == total_levels else "NEXT LEVEL"

	victory_overlay.visible = true
	victory_overlay.modulate.a = 1.0

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	replay_button.grab_focus()
	get_tree().paused = true

func show_death() -> void:
	death_overlay.visible = true
	death_overlay.modulate.a = 1.0

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	retry_button.grab_focus()
	get_tree().paused = true

func hide_death() -> void:
	death_overlay.visible = false

func set_level_info(level_number: int, level_name: String) -> void:
	level_heading.text = "LEVEL %d  •  %s" % [level_number, level_name.to_upper()]

func show_controls_hint() -> void:
	if not is_instance_valid(controls_hint) or not is_instance_valid(objective_hint):
		return
	if controls_tween and controls_tween.is_running():
		controls_tween.kill()
	controls_hint.visible = true
	controls_hint.modulate.a = 1.0
	objective_hint.visible = true
	objective_hint.modulate.a = 1.0
	controls_tween = create_tween()
	controls_tween.tween_interval(5.0)
	controls_tween.tween_property(controls_hint, "modulate:a", 0.0, 1.0)
	controls_tween.parallel().tween_property(objective_hint, "modulate:a", 0.0, 1.0)
	controls_tween.tween_callback(func():
		controls_hint.visible = false
		objective_hint.visible = false
	)

func _update_coin_counter(coins: int) -> void:
	if is_instance_valid(coins_label):
		coins_label.text = "🪙 %d / %02d" % [coins, coin_goal]
		var tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		coins_label.scale = Vector2(1.2, 1.2)
		tween.tween_property(coins_label, "scale", Vector2(1.0, 1.0), 0.2)

func toggle_pause() -> void:
	var is_paused = !pause_overlay.visible
	pause_overlay.visible = is_paused
	get_tree().paused = is_paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if is_paused else Input.MOUSE_MODE_CAPTURED
	if is_paused:
		if is_instance_valid(pause_status):
			pause_status.text = ""
		pause_resume_button.grab_focus()


func show_pause_status(text: String) -> void:
	## Feedback shown inside the pause menu. The normal finish message sits behind
	## the pause overlay, so save feedback needs its own label.
	if is_instance_valid(pause_status):
		pause_status.text = text

func _build_game_hud() -> void:
	objective_hint = Label.new()
	objective_hint.text = "SHIFT DIMENSIONS  •  COLLECT COINS  •  PRESS BOTH FAR-APART BUTTONS  •  REACH THE FLAG"
	objective_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	objective_hint.offset_left = -600
	objective_hint.offset_top = 24
	objective_hint.offset_right = 600
	objective_hint.offset_bottom = 66
	objective_hint.add_theme_font_override("font", UI_FONT)
	objective_hint.add_theme_font_size_override("font_size", 20)
	objective_hint.add_theme_color_override("font_color", Color("#fff6d5"))
	objective_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	objective_hint.add_theme_constant_override("shadow_offset_x", 2)
	objective_hint.add_theme_constant_override("shadow_offset_y", 3)
	add_child(objective_hint)

	shift_timer_label = Label.new()
	shift_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shift_timer_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	shift_timer_label.offset_left = -200
	shift_timer_label.offset_top = 66
	shift_timer_label.offset_right = 200
	shift_timer_label.offset_bottom = 100
	shift_timer_label.add_theme_font_override("font", UI_FONT)
	shift_timer_label.add_theme_font_size_override("font_size", 28)
	shift_timer_label.add_theme_color_override("font_color", Color("#ff6b8a"))
	shift_timer_label.visible = false
	add_child(shift_timer_label)

	level_heading = Label.new()
	level_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_heading.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	level_heading.offset_left = -350
	level_heading.offset_top = 122
	level_heading.offset_right = 350
	level_heading.offset_bottom = 154
	level_heading.add_theme_font_override("font", UI_FONT)
	level_heading.add_theme_font_size_override("font_size", 19)
	level_heading.add_theme_color_override("font_color", Color("#8ce7ff"))
	add_child(level_heading)

	controls_hint = Label.new()
	controls_hint.text = "WASD / STICK MOVE   MOUSE / RIGHT STICK LOOK   CLICK / SPACE / %s JUMP\nRIGHT CLICK / Q / %s SHIFT   F / %s FREEZE   E / %s INTERACT   ESC / %s MENU\nF1: SHOW HELP" % [InputPrompts.glyph("jump"), InputPrompts.glyph("shift_dimension"), InputPrompts.glyph("time_freeze"), InputPrompts.glyph("interact"), InputPrompts.glyph("back")]
	controls_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	controls_hint.offset_left = -540
	controls_hint.offset_top = -90
	controls_hint.offset_right = 540
	controls_hint.offset_bottom = -12
	controls_hint.add_theme_font_override("font", UI_FONT)
	controls_hint.add_theme_font_size_override("font_size", 15)
	controls_hint.add_theme_color_override("font_color", Color("#fff6d5"))
	controls_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	controls_hint.modulate.a = 0.0
	controls_hint.visible = false
	add_child(controls_hint)

	finish_message = Label.new()
	finish_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	finish_message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	finish_message.offset_left = -350
	finish_message.offset_top = 78
	finish_message.offset_right = 350
	finish_message.offset_bottom = 118
	finish_message.add_theme_font_override("font", UI_FONT)
	finish_message.add_theme_font_size_override("font_size", 24)
	finish_message.add_theme_color_override("font_color", Color("#ffe078"))
	finish_message.visible = false
	add_child(finish_message)

func _build_victory_overlay() -> void:
	victory_overlay = ColorRect.new()
	victory_overlay.color = Color(0.025, 0.045, 0.09, 0.82)
	victory_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	victory_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	victory_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	victory_overlay.visible = false
	add_child(victory_overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	victory_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(500, 250)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#17324f")
	panel_style.border_color = Color("#ffd66b")
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(18)
	panel_style.content_margin_left = 36
	panel_style.content_margin_right = 36
	panel_style.content_margin_top = 28
	panel_style.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var layout := VBoxContainer.new()
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_theme_constant_override("separation", 14)
	panel.add_child(layout)

	var heading := Label.new()
	victory_heading = heading
	heading.text = "LEVEL COMPLETE!"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_override("font", UI_FONT)
	heading.add_theme_font_size_override("font_size", 42)
	heading.add_theme_color_override("font_color", Color("#ffe078"))
	layout.add_child(heading)

	var subtitle := Label.new()
	victory_subtitle = subtitle
	subtitle.text = "Every coin collected. You made it to the summit!"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_override("font", UI_FONT)
	subtitle.add_theme_font_size_override("font_size", 19)
	subtitle.add_theme_color_override("font_color", Color("#ffffff"))
	layout.add_child(subtitle)

	var replay := Button.new()
	replay.text = "NEXT LEVEL"
	replay.custom_minimum_size = Vector2(210, 48)
	replay.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	replay.add_theme_font_override("font", UI_FONT)
	replay.add_theme_font_size_override("font_size", 22)
	replay.pressed.connect(func(): continue_pressed.emit())
	replay_button = replay
	layout.add_child(replay)

func _build_death_overlay() -> void:
	death_overlay = ColorRect.new()
	death_overlay.color = Color(0.09, 0.02, 0.03, 0.82)
	death_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	death_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	death_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	death_overlay.visible = false
	add_child(death_overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	death_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 260)
	panel.add_theme_stylebox_override("panel", _hud_panel_style(Color("#3a1620"), Color("#ff5b72")))
	center.add_child(panel)

	var layout := VBoxContainer.new()
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_theme_constant_override("separation", 16)
	panel.add_child(layout)

	death_heading = Label.new()
	death_heading.text = "YOU FELL"
	death_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_heading.add_theme_font_override("font", UI_FONT)
	death_heading.add_theme_font_size_override("font_size", 46)
	death_heading.add_theme_color_override("font_color", Color("#ff8a9c"))
	layout.add_child(death_heading)

	death_subtitle = Label.new()
	death_subtitle.text = "The sky swallowed you whole. Try again?"
	death_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_subtitle.add_theme_font_override("font", UI_FONT)
	death_subtitle.add_theme_font_size_override("font_size", 19)
	death_subtitle.add_theme_color_override("font_color", Color("#ffe7ea"))
	layout.add_child(death_subtitle)

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 18)
	layout.add_child(button_row)

	retry_button = _hud_button("RETRY", Color("#ff5b72"), Color("#2a0810"))
	retry_button.pressed.connect(func(): retry_pressed.emit())
	button_row.add_child(retry_button)

	menu_button = _hud_button("MAIN MENU", Color("#315784"), Color.WHITE)
	menu_button.pressed.connect(func(): menu_pressed.emit())
	button_row.add_child(menu_button)

func _build_pause_menu() -> void:
	pause_overlay = ColorRect.new()
	pause_overlay.color = Color(0, 0, 0, 0.6)
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_overlay.visible = false
	add_child(pause_overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 350)
	panel.add_theme_stylebox_override("panel", _hud_panel_style(Color("#1a2a3a"), Color("#8ce7ff")))
	center.add_child(panel)

	var layout := VBoxContainer.new()
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_theme_constant_override("separation", 12)
	panel.add_child(layout)

	pause_heading = Label.new()
	pause_heading.text = "GAME PAUSED"
	pause_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_heading.add_theme_font_override("font", UI_FONT)
	pause_heading.add_theme_font_size_override("font_size", 36)
	pause_heading.add_theme_color_override("font_color", Color("#8ce7ff"))
	layout.add_child(pause_heading)

	pause_resume_button = _hud_button("RESUME", Color("#315784"), Color.WHITE)
	pause_resume_button.pressed.connect(func(): toggle_pause())
	layout.add_child(pause_resume_button)

	pause_save_button = _hud_button("SAVE PROGRESS", Color("#2e7d32"), Color.WHITE)
	pause_save_button.pressed.connect(func(): save_pressed.emit())
	layout.add_child(pause_save_button)

	pause_status = Label.new()
	pause_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_status.add_theme_font_override("font", UI_FONT)
	pause_status.add_theme_font_size_override("font_size", 16)
	pause_status.add_theme_color_override("font_color", Color("#9be86a"))
	pause_status.text = ""
	layout.add_child(pause_status)

	pause_retry_button = _hud_button("RESTART", Color("#4a6a8a"), Color.WHITE)
	pause_retry_button.pressed.connect(func(): retry_pressed.emit())
	layout.add_child(pause_retry_button)

	pause_menu_button = _hud_button("MAIN MENU", Color("#263e64"), Color("#d6e6ff") )
	pause_menu_button.pressed.connect(func(): menu_pressed.emit())
	layout.add_child(pause_menu_button)

func _hud_panel_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(3)
	style.set_corner_radius_all(18)
	style.content_margin_left = 36
	style.content_margin_right = 36
	style.content_margin_top = 28
	style.content_margin_bottom = 28
	return style

func _hud_button(text: String, color: Color, text_color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(190, 48)
	button.add_theme_font_override("font", UI_FONT)
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	normal.set_corner_radius_all(12)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	var hover := normal.duplicate()
	hover.bg_color = color.lightened(0.14)
	hover.border_color = Color("#ffe078")
	hover.set_border_width_all(2)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", normal)
	button.add_theme_stylebox_override("focus", hover)
	return button
