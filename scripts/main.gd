extends Node3D

const PLATFORM := preload("res://objects/platform.tscn")
const PLATFORM_MEDIUM := preload("res://objects/platform_medium.tscn")
const PLATFORM_GRASS := preload("res://objects/platform_grass_large_round.tscn")
const PLATFORM_FALLING := preload("res://objects/platform_falling.tscn")
const COIN := preload("res://objects/coin.tscn")
const FLAG := preload("res://models/flag.glb")
# Built from primitives in code, so it needs no scene file of its own.
const ENEMY := preload("res://objects/enemy.gd")
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
const PLAYER_SCENE := preload("res://objects/player.tscn")
const ISLAND := preload("res://scenes/forgotten_island.tscn")
const FROZEN_SKIES_SCRIPT := preload("res://scripts/frozen_skies.gd")

const LEVEL_NAMES := ["Forgotten Island", "Switchback Sprint", "Frozen Skies", "Rising Ruins", "Sky Crown", "Gimmick Gauntlet"]

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

# Local split-screen co-op
var local_coop := false
var player_two: CharacterBody3D
var coins_collected := 0
## Level 1 is the hand-laid Forgotten Island instead of a generated course.
var island: ForgottenIsland = null
var frozen_skies: FrozenSkies = null
## Stops the dormant portal from spamming its message while the player stands in it.
var _portal_locked_cooldown := 0.0

# Route points of the current level (world space). Used to aim the starting camera.
var route_points: Array = []

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
	Audio.play_music("res://sounds/itty_bitty.mp3")
	$Sun.light_color = Color("#fff2d6")
	_ensure_key_action("interact", KEY_E, JOY_BUTTON_X)
	_ensure_key_action("time_freeze", KEY_F, JOY_BUTTON_Y)
	_ensure_key_action("shift_dimension", KEY_Q, JOY_BUTTON_LEFT_SHOULDER, MOUSE_BUTTON_RIGHT)
	_ensure_key_action("attack", KEY_J, JOY_BUTTON_B)
	_ensure_key_action("inventory", KEY_I, JOY_BUTTON_BACK)
	_ensure_key_action("fly", KEY_9, JOY_BUTTON_LEFT_STICK)
	# Rebound keys win over the defaults above.
	_apply_key_binds()
	current_level = int(get_tree().get_meta("level_number", 1))
	current_level = clampi(current_level, 1, LEVEL_NAMES.size())
	get_tree().set_meta("level_number", current_level)
	local_coop = bool(get_tree().get_meta("local_coop", false))
	online = bool(get_tree().get_meta("online", false))
	_build_level(current_level)
	if frozen_skies != null:
		Audio.play_music("res://sounds/pixelland.mp3")
	_aim_starting_camera()
	coin_goal = get_tree().get_nodes_in_group("collectible_coins").size()
	if island != null:
		# On the island the goal is the portal requirement, not every coin: the
		# level holds more coins than are needed, so exploring is a choice.
		coin_goal = island.coins_required
		island.notify_coins(0)
		hud.show_finish_message("THE FORGOTTEN ISLAND")
		hud.set_objective("Explore the Forgotten Island  -  %d more coins wake the portal" % coin_goal)
	elif frozen_skies != null:
		coin_goal = frozen_skies.coins_required
		coins_collected = Progress.frozen_coins_collected()
		hud.show_finish_message("LEVEL 3 – FROZEN SKIES")
		hud.set_objective("Explore Frozen Skies  -  defeat the Frost Titan and find 50 coins")
		_update_frozen_ability_hud()
		_update_frozen_progress_hud()
	else:
		hud.show_finish_message("RIGHT CLICK / Q / LB: SHIFT DIMENSION")
		hud.set_objective("SHIFT DIMENSIONS  •  COLLECT COINS  •  PRESS BOTH FAR-APART BUTTONS  •  REACH THE FLAG", false)
	hud.set_coin_goal(coin_goal)
	hud.set_level_info(current_level, LEVEL_NAMES[current_level - 1])
	hud.bind_players([player])
	hud.continue_pressed.connect(_on_continue_pressed)
	player.coin_collected.connect(_on_coin_collected)
	player.died.connect(_on_player_died.bind(player))
	hud.retry_pressed.connect(_on_retry_pressed)
	hud.menu_pressed.connect(_go_to_menu)
	finish.body_entered.connect(_on_finish_body_entered)
	_apply_dimension_visibility()
	hud.show_controls_hint()

	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		$Sun.light_energy = 0.24
		$Sun.shadow_opacity = 0.85
		$Environment.environment.background_energy_multiplier = 0.25

	if local_coop:
		_setup_local_coop()
	elif online:
		_setup_online()


## Start the camera behind the player, looking along the route. Otherwise the very
## next platforms can sit between the camera and the player and hide the character
## completely, which makes the level look broken on arrival.
func _aim_starting_camera() -> void:
	if route_points.size() < 2:
		return
	var ahead: Vector3 = route_points[1] - route_points[0]
	ahead.y = 0.0
	if ahead.length() < 0.01:
		return
	ahead = ahead.normalized()
	# The camera sits at local (0, 0, zoom), so put that offset opposite the route.
	var yaw := rad_to_deg(atan2(-ahead.x, -ahead.z))
	var view: Node3D = $View
	var current: Vector3 = view.get("camera_rotation")
	view.set("camera_rotation", Vector3(current.x, yaw, 0.0))
	view.rotation.y = deg_to_rad(yaw)


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


## Swap in any keys the player rebound in OPTIONS > KEY BINDS. This runs after the
## defaults are set up, so a rebound key replaces the default one for that action.
func _apply_key_binds() -> void:
	var settings := get_node_or_null("/root/Settings")
	if settings == null:
		return
	var binds: Dictionary = settings.get("key_binds")
	for action in binds.keys():
		_add_stored_bind(str(action), int(binds[action]))


## Put one stored bind on an action, replacing anything the game set up for it.
## The player may have bound a key or a mouse button, so both are handled here.
func _add_stored_bind(action_name: String, code: int) -> void:
	if code <= 0 or not InputMap.has_action(action_name):
		return
	for existing_event in InputMap.action_get_events(action_name):
		if existing_event is InputEventKey or existing_event is InputEventMouseButton:
			InputMap.action_erase_event(action_name, existing_event)
	var settings := get_node_or_null("/root/Settings")
	if settings != null and bool(settings.call("is_mouse_bind", code)):
		var mouse := InputEventMouseButton.new()
		mouse.button_index = int(settings.call("mouse_button_of", code)) as MouseButton
		mouse.device = -1
		InputMap.action_add_event(action_name, mouse)
		return
	var key := InputEventKey.new()
	key.physical_keycode = code as Key
	key.device = -1
	InputMap.action_add_event(action_name, key)


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
	island = null
	frozen_skies = null
	for child in world.get_children():
		world.remove_child(child)
		child.free()
	if level_number == 1:
		_build_island()
		return
	if level_number == 3:
		_build_frozen_skies()
		return
	var routes := _get_level_routes()
	var route: Array = routes[level_number - 1]
	route_points = route
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

		# One sentry per level, a little past the halfway point, hovering
		# within reach of a jump - any higher and only a fall past it would
		# ever connect.
		if i == int(route.size() / 2.0):
			var enemy: Node3D = ENEMY.new()
			enemy.name = "SkySentry"
			enemy.position = point + Vector3(0.0, 1.7, 0.0)
			enemy.set("max_health", 2 + int(level_number / 3.0))
			enemy.set("drift_speed", 1.5 + 0.15 * float(level_number))
			enemy.set("chase_range", 7.0)
			world.add_child(enemy)

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


## Level 1: the hand-laid Forgotten Island. The island builds itself and reports
## its spawn, checkpoints and portal; the level keeps running the same show -
## coins, checkpoints, death, and a finish that leads on to level 2.
func _build_island() -> void:
	var node: ForgottenIsland = ISLAND.instantiate()
	node.name = "ForgottenIsland"
	world.add_child(node)
	island = node
	node.message.connect(_on_island_message)
	node.build(self)
	route_points = node.waypoints
	player.position = node.spawn_point
	player.velocity = Vector3.ZERO
	checkpoint_position = node.spawn_point
	active_checkpoint = 0
	for index in node.checkpoint_points.size():
		_add_checkpoint(node.checkpoint_points[index], index)
	finish.position = node.portal_position
	_apply_dimension_visibility()
	_bind_island_boss()


func _build_frozen_skies() -> void:
	var node: FrozenSkies = FROZEN_SKIES_SCRIPT.new()
	node.name = "FrozenSkies"
	world.add_child(node)
	frozen_skies = node
	route_points = node.build(self)
	active_checkpoint = clampi(Progress.frozen_checkpoint_index, 0, 38)
	player.position = route_points[active_checkpoint] + Vector3(0.0, 0.55, 0.0)
	player.velocity = Vector3.ZERO
	checkpoint_position = player.position
	for checkpoint_index in [0, 9, 18, 29, 38]:
		_add_checkpoint(route_points[checkpoint_index], checkpoint_index)
	finish.position = route_points[route_points.size() - 1] + Vector3(0.0, 1.0, 0.0)
	_apply_dimension_visibility()


func _bind_frozen_boss(boss: Node) -> void:
	if boss == null or not boss.has_signal("health_changed"):
		return
	boss.health_changed.connect(func(health: int, maximum: int, phase: int):
		hud.show_boss("THE FROST TITAN")
		hud.update_boss(health, maximum, phase)
	)
	boss.defeated.connect(func():
		hud.hide_boss()
		hud.show_finish_message("The Frost Titan falls. Open the ancient chest!")
		hud.set_objective("Open the ancient chest and recover the Third Fragment.")
	)


func _on_frozen_fragment_recovered() -> void:
	if frozen_skies != null:
		frozen_skies.thaw_environment()
	hud.show_finish_message("You have recovered the Third Fragment of the Eternal Tree!")
	hud.set_objective("Find 50 coins to unlock the Level 4 portal.")
	_update_frozen_progress_hud()


func _on_frozen_mechanism_progress(current: int, total: int) -> void:
	_update_frozen_ability_hud()
	_update_frozen_progress_hud()
	if current >= total:
		hud.set_objective("All three frozen seals are active. Defeat the Frost Titan.")
	else:
		hud.set_objective("Activate the frozen mechanisms: %d / %d" % [current, total])

func _on_frozen_crystal_light_solved() -> void:
	hud.show_finish_message("Crystal light aligned! The frozen gate responds.")
	hud.set_objective("Crystal light aligned. Continue through Frozen Crystal Caves.")
	_update_frozen_progress_hud()

func _on_frozen_generator_progress(current: int, total: int) -> void:
	_update_frozen_progress_hud()
	if current >= total:
		hud.show_finish_message("All three crystal generators are charged. The cave door opens!")
		hud.set_objective("Continue through the Shattered Ice Fortress.")
	else:
		hud.set_objective("Activate the crystal generators: %d / %d" % [current, total])

func _on_frozen_mechanism_blocked(message: String) -> void:
	hud.show_finish_message(message)

func _update_frozen_ability_hud() -> void:
	if frozen_skies == null:
		return
	var unlocked: Array[String] = []
	if Progress.ice_shield_unlocked:
		unlocked.append("K Ice Shield")
	if Progress.frost_dash_unlocked:
		unlocked.append("L Frost Dash")
	if Progress.crystal_activation_unlocked:
		unlocked.append("E Crystal Activation")
	hud.set_frozen_abilities(unlocked)

func _update_frozen_progress_hud() -> void:
	if frozen_skies == null:
		return
	hud.set_frozen_progress(
		Progress.frozen_seals_activated,
		frozen_skies.mechanisms.size(),
		Progress.crystal_light_solved,
		Progress.third_fragment_recovered,
		active_checkpoint,
		Progress.frozen_generators_activated)


## The island's Warden drives the HUD's boss bar: up when it wakes, filled on
## every hit, gone when it falls.
func _bind_island_boss() -> void:
	var warden := get_tree().get_first_node_in_group("island_warden") as IslandWarden
	if warden == null:
		return
	warden.woke.connect(func(): hud.show_boss("THE CORRUPTED ISLAND WARDEN"))
	warden.health_changed.connect(func(health: int, max_health: int, phase: int):
		hud.update_boss(health, max_health, phase)
	)
	warden.defeated.connect(hud.hide_boss)


func _on_island_message(text: String) -> void:
	hud.show_finish_message(text)


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


func _switch_count(_level_number: int) -> int:
	# Every course uses the twin-button puzzle: press both far-apart buttons.
	return 2


func _theme_tint(level_number: int) -> Color:
	match level_number:
		1: return Color("#83f5ef")
		2: return Color("#ff9b4b")
		3: return Color("#d79bff")
		4: return Color("#d6bd91")
		5: return Color("#ffd667")
	return Color("#9be86a")


func _add_main_platform(level_number: int, route: Array, i: int, point: Vector3) -> void:
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
	# The trigger goes on before the checkpoint joins the world: a collision shape
	# that is attached to something already inside the tree is not registered by
	# the physics server, and a checkpoint nobody can trigger is a checkpoint that
	# silently sends a player back to the start of the level.
	var checkpoint := Node3D.new()
	checkpoint.name = "Checkpoint_%02d" % checkpoint_index
	checkpoint.add_to_group("course_checkpoints")
	checkpoint.set_meta("checkpoint_index", checkpoint_index)
	checkpoint.position = point

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
	world.add_child(checkpoint)

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
	if frozen_skies != null:
		Progress.set_frozen_checkpoint(checkpoint_index)
		_update_frozen_progress_hud()
	flag_material.albedo_color = Color("#ffe25a")
	flag_material.emission = Color("#ffc928")
	if frozen_skies != null:
		if checkpoint_index >= 9:
			Progress.unlock_ice_shield()
		if checkpoint_index >= 18:
			Progress.unlock_frost_dash()
		if checkpoint_index >= 29:
			Progress.unlock_crystal_activation()
		var region := frozen_skies.region_name_for_checkpoint(checkpoint_index)
		hud.show_finish_message("Checkpoint reached: %s" % region)
		hud.set_objective("Explore %s" % region)
	else:
		hud.show_finish_message("Checkpoint reached! Fall back here if you miss a jump.")


func respawn_player(who: CharacterBody3D = null) -> void:
	var target := who if who != null else player
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	target.is_dead = false
	if target.has_method("reset_vitals"):
		target.call("reset_vitals")
	target.slippery = false
	target.sticky = false
	target.external_velocity = Vector3.ZERO
	target.wind_lift = 0.0
	target.global_position = checkpoint_position
	target.velocity = Vector3.ZERO
	target.movement_velocity = Vector3.ZERO
	target.gravity = 0.0
	target.gravity_scale = 1.0
	target.jumps_remaining = 2
	target.previously_floored = false
	target.model.scale = Vector3.ONE
	hud.show_finish_message("Back at checkpoint %d" % active_checkpoint if active_checkpoint > 0 else "Back at the start")
	_reset_enemies()


## Send every enemy that has a patrol spot back to it. The island's Shadow Slimes
## do, so a player who respawns is not dropped straight back into a chase; the sky
## sentries drift freely and have nothing to reset to.
func _reset_enemies() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		if node.has_method("reset_to_home"):
			node.call("reset_to_home")
	hud.hide_boss()


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
	if _portal_locked_cooldown > 0.0:
		_portal_locked_cooldown -= delta
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
	elif shift_active and not mirror_dimension:
		# Allow shifting back manually before timer ends
		mirror_dimension = false
		_apply_dimension_visibility()
		$Sun.light_color = Color("#fff2d6")
		hud.show_finish_message("MATERIAL DIMENSION")
		shift_active = false


func _build_level_identity(level_number: int, route: Array) -> void:
	var n := route.size()
	var tint := _theme_tint(level_number)
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


func _add_map_ring(point: Vector3, radius: float, tint: Color) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.09
	torus.outer_radius = radius
	ring.mesh = torus
	ring.position = point
	ring.rotation.x = PI / 2.0
	ring.material_override = _map_material(tint, true)
	world.add_child(ring)


func _add_map_column(point: Vector3, height: float, radius: float, tint: Color) -> void:
	var column := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius * 0.74
	cylinder.bottom_radius = radius
	cylinder.height = height
	column.mesh = cylinder
	column.position = point + Vector3(0, 0.5 + height * 0.5, 0)
	column.material_override = _map_material(tint)
	world.add_child(column)


func _add_ruin_arch(point: Vector3, width: float, height: float, tint: Color) -> void:
	var pillar_width := 0.22
	_add_map_box(point + Vector3(-width * 0.5, height * 0.5, 0), Vector3(pillar_width, height, pillar_width), tint)
	_add_map_box(point + Vector3(width * 0.5, height * 0.5, 0), Vector3(pillar_width, height, pillar_width), tint)
	_add_map_box(point + Vector3(0, height, 0), Vector3(width + pillar_width, pillar_width, pillar_width), tint)


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


func _add_map_box(point: Vector3, size: Vector3, tint: Color) -> void:
	var visual := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	visual.mesh = box
	visual.position = point
	visual.material_override = _map_material(tint)
	world.add_child(visual)


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
		# 1 is the Forgotten Island - see _build_island and scripts/forgotten_island.gd.
		_serpentine_route(3, 5, 2.35, 0.3),
		# 2 Switchback Sprint: 20 platforms.
		_serpentine_route(4, 5, 2.4, 0.3),
		# 3 Moonflip Maze: 25 platforms.
		_serpentine_route(5, 5, 2.4, 0.3),
		# 4 Rising Ruins: 30 platforms.
		_serpentine_route(5, 6, 2.4, 0.3),
		# 5 Sky Crown: 36 platforms, the longest and hardest course.
		_serpentine_route(6, 6, 2.4, 0.3),
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
		if frozen_skies != null and frozen_skies.try_activate_nearby(player):
			return
		_try_press_switch()


func _on_coin_collected(_coins: int) -> void:
	coins_collected += 1
	hud._on_coin_collected(coins_collected)
	if island != null:
		# The island watches its own coin count: it needs 30 for the portal, and
		# the level holds more than that on purpose.
		island.notify_coins(coins_collected)
		return
	if coins_collected >= coin_goal:
		hud.show_finish_message("All coins collected! Press the switches, then reach the flag!")
	if frozen_skies != null and coins_collected >= coin_goal \
			and frozen_skies.boss_defeated and Progress.third_fragment_recovered:
		hud.set_objective("The path to the fourth island has opened! Step through the icy portal.")


func _on_finish_body_entered(body: Node3D) -> void:
	if body != player and body != player_two:
		return
	if frozen_skies != null and not frozen_skies.is_portal_ready(coins_collected):
		if _portal_locked_cooldown <= 0.0:
			_portal_locked_cooldown = 2.5
			hud.show_finish_message(frozen_skies.portal_blocked_reason(coins_collected))
		return
	if island != null and not island.is_portal_ready():
		# The portal is dormant until the guardian is gone, the Fragment is
		# recovered and the coins are in.
		if _portal_locked_cooldown <= 0.0:
			_portal_locked_cooldown = 2.5
			hud.show_finish_message(island.portal_blocked_reason())
		return
	# Reaching the flag - or stepping through an open portal - finishes the level.
	Engine.time_scale = 1.0
	hud.show_victory(current_level, LEVEL_NAMES.size())


func _on_continue_pressed() -> void:
	_go_to_next_level()


func _go_to_next_level() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	var next_level := current_level + 1
	if next_level > LEVEL_NAMES.size():
		next_level = 1
	get_tree().set_meta("level_number", next_level)
	if next_level == 3:
		hud.play_level_transition("LEVEL 3 – FROZEN SKIES", func(): get_tree().reload_current_scene())
	else:
		get_tree().reload_current_scene()


func _on_player_died(who: CharacterBody3D) -> void:
	if local_coop:
		# In co-op, drop the fallen player back in rather than stopping the game.
		respawn_player(who)
	else:
		Engine.time_scale = 1.0
		var cause := str(who.get("last_death_cause")) if who != null and who.get("last_death_cause") != null else "fall"
		hud.show_death(cause)


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
		"attack": KEY_J, "inventory": KEY_I,
	},
	2: {
		"left": KEY_LEFT, "right": KEY_RIGHT, "forward": KEY_UP, "back": KEY_DOWN,
		"jump": KEY_ENTER, "dash": KEY_KP_0, "time_freeze": KEY_KP_2,
		"attack": KEY_KP_3, "inventory": KEY_KP_5,
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

	# The inventory shows both players once player 2 exists.
	hud.bind_players([player, player_two])

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


# Wire one player slot to the chosen device. Each slot gets its own action set
# ("p1_"/"p2_") so two players never share the same action, even when both use
# the keyboard or both use controllers.
func _configure_local_player(p: CharacterBody3D, v: Node3D, device: String, slot: int) -> void:
	var prefix := "p%d_" % slot
	for suffix in ["left", "right", "forward", "back", "jump", "dash", "time_freeze",
			"attack", "inventory", "cam_left", "cam_right", "cam_up", "cam_down"]:
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
	p.set("action_attack", prefix + "attack")

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
	var settings := get_node_or_null("/root/Settings")
	var binds: Dictionary = settings.get("key_binds") if settings != null else {}
	for action in keys.keys():
		# Player 1 on the keyboard uses whatever they rebound in the options;
		# player 2 keeps the arrow-key side so the two never collide.
		if slot == 1 and binds.has(str(action)):
			_add_stored_bind(prefix + str(action), int(binds[str(action)]))
			continue
		var key := InputEventKey.new()
		key.physical_keycode = keys[action] as Key
		key.device = -1
		InputMap.action_add_event(prefix + str(action), key)
	if slot == 1 and not binds.has("jump"):
		# Player 1 can also jump with the left mouse button, until they rebind jump.
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
	_add_button(prefix + "attack", JOY_BUTTON_B, pad_id)
	_add_button(prefix + "inventory", JOY_BUTTON_BACK, pad_id)


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
	var proxy: CharacterBody3D = PLAYER_SCENE.instantiate()
	proxy.name = "Remote_%d" % id
	proxy.set_physics_process(false)
	proxy.set("view", null)
	# Each peer gets a distinct colour and their own character.
	proxy.set("player_index", _player_index_for(id))
	proxy.set("character_id", "" if network == null else network.get_player_character(id))
	proxy.position = player.position + Vector3(1.6, 0.0, 0.0)
	add_child(proxy)
	proxy.set_meta("net_target", proxy.position)
	proxy.set_meta("net_rot", 0.0)
	remote_players[id] = proxy


func _remove_remote_player(id: int) -> void:
	if remote_players.has(id):
		var proxy: Node = remote_players[id]
		remote_players.erase(id)
		if is_instance_valid(proxy):
			proxy.queue_free()


func _physics_process(_delta: float) -> void:
	if not online or multiplayer.multiplayer_peer == null:
		return
	var id := multiplayer.get_unique_id()
	var pos := player.position
	var rot := player.rotation.y
	if multiplayer.is_server():
		rpc("_recv_transform", id, pos, rot)
	else:
		rpc_id(1, "_recv_transform", id, pos, rot)


@rpc("any_peer", "call_remote", "unreliable")
func _recv_transform(id: int, net_position: Vector3, net_rotation_y: float) -> void:
	var sender_id := multiplayer.get_remote_sender_id()

	# Server: only accept if the supplied ID matches the actual sender.
	# Clients: only accept if the message comes from the server (peer 1).
	if multiplayer.is_server():
		if sender_id != id:
			return
	else:
		if sender_id != 1:
			return

	var proxy: Node3D = remote_players.get(id)
	if proxy != null and is_instance_valid(proxy):
		proxy.set_meta("net_target", net_position)
		proxy.set_meta("net_rot", net_rotation_y)
	# The host relays other clients' transforms so everyone sees everyone.
	if multiplayer.is_server():
		for peer_id in multiplayer.get_peers():
			if peer_id != id:
				rpc_id(peer_id, "_recv_transform", id, net_position, net_rotation_y)
