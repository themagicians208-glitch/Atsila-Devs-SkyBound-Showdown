extends Node3D

const PLATFORM := preload("res://objects/platform.tscn")
const PLATFORM_MEDIUM := preload("res://objects/platform_medium.tscn")
const PLATFORM_GRASS := preload("res://objects/platform_grass_large_round.tscn")
const PLATFORM_FALLING := preload("res://objects/platform_falling.tscn")
const COIN := preload("res://objects/coin.tscn")
const FLAG := preload("res://models/flag.glb")
const GRAVITY_ZONE_SCRIPT := preload("res://scripts/anti_gravity_zone.gd")
const SPINNING_HAZARD_SCRIPT := preload("res://scripts/spinning_hazard.gd")
const MOVING_PLATFORM_SCRIPT := preload("res://objects/moving_platform.gd")
const PHASE_PLATFORM_SCRIPT := preload("res://objects/phase_platform.gd")
const PUZZLE_GATE_SCRIPT := preload("res://objects/puzzle_gate.gd")
const SEE_SAW_SCRIPT := preload("res://scripts/see_saw.gd")
const ROTATING_LOG_SCRIPT := preload("res://scripts/rotating_log.gd")
const ROLLING_BARREL_SCRIPT := preload("res://scripts/rolling_barrel.gd")
const SLIPPERY_SCRIPT := preload("res://scripts/slippery_zone.gd")
const STICKY_SCRIPT := preload("res://scripts/sticky_zone.gd")
const FAN_SCRIPT := preload("res://scripts/fan_tunnel.gd")
const BOUNCE_SCRIPT := preload("res://scripts/bounce_pad.gd")
const SHADOW_GUARDIAN_SCRIPT := preload("res://scripts/shadow_guardian.gd")
const MALAKAR_SCRIPT := preload("res://objects/malakar.gd")
const ANIMAL_SCENE := preload("res://objects/character.tscn")
const ISLAND_GRASS_TEXTURE := preload("res://assets/generated/malakar_island_grass.png")
const BUTTERFLY_TEXTURE := preload("res://assets/generated/island_butterfly.png")
const PLAYER_SCENE := preload("res://objects/player.tscn")

const LEVEL_NAMES := ["Cloud Hop", "Switchback Sprint", "Moonflip Maze", "Rising Ruins", "Malakar's Fortress", "Gimmick Gauntlet"]

@onready var player: CharacterBody3D = $Player
@onready var hud: Control = $HUD
@onready var world: Node3D = $World
@onready var finish: Area3D = $Finish

var current_level := 1
var coin_goal := 0
var puzzle_solved := false
var switches: Array[Node3D] = []
var gates: Array[Node3D] = []
var switches_pressed := 0
var mirror_dimension := false
var checkpoint_position := Vector3.ZERO
var active_checkpoint := 0
var _castle_spawn := Vector3.ZERO

# Local split-screen co-op
var local_coop := false
var player_two: CharacterBody3D
var coins_collected := 0

# Online co-op (ENet)
var online := false
var remote_players: Dictionary = {}
# Dimension shift constraints
var dimension_shifts_left := 2
var shift_timer := 0.0
var shift_active := false


func _ready() -> void:
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_node("/root/Audio").play_music("res://sounds/itty_bitty.mp3")
	$Sun.light_color = Color("#fff2d6")
	_ensure_key_action("interact", KEY_E, JOY_BUTTON_X)
	_ensure_key_action("time_freeze", KEY_F, JOY_BUTTON_Y)
	_ensure_key_action("shift_dimension", KEY_Q, JOY_BUTTON_LEFT_SHOULDER, MOUSE_BUTTON_RIGHT)
	current_level = int(get_tree().get_meta("level_number", 1))
	current_level = clampi(current_level, 1, LEVEL_NAMES.size())
	if current_level == 5:
		dimension_shifts_left = 4
	get_tree().set_meta("level_number", current_level)
	local_coop = bool(get_tree().get_meta("local_coop", false))
	online = bool(get_tree().get_meta("online", false))
	var resuming := bool(get_tree().get_meta("resume_save", false))

	_build_level(current_level)

	# CONTINUE PROGRESS restores the exact spot that was saved on this level.
	var settings = get_node_or_null("/root/Settings")
	if resuming and settings and int(settings.get_saved_level()) == current_level:
		var saved_position: Vector3 = settings.get_saved_position()
		if saved_position != Vector3.ZERO:
			player.global_position = saved_position
			player.rotation.y = settings.get_saved_rotation_y()
			player.velocity = Vector3.ZERO
			checkpoint_position = saved_position
			active_checkpoint = 0
	# Remember where this level was entered from. The pause menu can update it.
	if settings:
		settings.save_progress(current_level, player.global_position, player.rotation.y)
	coin_goal = get_tree().get_nodes_in_group("collectible_coins").size()
	hud.set_coin_goal(coin_goal)
	hud.set_level_info(current_level, LEVEL_NAMES[current_level - 1])
	hud.show_finish_message("RIGHT CLICK / Q / %s: SHIFT DIMENSION" % InputPrompts.glyph("shift_dimension"))
	hud.continue_pressed.connect(_on_continue_pressed)
	player.coin_collected.connect(_on_coin_collected)
	player.died.connect(_on_player_died.bind(player))
	hud.retry_pressed.connect(_on_retry_pressed)
	hud.menu_pressed.connect(_go_to_menu)
	hud.save_pressed.connect(_on_save_pressed)
	finish.body_entered.connect(_on_finish_body_entered)
	_apply_dimension_visibility()
	hud.show_controls_hint()
	if current_level == 5:
		hud.show_finish_message("Teleported to Malakar's island — parkour up to the fortress!")

	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		$Sun.light_energy = 0.24
		$Sun.shadow_opacity = 0.85
		$Environment.environment.background_energy_multiplier = 0.25

	if local_coop:
		_setup_local_coop()
	elif online:
		_setup_online()


func _ensure_key_action(action_name: String, key_code: Key, joy_button: JoyButton, mouse_button: MouseButton = MOUSE_BUTTON_NONE) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
		InputMap.action_set_deadzone(action_name, 0.5)
	var has_key := false
	var has_button := false
	var has_mouse_button := false
	for existing_event in InputMap.action_get_events(action_name):
		if existing_event is InputEventKey and existing_event.physical_keycode == key_code:
			has_key = true
		elif existing_event is InputEventJoypadButton and existing_event.button_index == joy_button:
			has_button = true
		elif existing_event is InputEventMouseButton and existing_event.button_index == mouse_button:
			has_mouse_button = true
	if not has_key:
		var key := InputEventKey.new()
		key.physical_keycode = key_code
		key.device = -1
		InputMap.action_add_event(action_name, key)
	if not has_button:
		var button := InputEventJoypadButton.new()
		button.button_index = joy_button
		button.device = -1
		InputMap.action_add_event(action_name, button)
	if mouse_button != MOUSE_BUTTON_NONE and not has_mouse_button:
		var mouse_event := InputEventMouseButton.new()
		mouse_event.button_index = mouse_button
		mouse_event.device = -1
		InputMap.action_add_event(action_name, mouse_event)


func _ensure_key_binding(action_name: String, key_code: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
		InputMap.action_set_deadzone(action_name, 0.5)
	for existing_event in InputMap.action_get_events(action_name):
		if existing_event is InputEventKey and existing_event.physical_keycode == key_code:
			return
	var key := InputEventKey.new()
	key.physical_keycode = key_code
	key.device = -1
	InputMap.action_add_event(action_name, key)


func _build_level(level_number: int) -> void:
	switches.clear()
	gates.clear()
	switches_pressed = 0
	puzzle_solved = false
	var routes := _get_level_routes()
	var route: Array = routes[level_number - 1]
	for child in world.get_children():
		world.remove_child(child)
		child.free()
	_build_specials(level_number, route.size())

	for i in range(route.size()):
		var point: Vector3 = route[i]
		_add_main_platform(level_number, route, i, point)

		# The mirror path is offset, so shifting dimensions in mid-air creates alternate jumps.
		var mirror_platform: Node3D = PLATFORM_MEDIUM.instantiate()
		mirror_platform.name = "MirrorPlatform_%02d" % i
		mirror_platform.position = _get_mirror_platform_point(route, i)
		mirror_platform.rotation.y = -float((i * 23 + level_number * 17) % 50) * PI / 180.0
		if level_number == 1:
			mirror_platform.scale.y = 0.62
		mirror_platform.add_to_group("mirror_dimension")
		world.add_child(mirror_platform)
		_add_phase_glow(mirror_platform)

		if i > 0 and i < route.size() - 1:
			var coin: Area3D = COIN.instantiate()
			var coin_height := 1.1 + float(i % 2) * 0.3
			# Coins stay visible in both dimensions so the amount in the level
			# always matches the goal shown on the HUD.
			coin.position = point + Vector3(0, coin_height, 0)
			world.add_child(coin)

		if i % 3 == 1:
			var cloud := preload("res://objects/cloud.tscn").instantiate()
			cloud.position = point + Vector3(0, 1.2, 2.0)
			world.add_child(cloud)

	var goal: Vector3 = route[route.size() - 1]
	var flag: Node3D = FLAG.instantiate()
	flag.position = goal + Vector3(0, 0.45, 0)
	world.add_child(flag)
	player.position = route[0] + Vector3(0, 0.55, 0)
	player.velocity = Vector3.ZERO
	checkpoint_position = player.position
	active_checkpoint = 0
	for checkpoint_index in _get_checkpoint_indices(level_number, route.size()):
		_add_checkpoint(route[checkpoint_index], checkpoint_index)
	finish.position = goal + Vector3(0, 1.0, 0)
	if level_number in [1, 2, 4, 5]:
		@warning_ignore("integer_division")
		_add_anti_gravity_zone(route[route.size() / 2])
	_build_level_identity(level_number, route)
	_build_gimmicks(level_number, route)
	_build_puzzle(level_number, route)
	_apply_dimension_visibility()


func _get_checkpoint_indices(level_number: int, route_size: int) -> Array[int]:
	var second_checkpoint := route_size - 3
	if level_number == 3:
		# The maze folds close to its start near the end, so place the second marker earlier.
		second_checkpoint = route_size - 5
	return [2, second_checkpoint]


# --- Platform layout ---------------------------------------------------------
# Difficulty escalates every level: more platforms, more moving/phase/falling
# platforms and more switches. The special indices are spread evenly along the
# route so no two features collide.

var _special: Dictionary = {"moving": [], "phase": [], "falling": [], "see_saw": [], "log": [], "all": {}}


func _build_specials(level_number: int, n: int) -> void:
	_special = {"moving": [], "phase": [], "falling": [], "see_saw": [], "log": [], "all": {0: true, n - 1: true}}
	var moving := _spread(_moving_count(level_number), n, _special["all"])
	_special["moving"] = moving
	for i in moving:
		_special["all"][i] = true
	var phase := _spread(_phase_count(level_number), n, _special["all"])
	_special["phase"] = phase
	for i in phase:
		_special["all"][i] = true
	var falling := _spread(_falling_count(level_number), n, _special["all"])
	_special["falling"] = falling
	for i in falling:
		_special["all"][i] = true
	var see_saw := _spread(_see_saw_count(level_number), n, _special["all"])
	_special["see_saw"] = see_saw
	for i in see_saw:
		_special["all"][i] = true
	var log_indices := _spread(_log_count(level_number), n, _special["all"])
	_special["log"] = log_indices
	for i in log_indices:
		_special["all"][i] = true


## Evenly distributes count picks across route indices 1..n-2, walking outward from
## each target slot to the nearest free index so categories never overlap.
func _spread(count: int, n: int, blocked: Dictionary) -> Array[int]:
	var result: Array[int] = []
	if count <= 0 or n <= 3:
		return result
	for k in range(count):
		var target := 1 + int(round(float(k + 1) * float(n - 2) / float(count + 1)))
		for step in range(n):
			var up := target + step
			if up > 0 and up < n - 1 and not blocked.has(up) and not result.has(up):
				result.append(up)
				break
			var down := target - step
			if down > 0 and down < n - 1 and not blocked.has(down) and not result.has(down):
				result.append(down)
				break
	return result


func _moving_count(level_number: int) -> int:
	return [0, 2, 3, 4, 5, 2][level_number - 1]


func _phase_count(level_number: int) -> int:
	return [0, 0, 2, 3, 4, 2][level_number - 1]


func _falling_count(level_number: int) -> int:
	return [2, 3, 4, 5, 5, 3][level_number - 1]


func _see_saw_count(level_number: int) -> int:
	return [0, 0, 0, 0, 0, 3][level_number - 1]


func _log_count(level_number: int) -> int:
	return [0, 0, 0, 0, 0, 2][level_number - 1]


func _ring_count(level_number: int) -> int:
	return [3, 3, 4, 4, 5, 3][level_number - 1]


func _hurdle_count(level_number: int) -> int:
	return [0, 1, 2, 3, 4, 2][level_number - 1]


func _wall_count(level_number: int) -> int:
	return [0, 0, 1, 2, 3, 1][level_number - 1]


func _sweeper_count(level_number: int) -> int:
	return [2, 3, 4, 5, 6, 3][level_number - 1]


func _theme_tint(level_number: int) -> Color:
	match level_number:
		1: return Color("#83f5ef")
		2: return Color("#ff9b4b")
		3: return Color("#d79bff")
		4: return Color("#d6bd91")
		5: return Color("#ffd667")
	return Color("#9be86a")


func _add_main_platform(level_number: int, route: Array, i: int, point: Vector3) -> void:
	if level_number == 5:
		var fortress_platform: Node3D = PLATFORM_MEDIUM.instantiate() if i % 3 == 1 else PLATFORM_GRASS.instantiate()
		fortress_platform.name = "FortressRoute_%02d" % i
		fortress_platform.position = point
		fortress_platform.scale = Vector3(1.12, 1.0, 1.12)
		fortress_platform.add_to_group("material_dimension")
		world.add_child(fortress_platform)
		return
	if i in _special["moving"]:
		_add_moving_platform(route, i, point)
		return
	if i in _special["phase"]:
		_add_phase_platform(point)
		return
	if i in _special["see_saw"]:
		_add_see_saw(route, i, point)
		return
	if i in _special["log"]:
		_add_log(route, i, point)
		return
	var platform_scene := _platform_scene_for(level_number, i)
	var platform: Node3D = platform_scene.instantiate()
	platform.position = point
	platform.rotation.y = float((i * 23 + level_number * 17) % 50) * PI / 180.0
	if level_number == 1:
		platform.scale.y = 0.62
	platform.add_to_group("material_dimension")
	world.add_child(platform)


func _platform_scene_for(level_number: int, i: int) -> PackedScene:
	if i in _special["falling"]:
		return PLATFORM_FALLING
	match level_number:
		1:
			if i % 3 == 1:
				return PLATFORM_MEDIUM
			if i % 3 == 2:
				return PLATFORM_GRASS
		2:
			if i % 2 == 0:
				return PLATFORM_MEDIUM
		3:
			if i % 3 == 0:
				return PLATFORM_GRASS
			return PLATFORM_MEDIUM
		4:
			if i % 3 == 1:
				return PLATFORM_GRASS
		5:
			if i % 2 == 1:
				return PLATFORM_MEDIUM
	return PLATFORM

# --- New puzzle mechanics ----------------------------------------------------

func _add_moving_platform(route: Array, i: int, point: Vector3) -> void:
	var direction: Vector3
	if i < route.size() - 1:
		direction = route[i + 1] - route[i]
	else:
		direction = route[i] - route[i - 1]
	direction.y = 0.0
	direction = direction.normalized()
	var across := Vector3(-direction.z, 0.0, direction.x)
	var offset: Vector3 = across * (1.8 if i % 2 == 0 else -1.8)
	var platform := AnimatableBody3D.new()
	platform.name = "MovingPlatform"
	platform.set_script(MOVING_PLATFORM_SCRIPT)
	platform.position = point
	platform.set("move_offset", offset)
	platform.set("speed", 0.8 + float(i % 3) * 0.2)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.9, 0.5, 1.9)
	shape.shape = box
	shape.position.y = 0.25
	platform.add_child(shape)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.9, 0.5, 1.9)
	visual.mesh = mesh
	visual.position.y = 0.25
	visual.material_override = _map_material(Color("#54e0d0"), true)
	platform.add_child(visual)
	world.add_child(platform)


func _add_phase_platform(point: Vector3) -> void:
	var platform := AnimatableBody3D.new()
	platform.name = "PhasePlatform"
	platform.set_script(PHASE_PLATFORM_SCRIPT)
	platform.position = point
	platform.set("on_duration", 2.2)
	platform.set("off_duration", 1.6)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 0.5, 2.0)
	shape.shape = box
	shape.position.y = 0.25
	platform.add_child(shape)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.0, 0.5, 2.0)
	visual.mesh = mesh
	visual.position.y = 0.25
	var material := _map_material(Color("#c8a3ff"), true)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.78, 0.64, 1.0, 0.68)
	visual.material_override = material
	platform.add_child(visual)
	world.add_child(platform)

# --- Level 6 gimmicks --------------------------------------------------------

func _path_yaw(route: Array, i: int) -> float:
	var direction: Vector3
	if i <= 0:
		direction = route[1] - route[0]
	elif i >= route.size() - 1:
		direction = route[i] - route[i - 1]
	else:
		direction = route[i + 1] - route[i - 1]
	direction.y = 0.0
	return atan2(direction.x, direction.z)


func _add_see_saw(route: Array, i: int, point: Vector3) -> void:
	var see_saw := Node3D.new()
	see_saw.name = "SeeSaw"
	see_saw.position = point + Vector3(0, 0.55, 0)
	see_saw.rotation.y = _path_yaw(route, i)
	see_saw.set_script(SEE_SAW_SCRIPT)

	var plank := AnimatableBody3D.new()
	plank.name = "Plank"
	plank.sync_to_physics = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.7, 0.22, 2.8)
	shape.shape = box
	plank.add_child(shape)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.7, 0.22, 2.8)
	visual.mesh = mesh
	visual.material_override = _map_material(Color("#ffcf6b"))
	plank.add_child(visual)
	see_saw.add_child(plank)

	var fulcrum := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.16
	cone.bottom_radius = 0.32
	cone.height = 0.6
	fulcrum.mesh = cone
	fulcrum.position.y = -0.42
	fulcrum.material_override = _map_material(Color("#8a6a3a"))
	see_saw.add_child(fulcrum)

	world.add_child(see_saw)
	see_saw.configure(plank, player)


func _add_log(route: Array, i: int, point: Vector3) -> void:
	var log_roller := AnimatableBody3D.new()
	log_roller.name = "LogRoller"
	log_roller.set_script(ROTATING_LOG_SCRIPT)
	log_roller.position = point + Vector3(0, 0.42, 0)
	log_roller.rotation.y = _path_yaw(route, i)
	log_roller.set("spin_speed", 2.5)
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.42
	cylinder.height = 2.6
	shape.shape = cylinder
	shape.rotation = Vector3(0, 0, PI / 2.0)
	log_roller.add_child(shape)
	var visual := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.42
	mesh.bottom_radius = 0.42
	mesh.height = 2.6
	visual.mesh = mesh
	visual.rotation = Vector3(0, 0, PI / 2.0)
	visual.material_override = _map_material(Color("#b07a3c"))
	log_roller.add_child(visual)
	world.add_child(log_roller)


func _add_barrel(route: Array, i: int, point: Vector3) -> void:
	var direction: Vector3 = route[i + 1] - route[i] if i < route.size() - 1 else route[i] - route[i - 1]
	direction.y = 0.0
	var barrel := AnimatableBody3D.new()
	barrel.name = "RollingBarrel"
	barrel.set_script(ROLLING_BARREL_SCRIPT)
	barrel.position = point + Vector3(0, 0.55, 0)
	barrel.rotation.y = _path_yaw(route, i)
	barrel.set("move_offset", direction.normalized() * 3.2)
	barrel.set("move_speed", 1.0 + float(i % 3) * 0.25)
	barrel.set("roll_speed", 4.0)
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.45
	cylinder.height = 1.0
	shape.shape = cylinder
	shape.rotation = Vector3(0, 0, PI / 2.0)
	barrel.add_child(shape)
	var visual := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.45
	mesh.bottom_radius = 0.45
	mesh.height = 1.0
	visual.mesh = mesh
	visual.rotation = Vector3(0, 0, PI / 2.0)
	visual.material_override = _map_material(Color("#c47a3a"))
	barrel.add_child(visual)
	world.add_child(barrel)


func _add_zone(point: Vector3, size: Vector3, script: Script, tint: Color, y_offset: float = 0.5) -> Area3D:
	var zone := Area3D.new()
	zone.position = point + Vector3(0, y_offset, 0)
	zone.collision_layer = 0
	zone.collision_mask = 1
	zone.set_script(script)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	zone.add_child(shape)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.position.y = 0.0
	var material := _map_material(tint, true)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(tint.r, tint.g, tint.b, 0.45)
	visual.material_override = material
	zone.add_child(visual)
	world.add_child(zone)
	return zone


func _add_slide(route: Array, i: int, point: Vector3) -> void:
	var slide := StaticBody3D.new()
	slide.name = "Slide"
	slide.position = point + Vector3(0, 0.85, -1.2)
	slide.rotation.y = _path_yaw(route, i)
	slide.rotation.x = deg_to_rad(24.0)
	var size := Vector3(1.7, 0.16, 4.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	slide.add_child(shape)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	var material := _map_material(Color("#7fd8ff"))
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.5, 0.85, 1.0, 0.75)
	visual.material_override = material
	slide.add_child(visual)
	world.add_child(slide)
	# Slippery coating so the player actually slides down the ramp.
	_add_zone(point + Vector3(0, 0.4, -1.2), Vector3(2.0, 1.6, 4.2), SLIPPERY_SCRIPT, Color("#7fd8ff"), 0.0)


func _build_gimmicks(level_number: int, route: Array) -> void:
	if level_number == 5:
		_build_fortress(level_number, route)
		return
	if level_number != 6:
		return
	var n := route.size()
	var used: Dictionary = _special["all"].duplicate()

	var slippery := _spread(3, n, used)
	for index in slippery:
		used[index] = true
	for index in slippery:
		_add_zone(route[index], Vector3(2.4, 1.4, 2.4), SLIPPERY_SCRIPT, Color("#8fe0ff"))

	var sticky := _spread(2, n, used)
	for index in sticky:
		used[index] = true
	for index in sticky:
		_add_zone(route[index], Vector3(2.4, 1.4, 2.4), STICKY_SCRIPT, Color("#c0a06a"))

	var bounce := _spread(3, n, used)
	for index in bounce:
		used[index] = true
	for index in bounce:
		_add_zone(route[index], Vector3(2.0, 1.2, 2.0), BOUNCE_SCRIPT, Color("#ff8ad0"))
		_add_bounce_disc(route[index])

	var fans := _spread(2, n, used)
	for index in fans:
		used[index] = true
	for index in fans:
		_add_fan(route[index])

	var slides := _spread(1, n, used)
	for index in slides:
		used[index] = true
	for index in slides:
		_add_slide(route, index, route[index])

	var barrels := _spread(3, n, used)
	for index in barrels:
		used[index] = true
	for index in barrels:
		_add_barrel(route, index, route[index])


func _build_fortress(_level_number: int, route: Array) -> void:
	# Malakar's Fortress: a castle on a floating island the player is teleported into.
	var n: int = route.size()

	# The castle shell, island, great hall and parkour dressing.
	_build_castle(route)

	# Shadow Guardians patrol the halls.
	for fraction: float in [0.15, 0.40, 0.65, 0.85]:
		var index: int = clampi(roundi(float(n - 1) * fraction), 1, n - 2)
		_add_shadow_guardian(route[index] + Vector3(0, 0.6, 0))

	# Mirror rifts tear through the corridors.
	for fraction: float in [0.25, 0.55, 0.75]:
		var index: int = clampi(roundi(float(n - 1) * fraction), 1, n - 2)
		_add_fortress_rift(route, index)

	# The final fragment sits on an altar before the throne room.
	_add_fragment_altar(route[n - 3])

	# Throne room, the captured Eternal Tree, and Malakar himself.
	var goal: Vector3 = route[n - 1]
	_add_throne_room(goal)
	var tree: Node3D = _add_great_tree(goal + Vector3(-3.4, 0.5, 2.6))
	var boss: Node3D = MALAKAR_SCRIPT.new()
	boss.name = "Malakar"
	boss.position = goal + Vector3(4.2, 5.2, 0.0)
	boss.rotation.y = atan2(tree.position.x - boss.position.x, tree.position.z - boss.position.z)
	world.add_child(boss)
	boss.configure(tree.get_node("TreeCanopy"))

	# Spawn safely on the island terrace, facing the castle approach.
	player.global_position = _castle_spawn + Vector3(0, 0.55, 0)
	player.velocity = Vector3.ZERO
	checkpoint_position = player.global_position
	active_checkpoint = 0

func _add_shadow_guardian(point: Vector3) -> void:
	var guardian := Area3D.new()
	guardian.name = "ShadowGuardian"
	guardian.set_script(SHADOW_GUARDIAN_SCRIPT)
	guardian.position = point
	guardian.set("patrol_radius", 0.78)
	guardian.set("patrol_speed", 2.0)
	guardian.set("hover_height", 0.95)
	guardian.collision_layer = 0
	guardian.collision_mask = 1
	var shape_node := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.58
	shape_node.shape = sphere
	shape_node.position.y = 1.05
	guardian.add_child(shape_node)
	var orb := MeshInstance3D.new()
	var orb_mesh := SphereMesh.new()
	orb_mesh.radius = 0.46
	orb_mesh.height = 0.92
	orb.mesh = orb_mesh
	orb.position.y = 1.05
	orb.material_override = _map_material(Color("#241344"), true)
	guardian.add_child(orb)
	var eye := MeshInstance3D.new()
	var eye_mesh := BoxMesh.new()
	eye_mesh.size = Vector3(0.48, 0.1, 0.12)
	eye.mesh = eye_mesh
	eye.position = Vector3(0, 1.12, -0.4)
	eye.material_override = _map_material(Color("#ff315d"), true)
	guardian.add_child(eye)
	world.add_child(guardian)

func _add_fortress_rift(route: Array, index: int) -> void:
	var point: Vector3 = route[index]
	var direction: Vector3 = route[index + 1] - route[index]
	direction.y = 0.0
	var across := Vector3(-direction.z, 0.0, direction.x).normalized()
	var bridge_point := point + across * (1.0 if index % 2 == 0 else -1.0) + Vector3(0, 0.22, 0)
	var stone: Node3D = PLATFORM_MEDIUM.instantiate()
	stone.name = "MirrorRiftStone"
	stone.position = bridge_point
	stone.scale = Vector3(0.72, 0.8, 0.72)
	stone.add_to_group("mirror_dimension")
	world.add_child(stone)
	_add_phase_glow(stone)
	_add_map_ring(bridge_point + Vector3(0, 1.0, 0), 0.84, Color("#bd58ff"))

# --- Castle on an island -----------------------------------------------------

func _build_castle(route: Array) -> void:
	var min_x := 1e9
	var max_x := -1e9
	var min_z := 1e9
	var max_z := -1e9
	for point in route:
		var p: Vector3 = point
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	var cx := (min_x + max_x) * 0.5
	var cz := (min_z + max_z) * 0.5
	var floor_y := 2.0
	var terrace_y := 0.0
	var stone := Color("#4a4458")

	var half_x := (max_x - min_x) * 0.5 + 14.0
	var half_z := (max_z - min_z) * 0.5 + 14.0
	var wall_h := 12.0
	var wall_t := 0.9
	var top_y := floor_y + wall_h
	var front_z := cz - half_z

	# A large floating island with the castle raised on a plateau at its heart.
	_add_castle_island(Vector3(cx, terrace_y, cz), 58.0)
	_add_castle_block(Vector3(cx, (terrace_y + floor_y) * 0.5, cz), Vector3(half_x * 2.0 + 2.0, floor_y - terrace_y, half_z * 2.0 + 2.0), Color("#5a5470"))

	# Stone interior floor (the green island top shows as a ring outside the walls).
	_add_castle_block(Vector3(cx, floor_y - 0.13, cz), Vector3(half_x * 2.0 - 1.6, 0.3, half_z * 2.0 - 1.6), Color("#6b6a78"))
	_add_map_ring(Vector3(cx, floor_y + 0.1, cz), 6.0, Color("#8a7fb0"))
	_add_map_ring(Vector3(cx, floor_y + 0.1, cz - half_z * 0.5), 3.2, Color("#8a7fb0"))
	_add_map_ring(Vector3(cx, floor_y + 0.1, cz + half_z * 0.5), 3.2, Color("#8a7fb0"))

	# Curtain walls, with a gap in the front wall for the gate.
	var gate_half := 3.2
	var side_span := half_x - gate_half
	_add_castle_block(Vector3(cx - (gate_half + side_span * 0.5), floor_y + wall_h * 0.5, front_z), Vector3(side_span, wall_h, wall_t), stone)
	_add_castle_block(Vector3(cx + (gate_half + side_span * 0.5), floor_y + wall_h * 0.5, front_z), Vector3(side_span, wall_h, wall_t), stone)
	_add_castle_block(Vector3(cx, floor_y + wall_h * 0.5, cz + half_z), Vector3(half_x * 2.0, wall_h, wall_t), stone)
	_add_castle_block(Vector3(cx - half_x, floor_y + wall_h * 0.5, cz), Vector3(wall_t, wall_h, half_z * 2.0), stone)
	_add_castle_block(Vector3(cx + half_x, floor_y + wall_h * 0.5, cz), Vector3(wall_t, wall_h, half_z * 2.0), stone)

	# Battlements along every wall top (the front is split by the gate).
	_add_battlement_run(Vector3(cx - half_x, top_y, front_z), Vector3(cx - gate_half, top_y, front_z))
	_add_battlement_run(Vector3(cx + gate_half, top_y, front_z), Vector3(cx + half_x, top_y, front_z))
	_add_battlement_run(Vector3(cx - half_x, top_y, cz + half_z), Vector3(cx + half_x, top_y, cz + half_z))
	_add_battlement_run(Vector3(cx - half_x, top_y, front_z), Vector3(cx - half_x, top_y, cz + half_z))
	_add_battlement_run(Vector3(cx + half_x, top_y, front_z), Vector3(cx + half_x, top_y, cz + half_z))

	# Corner towers.
	for corner in [
		Vector3(cx - half_x, floor_y, cz - half_z),
		Vector3(cx + half_x, floor_y, cz - half_z),
		Vector3(cx - half_x, floor_y, cz + half_z),
		Vector3(cx + half_x, floor_y, cz + half_z),
	]:
		var tower_base: Vector3 = corner
		_add_castle_tower(tower_base, wall_h + 4.0, 2.6)

	# Great-hall columns and torch light along both long walls, kept out of the
	# middle of the hall so the third-person camera never clips them.
	for row in range(4):
		var row_z := cz - half_z + 8.0 + float(row) * ((half_z * 2.0 - 16.0) / 3.0)
		for side in [-1.0, 1.0]:
			var column_base := Vector3(cx + side * (half_x - 1.5), floor_y, row_z)
			_add_castle_pillar(column_base, wall_h - 1.5)
			if row % 2 == 0:
				_add_torch(column_base + Vector3(0, 4.0, 0))

	# Banners on the far wall.
	_add_banner(Vector3(cx - 3.0, floor_y + 7.0, cz - half_z + 0.6), 2.2, 3.4)
	_add_banner(Vector3(cx + 3.0, floor_y + 7.0, cz - half_z + 0.6), 2.2, 3.4)

	# Clear interior walkways connect the platform course without forcing precision beams.
	for index: int in [5, 11, 17, 23, 29]:
		if index + 1 < route.size():
			_add_balance_beam(route[index], route[index + 1])
	_add_castle_block(Vector3(cx, floor_y + 0.12, cz), Vector3(half_x * 1.25, 0.25, half_z * 1.3), Color("#625c70"))

	# Teleport arrival arch inside the entrance.
	_add_entrance_arch(route[0])

	# Grand gate in the front wall, the outdoor parkour approach, and the arrival point.
	_add_castle_gate(Vector3(cx, floor_y, front_z))
	_add_island_scatter(cx, cz, terrace_y)
	_add_island_waterfalls(cx, cz, terrace_y, 58.0)
	_add_island_grass(cx, cz, terrace_y, front_z)
	_add_approach(cx, front_z, floor_y, terrace_y)
	_add_island_parkour(cx, cz, terrace_y, half_x, half_z, front_z)
	_add_island_life(cx, cz, terrace_y, half_x, half_z, front_z)
	_add_fortress_life(cx, cz, floor_y, half_x, half_z, front_z)
	_castle_spawn = Vector3(cx, terrace_y + 1.0, front_z + 7.0)
	_add_map_ring(Vector3(cx, terrace_y + 0.2, front_z + 7.0), 2.2, Color("#ff5fd0"))


func _add_throne_room(goal: Vector3) -> void:
	# Raised dais with a throne and pillars behind the finish.
	_add_castle_block(goal + Vector3(0, 0.1, 0), Vector3(8.0, 0.8, 8.0), Color("#5a5470"))
	for offset in [Vector3(-3.2, 0, -3.2), Vector3(3.2, 0, -3.2), Vector3(-3.2, 0, 3.2), Vector3(3.2, 0, 3.2)]:
		var corner_offset: Vector3 = offset
		_add_castle_pillar(goal + corner_offset + Vector3(0, 0.5, 0), 6.0)
	_add_castle_block(goal + Vector3(0, 0.9, -3.0), Vector3(1.8, 0.8, 1.8), Color("#2a2436"))
	_add_castle_block(goal + Vector3(0, 2.2, -3.6), Vector3(2.0, 3.2, 0.4), Color("#2a2436"))
	_add_castle_deco(_box_mesh(Vector3(2.2, 0.2, 0.5)), goal + Vector3(0, 3.9, -3.6), Color("#f6c945"), true)


func _add_castle_island(center: Vector3, radius: float) -> void:
	var top_body := StaticBody3D.new()
	top_body.name = "IslandTop"
	top_body.position = Vector3(center.x, center.y - 0.5, center.z)
	var collision := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = 1.0
	collision.shape = cylinder
	top_body.add_child(collision)
	var visual := MeshInstance3D.new()
	var top_mesh := CylinderMesh.new()
	top_mesh.bottom_radius = radius
	top_mesh.top_radius = radius
	top_mesh.height = 1.0
	visual.mesh = top_mesh
	var grass_material := StandardMaterial3D.new()
	grass_material.albedo_color = Color("#a7d35d")
	grass_material.albedo_texture = load("res://assets/generated/fortress_grass_tile.png")
	grass_material.roughness = 0.9
	visual.material_override = grass_material
	top_body.add_child(visual)
	world.add_child(top_body)

	var rock_mesh := CylinderMesh.new()
	rock_mesh.bottom_radius = radius * 0.32
	rock_mesh.top_radius = radius
	rock_mesh.height = 8.0
	_add_castle_deco(rock_mesh, Vector3(center.x, center.y - 5.0, center.z), Color("#5a4a5f"))
	var skirt_mesh := CylinderMesh.new()
	skirt_mesh.bottom_radius = radius * 1.02
	skirt_mesh.top_radius = radius * 0.99
	skirt_mesh.height = 0.6
	_add_castle_deco(skirt_mesh, Vector3(center.x, center.y - 1.1, center.z), Color("#5f7a45"))


func _add_castle_block(point: Vector3, size: Vector3, tint: Color, emissive: bool = false) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "CastleBlock"
	body.position = point
	var collision := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	collision.shape = box_shape
	body.add_child(collision)
	var visual := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	visual.mesh = box
	visual.material_override = _map_material(tint, emissive)
	body.add_child(visual)
	world.add_child(body)
	return body


func _add_castle_deco(mesh: Mesh, point: Vector3, tint: Color, emissive: bool = false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "CastleDeco"
	node.mesh = mesh
	node.material_override = _map_material(tint, emissive)
	node.position = point
	world.add_child(node)
	return node


func _add_castle_pillar(base: Vector3, height: float) -> void:
	var body := StaticBody3D.new()
	body.name = "CastlePillar"
	body.position = base + Vector3(0, height * 0.5, 0)
	var collision := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.5
	cylinder.height = height
	collision.shape = cylinder
	body.add_child(collision)
	var visual := MeshInstance3D.new()
	var shaft := CylinderMesh.new()
	shaft.bottom_radius = 0.55
	shaft.top_radius = 0.45
	shaft.height = height
	visual.mesh = shaft
	visual.material_override = _map_material(Color("#5a5470"))
	body.add_child(visual)
	world.add_child(body)
	var cap_mesh := _box_mesh(Vector3(1.2, 0.4, 1.2))
	_add_castle_deco(cap_mesh, base + Vector3(0, height - 0.2, 0), Color("#6a6480"))
	_add_castle_deco(cap_mesh, base + Vector3(0, 0.2, 0), Color("#6a6480"))


func _add_castle_tower(base: Vector3, height: float, radius: float) -> void:
	var body := StaticBody3D.new()
	body.name = "CastleTower"
	body.position = base + Vector3(0, height * 0.5, 0)
	var collision := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = height
	collision.shape = cylinder
	body.add_child(collision)
	var visual := MeshInstance3D.new()
	var shaft := CylinderMesh.new()
	shaft.bottom_radius = radius
	shaft.top_radius = radius * 0.94
	shaft.height = height
	visual.mesh = shaft
	visual.material_override = _map_material(Color("#3a3446"))
	body.add_child(visual)
	world.add_child(body)
	for i in range(10):
		var angle := TAU * float(i) / 10.0
		_add_castle_deco(_box_mesh(Vector3(0.5, 0.7, 0.5)), base + Vector3(sin(angle) * radius, height + 0.35, cos(angle) * radius), Color("#2f2b3a"))
	var roof_mesh := CylinderMesh.new()
	roof_mesh.bottom_radius = radius + 0.35
	roof_mesh.top_radius = 0.0
	roof_mesh.height = height * 0.28
	_add_castle_deco(roof_mesh, base + Vector3(0, height + 0.7 + height * 0.14, 0), Color("#7a2f5a"), true)


func _add_battlement_run(from_point: Vector3, to_point: Vector3) -> void:
	var direction := to_point - from_point
	var length := direction.length()
	if length < 0.1:
		return
	var step := 1.7
	var count := int(length / step)
	for i in range(count + 1):
		if i % 2 == 1:
			continue
		var t := float(i) / float(maxi(count, 1))
		var p := from_point.lerp(to_point, t)
		_add_castle_deco(_box_mesh(Vector3(0.7, 0.9, 0.7)), p + Vector3(0, 0.45, 0), Color("#332e42"))


func _add_torch(point: Vector3) -> void:
	_add_castle_deco(_box_mesh(Vector3(0.12, 0.4, 0.12)), point, Color("#241f2e"))
	_add_castle_deco(_sphere_mesh(0.16), point + Vector3(0, 0.42, 0), Color("#ffb054"), true)
	var light := OmniLight3D.new()
	light.name = "TorchLight"
	light.light_color = Color("#ffa64d")
	light.light_energy = 1.4
	light.omni_range = 8.0
	light.position = point + Vector3(0, 0.5, 0)
	world.add_child(light)


func _add_banner(point: Vector3, width: float, height: float) -> void:
	_add_castle_deco(_box_mesh(Vector3(width, height, 0.08)), point, Color("#3a1f5e"))
	_add_castle_deco(_box_mesh(Vector3(width + 0.25, 0.14, 0.14)), point + Vector3(0, height * 0.5 + 0.07, 0), Color("#f6c945"), true)


func _add_balance_beam(from_point: Vector3, to_point: Vector3) -> void:
	var direction := to_point - from_point
	var mid := (from_point + to_point) * 0.5 + Vector3(0, 0.35, 0)
	var beam := _add_castle_block(mid, Vector3(0.7, 0.25, direction.length() + 0.6), Color("#6a6480"))
	beam.rotation.y = atan2(direction.x, direction.z)


func _add_entrance_arch(point: Vector3) -> void:
	# Framed gateway where the player is teleported in, with a glowing portal.
	_add_castle_deco(_box_mesh(Vector3(0.6, 5.0, 0.6)), point + Vector3(-2.4, 2.5, -2.2), Color("#3a3446"))
	_add_castle_deco(_box_mesh(Vector3(0.6, 5.0, 0.6)), point + Vector3(2.4, 2.5, -2.2), Color("#3a3446"))
	_add_castle_deco(_box_mesh(Vector3(5.4, 0.7, 0.7)), point + Vector3(0, 5.2, -2.2), Color("#7a2f5a"), true)
	_add_castle_deco(_sphere_mesh(1.6), point + Vector3(0, 2.4, -2.2), Color("#b13fff"))
	_add_map_ring(point + Vector3(0, 1.2, -2.2), 1.6, Color("#ff5fd0"))


func _box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _sphere_mesh(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	return mesh


func _add_castle_gate(point: Vector3) -> void:
	_add_castle_block(point + Vector3(-3.7, 3.5, 0), Vector3(0.9, 7.0, 1.3), Color("#3a3446"))
	_add_castle_block(point + Vector3(3.7, 3.5, 0), Vector3(0.9, 7.0, 1.3), Color("#3a3446"))
	_add_castle_deco(_box_mesh(Vector3(8.6, 1.0, 1.5)), point + Vector3(0, 7.6, 0), Color("#7a2f5a"), true)
	for i in range(6):
		_add_castle_deco(_box_mesh(Vector3(0.12, 3.6, 0.12)), point + Vector3(-2.5 + float(i), 3.6, 0), Color("#6a6480"))


func _add_island_scatter(cx: float, cz: float, terrace_y: float) -> void:
	for rock in [
		Vector2(cx - 34.0, cz - 20.0),
		Vector2(cx + 36.0, cz - 12.0),
		Vector2(cx - 38.0, cz + 14.0),
		Vector2(cx + 40.0, cz + 10.0),
		Vector2(cx - 20.0, cz - 34.0),
		Vector2(cx + 24.0, cz - 30.0),
	]:
		var point: Vector2 = rock
		var rock_mesh := CylinderMesh.new()
		rock_mesh.bottom_radius = 2.2
		rock_mesh.top_radius = 0.6
		rock_mesh.height = 3.0
		_add_castle_deco(rock_mesh, Vector3(point.x, terrace_y + 1.4, point.y), Color("#5a4a5f"))
		_add_castle_deco(_sphere_mesh(1.3), Vector3(point.x, terrace_y + 2.8, point.y), Color("#6a5a6f"))


func _add_island_waterfalls(cx: float, cz: float, terrace_y: float, island_radius: float) -> void:
	var water_material := StandardMaterial3D.new()
	water_material.albedo_color = Color(0.24, 0.78, 0.96, 0.72)
	water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	water_material.emission_enabled = true
	water_material.emission = Color("#53cfff")
	water_material.emission_energy_multiplier = 0.7
	for index in range(3):
		var angle := -PI * 0.5 + float(index) * TAU / 3.0
		var fall := MeshInstance3D.new()
		fall.name = "IslandWaterfall_%02d" % index
		var water_mesh := BoxMesh.new()
		water_mesh.size = Vector3(2.8, 7.0, 0.18)
		fall.mesh = water_mesh
		fall.material_override = water_material.duplicate()
		fall.position = Vector3(cx + cos(angle) * (island_radius - 0.5), terrace_y - 4.1, cz + sin(angle) * (island_radius - 0.5))
		fall.rotation.y = -angle
		world.add_child(fall)
		var foam := MeshInstance3D.new()
		foam.name = "WaterfallFoam_%02d" % index
		var foam_mesh := BoxMesh.new()
		foam_mesh.size = Vector3(3.2, 0.22, 0.32)
		foam.mesh = foam_mesh
		foam.position = fall.position + Vector3(0, 3.5, 0)
		foam.rotation.y = -angle
		foam.material_override = _map_material(Color("#d6fbff"), true)
		world.add_child(foam)


func _add_island_grass(cx: float, cz: float, terrace_y: float, front_z: float) -> void:
	var grass_material := _map_material(Color("#6da943"))
	for i in range(90):
		var angle := float(i) * 2.399963
		var radius := 7.0 + float((i * 17) % 420) / 10.0
		var x := cx + cos(angle) * radius
		var z := cz + sin(angle) * radius
		if radius > 49.0 or (absf(x - cx) < 5.0 and z < front_z + 5.0):
			continue
		var tuft := MeshInstance3D.new()
		tuft.name = "IslandGrassTuft_%02d" % i
		var blade := PrismMesh.new()
		blade.size = Vector3(0.12, 0.34 + float(i % 3) * 0.06, 0.12)
		tuft.mesh = blade
		tuft.material_override = grass_material
		tuft.position = Vector3(x, terrace_y + 0.18, z)
		tuft.rotation.y = angle
		world.add_child(tuft)


func _add_approach(cx: float, front_z: float, floor_y: float, terrace_y: float) -> void:
	# Broad, evenly spaced steps lead directly from the arrival terrace to the gate.
	var count := 8
	for i in range(count):
		var x := cx + sin(float(i) * 0.72) * 1.0
		var z := front_z - 28.0 + float(i) * 3.2
		var top_y := terrace_y + 0.5 + float(i) * ((floor_y - terrace_y + 0.5) / float(count - 1))
		var step: Node3D = PLATFORM_GRASS.instantiate() if i % 3 == 0 else PLATFORM_MEDIUM.instantiate()
		step.name = "GateApproach_%02d" % i
		step.position = Vector3(x, top_y - 0.5, z)
		if i % 2 == 1:
			step.scale = Vector3(0.82, 1.0, 0.82)
		world.add_child(step)
	# A ruined archway partway along the climb.
	_add_castle_deco(_box_mesh(Vector3(0.5, 3.0, 0.5)), Vector3(cx - 6.0, terrace_y + 2.5, front_z - 17.5), Color("#4a4458"))
	_add_castle_deco(_box_mesh(Vector3(0.5, 3.0, 0.5)), Vector3(cx + 6.0, terrace_y + 2.5, front_z - 17.5), Color("#4a4458"))
	_add_castle_deco(_box_mesh(Vector3(12.5, 0.6, 0.6)), Vector3(cx, terrace_y + 4.0, front_z - 17.5), Color("#4a4458"))


func _add_island_parkour(cx: float, cz: float, terrace_y: float, _half_x: float, _half_z: float, front_z: float) -> void:
	# A rounded grass-platform loop, matching the other levels' jumping surfaces.
	var path_radius := 30.0
	for i in range(64):
		var angle := TAU * float(i) / 64.0
		var step: Node3D = PLATFORM_GRASS.instantiate() if i % 4 == 0 else PLATFORM_MEDIUM.instantiate()
		step.name = "IslandLoopPlatform_%02d" % i
		step.position = Vector3(cx + cos(angle) * path_radius, terrace_y - 0.5 + sin(angle * 2.0) * 0.04, cz + sin(angle) * path_radius)
		step.rotation.y = -angle
		step.scale = Vector3(0.78, 1.0, 0.78)
		world.add_child(step)
		if i % 8 == 0:
			_add_map_ring(step.position + Vector3(0, 0.48, 0), 0.8, Color("#85e5ce"))
	# Floating stepping route uses the same modeled grass platforms as the other courses.
	for i in range(10):
		var t := float(i) / 9.0
		var z := front_z - 30.0 + t * 32.0
		var x := cx + sin(float(i) * 0.85) * 1.4
		var top_y := terrace_y + 0.5 + t * 1.5
		var step: Node3D = PLATFORM_GRASS.instantiate() if i % 3 == 0 else PLATFORM_MEDIUM.instantiate()
		step.name = "IslandParkour_%02d" % i
		step.position = Vector3(x, top_y - 0.5, z)
		if i % 2 == 1:
			step.scale = Vector3(0.82, 1.0, 0.82)
		world.add_child(step)
		if i % 3 == 1:
			_add_map_ring(Vector3(x, top_y + 0.05, z), 0.75, Color("#f4d779"))
	# Optional lift rings stay close to the island surface and outside the main approach.
	for point in [Vector3(cx - 31.0, terrace_y + 0.1, cz + 28.0), Vector3(cx + 30.0, terrace_y + 0.1, cz - 24.0)]:
		_add_fan(point)
	# Low stone markers identify the outer loop without tall floating posts.
	for i in range(10):
		var angle := TAU * float(i) / 10.0
		var point := Vector3(cx + cos(angle) * 45.0, terrace_y, cz + sin(angle) * 45.0)
		_add_castle_deco(_sphere_mesh(0.42), point + Vector3(0, 0.25, 0), Color("#6a6480"))


func _add_island_life(cx: float, cz: float, terrace_y: float, _half_x: float, _half_z: float, front_z: float) -> void:
	# A clear travel lane from the spawn, with garden clusters off either side.
	for i in range(12):
		var angle := TAU * float(i) / 12.0
		var radius := 22.0 + float(i % 3) * 3.0
		var point := Vector3(cx + cos(angle) * radius, terrace_y + 0.02, cz + sin(angle) * radius)
		_add_island_tree(point, 2.0 + float(i % 3) * 0.25, Color("#5e9a62" if i % 2 == 0 else "#9bbd65"))
		for flower_index in range(4):
			var flower_angle := angle + float(flower_index) * TAU / 4.0
			var flower_point := point + Vector3(cos(flower_angle) * 1.5, 0.14, sin(flower_angle) * 1.5)
			_add_castle_deco(_sphere_mesh(0.12), flower_point, [Color("#ffe285"), Color("#ff91bd"), Color("#d5a5ff")][(i + flower_index) % 3], true)
		if i % 2 == 0:
			_add_butterfly(point + Vector3(sin(angle) * 1.4, 2.0 + float(i % 3) * 0.3, cos(angle) * 1.4), float(i) * 0.7)
	# Small flower/tree clusters beside, never on, the safe approach route.
	for i in range(10):
		var row := floori(float(i) / 5.0)
		var column := i % 5
		var x := cx - 13.0 + float(column) * 6.5
		var z := cz - 15.0 + float(row) * 16.0
		if absf(x - cx) < 5.0 and absf(z - front_z) < 12.0:
			continue
		_add_island_tree(Vector3(x, terrace_y + 0.05, z), 1.7 + float(i % 3) * 0.2, Color("#5e9a62"))
	# Calm, walking wildlife: the existing animated raccoon character scene.
	for i in range(7):
		var animal: Node3D = ANIMAL_SCENE.instantiate()
		animal.name = "IslandRaccoon_%02d" % i
		var angle := TAU * float(i) / 7.0
		var animal_radius := 16.0 + float(i % 3) * 2.0
		animal.position = Vector3(cx + cos(angle) * animal_radius, terrace_y + 0.5, cz + sin(angle) * animal_radius)
		animal.scale = Vector3(0.72, 0.72, 0.72)
		world.add_child(animal)
		var stroll := create_tween().set_loops()
		stroll.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		stroll.tween_property(animal, "position", animal.position + Vector3(cos(angle + 1.3) * 3.2, 0, sin(angle + 1.3) * 3.2), 3.5 + float(i % 3))
		stroll.tween_property(animal, "position", animal.position - Vector3(cos(angle + 1.3) * 3.2, 0, sin(angle + 1.3) * 3.2), 3.5 + float(i % 3))
		# Visible gold food crumbs guide toward the animals.
		_add_map_ring(animal.position + Vector3(0, 0.1, 0), 0.48, Color("#f3d579"))


func _add_butterfly(point: Vector3, phase: float) -> void:
	var root := Node3D.new()
	root.name = "IslandButterfly"
	root.position = point
	root.set_meta("fly_phase", phase)
	var sprite := Sprite3D.new()
	sprite.texture = BUTTERFLY_TEXTURE
	sprite.pixel_size = 0.006
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.modulate = Color(1.0, 1.0, 1.0, 0.96)
	root.add_child(sprite)
	world.add_child(root)
	var flight := create_tween().set_loops()
	flight.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	flight.tween_property(root, "position", point + Vector3(1.2, 0.7, 1.5), 1.4 + fmod(phase, 0.5))
	flight.tween_property(root, "position", point + Vector3(-1.1, 0.2, -1.3), 1.6 + fmod(phase, 0.4))
	flight.tween_property(root, "position", point, 1.3)


func _add_island_tree(point: Vector3, height: float, foliage_color: Color) -> void:
	var trunk := CylinderMesh.new()
	trunk.bottom_radius = 0.16
	trunk.top_radius = 0.1
	trunk.height = height * 0.78
	_add_castle_deco(trunk, point + Vector3(0, height * 0.39, 0), Color("#725038"))
	var foliage_sizes: Array[float] = [0.72, 0.62, 0.58]
	var foliage_points: Array[Vector3] = [Vector3(0, height * 0.78, 0), Vector3(-0.4, height * 0.68, 0.12), Vector3(0.38, height * 0.7, -0.12)]
	for index in range(foliage_points.size()):
		_add_castle_deco(_sphere_mesh(foliage_sizes[index]), point + foliage_points[index], foliage_color)
	var blossom_points: Array[Vector3] = [Vector3(-0.48, height * 0.76, 0.12), Vector3(0.46, height * 0.82, -0.12)]
	for index in range(blossom_points.size()):
		_add_castle_deco(_sphere_mesh(0.09), point + blossom_points[index], Color("#ffd7e3"), true)


func _add_fortress_life(cx: float, cz: float, floor_y: float, half_x: float, half_z: float, front_z: float) -> void:
	# Weapon racks, braziers, rugs, benches, treasure, and warm pools of light.
	for row in range(5):
		var z := cz - half_z + 7.0 + float(row) * 9.0
		_add_castle_block(Vector3(cx, floor_y + 0.08, z), Vector3(3.6, 0.12, 5.0), Color("#3c254f"))
		_add_castle_deco(_box_mesh(Vector3(2.6, 0.04, 0.16)), Vector3(cx, floor_y + 0.17, z), Color("#d5aa51"), true)
		for side: float in [-1.0, 1.0]:
			var x: float = cx + side * (half_x - 3.3)
			_add_brazier(Vector3(x, floor_y, z + 2.6))
	# Armor stands and weapon racks along the walls.
	for side in [-1.0, 1.0]:
		for row in range(3):
			var z: float = cz - 8.0 + float(row) * 13.0
			var x: float = cx + side * (half_x - 2.2)
			_add_castle_block(Vector3(x, floor_y + 0.8, z), Vector3(0.22, 1.6, 0.22), Color("#8c6b46"))
			_add_castle_block(Vector3(x, floor_y + 1.2, z), Vector3(1.0, 0.13, 0.18), Color("#ba9457"))
			_add_castle_deco(_box_mesh(Vector3(0.12, 1.2, 0.12)), Vector3(x, floor_y + 2.0, z), Color("#b3d8e8"), true)
	# Seating nooks, side tables and glowing crystals near the rear hall.
	for side in [-1.0, 1.0]:
		var x: float = cx + side * 8.0
		_add_castle_block(Vector3(x, floor_y + 0.55, cz + 2.0), Vector3(3.2, 0.5, 1.2), Color("#463044"))
		_add_castle_deco(_box_mesh(Vector3(3.2, 0.16, 1.2)), Vector3(x, floor_y + 0.9, cz + 2.0), Color("#8b456c"))
		_add_castle_deco(_sphere_mesh(0.7), Vector3(x, floor_y + 1.6, cz + 2.0), Color("#8ce7de"), true)
	# More banners, sconces and a bright entry rug facing the gate.
	_add_banner(Vector3(cx - half_x + 0.8, floor_y + 7.0, cz + half_z - 0.7), 2.3, 3.5)
	_add_banner(Vector3(cx + half_x - 0.8, floor_y + 7.0, cz + half_z - 0.7), 2.3, 3.5)
	_add_castle_block(Vector3(cx, floor_y + 0.08, front_z + 7.0), Vector3(7.5, 0.16, 13.0), Color("#6f315a"))
	for i in range(6):
		var z := cz - half_z + 5.0 + float(i) * 10.0
		_add_wall_sconce(Vector3(cx - half_x + 1.3, floor_y + 4.5, z), -1.0)
		_add_wall_sconce(Vector3(cx + half_x - 1.3, floor_y + 4.5, z), 1.0)


func _add_brazier(point: Vector3) -> void:
	_add_castle_deco(_box_mesh(Vector3(1.0, 1.0, 1.0)), point + Vector3(0, 0.5, 0), Color("#332b3d"))
	_add_castle_deco(_box_mesh(Vector3(0.78, 0.16, 0.78)), point + Vector3(0, 1.05, 0), Color("#7f5366"))
	_add_castle_deco(_sphere_mesh(0.38), point + Vector3(0, 1.55, 0), Color("#ff8c40"), true)
	var light := OmniLight3D.new()
	light.light_color = Color("#ff8b48")
	light.light_energy = 1.6
	light.omni_range = 7.0
	light.position = point + Vector3(0, 1.7, 0)
	world.add_child(light)


func _add_wall_sconce(point: Vector3, facing: float) -> void:
	_add_castle_deco(_box_mesh(Vector3(0.16, 0.6, 0.16)), point, Color("#4a3a4e"))
	_add_castle_deco(_sphere_mesh(0.24), point + Vector3(0, 0.45, 0), Color("#ffba64"), true)
	var light := OmniLight3D.new()
	light.light_color = Color("#ffad5b")
	light.light_energy = 0.8
	light.omni_range = 5.5
	light.position = point + Vector3(facing * -0.4, 0.4, 0)
	world.add_child(light)


func _add_fragment_altar(point: Vector3) -> void:
	_add_solid_map_box(point + Vector3(0, 0.8, 0), Vector3(1.2, 0.6, 1.2), Color("#49335d"))
	var fragment := MeshInstance3D.new()
	fragment.name = "EternalTreeFragment"
	var shard := PrismMesh.new()
	shard.size = Vector3(0.42, 0.85, 0.42)
	fragment.mesh = shard
	fragment.position = point + Vector3(0, 1.75, 0)
	fragment.material_override = _map_material(Color("#74ffe2"), true)
	world.add_child(fragment)
	_add_map_ring(point + Vector3(0, 1.25, 0), 0.7, Color("#74ffe2"))


func _add_great_tree(point: Vector3) -> Node3D:
	# The Eternal Tree: Malakar's staff drains its light with a magenta beam.
	var tree := Node3D.new()
	tree.name = "GreatTree"
	tree.position = point

	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.bottom_radius = 0.5
	trunk_mesh.top_radius = 0.34
	trunk_mesh.height = 3.6
	trunk.mesh = trunk_mesh
	trunk.position.y = 1.8
	trunk.material_override = _map_material(Color("#3d2a1c"))
	tree.add_child(trunk)

	for blob in [
		[Vector3(0, 4.25, 0), 1.4],
		[Vector3(0, 5.35, 0), 1.1],
		[Vector3(0.62, 4.75, 0.32), 0.95],
		[Vector3(-0.62, 4.75, -0.32), 0.95],
		[Vector3(0.1, 5.9, -0.2), 0.8],
	]:
		var foliage := MeshInstance3D.new()
		var blob_mesh := SphereMesh.new()
		var radius: float = blob[1]
		blob_mesh.radius = radius
		blob_mesh.height = radius * 2.0
		foliage.mesh = blob_mesh
		foliage.position = blob[0]
		foliage.material_override = _map_material(Color("#7a3fb0"), true)
		tree.add_child(foliage)

	var canopy := Node3D.new()
	canopy.name = "TreeCanopy"
	canopy.position = Vector3(0, 5.4, 0)
	tree.add_child(canopy)
	world.add_child(tree)
	return tree


func _add_bounce_disc(point: Vector3) -> void:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.9
	mesh.bottom_radius = 0.9
	mesh.height = 0.12
	disc.mesh = mesh
	disc.position = point + Vector3(0, 0.56, 0)
	disc.material_override = _map_material(Color("#ff5fb8"), true)
	world.add_child(disc)


func _add_fan(point: Vector3) -> void:
	# Tall wind column; the FanTunnel area lifts the player while inside.
	_add_zone(point, Vector3(2.2, 7.0, 2.2), FAN_SCRIPT, Color("#bff4ff"), 3.4)
	_add_fan_ring(point + Vector3(0, 0.6, 0))


func _add_fan_ring(point: Vector3) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.7
	torus.outer_radius = 0.92
	ring.mesh = torus
	ring.rotation.x = PI / 2.0
	ring.position = point
	ring.material_override = _map_material(Color("#9be8ff"), true)
	world.add_child(ring)


# --- Locked gate + lever puzzle ---------------------------------------------

func _build_puzzle(level_number: int, route: Array) -> void:
	var n := route.size()
	# Twin-button puzzle: one button near the start, one near the flag, with a
	# locked inner gate in the middle. The first button opens the inner gate,
	# the second opens the final gate to the flag. Complex platforms and hazards
	# fill the whole stretch between the two buttons.
	var inner := _inner_gate_segment(route)
	_add_gate(route[inner], route[inner + 1])
	_add_gate(route[n - 2], route[n - 1])
	for index in _pick_switch_indices(level_number, n):
		_add_lever(route[index])


## Picks the row-transition segment nearest the middle of the course, where an
## inner gate can block all forward progress.
func _inner_gate_segment(route: Array) -> int:
	var n := route.size()
	var middle := floori(n / 2.0)
	var best := clampi(middle, 1, n - 2)
	var best_distance := n + 1
	for m in range(1, n - 2):
		var direction: Vector3 = route[m + 1] - route[m]
		if absf(direction.z) > absf(direction.x):
			var distance := absi(m - middle)
			if distance < best_distance:
				best_distance = distance
				best = m
	return best


func _pick_switch_indices(level_number: int, n: int) -> Array[int]:
	# One button as close to the start as possible, one as close to the flag as
	# possible, so the two buttons are always far apart.
	var blocked: Dictionary = _special["all"].duplicate()
	for index in _get_checkpoint_indices(level_number, n):
		blocked[index] = true
	var first := 2
	while blocked.has(first) and first < n - 1:
		first += 1
	blocked[first] = true
	var last := n - 2
	while blocked.has(last) and last > 1:
		last -= 1
	return [first, last]


func _add_gate(from_point: Vector3, to_point: Vector3) -> void:
	var mid := (from_point + to_point) * 0.5 + Vector3(0, 1.55, 0)
	var direction := to_point - from_point
	direction.y = 0.0
	var yaw := atan2(direction.x, direction.z)
	var gate := StaticBody3D.new()
	gate.name = "PuzzleGate"
	gate.set_script(PUZZLE_GATE_SCRIPT)
	gate.position = mid
	gate.rotation.y = yaw
	var size := Vector3(3.8, 2.1, 0.35)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	gate.add_child(shape)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = _map_material(Color("#ff6b8a"), true)
	gate.add_child(visual)
	world.add_child(gate)
	gates.append(gate)


func _add_lever(point: Vector3) -> void:
	var lever := Node3D.new()
	lever.name = "PuzzleSwitch"
	lever.position = point + Vector3(0, 0.55, 0)
	lever.set_meta("pressed", false)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#ff5b72")
	material.emission_enabled = true
	material.emission = Color("#ff254a")
	lever.set_meta("material", material)

	var button := CSGCylinder3D.new()
	button.name = "SwitchButton"
	button.radius = 0.48
	button.height = 0.28
	button.position.y = 0.16
	button.material = material
	lever.add_child(button)

	var post := CSGBox3D.new()
	post.size = Vector3(0.16, 0.9, 0.16)
	post.position.y = -0.42
	var post_material := StandardMaterial3D.new()
	post_material.albedo_color = Color("#304d72")
	post.material = post_material
	lever.add_child(post)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.58
	torus.outer_radius = 0.68
	ring.mesh = torus
	ring.rotation.x = PI / 2.0
	ring.material_override = _map_material(Color("#ff8fa6"), true)
	lever.add_child(ring)

	# A tall glowing beacon so the two buttons can be spotted from far away.
	var beacon := MeshInstance3D.new()
	beacon.name = "ButtonBeacon"
	var beam := CylinderMesh.new()
	beam.top_radius = 0.07
	beam.bottom_radius = 0.07
	beam.height = 2.4
	beacon.mesh = beam
	beacon.position.y = 1.55
	var beam_material := _map_material(Color("#ffa3b5"), true)
	beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_material.albedo_color = Color(1.0, 0.55, 0.66, 0.5)
	beacon.material_override = beam_material
	lever.add_child(beacon)

	world.add_child(lever)
	switches.append(lever)


func _try_press_switch() -> void:
	for lever in switches:
		if lever.get_meta("pressed", false):
			continue
		for who in [player, player_two]:
			if who == null:
				continue
			if who.global_position.distance_to(lever.global_position) < 2.6:
				_press_switch(lever)
				return


func _press_switch(lever: Node3D) -> void:
	lever.set_meta("pressed", true)
	var material: StandardMaterial3D = lever.get_meta("material")
	material.albedo_color = Color("#65f6ad")
	material.emission = Color("#25ff95")
	switches_pressed += 1
	# Each button opens the gate that corresponds to it (inner gate first, then
	# the final gate to the flag).
	var gate_index := switches_pressed - 1
	if gate_index >= 0 and gate_index < gates.size():
		gates[gate_index].open()
	if switches_pressed >= switches.size():
		puzzle_solved = true
		hud.show_finish_message("Both buttons pressed! The flag gate is open!")
	else:
		hud.show_finish_message("Button %d of %d pressed - a gate opened ahead!" % [switches_pressed, switches.size()])


func _add_checkpoint(point: Vector3, checkpoint_index: int) -> void:
	var checkpoint := Node3D.new()
	checkpoint.name = "Checkpoint_%02d" % checkpoint_index
	checkpoint.add_to_group("course_checkpoints")
	checkpoint.set_meta("checkpoint_index", checkpoint_index)
	checkpoint.position = point
	world.add_child(checkpoint)

	var area := Area3D.new()
	area.name = "CheckpointTrigger"
	area.position.y = 0.8
	area.collision_layer = 0
	area.collision_mask = 1
	var trigger_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.05
	trigger_shape.shape = sphere
	area.add_child(trigger_shape)
	checkpoint.add_child(area)

	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.045
	pole_mesh.bottom_radius = 0.07
	pole_mesh.height = 1.3
	pole.mesh = pole_mesh
	pole.position.y = 0.72
	pole.material_override = _map_material(Color("#18202b"))
	checkpoint.add_child(pole)

	var flag := MeshInstance3D.new()
	flag.name = "CheckpointFlag"
	var flag_mesh := BoxMesh.new()
	flag_mesh.size = Vector3(0.62, 0.34, 0.055)
	flag.mesh = flag_mesh
	flag.position = Vector3(0.34, 1.16, 0)
	var flag_material := _map_material(Color("#bda334"), true)
	flag.material_override = flag_material
	checkpoint.add_child(flag)
	area.body_entered.connect(_on_checkpoint_body_entered.bind(checkpoint_index, point + Vector3(0, 0.55, 0), flag_material))


func _on_checkpoint_body_entered(body: Node3D, checkpoint_index: int, respawn_point: Vector3, flag_material: StandardMaterial3D) -> void:
	if (body != player and body != player_two) or checkpoint_index <= active_checkpoint:
		return
	active_checkpoint = checkpoint_index
	checkpoint_position = respawn_point
	flag_material.albedo_color = Color("#ffe25a")
	flag_material.emission = Color("#ffc928")
	hud.show_finish_message("Checkpoint reached! Fall back here if you miss a jump.")


func respawn_player(who: CharacterBody3D = null) -> void:
	var target := who if who != null else player
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	target.is_dead = false
	target.slippery = false
	target.sticky = false
	if target.has_method("clear_surface_effects"):
		target.clear_surface_effects()
	else:
		target.wind_lift = 0.0
		target.slippery = false
		target.sticky = false
	target.global_position = checkpoint_position
	target.velocity = Vector3.ZERO
	target.movement_velocity = Vector3.ZERO
	target.gravity = 0.0
	target.gravity_scale = 1.0
	target.jumps_remaining = 2
	target.previously_floored = false
	target.model.scale = Vector3.ONE
	hud.show_finish_message("Back at checkpoint %d" % active_checkpoint if active_checkpoint > 0 else "Back at the start")


func _get_mirror_platform_point(route: Array, index: int) -> Vector3:
	var direction: Vector3
	if index == 0:
		direction = route[1] - route[0]
	elif index == route.size() - 1:
		direction = route[index] - route[index - 1]
	else:
		direction = route[index + 1] - route[index - 1]
	direction.y = 0.0
	direction = direction.normalized()
	var side := -1.0 if index % 2 == 0 else 1.0
	var offset := Vector3(-direction.z, 0.0, direction.x) * side * 0.72
	var height_offset := 0.22 if index % 3 == 1 else 0.0
	return route[index] + offset + Vector3(0, height_offset, 0)


func _add_phase_glow(platform: Node3D) -> void:
	var marker := MeshInstance3D.new()
	marker.name = "MirrorPhaseMarker"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.74
	torus.outer_radius = 0.82
	marker.mesh = torus
	marker.position.y = 0.54
	marker.material_override = _map_material(Color("#54f4e8"), true)
	platform.add_child(marker)


func _apply_dimension_visibility() -> void:
	for node in get_tree().get_nodes_in_group("material_dimension"):
		_set_phase_active(node, not mirror_dimension)
	for node in get_tree().get_nodes_in_group("mirror_dimension"):
		_set_phase_active(node, mirror_dimension)


func _set_phase_active(root: Node, active: bool) -> void:
	if root is Node3D:
		(root as Node3D).visible = active
	var collision_nodes := root.find_children("*", "CollisionObject3D", true, false)
	if root is CollisionObject3D:
		collision_nodes.append(root)
	for collision_node in collision_nodes:
		var collision_object := collision_node as CollisionObject3D
		if not collision_object.has_meta("phase_original_layer"):
			collision_object.set_meta("phase_original_layer", collision_object.collision_layer)
			collision_object.set_meta("phase_original_mask", collision_object.collision_mask)
		if active:
			collision_object.collision_layer = int(collision_object.get_meta("phase_original_layer"))
			collision_object.collision_mask = int(collision_object.get_meta("phase_original_mask"))
		else:
			collision_object.collision_layer = 0
			collision_object.collision_mask = 0


func _process(delta: float) -> void:
	if shift_active:
		shift_timer -= delta
		if shift_timer > 0:
			# Update the HUD timer label
			if is_instance_valid(hud) and is_instance_valid(hud.shift_timer_label):
				hud.shift_timer_label.visible = true
				hud.shift_timer_label.text = "SHIFT ENDS IN: %.1fs" % shift_timer
		else:
			# FORCE shift back to material dimension
			mirror_dimension = false
			_apply_dimension_visibility()
			$Sun.light_color = Color("#fff2d6")
			if is_instance_valid(hud):
				hud.show_finish_message("MATERIAL DIMENSION")

			shift_active = false
			if is_instance_valid(hud) and is_instance_valid(hud.shift_timer_label):
				hud.shift_timer_label.visible = false
	if online:
		for id in remote_players.keys():
			var proxy: Node3D = remote_players[id]
			if not is_instance_valid(proxy):
				continue
			var target: Vector3 = proxy.get_meta("net_target", proxy.position)
			proxy.position = proxy.position.lerp(target, delta * 12.0)
			var target_rot: float = proxy.get_meta("net_rot", proxy.rotation.y)
			proxy.rotation.y = lerp_angle(proxy.rotation.y, target_rot, delta * 12.0)


func _shift_dimension() -> void:
	if not shift_active and dimension_shifts_left > 0:
		mirror_dimension = not mirror_dimension
		_apply_dimension_visibility()
		$Sun.light_color = Color("#a7eaff") if mirror_dimension else Color("#fff2d6")
		hud.show_finish_message("MIRROR DIMENSION" if mirror_dimension else "MATERIAL DIMENSION")

		# Start the timer if we shifted into Mirror
		if mirror_dimension:
			shift_active = true
			shift_timer = 5.0
			dimension_shifts_left -= 1
	elif shift_active and mirror_dimension:
		# Allow shifting back manually before the timer forces the return.
		mirror_dimension = false
		_apply_dimension_visibility()
		$Sun.light_color = Color("#fff2d6")
		hud.show_finish_message("MATERIAL DIMENSION")
		shift_active = false
		if is_instance_valid(hud) and is_instance_valid(hud.shift_timer_label):
			hud.shift_timer_label.visible = false


func _build_level_identity(level_number: int, route: Array) -> void:
	var n := route.size()
	var tint := _theme_tint(level_number)
	if level_number == 5:
		tint = Color("#8e3a67")
	var used: Dictionary = _special["all"].duplicate()

	# Hoops are scenic markers; their count also grows with the level.
	var rings := _spread(_ring_count(level_number), n, used)
	for index in rings:
		used[index] = true
	for index in rings:
		_add_map_ring(route[index] + Vector3(0, 1.0, 0), 0.55 + 0.02 * float(level_number), tint)

	# Hurdles you must jump, from level 2 onward.
	var hurdles := _spread(_hurdle_count(level_number), n, used)
	for index in hurdles:
		used[index] = true
	for index in hurdles:
		_add_jump_hurdle(route, index)

	# Maze walls you must weave through, from level 3 onward.
	var walls := _spread(_wall_count(level_number), n, used)
	for index in walls:
		used[index] = true
	for index in walls:
		_add_maze_wall(route, index, 1.0 if index % 2 == 0 else -1.0)

	# Sweepers to dodge, more and faster every level.
	var sweepers := _spread(_sweeper_count(level_number), n, used)
	for index in sweepers:
		used[index] = true
	for index in sweepers:
		_add_spinning_bar(route[index], 1.5 + 0.1 * float(level_number), tint, 1.1 + 0.2 * float(level_number))

	if level_number == 5:
		_add_crown_spires(route[n - 1])
		_add_fortress_arches(route)


func _add_jump_hurdle(route: Array, route_index: int) -> void:
	var direction: Vector3 = route[route_index + 1] - route[route_index - 1]
	direction.y = 0.0
	var rotation_y := atan2(direction.x, direction.z)
	# Platform tops sit at y + 0.5; this bar is low enough to jump over.
	_add_solid_map_box(route[route_index] + Vector3(0, 0.77, 0), Vector3(1.55, 0.42, 0.24), Color("#ff734f"), rotation_y)


func _add_maze_wall(route: Array, route_index: int, side: float) -> void:
	var direction: Vector3 = route[route_index + 1] - route[route_index]
	direction.y = 0.0
	direction = direction.normalized()
	var across := Vector3(direction.z, 0.0, -direction.x)
	var rotation_y := atan2(direction.x, direction.z)
	var point: Vector3 = route[route_index] + across * side * 0.42 + Vector3(0, 0.95, 0)
	# The wall spans most of each island, so players must follow the alternating openings.
	_add_solid_map_box(point, Vector3(1.05, 0.8, 0.22), Color("#7654b8"), rotation_y)


func _add_solid_map_box(point: Vector3, size: Vector3, tint: Color, rotation_y: float = 0.0) -> void:
	var obstacle := StaticBody3D.new()
	obstacle.name = "CourseObstacle"
	obstacle.add_to_group("material_dimension")
	obstacle.position = point
	obstacle.rotation.y = rotation_y
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	obstacle.add_child(collision)
	var visual := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	visual.mesh = box
	visual.material_override = _map_material(tint)
	obstacle.add_child(visual)
	world.add_child(obstacle)


func _add_spinning_bar(platform_point: Vector3, length: float, tint: Color, speed: float) -> void:
	var obstacle := AnimatableBody3D.new()
	obstacle.name = "SpinningSweeper"
	obstacle.add_to_group("mirror_dimension")
	obstacle.position = platform_point + Vector3(0, 1.05, 0)
	obstacle.set_script(SPINNING_HAZARD_SCRIPT)
	obstacle.set("spin_speed", speed)
	var bar_size := Vector3(length, 0.18, 0.2)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = bar_size
	collision.shape = shape
	obstacle.add_child(collision)
	var visual := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = bar_size
	visual.mesh = box
	visual.material_override = _map_material(tint, true)
	obstacle.add_child(visual)
	world.add_child(obstacle)


func _add_map_ring(_point: Vector3, radius: float, tint: Color) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.09
	torus.outer_radius = radius
	ring.mesh = torus
	ring.rotation.x = PI / 2.0
	ring.material_override = _map_material(tint, true)
	world.add_child(ring)


func _add_fortress_arches(route: Array) -> void:
	for index: int in [0, 9, 18, 27]:
		if index >= route.size():
			continue
		var point: Vector3 = route[index] + Vector3(0, 1.3, 0)
		var left_pillar := MeshInstance3D.new()
		var pillar_mesh := BoxMesh.new()
		pillar_mesh.size = Vector3(0.28, 2.6, 0.28)
		left_pillar.mesh = pillar_mesh
		left_pillar.position = point + Vector3(-1.25, 0, 0)
		left_pillar.material_override = _map_material(Color("#34253c"))
		world.add_child(left_pillar)
		var right_pillar := MeshInstance3D.new()
		right_pillar.mesh = pillar_mesh
		right_pillar.position = point + Vector3(1.25, 0, 0)
		right_pillar.material_override = _map_material(Color("#34253c"))
		world.add_child(right_pillar)
		var lintel := MeshInstance3D.new()
		var lintel_mesh := BoxMesh.new()
		lintel_mesh.size = Vector3(2.8, 0.3, 0.35)
		lintel.mesh = lintel_mesh
		lintel.position = point + Vector3(0, 1.3, 0)
		lintel.material_override = _map_material(Color("#a52d54"), true)
		world.add_child(lintel)


func _add_crown_spires(point: Vector3) -> void:
	var gold := _map_material(Color("#ffd667"), true)
	for offset in [Vector3(-1.45, 0, -0.9), Vector3(-0.5, 0, -1.55), Vector3(0.5, 0, -1.55), Vector3(1.45, 0, -0.9)]:
		var spire := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.bottom_radius = 0.3
		cone.top_radius = 0.0
		cone.height = 0.85
		spire.mesh = cone
		spire.position = point + offset + Vector3(0, 0.425, 0)
		spire.material_override = gold
		world.add_child(spire)


func _map_material(tint: Color, emissive: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.58
	if emissive:
		material.emission_enabled = true
		material.emission = tint
	return material


func _get_level_routes() -> Array:
	# Each level is deliberately longer than the one before it, so the difficulty
	# and complexity climb from course to course. Gaps stay within a double jump.
	return [
		# 1 Cloud Hop: 15 platforms, gentle climb.
		_serpentine_route(3, 5, 2.35, 0.3),
		# 2 Switchback Sprint: 20 platforms.
		_serpentine_route(4, 5, 2.4, 0.3),
		# 3 Moonflip Maze: 25 platforms.
		_serpentine_route(5, 5, 2.4, 0.3),
		# 4 Rising Ruins: 30 platforms.
		_serpentine_route(5, 6, 2.4, 0.3),
		# 5 Malakar's Fortress: 36 platforms, tight jumps through guardian patrols and mirror-rift crossings.
		_serpentine_route(6, 6, 2.4, 0.36),
		# 6 Gimmick Gauntlet: 42 platforms stuffed with new puzzle surfaces.
		_serpentine_route(6, 7, 2.4, 0.28),
	]


func _serpentine_route(rows: int, columns: int, step: float, rise: float) -> Array:
	var route: Array = []
	var row_gap := 4.0
	var index := 0
	for row in range(rows):
		var z := float(row) * row_gap
		for column in range(columns):
			var x_index := column if row % 2 == 0 else columns - 1 - column
			route.append(Vector3(float(x_index) * step, float(index) * rise, z))
			index += 1
	return route


func _add_anti_gravity_zone(point: Vector3) -> void:
	var zone := Area3D.new()
	zone.name = "AntiGravityZone"
	zone.position = point + Vector3(0, 1.1, 0)
	zone.collision_layer = 0
	zone.collision_mask = 1
	zone.set_script(GRAVITY_ZONE_SCRIPT)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 3.2, 2.2)
	shape.shape = box
	zone.add_child(shape)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.72
	torus.outer_radius = 0.9
	ring.mesh = torus
	ring.position.y = -0.75
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("#62f5ef")
	glow.emission_enabled = true
	glow.emission = Color("#1acdd1")
	ring.material_override = glow
	zone.add_child(ring)
	world.add_child(zone)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		hud.show_controls_hint()
	if not get_tree().paused:
		var shifting := event.is_action_pressed("shift_dimension")
		if not shifting and InputMap.has_action("shift_dimension_p2"):
			shifting = event.is_action_pressed("shift_dimension_p2")
		if shifting:
			_shift_dimension()
			return
	if event.is_action_pressed("ui_cancel") and not get_tree().paused:
		hud.toggle_pause()
		return
	if event.is_action_pressed("interact") and not puzzle_solved:
		_try_press_switch()


func _on_coin_collected(_coins: int) -> void:
	coins_collected += 1
	hud._on_coin_collected(coins_collected)
	if coins_collected >= coin_goal:
		hud.show_finish_message("All coins collected! Press the switches, then reach the flag!")


func _on_finish_body_entered(body: Node3D) -> void:
	if body != player and body != player_two:
		return
	# Reaching the flag shows the level complete screen.
	Engine.time_scale = 1.0

	# Record this level as the continue point (restarts at its beginning).
	get_node("/root/Settings").save_progress(current_level, Vector3.ZERO, player.rotation.y)

	hud.show_victory(current_level, LEVEL_NAMES.size())


func _on_continue_pressed() -> void:
	_go_to_next_level()


func _on_save_pressed() -> void:
	var settings = get_node_or_null("/root/Settings")
	if settings == null:
		hud.show_pause_status("Could not save progress.")
		return
	settings.save_progress(current_level, player.global_position, player.rotation.y)
	hud.show_pause_status("Progress saved at Level %d" % current_level)


func _go_to_next_level() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	var next_level := current_level + 1
	if next_level > LEVEL_NAMES.size():
		next_level = 1
	get_tree().set_meta("level_number", next_level)
	get_tree().reload_current_scene()


func _on_player_died(who: CharacterBody3D) -> void:
	if local_coop:
		# In co-op, drop the fallen player back in rather than stopping the game.
		respawn_player(who)
	else:
		Engine.time_scale = 1.0
		hud.show_death()


func _on_retry_pressed() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	hud.hide_death()
	respawn_player()


func _go_to_menu() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var network := get_node_or_null("/root/Network")
	if network != null:
		network.close()
	get_tree().set_meta("online", false)
	get_tree().set_meta("local_coop", false)
	get_tree().change_scene_to_file("res://scenes/home.tscn")


# --- Local split-screen co-op ------------------------------------------------
# Keyboard bindings per player slot (slot 1 = WASD side, slot 2 = arrow-key side).
const _SLOT_KEYBOARD := {
	1: {
		"left": KEY_A, "right": KEY_D, "forward": KEY_W, "back": KEY_S,
		"jump": KEY_SPACE, "dash": KEY_SHIFT, "time_freeze": KEY_F,
	},
	2: {
		"left": KEY_LEFT, "right": KEY_RIGHT, "forward": KEY_UP, "back": KEY_DOWN,
		"jump": KEY_ENTER, "dash": KEY_KP_0, "time_freeze": KEY_KP_2,
	},
}

func _setup_local_coop() -> void:
	_ensure_key_binding("shift_dimension_p2", KEY_KP_1)
	var p1_device := str(get_tree().get_meta("local_p1_device", "keyboard"))
	var p2_device := str(get_tree().get_meta("local_p2_device", "keyboard"))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if p1_device.begins_with("pad") else Input.MOUSE_MODE_CAPTURED

	var view_a: Node3D = $View
	var view_a_rotation := view_a.rotation

	# Two SubViewports side by side. The 3D world stays in the root viewport and
	# each subviewport renders it through its own camera (own_world_3d = false).
	var layer := CanvasLayer.new()
	layer.name = "SplitScreen"
	layer.layer = -1
	add_child(layer)
	var columns := HBoxContainer.new()
	columns.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	columns.add_theme_constant_override("separation", 3)
	layer.add_child(columns)

	var container_a := SubViewportContainer.new()
	container_a.stretch = true
	container_a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container_a.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container_a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_child(container_a)
	var viewport_a := SubViewport.new()
	viewport_a.size = Vector2i(640, 720)
	viewport_a.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_a.handle_input_locally = false
	container_a.add_child(viewport_a)

	var container_b := SubViewportContainer.new()
	container_b.stretch = true
	container_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container_b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container_b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_child(container_b)
	var viewport_b := SubViewport.new()
	viewport_b.size = Vector2i(640, 720)
	viewport_b.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_b.handle_input_locally = false
	container_b.add_child(viewport_b)

	# Player 1's camera goes into the left viewport.
	remove_child(view_a)
	viewport_a.add_child(view_a)

	# Player 2 shares the world, with its own camera in the right viewport.
	player_two = PLAYER_SCENE.instantiate()
	# Second player uses the second colour and their own character pick.
	player_two.set("player_index", 1)
	player_two.set("character_id", str(get_tree().get_meta("p2_character", "")))
	player_two.position = player.position + Vector3(2.0, 0.0, 0.0)
	add_child(player_two)

	var view_b := Node3D.new()
	view_b.name = "View2"
	view_b.set_script(preload("res://scripts/view.gd"))
	view_b.rotation = view_a_rotation
	view_b.set("input_enabled", false)
	view_b.set("target", player_two)
	var camera_b := Camera3D.new()
	camera_b.name = "Camera"
	camera_b.position = Vector3(0, 0, 10)
	camera_b.fov = 42.0
	camera_b.current = true
	view_b.add_child(camera_b)
	viewport_b.add_child(view_b)
	player_two.set("view", view_b)

	player_two.coin_collected.connect(_on_coin_collected)
	player_two.died.connect(_on_player_died.bind(player_two))
	player_two.add_to_group("player")

	# Give each player their own input device (keyboard or a specific controller).
	_configure_local_player(player, view_a, p1_device, 1)
	_configure_local_player(player_two, view_b, p2_device, 2)

	# Name tags above each player's head.
	player.set_player_name(str(get_tree().get_meta("local_p1_name", "Player 1")))
	player_two.set_player_name(str(get_tree().get_meta("local_p2_name", "Player 2")))
	hud.show_finish_message("LOCAL CO-OP  •  P1: %s    P2: %s" % [_device_label(p1_device, 1), _device_label(p2_device, 2)])


func _device_label(device: String, slot: int) -> String:
	if device.begins_with("pad"):
		return "controller"
	if slot == 1:
		return "WASD + mouse"
	return "arrows + Enter"

func _configure_local_player(p: CharacterBody3D, v: Node3D, device: String, slot: int) -> void:
	var prefix := "p%d_" % slot
	for suffix in ["left", "right", "forward", "back", "jump", "dash", "time_freeze",
			"cam_left", "cam_right", "cam_up", "cam_down"]:
		_define_action(prefix + suffix)

	var is_pad := device.begins_with("pad")
	if is_pad:
		_bind_pad_actions(prefix, int(device.split(":")[1]))
	else:
		_bind_keyboard_actions(prefix, slot)

	p.set("action_left", prefix + "left")
	p.set("action_right", prefix + "right")
	p.set("action_forward", prefix + "forward")
	p.set("action_back", prefix + "back")
	p.set("action_jump", prefix + "jump")
	p.set("action_dash", prefix + "dash")
	p.set("action_time_freeze", prefix + "time_freeze")

	if v != null:
		v.set("action_cam_left", prefix + "cam_left")
		v.set("action_cam_right", prefix + "cam_right")
		v.set("action_cam_up", prefix + "cam_up")
		v.set("action_cam_down", prefix + "cam_down")
		v.set("input_enabled", true)
		# Only player 1 on the keyboard looks with the mouse.
		v.set("mouse_look", slot == 1 and not is_pad)

func _define_action(action_name: String) -> void:
	if InputMap.has_action(action_name):
		for existing_event in InputMap.action_get_events(action_name):
			InputMap.action_erase_event(action_name, existing_event)
	else:
		InputMap.add_action(action_name)
		InputMap.action_set_deadzone(action_name, 0.25)

func _bind_keyboard_actions(prefix: String, slot: int) -> void:
	var keys: Dictionary = _SLOT_KEYBOARD[slot]
	for action in keys.keys():
		var key := InputEventKey.new()
		key.physical_keycode = keys[action]
		key.device = -1
		InputMap.action_add_event(prefix + str(action), key)
	if slot == 1:
		# Player 1 can also jump with the left mouse button.
		var mouse_jump := InputEventMouseButton.new()
		mouse_jump.button_index = MOUSE_BUTTON_LEFT
		mouse_jump.device = -1
		InputMap.action_add_event(prefix + "jump", mouse_jump)

func _bind_pad_actions(prefix: String, pad_id: int) -> void:
	_add_motion(prefix + "left", JOY_AXIS_LEFT_X, -1.0, pad_id)
	_add_motion(prefix + "right", JOY_AXIS_LEFT_X, 1.0, pad_id)
	_add_motion(prefix + "forward", JOY_AXIS_LEFT_Y, -1.0, pad_id)
	_add_motion(prefix + "back", JOY_AXIS_LEFT_Y, 1.0, pad_id)
	_add_motion(prefix + "cam_left", JOY_AXIS_RIGHT_X, -1.0, pad_id)
	_add_motion(prefix + "cam_right", JOY_AXIS_RIGHT_X, 1.0, pad_id)
	_add_motion(prefix + "cam_up", JOY_AXIS_RIGHT_Y, -1.0, pad_id)
	_add_motion(prefix + "cam_down", JOY_AXIS_RIGHT_Y, 1.0, pad_id)
	_add_button(prefix + "left", JOY_BUTTON_DPAD_LEFT, pad_id)
	_add_button(prefix + "right", JOY_BUTTON_DPAD_RIGHT, pad_id)
	_add_button(prefix + "forward", JOY_BUTTON_DPAD_UP, pad_id)
	_add_button(prefix + "back", JOY_BUTTON_DPAD_DOWN, pad_id)
	_add_button(prefix + "jump", JOY_BUTTON_A, pad_id)
	_add_button(prefix + "dash", JOY_BUTTON_X, pad_id)
	_add_button(prefix + "dash", JOY_BUTTON_RIGHT_SHOULDER, pad_id)
	_add_button(prefix + "time_freeze", JOY_BUTTON_Y, pad_id)

func _add_motion(action_name: String, axis: JoyAxis, value: float, device: int) -> void:
	var motion := InputEventJoypadMotion.new()
	motion.axis = axis
	motion.axis_value = value
	motion.device = device
	InputMap.action_add_event(action_name, motion)

func _add_button(action_name: String, button: JoyButton, device: int) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.device = device
	InputMap.action_add_event(action_name, event)

# --- Online co-op (ENet) -----------------------------------------------------

func _setup_online() -> void:
	var network := get_node_or_null("/root/Network")
	if network == null:
		return
	network.peer_list_changed.connect(_refresh_remote_players)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.set_player_name(network.local_name)
	player.call("set_player_index", _player_index_for(multiplayer.get_unique_id()))
	_refresh_remote_players()
	var role := "HOST" if multiplayer.is_server() else "CLIENT"
	hud.show_finish_message("ONLINE %s  •  players: %d" % [role, network.player_ids().size()])

func _player_index_for(id: int) -> int:
	# A stable 0-based slot for a peer, used to pick a distinct character colour.
	var ids: Array = []
	for peer in multiplayer.get_peers():
		ids.append(int(peer))
	ids.append(multiplayer.get_unique_id())
	ids.sort()
	var index: int = ids.find(id)
	return maxi(0, index)

func _refresh_remote_players() -> void:
	var network := get_node_or_null("/root/Network")
	if network == null:
		return
	var local_id := multiplayer.get_unique_id()
	# Spawn a proxy for every other peer.
	for id in network.players.keys():
		if id == local_id or remote_players.has(id):
			continue
		_spawn_remote_player(id)
	# Drop proxies whose peer left.
	for id in remote_players.keys():
		if not network.players.has(id):
			_remove_remote_player(id)
	# Keep every remote player's name tag and character current.
	for id in remote_players.keys():
		var proxy: Node = remote_players[id]
		if not is_instance_valid(proxy):
			continue
		if str(proxy.get("character_id")) != network.get_player_character(id):
			# They changed character: rebuild the proxy with the new model.
			_remove_remote_player(id)
			_spawn_remote_player(id)
			continue
		proxy.set_player_name(network.get_player_name(id))
	hud.show_finish_message("ONLINE  •  players connected: %d" % network.player_ids().size())

func _spawn_remote_player(id: int) -> void:
	var network := get_node_or_null("/root/Network")
	if network == null or not network.players.has(id):
		return
	var character_scene: PackedScene = preload("res://objects/player.tscn")
	var proxy: CharacterBody3D = character_scene.instantiate()
	proxy.name = "RemotePlayer_%d" % id
	proxy.set("character_id", network.get_player_character(id))
	proxy.set("player_index", _player_index_for(id))
	proxy.set("action_left", "")
	proxy.set("action_right", "")
	proxy.set("action_forward", "")
	proxy.set("action_back", "")
	proxy.set("action_jump", "")
	proxy.set("action_dash", "")
	proxy.set("action_time_freeze", "")
	world.add_child(proxy)
	proxy.global_position = player.global_position
	proxy.set_player_name(network.get_player_name(id))
	remote_players[id] = proxy


func _remove_remote_player(id: int) -> void:
	if not remote_players.has(id):
		return
	var proxy: Node = remote_players[id]
	remote_players.erase(id)
	if is_instance_valid(proxy):
		proxy.queue_free()


func _on_network_state_received(id: int, state: Dictionary) -> void:
	if not remote_players.has(id):
		return
	var proxy: Node3D = remote_players[id]
	proxy.set_meta("net_target", state.get("position", proxy.position))
	proxy.set_meta("net_rot", float(state.get("rotation", proxy.rotation.y)))