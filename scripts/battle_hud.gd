class_name BattleHUD
extends CanvasLayer

## The dedicated 1v1 BATTLE ARENA HUD.
##
## Built in code, in the same visual language as the story HUD (same font, same
## panel and button styles), and driven entirely by the arena's match state. It
## shows both duelists' names and health, the round score, the synchronized cage
## countdown, round announcements and the two end-of-match screens (victory and
## opponent-left), plus a hurt flash when the local duelist is hit.

signal rematch_pressed
signal menu_pressed

const UI_FONT := preload("res://fonts/lilita_one_regular.ttf")

var local_slot := 1

var p1_panel: PanelContainer
var p1_name_label: Label
var p1_health: ProgressBar
var p1_hp_label: Label
var p2_panel: PanelContainer
var p2_name_label: Label
var p2_health: ProgressBar
var p2_hp_label: Label

var round_label: Label
var score_label: Label
var pips_label: Label

var countdown_label: Label
var announce_label: Label
var hint_label: Label

var banner: PanelContainer
var banner_label: Label

var waiting_overlay: ColorRect
var waiting_players: Label
var waiting_address: Label

var victory_overlay: ColorRect
var victory_heading: Label
var victory_score: Label
var victory_detail: Label
var rematch_status: Label
var rematch_button: Button
var victory_menu_button: Button

var disconnect_overlay: ColorRect
var disconnect_heading: Label
var disconnect_body: Label
var disconnect_count: Label
var return_button: Button

var hurt_flash: ColorRect
var _announce_tween: Tween
var _countdown_tween: Tween


func _ready() -> void:
	layer = 10
	_build_duelist_panels()
	_build_round_area()
	_build_announcements()
	_build_waiting()
	_build_victory()
	_build_disconnect()
	_build_hurt_flash()


func _build_duelist_panels() -> void:
	# Player 1 sits top-left, player 2 top-right: the layout mirrors the duel.
	var left := _duelist_panel(Color("#6fe7ef"))
	p1_panel = left[0]
	p1_name_label = left[1]
	p1_health = left[2]
	p1_hp_label = left[3]
	p1_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	p1_panel.offset_left = 26
	p1_panel.offset_top = 22
	p1_panel.offset_right = 326
	p1_panel.offset_bottom = 112

	var right := _duelist_panel(Color("#ffd451"))
	p2_panel = right[0]
	p2_name_label = right[1]
	p2_health = right[2]
	p2_hp_label = right[3]
	p2_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	p2_panel.offset_left = -326
	p2_panel.offset_top = 22
	p2_panel.offset_right = -26
	p2_panel.offset_bottom = 112
	p2_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p2_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	# The right panel's header flips so the name sits on the outer edge.
	var vbox2 := p2_panel.get_child(0) as VBoxContainer
	var header2 := vbox2.get_child(0) as HBoxContainer
	var left_title := header2.get_child(0) as Label
	left_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


## Returns [panel, name_label, bar, value_label]; the header row carries a small
## "PLAYER n" tag plus the player's actual name.
func _duelist_panel(accent: Color) -> Array:
	var panel := PanelContainer.new()
	var style := _panel_style(Color(0.05, 0.09, 0.19, 0.86), accent)
	style.set_corner_radius_all(14)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	var tag := _label("", 15, accent)
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(tag)
	var value := _label("100", 15, Color("#ffe7ea"))
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(value)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(260, 16)
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.value = 100.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.14, 0.05, 0.08, 0.9)
	bg.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#ff5b72")
	fill.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("fill", fill)
	vbox.add_child(bar)
	return [panel, tag, bar, value]


func _build_round_area() -> void:
	var centre := VBoxContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	centre.offset_left = -240
	centre.offset_right = 240
	centre.offset_top = 18
	centre.offset_bottom = 108
	centre.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.add_theme_constant_override("separation", 0)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	round_label = _label("ROUND 1", 22, Color("#cfe9ff"))
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	centre.add_child(round_label)

	score_label = _label("0  —  0", 36, Color("#ffe078"))
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	centre.add_child(score_label)

	pips_label = _label("", 16, Color("#a6f4ff"))
	pips_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	centre.add_child(pips_label)


func _build_announcements() -> void:
	countdown_label = _label("", 108, Color("#ffd451"))
	countdown_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	countdown_label.offset_left = -260
	countdown_label.offset_right = 260
	countdown_label.offset_top = -190
	countdown_label.offset_bottom = 30
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	countdown_label.add_theme_color_override("font_shadow_color", Color(0.05, 0.05, 0.15, 0.85))
	countdown_label.add_theme_constant_override("shadow_offset_x", 4)
	countdown_label.add_theme_constant_override("shadow_offset_y", 5)
	countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	countdown_label.visible = false
	add_child(countdown_label)

	announce_label = _label("", 40, Color("#ffffff"))
	announce_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	announce_label.offset_left = -420
	announce_label.offset_right = 420
	announce_label.offset_top = 30
	announce_label.offset_bottom = 130
	announce_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	announce_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	announce_label.add_theme_color_override("font_shadow_color", Color(0.05, 0.05, 0.15, 0.85))
	announce_label.add_theme_constant_override("shadow_offset_x", 3)
	announce_label.add_theme_constant_override("shadow_offset_y", 4)
	announce_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(announce_label)

	banner = PanelContainer.new()
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	banner.offset_left = -330
	banner.offset_right = 330
	banner.offset_top = -58
	banner.offset_bottom = 58
	var banner_style := _panel_style(Color(0.04, 0.08, 0.18, 0.9), Color("#ffd451"))
	banner_style.set_corner_radius_all(18)
	banner.add_theme_stylebox_override("panel", banner_style)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(banner)
	banner_label = _label("", 30, Color("#ffe078"))
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner.add_child(banner_label)
	banner.visible = false

	hint_label = _label("MOVE • SPACE ×2: DOUBLE JUMP • J: SLASH • SHIFT: DASH • H/K: MAGICAL SHIELD • Q: SHIFT THE SHARED WORLD", 14, Color("#9fc4e8"))
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.offset_left = -520
	hint_label.offset_right = 520
	hint_label.offset_top = -36
	hint_label.offset_bottom = -14
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint_label)


func _build_waiting() -> void:
	waiting_overlay = ColorRect.new()
	waiting_overlay.color = Color(0.02, 0.04, 0.09, 0.86)
	waiting_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(waiting_overlay)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	waiting_overlay.add_child(centre)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color("#17324f"), Color("#6fe7ef")))
	centre.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var heading := _label("WAITING FOR OPPONENT", 34, Color("#8fe0ff"))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)
	waiting_players = _label("", 20, Color("#ffffff"))
	waiting_players.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(waiting_players)
	waiting_address = _label("", 20, Color("#ffe078"))
	waiting_address.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	waiting_address.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	waiting_address.custom_minimum_size.x = 460
	box.add_child(waiting_address)
	var tip := _label("The duel starts the moment your opponent is in their cage.\nBoth cages stay sealed through an 8-second countdown.", 16, Color("#9fc4e8"))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size.x = 460
	box.add_child(tip)
	var leave := _button("RETURN TO MULTIPLAYER MENU", Color("#315784"), Color.WHITE)
	leave.pressed.connect(func() -> void: menu_pressed.emit())
	box.add_child(leave)
	waiting_overlay.visible = false


func _build_victory() -> void:
	victory_overlay = ColorRect.new()
	victory_overlay.color = Color(0.02, 0.03, 0.08, 0.88)
	victory_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(victory_overlay)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	victory_overlay.add_child(centre)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color("#1b2f4d"), Color("#ffd451")))
	centre.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var kicker := _label("MATCH COMPLETE", 18, Color("#a6f4ff"))
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(kicker)
	victory_heading = _label("PLAYER 1 WINS!", 46, Color("#ffe078"))
	victory_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(victory_heading)
	victory_score = _label("2 — 1", 30, Color("#ffffff"))
	victory_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(victory_score)
	victory_detail = _label("", 18, Color("#cfe9ff"))
	victory_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	victory_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	victory_detail.custom_minimum_size.x = 460
	box.add_child(victory_detail)
	rematch_status = _label("", 16, Color("#9fc4e8"))
	rematch_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(rematch_status)
	rematch_button = _button("PLAY AGAIN", Color("#ffd451"), Color("#493600"))
	rematch_button.pressed.connect(func() -> void: rematch_pressed.emit())
	box.add_child(rematch_button)
	victory_menu_button = _button("RETURN TO MULTIPLAYER MENU", Color("#315784"), Color.WHITE)
	victory_menu_button.pressed.connect(func() -> void: menu_pressed.emit())
	box.add_child(victory_menu_button)
	victory_overlay.visible = false


func _build_disconnect() -> void:
	disconnect_overlay = ColorRect.new()
	disconnect_overlay.color = Color(0.04, 0.02, 0.06, 0.88)
	disconnect_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(disconnect_overlay)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	disconnect_overlay.add_child(centre)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color("#2a1c33"), Color("#ff8a9c")))
	centre.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	disconnect_heading = _label("OPPONENT LEFT THE ARENA", 32, Color("#ff8a9c"))
	disconnect_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(disconnect_heading)
	disconnect_body = _label("", 18, Color("#e6f3ff"))
	disconnect_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	disconnect_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	disconnect_body.custom_minimum_size.x = 460
	box.add_child(disconnect_body)
	disconnect_count = _label("", 22, Color("#ffe078"))
	disconnect_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(disconnect_count)
	return_button = _button("RETURN NOW", Color("#8fe0ff"), Color("#062a3d"))
	return_button.pressed.connect(func() -> void: menu_pressed.emit())
	box.add_child(return_button)
	disconnect_overlay.visible = false


func _build_hurt_flash() -> void:
	hurt_flash = ColorRect.new()
	hurt_flash.color = Color(0.85, 0.1, 0.2, 0.0)
	hurt_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hurt_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hurt_flash)


# --- Driven by the arena -------------------------------------------------------


func set_names(player_one: String, player_two: String) -> void:
	p1_name_label.text = "PLAYER 1  •  %s" % player_one
	p2_name_label.text = "%s  •  PLAYER 2" % player_two


func set_health(slot: int, value: float, maximum: float) -> void:
	var bar := p1_health if slot == 1 else p2_health
	var tag := p1_hp_label if slot == 1 else p2_hp_label
	if bar == null:
		return
	bar.max_value = maximum
	bar.value = value
	tag.text = "%d" % roundi(value)


func set_round(number: int, wins_one: int, wins_two: int) -> void:
	round_label.text = "ROUND %d" % number
	score_label.text = "%d  —  %d" % [wins_one, wins_two]
	pips_label.text = "%s      %s" % [_pips(wins_one), _pips(wins_two)]


func _pips(won: int) -> String:
	var text := ""
	for i in 2:
		text += "●" if i < won else "○"
	return text


func show_countdown(seconds: int) -> void:
	countdown_label.visible = true
	countdown_label.text = "%d" % maxi(seconds, 0)
	countdown_label.modulate.a = 1.0
	if _countdown_tween != null and _countdown_tween.is_valid():
		_countdown_tween.kill()
	_countdown_tween = create_tween()
	_countdown_tween.tween_property(countdown_label, "modulate:a", 0.35, 0.75)


func hide_countdown() -> void:
	countdown_label.visible = false


func announce(text: String, size := 40, color := Color("#ffffff")) -> void:
	announce_label.text = text
	announce_label.add_theme_font_size_override("font_size", size)
	announce_label.add_theme_color_override("font_color", color)
	announce_label.modulate.a = 1.0
	if _announce_tween != null and _announce_tween.is_valid():
		_announce_tween.kill()
	_announce_tween = create_tween()
	_announce_tween.tween_interval(2.2)
	_announce_tween.tween_property(announce_label, "modulate:a", 0.0, 0.8)


func show_banner(text: String, color := Color("#ffe078")) -> void:
	banner_label.text = text
	banner_label.add_theme_color_override("font_color", color)
	banner.visible = true
	banner.modulate.a = 0.0
	create_tween().tween_property(banner, "modulate:a", 1.0, 0.25)


func hide_banner() -> void:
	banner.visible = false


func show_waiting(player_lines: String, address_line: String) -> void:
	waiting_players.text = player_lines
	waiting_address.text = address_line
	waiting_overlay.visible = true


func hide_waiting() -> void:
	waiting_overlay.visible = false


func show_victory(winner_name: String, score_text: String, detail: String, local_won: bool) -> void:
	victory_heading.text = "%s WINS!" % winner_name.to_upper()
	victory_heading.add_theme_color_override("font_color", Color("#8fe0ff") if local_won else Color("#ffe078"))
	victory_score.text = score_text
	victory_detail.text = detail
	rematch_status.text = "PLAY AGAIN needs both duelists to agree."
	victory_overlay.visible = true


func hide_victory() -> void:
	victory_overlay.visible = false


func set_rematch_status(text: String) -> void:
	rematch_status.text = text


func show_disconnect(body: String, seconds: int) -> void:
	disconnect_body.text = body
	disconnect_count.text = "Returning to the multiplayer menu in %d…" % seconds
	disconnect_overlay.visible = true


func set_disconnect_count(seconds: int) -> void:
	disconnect_count.text = "Returning to the multiplayer menu in %d…" % seconds


func hide_disconnect() -> void:
	disconnect_overlay.visible = false


func flash_hurt() -> void:
	hurt_flash.color = Color(0.85, 0.1, 0.2, 0.34)
	var tween := create_tween()
	tween.tween_property(hurt_flash, "color", Color(0.85, 0.1, 0.2, 0.0), 0.45)


# --- Styling helpers (same shapes as the story HUD) ----------------------------


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
	button.custom_minimum_size = Vector2(390, 46)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_override("font", UI_FONT)
	button.add_theme_font_size_override("font_size", 21)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", Color.WHITE)

	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	normal.border_color = color.lightened(0.14)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(16)
	normal.content_margin_left = 22
	normal.content_margin_right = 22
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	var hover := normal.duplicate()
	hover.bg_color = color.lightened(0.13)
	hover.border_color = Color("#ffe078")
	var pressed := normal.duplicate()
	pressed.bg_color = color.darkened(0.15)
	pressed.border_color = Color("#ffe078")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", normal.duplicate())
	return button


func _panel_style(color: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.shadow_color = Color(border.r, border.g, border.b, 0.35)
	style.shadow_size = 10
	style.content_margin_left = 26
	style.content_margin_right = 26
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	return style