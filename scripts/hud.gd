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
var frozen_ability_hint: Label
var frozen_progress_hint: Label
## When true the objective stays on screen after the controls hint fades.
var objective_persistent := false
var controls_tween: Tween
var shift_timer_label: Label
var controls_tween_shift: Tween
signal continue_pressed
signal retry_pressed
signal menu_pressed
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

# Inventory: the button in the corner and the panel it opens.
var inventory_button: Button
var fly_button: Button
var pause_fly_button: Button
var inventory_overlay: ColorRect
var inventory_rows: VBoxContainer
## The boss bar, shown while the island's Warden is on its feet.
var boss_panel: PanelContainer
var boss_name_label: Label
var boss_phase_label: Label
var boss_bar: ProgressBar
## Player health and stamina bars in the top-left below the coin counter.
var status_panel: PanelContainer
var health_bar: ProgressBar
var health_label: Label
var stamina_bar: ProgressBar
var stamina_label: Label
var combat_level := 1
var combat_level_name := ""
var _players: Array = []
var _coins := 0
var _transition_overlay: ColorRect

func _ready() -> void:
	# The HUD keeps working while the game is paused, so the inventory key can
	# close the inventory it opened.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_game_hud()
	_build_status_bars()
	_build_victory_overlay()
	_build_death_overlay()
	_build_pause_menu()
	_build_inventory_button()
	_build_inventory()
	_build_boss_bar()
	_update_coin_counter(0)


func _process(_delta: float) -> void:
	if _players.is_empty():
		return
	var primary: Node = _players[0] as Node
	if primary == null or not is_instance_valid(primary):
		return
	if primary.get("health") != null and primary.get("max_health") != null:
		update_health(float(primary.get("health")), float(primary.get("max_health")))
	if primary.get("stamina") != null and primary.get("max_stamina") != null:
		update_stamina(float(primary.get("stamina")), float(primary.get("max_stamina")))


func _build_status_bars() -> void:
	status_panel = PanelContainer.new()
	status_panel.name = "StatusPanel"
	status_panel.offset_left = 48
	status_panel.offset_top = 124
	status_panel.offset_right = 308
	status_panel.offset_bottom = 204
	var style := _hud_panel_style(Color(0.07, 0.11, 0.18, 0.82), Color("#5aa8e8"))
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 10
	status_panel.add_theme_stylebox_override("panel", style)
	add_child(status_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	status_panel.add_child(vbox)

	# Health row
	var hp_box := VBoxContainer.new()
	hp_box.add_theme_constant_override("separation", 2)
	vbox.add_child(hp_box)

	var hp_header := HBoxContainer.new()
	hp_box.add_child(hp_header)

	var hp_title := Label.new()
	hp_title.text = "HP"
	hp_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_title.add_theme_font_override("font", UI_FONT)
	hp_title.add_theme_font_size_override("font_size", 14)
	hp_title.add_theme_color_override("font_color", Color("#ff8a9c"))
	hp_header.add_child(hp_title)

	health_label = Label.new()
	health_label.text = "100%"
	health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	health_label.add_theme_font_override("font", UI_FONT)
	health_label.add_theme_font_size_override("font_size", 14)
	health_label.add_theme_color_override("font_color", Color("#ffe7ea"))
	hp_header.add_child(health_label)

	health_bar = ProgressBar.new()
	health_bar.name = "HealthBar"
	health_bar.custom_minimum_size = Vector2(228, 12)
	health_bar.show_percentage = false
	health_bar.max_value = 100.0
	health_bar.value = 100.0
	var hp_bg := StyleBoxFlat.new()
	hp_bg.bg_color = Color(0.14, 0.05, 0.08, 0.9)
	hp_bg.set_corner_radius_all(5)
	health_bar.add_theme_stylebox_override("background", hp_bg)
	var hp_fill := StyleBoxFlat.new()
	hp_fill.bg_color = Color("#ff5b72")
	hp_fill.set_corner_radius_all(5)
	health_bar.add_theme_stylebox_override("fill", hp_fill)
	hp_box.add_child(health_bar)

	# Stamina row
	var st_box := VBoxContainer.new()
	st_box.add_theme_constant_override("separation", 2)
	vbox.add_child(st_box)

	var st_header := HBoxContainer.new()
	st_box.add_child(st_header)

	var st_title := Label.new()
	st_title.text = "STAMINA"
	st_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st_title.add_theme_font_override("font", UI_FONT)
	st_title.add_theme_font_size_override("font_size", 14)
	st_title.add_theme_color_override("font_color", Color("#6ef2b8"))
	st_header.add_child(st_title)

	stamina_label = Label.new()
	stamina_label.text = "100%"
	stamina_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stamina_label.add_theme_font_override("font", UI_FONT)
	stamina_label.add_theme_font_size_override("font_size", 14)
	stamina_label.add_theme_color_override("font_color", Color("#e2fff2"))
	st_header.add_child(stamina_label)

	stamina_bar = ProgressBar.new()
	stamina_bar.name = "StaminaBar"
	stamina_bar.custom_minimum_size = Vector2(228, 12)
	stamina_bar.show_percentage = false
	stamina_bar.max_value = 100.0
	stamina_bar.value = 100.0
	var st_bg := StyleBoxFlat.new()
	st_bg.bg_color = Color(0.05, 0.14, 0.11, 0.9)
	st_bg.set_corner_radius_all(5)
	stamina_bar.add_theme_stylebox_override("background", st_bg)
	var st_fill := StyleBoxFlat.new()
	st_fill.bg_color = Color("#3ae09e")
	st_fill.set_corner_radius_all(5)
	stamina_bar.add_theme_stylebox_override("fill", st_fill)
	st_box.add_child(stamina_bar)


func update_health(current: float, maximum: float) -> void:
	if health_bar == null or maximum <= 0.0:
		return
	health_bar.max_value = maximum
	health_bar.value = clampf(current, 0.0, maximum)
	var pct := roundi((clampf(current, 0.0, maximum) / maximum) * 100.0)
	if health_label != null:
		health_label.text = "%d%%" % pct


func update_stamina(current: float, maximum: float) -> void:
	if stamina_bar == null or maximum <= 0.0:
		return
	stamina_bar.max_value = maximum
	stamina_bar.value = clampf(current, 0.0, maximum)
	var pct := roundi((clampf(current, 0.0, maximum) / maximum) * 100.0)
	if stamina_label != null:
		stamina_label.text = "%d%%" % pct


## The boss bar: a name, a health strip and the phase it is in. Hidden until a
## boss wakes up.
func _build_boss_bar() -> void:
	boss_panel = PanelContainer.new()
	boss_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	boss_panel.offset_left = -310
	boss_panel.offset_top = 166
	boss_panel.offset_right = 310
	boss_panel.offset_bottom = 246
	var style := _hud_panel_style(Color(0.09, 0.06, 0.15, 0.82), Color("#b06bff"))
	style.set_corner_radius_all(12)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 10
	style.content_margin_bottom = 12
	boss_panel.add_theme_stylebox_override("panel", style)
	boss_panel.visible = false
	add_child(boss_panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 4)
	boss_panel.add_child(layout)

	var headings := HBoxContainer.new()
	layout.add_child(headings)

	boss_name_label = Label.new()
	boss_name_label.text = "THE CORRUPTED ISLAND WARDEN"
	boss_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boss_name_label.add_theme_font_override("font", UI_FONT)
	boss_name_label.add_theme_font_size_override("font_size", 18)
	boss_name_label.add_theme_color_override("font_color", Color("#e6d6ff"))
	headings.add_child(boss_name_label)

	boss_phase_label = Label.new()
	boss_phase_label.text = "PHASE 1"
	boss_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	boss_phase_label.add_theme_font_override("font", UI_FONT)
	boss_phase_label.add_theme_font_size_override("font_size", 18)
	boss_phase_label.add_theme_color_override("font_color", Color("#ff9d6b"))
	headings.add_child(boss_phase_label)

	boss_bar = ProgressBar.new()
	boss_bar.custom_minimum_size = Vector2(560, 22)
	boss_bar.show_percentage = false
	boss_bar.max_value = 1.0
	boss_bar.value = 1.0
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.06, 0.05, 0.1, 0.9)
	bar_bg.set_corner_radius_all(6)
	boss_bar.add_theme_stylebox_override("background", bar_bg)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color("#b06bff")
	bar_fill.set_corner_radius_all(6)
	boss_bar.add_theme_stylebox_override("fill", bar_fill)
	layout.add_child(boss_bar)


func show_boss(boss_name: String) -> void:
	boss_name_label.text = boss_name
	boss_phase_label.text = "PHASE 1"
	boss_bar.value = 1.0
	boss_panel.visible = true


func update_boss(health: int, max_health: int, phase: int) -> void:
	if max_health <= 0:
		return
	boss_bar.max_value = float(max_health)
	boss_bar.value = float(health)
	boss_phase_label.text = "PHASE %d" % phase


func hide_boss() -> void:
	boss_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	# In local co-op each slot gets its own inventory key, so player 2 can open
	# the shared panel too.
	for action in ["inventory", "p1_inventory", "p2_inventory"]:
		if InputMap.has_action(action) and event.is_action_pressed(action) \
				and not event.is_echo():
			toggle_inventory()
			get_viewport().set_input_as_handled()
			return
	for action in ["fly", "p1_fly", "p2_fly"]:
		if InputMap.has_action(action) and event.is_action_pressed(action) \
				and not event.is_echo():
			toggle_fly_mode()
			get_viewport().set_input_as_handled()
			return

func set_coin_goal(amount: int) -> void:
	coin_goal = amount
	_update_coin_counter(0)


## Set the objective line. A persistent objective (the island's coin hunt) stays
## on screen after the controls hint has faded; the default one fades with it.
func set_objective(text: String, persistent := true) -> void:
	if not is_instance_valid(objective_hint):
		return
	objective_hint.text = text
	objective_hint.visible = true
	objective_hint.modulate.a = 1.0
	objective_persistent = persistent

func set_frozen_abilities(unlocked: Array[String]) -> void:
	if not is_instance_valid(frozen_ability_hint):
		return
	if unlocked.is_empty():
		frozen_ability_hint.visible = false
		return
	frozen_ability_hint.text = "ICE ABILITIES  •  " + "  |  ".join(unlocked)
	frozen_ability_hint.visible = true

func set_frozen_progress(seals: int, total: int, crystal_solved: bool, fragment_recovered: bool, checkpoint: int, generators: int = 0) -> void:
	if not is_instance_valid(frozen_progress_hint):
		return
	frozen_progress_hint.text = "SEALS %d/%d  •  GENERATORS %d/3  •  CRYSTAL LIGHT %s  •  FRAGMENT %s  •  CHECKPOINT %d" % [
		seals, total, generators, "ALIGNED" if crystal_solved else "PENDING",
		"RECOVERED" if fragment_recovered else "PENDING", checkpoint]
	frozen_progress_hint.visible = true

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

func play_level_transition(title: String, callback: Callable) -> void:
	if _transition_overlay != null:
		_transition_overlay.queue_free()
	_transition_overlay = ColorRect.new()
	_transition_overlay.color = Color("#071526")
	_transition_overlay.modulate.a = 0.0
	_transition_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_transition_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_transition_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_transition_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_transition_overlay.add_child(center)
	var label := Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", UI_FONT)
	label.add_theme_font_size_override("font_size", 42)
	label.add_theme_color_override("font_color", Color("#dffaff"))
	center.add_child(label)
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_transition_overlay, "modulate:a", 1.0, 0.35)
	tween.tween_interval(0.55)
	tween.tween_callback(callback)

func show_victory(level_number: int, total_levels: int) -> void:
	victory_heading.text = "ALL 5 LEVELS COMPLETE!" if level_number == total_levels else "LEVEL %d COMPLETE!" % level_number
	victory_subtitle.text = "You conquered %s!" % level_heading.text.get_slice("•", 1).strip_edges().capitalize()
	replay_button.text = "PLAY AGAIN" if level_number == total_levels else "NEXT LEVEL"

	victory_overlay.visible = true
	victory_overlay.modulate.a = 1.0

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	replay_button.grab_focus()
	get_tree().paused = true

func show_death(cause: String = "fall") -> void:
	if cause == "slime":
		death_heading.text = "SLIMED!"
		death_subtitle.text = "A Shadow Slime drained the last of your health. Try again?"
	elif cause == "enemy" or cause == "warden":
		death_heading.text = "STRUCK DOWN"
		death_subtitle.text = "You were overwhelmed in battle. Try again?"
	else:
		death_heading.text = "YOU FELL"
		death_subtitle.text = "The sky swallowed you whole. Try again?"

	death_overlay.visible = true
	death_overlay.modulate.a = 1.0

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	retry_button.grab_focus()
	get_tree().paused = true

func hide_death() -> void:
	death_overlay.visible = false

func set_level_info(level_number: int, level_name: String) -> void:
	combat_level = level_number
	combat_level_name = level_name
	level_heading.text = "LEVEL %d  •  %s" % [level_number, level_name.to_upper()]
	if inventory_overlay != null and inventory_overlay.visible:
		_fill_inventory()


# --- The inventory -------------------------------------------------------------

## Which players the inventory lists. Called again when local co-op adds player 2.
func bind_players(players: Array) -> void:
	_players = players
	if not _players.is_empty() and _players[0] != null:
		var primary: Node = _players[0] as Node
		if primary.has_signal("health_changed") and not primary.is_connected("health_changed", update_health):
			primary.connect("health_changed", update_health)
		if primary.has_signal("stamina_changed") and not primary.is_connected("stamina_changed", update_stamina):
			primary.connect("stamina_changed", update_stamina)
		if primary.get("health") != null and primary.get("max_health") != null:
			update_health(float(primary.get("health")), float(primary.get("max_health")))
		if primary.get("stamina") != null and primary.get("max_stamina") != null:
			update_stamina(float(primary.get("stamina")), float(primary.get("max_stamina")))


func _build_inventory_button() -> void:
	inventory_button = _hud_button("INVENTORY  (I)", Color("#27496f"), Color.WHITE)
	inventory_button.custom_minimum_size = Vector2(180, 42)
	inventory_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	inventory_button.offset_left = -206
	inventory_button.offset_top = 24
	inventory_button.offset_right = -26
	inventory_button.offset_bottom = 66
	inventory_button.pressed.connect(toggle_inventory)
	add_child(inventory_button)

	fly_button = _hud_button("FLY: OFF  (9)", Color("#27496f"), Color.WHITE)
	fly_button.custom_minimum_size = Vector2(180, 42)
	fly_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	fly_button.offset_left = -206
	fly_button.offset_top = 74
	fly_button.offset_right = -26
	fly_button.offset_bottom = 116
	fly_button.pressed.connect(toggle_fly_mode)
	add_child(fly_button)


func toggle_fly_mode() -> void:
	var enabled := false
	for who in _players:
		var p: Node = who as Node
		if p != null and is_instance_valid(p) and p.has_method("toggle_fly_mode"):
			enabled = bool(p.call("toggle_fly_mode"))
	_refresh_fly_buttons(enabled)
	show_finish_message("FLY MODE: ON  (INFINITE DOUBLE JUMP)" if enabled else "FLY MODE: OFF")
	if inventory_overlay != null and inventory_overlay.visible:
		_fill_inventory()


func _refresh_fly_buttons(enabled: bool) -> void:
	var label_text := "FLY: ON  (9)" if enabled else "FLY: OFF  (9)"
	var bg := Color("#2b7a52") if enabled else Color("#27496f")
	for btn in [fly_button, pause_fly_button]:
		if btn == null:
			continue
		btn.text = label_text
		var normal := StyleBoxFlat.new()
		normal.bg_color = bg
		normal.set_corner_radius_all(12)
		normal.content_margin_left = 18
		normal.content_margin_right = 18
		normal.content_margin_top = 10
		normal.content_margin_bottom = 10
		btn.add_theme_stylebox_override("normal", normal)


func _build_inventory() -> void:
	inventory_overlay = ColorRect.new()
	inventory_overlay.color = Color(0, 0, 0, 0.62)
	inventory_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inventory_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	inventory_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	inventory_overlay.visible = false
	add_child(inventory_overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inventory_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(430, 0)
	panel.add_theme_stylebox_override("panel", _hud_panel_style(Color("#172433"), Color("#ffd66b")))
	center.add_child(panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	layout.add_theme_constant_override("margin_left", 26)
	layout.add_theme_constant_override("margin_right", 26)
	layout.add_theme_constant_override("margin_top", 20)
	layout.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(layout)

	var heading := Label.new()
	heading.text = "INVENTORY"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_override("font", UI_FONT)
	heading.add_theme_font_size_override("font_size", 34)
	heading.add_theme_color_override("font_color", Color("#ffe078"))
	layout.add_child(heading)

	inventory_rows = VBoxContainer.new()
	inventory_rows.add_theme_constant_override("separation", 6)
	layout.add_child(inventory_rows)

	var close := _hud_button("CLOSE  (I)", Color("#315784"), Color.WHITE)
	close.pressed.connect(close_inventory)
	layout.add_child(close)

	var hint := Label.new()
	hint.text = "Slash with J, or B on a pad. Hold forward to aim it up, or hold back in\nmid-air to aim it down and pogo off a sentry. Touching one ends the run."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_override("font", UI_FONT)
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color("#9fc4e8"))
	layout.add_child(hint)


func _inventory_row(label: String, value: String, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = label
	name_label.custom_minimum_size = Vector2(150, 0)
	name_label.add_theme_font_override("font", UI_FONT)
	name_label.add_theme_font_size_override("font_size", 19)
	name_label.add_theme_color_override("font_color", Color("#9fc4e8"))
	row.add_child(name_label)
	var value_label := Label.new()
	value_label.text = value
	value_label.add_theme_font_override("font", UI_FONT)
	value_label.add_theme_font_size_override("font_size", 19)
	value_label.add_theme_color_override("font_color", color)
	row.add_child(value_label)
	return row


func _fill_inventory() -> void:
	if inventory_rows == null:
		return
	for child in inventory_rows.get_children():
		inventory_rows.remove_child(child)
		child.queue_free()

	for index in _players.size():
		var player = _players[index]
		if player == null:
			continue
		var who := "PLAYER %d" % (index + 1) if _players.size() > 1 else "PLAYER"
		var heading := Label.new()
		heading.text = who
		heading.add_theme_font_override("font", UI_FONT)
		heading.add_theme_font_size_override("font_size", 24)
		heading.add_theme_color_override("font_color", Color("#ffd451") if index == 0 else Color("#8fe0ff"))
		inventory_rows.add_child(heading)

		var character := str(player.get("character_id"))
		if character.is_empty():
			character = "Jamal"
		inventory_rows.add_child(_inventory_row("Character", character, Color.WHITE))
		if player.get("health") != null and player.get("max_health") != null:
			var hp_pct := roundi((float(player.get("health")) / maxf(float(player.get("max_health")), 1.0)) * 100.0)
			inventory_rows.add_child(_inventory_row("Health", "%d%%" % hp_pct, Color("#ff8a9c")))
		if player.get("stamina") != null and player.get("max_stamina") != null:
			var st_pct := roundi((float(player.get("stamina")) / maxf(float(player.get("max_stamina")), 1.0)) * 100.0)
			inventory_rows.add_child(_inventory_row("Stamina", "%d%%" % st_pct, Color("#6ef2b8")))
		var is_fly := bool(player.get("fly_mode")) if player.get("fly_mode") != null else false
		inventory_rows.add_child(_inventory_row("Fly mode (9)", "ON (Infinite Jump)" if is_fly else "OFF", Color("#6ef2b8") if is_fly else Color("#9fc4e8")))
		inventory_rows.add_child(_inventory_row("Slash", "J / pad B", Color("#fff3d6")))
		inventory_rows.add_child(_inventory_row("Aim the slash", "hold forward = up, back in mid-air = down", Color("#9fc4e8")))

	inventory_rows.add_child(_inventory_row("Coins",
		"%d / %d" % [_coins, coin_goal], Color("#ffd451")))
	inventory_rows.add_child(_inventory_row("Level",
		"%d  •  %s" % [combat_level, combat_level_name.to_upper()], Color.WHITE))


func toggle_inventory() -> void:
	if inventory_overlay == null:
		return
	if inventory_overlay.visible:
		close_inventory()
	else:
		open_inventory()


func open_inventory() -> void:
	if inventory_overlay == null or pause_overlay.visible:
		return
	_fill_inventory()
	inventory_overlay.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_inventory() -> void:
	if inventory_overlay == null:
		return
	inventory_overlay.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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
		if not objective_persistent:
			objective_hint.visible = false
	)

func _update_coin_counter(coins: int) -> void:
	_coins = coins
	if is_instance_valid(coins_label):
		coins_label.text = "🪙 %d / %02d" % [coins, coin_goal]
		var tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		coins_label.scale = Vector2(1.2, 1.2)
		tween.tween_property(coins_label, "scale", Vector2(1.0, 1.0), 0.2)
	if inventory_overlay != null and inventory_overlay.visible:
		_fill_inventory()

func toggle_pause() -> void:
	# The inventory and the pause menu are both modal; close one before opening
	# the other, so the game never ends up paused with neither showing.
	if inventory_overlay != null and inventory_overlay.visible:
		close_inventory()
	var is_paused = !pause_overlay.visible
	pause_overlay.visible = is_paused
	get_tree().paused = is_paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if is_paused else Input.MOUSE_MODE_CAPTURED
	if is_paused:
		pause_resume_button.grab_focus()

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

	frozen_ability_hint = Label.new()
	frozen_ability_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	frozen_ability_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	frozen_ability_hint.offset_left = -520
	frozen_ability_hint.offset_top = 68
	frozen_ability_hint.offset_right = 520
	frozen_ability_hint.offset_bottom = 96
	frozen_ability_hint.add_theme_font_override("font", UI_FONT)
	frozen_ability_hint.add_theme_font_size_override("font_size", 16)
	frozen_ability_hint.add_theme_color_override("font_color", Color("#b9f5ff"))
	frozen_ability_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	frozen_ability_hint.add_theme_constant_override("shadow_offset_x", 2)
	frozen_ability_hint.add_theme_constant_override("shadow_offset_y", 2)
	frozen_ability_hint.visible = false
	add_child(frozen_ability_hint)

	frozen_progress_hint = Label.new()
	frozen_progress_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	frozen_progress_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	frozen_progress_hint.offset_left = -560
	frozen_progress_hint.offset_top = 96
	frozen_progress_hint.offset_right = 560
	frozen_progress_hint.offset_bottom = 122
	frozen_progress_hint.add_theme_font_override("font", UI_FONT)
	frozen_progress_hint.add_theme_font_size_override("font_size", 14)
	frozen_progress_hint.add_theme_color_override("font_color", Color("#d8f8ff"))
	frozen_progress_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	frozen_progress_hint.add_theme_constant_override("shadow_offset_x", 2)
	frozen_progress_hint.add_theme_constant_override("shadow_offset_y", 2)
	frozen_progress_hint.visible = false
	add_child(frozen_progress_hint)

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
	# A shadow, because this line sits over bright scenery - a waterfall or a
	# glowing mushroom washes thin cyan text out completely without one.
	level_heading.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	level_heading.add_theme_constant_override("shadow_offset_x", 2)
	level_heading.add_theme_constant_override("shadow_offset_y", 2)
	add_child(level_heading)

	controls_hint = Label.new()
	controls_hint.text = "WASD / STICK MOVE   MOUSE / RIGHT STICK LOOK   CLICK / SPACE / A JUMP\nRIGHT CLICK / Q / LB SHIFT   F / Y FREEZE   E / X INTERACT   ESC / B MENU\nJ / B SLASH   I INVENTORY      F1: SHOW HELP"
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

	pause_fly_button = _hud_button("FLY: OFF  (9)", Color("#27496f"), Color.WHITE)
	pause_fly_button.pressed.connect(func(): toggle_fly_mode())
	layout.add_child(pause_fly_button)

	pause_save_button = _hud_button("SAVE PROGRESS", Color("#2e7d32"), Color.WHITE)
	pause_save_button.pressed.connect(func(): show_finish_message("Game Saved!"))
	layout.add_child(pause_save_button)

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
