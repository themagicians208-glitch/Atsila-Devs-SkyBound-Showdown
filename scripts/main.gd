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
const SHADOW_GUARDIAN_SCRIPT := preload("res://scripts/shadow_guardian.gd")
const MALAKAR_SCRIPT := preload("res://objects/malakar.gd")
const ANIMAL_SCENE := preload("res://objects/character.tscn")
const BUTTERFLY_TEXTURE := preload("res://assets/generated/island_butterfly.png")
const PLAYER_SCENE := preload("res://objects/player.tscn")
const ISLAND := preload("res://scenes/forgotten_island.tscn")
const WOODS := preload("res://scenes/whispering_woods.tscn")
const FROZEN_SKIES_SCRIPT := preload("res://scripts/frozen_skies.gd")
const SHADOW_WOLF := preload("res://objects/shadow_wolf.gd")
const SECOND_FRAGMENT_CHEST := preload("res://objects/second_fragment_chest.gd")

const LEVEL_NAMES := ["Forgotten Island", "The Whispering Woods", "Frozen Skies", "Rising Ruins", "Malakar's Fortress", "Gimmick Gauntlet"]

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
## Level 1 is the hand-laid Forgotten Island instead of a generated course.
var island: ForgottenIsland = null
var woods: WhisperingWoods = null
var frozen_skies: FrozenSkies = null
var level2_wolf: Node = null
var level2_chest: Node = null
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
var fortress_boss: Node3D
var fortress_boss_complete := false
var _fortress_material_cache: Dictionary = {}


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
	if current_level == 5:
		dimension_shifts_left = 4
	get_tree().set_meta("level_number", current_level)
	local_coop = bool(get_tree().get_meta("local_coop", false))
	online = bool(get_tree().get_meta("online", false))
	_build_level(current_level)
	if current_level == 5:
		_configure_fortress_environment(1)
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
	elif woods != null:
		coin_goal = woods.coins_required
		woods.notify_coins(0)
		hud.show_finish_message("THE WHISPERING WOODS")
		woods.main_objective()
	elif frozen_skies != null:
		coin_goal = frozen_skies.coins_required
		coins_collected = Progress.frozen_coins_collected()
		hud.show_finish_message("LEVEL 3 – FROZEN SKIES")
		_update_frozen_ability_hud()
		_update_frozen_progress_hud()
		_update_frozen_portal_objective()
	elif current_level == 5:
		hud.show_finish_message("Teleported to Malakar's island — parkour up to the fortress!")
		hud.set_objective("Align the three conduits, reach the throne, and face Malakar.")
	else:
		hud.show_finish_message("RIGHT CLICK / Q / LB: SHIFT DIMENSION")
		hud.set_objective("SHIFT DIMENSIONS  •  COLLECT COINS  •  PRESS BOTH FAR-APART BUTTONS  •  REACH THE FLAG", false)
	hud.set_coin_goal(coin_goal)
	if frozen_skies != null:
		hud._on_coin_collected(coins_collected)
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
	woods = null
	frozen_skies = null
	for child in world.get_children():
		world.remove_child(child)
		child.free()
	if level_number == 1:
		_build_island()
		return
	if level_number == 2:
		_build_woods()
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
		if level_number == 5:
			_apply_fortress_stone(mirror_platform, Color("#4a285f"))
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


func _build_woods() -> void:
	var node: WhisperingWoods = WOODS.instantiate()
	node.name = "WhisperingWoods"
	world.add_child(node)
	woods = node
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
	_bind_woods_boss()


func _bind_woods_boss() -> void:
	var boss := get_tree().get_first_node_in_group("woods_boss") as ShadowWolfBoss
	if boss == null:
		return
	boss.woke.connect(func(): hud.show_boss("THE SHADOW WOLF - GUARDIAN OF THE WOODS"))
	boss.health_changed.connect(func(health: int, max_health: int, phase: int):
		hud.update_boss(health, max_health, phase)
	)
	boss.defeated.connect(hud.hide_boss)

func _build_level2_progression(route: Array) -> void:
	var boss_point: Vector3 = route[route.size() - 3] + Vector3(0.0, 1.2, 0.0)
	level2_wolf = SHADOW_WOLF.new()
	level2_wolf.name = "ShadowWolf"
	level2_wolf.position = boss_point
	world.add_child(level2_wolf)
	level2_wolf.defeated.connect(_on_level2_wolf_defeated)
	level2_chest = SECOND_FRAGMENT_CHEST.new()
	level2_chest.name = "SecondFragmentChest"
	level2_chest.position = route[route.size() - 2] + Vector3(0.0, 0.0, 0.8)
	world.add_child(level2_chest)
	level2_chest.fragment_recovered.connect(_on_level2_fragment_recovered)
	if Progress.second_fragment_recovered:
		level2_chest.unlock()
	if is_instance_valid(level2_wolf) and Progress.second_fragment_recovered:
		level2_wolf.queue_free()

func _on_level2_wolf_defeated() -> void:
	if level2_chest != null:
		level2_chest.unlock()
	hud.show_finish_message("The Shadow Wolf falls. Recover the Second Fragment!")
	hud.set_objective("Open the Second Fragment chest, then activate the portal.")

func _on_level2_fragment_recovered() -> void:
	hud.show_finish_message("You have recovered the Second Fragment of the Eternal Tree!")
	hud.set_objective("Collect the required coins and activate the Level 3 portal.")


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
	call_deferred("_play_frozen_arrival_reveal")

func _play_frozen_arrival_reveal() -> void:
	if frozen_skies == null or not is_instance_valid($View):
		return
	var view: Node3D = $View
	view.input_enabled = false
	var start_zoom: float = view.zoom
	var start_rotation: Vector3 = view.camera_rotation
	var reveal_rotation := Vector3(-20.0, start_rotation.y + 12.0, 0.0)
	var tween := create_tween()
	tween.tween_property(view, "camera_rotation", reveal_rotation, 0.65)
	tween.parallel().tween_property(view, "zoom", minf(start_zoom + 4.0, view.zoom_minimum), 0.65)
	tween.tween_interval(0.8)
	tween.tween_property(view, "camera_rotation", start_rotation, 0.65)
	tween.parallel().tween_property(view, "zoom", start_zoom, 0.65)
	tween.tween_callback(func(): view.input_enabled = true)


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
		_update_frozen_portal_objective()
	)


func _on_frozen_fragment_recovered() -> void:
	if frozen_skies != null:
		frozen_skies.thaw_environment()
	hud.show_finish_message("You have recovered the Third Fragment of the Eternal Tree!")
	_update_frozen_portal_objective()
	_update_frozen_progress_hud()


func _on_frozen_mechanism_progress(current: int, total: int) -> void:
	_update_frozen_ability_hud()
	_update_frozen_progress_hud()
	if current >= total:
		hud.set_objective("All three frozen seals are active. Defeat the Frost Titan.")
	else:
		hud.set_objective("Activate the frozen mechanisms: %d / %d" % [current, total])

func _on_frozen_crystal_light_solved() -> void:
	_update_frozen_ability_hud()
	hud.show_finish_message("Crystal light aligned! The frozen gate responds.")
	hud.set_objective("Crystal light aligned. Continue through Frozen Crystal Caves.")
	_update_frozen_progress_hud()

func _on_frozen_generator_progress(current: int, total: int) -> void:
	_update_frozen_progress_hud()
	if current >= total and not Progress.frozen_crystal_blocks_aligned:
		hud.show_finish_message("Generators charged. Align the three crystal blocks.")
		hud.set_objective("Align the three crystal blocks to open the ancient cave door.")
	elif current >= total:
		hud.show_finish_message("All three crystal generators are charged. The cave door opens!")
		hud.set_objective("Continue through the Shattered Ice Fortress.")
	else:
		hud.set_objective("Activate the crystal generators: %d / %d" % [current, total])

func _on_frozen_block_progress(aligned: bool, _total: int) -> void:
	_update_frozen_progress_hud()
	if aligned and Progress.frozen_generators_activated >= 3:
		hud.show_finish_message("Crystal blocks aligned. The cave door opens!")
		hud.set_objective("Continue through the Shattered Ice Fortress.")
	elif aligned:
		hud.set_objective("Crystal blocks aligned. Activate all three crystal generators.")
	else:
		hud.set_objective("Align the crystal blocks: rotate each block into its glowing slot.")

func _on_frozen_mechanism_blocked(message: String) -> void:
	hud.show_finish_message(message)

func _on_frozen_return_portal_entered(body: Node3D) -> void:
	if body != player and body != player_two:
		return
	if not Progress.second_fragment_recovered:
		hud.show_finish_message("The Level 2 portal needs the Second Fragment.")
		return
	get_tree().set_meta("level_number", 2)
	Engine.time_scale = 1.0
	hud.play_level_transition("RETURNING TO LEVEL 2 – WHISPERING WOODS", func(): get_tree().reload_current_scene())

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
		Progress.frozen_generators_activated,
		Progress.frozen_crystal_blocks_aligned)

func _update_frozen_portal_objective() -> void:
	if frozen_skies == null:
		return
	if frozen_skies.boss_defeated and Progress.third_fragment_recovered and coins_collected >= coin_goal:
		hud.set_objective("The path to the fourth island has opened! Step through the icy portal.")
	else:
		# Keep the HUD and portal interaction in agreement about every remaining requirement.
		hud.set_objective(frozen_skies.portal_blocked_reason(coins_collected))


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
	if level_number == 5:
		second_checkpoint = route_size - 11
	elif level_number == 3:
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
	if level_number == 5:
		if i in [8, 9, 20, 21, 30]:
			var falling_platform: Node3D = PLATFORM_FALLING.instantiate()
			falling_platform.name = "ShatteredPath_%02d" % i
			falling_platform.position = point
			falling_platform.add_to_group("material_dimension")
			_apply_fortress_stone(falling_platform, Color("#4a285f"))
			world.add_child(falling_platform)
			return
		if i in [13, 24]:
			_add_moving_platform(route, i, point)
			return
		var fortress_platform: Node3D = PLATFORM_MEDIUM.instantiate() if i % 3 == 1 else PLATFORM_GRASS.instantiate()
		fortress_platform.name = "FortressRoute_%02d" % i
		fortress_platform.position = point
		fortress_platform.scale = Vector3(1.12, 1.0, 1.12)
		fortress_platform.add_to_group("material_dimension")
		_apply_fortress_stone(fortress_platform, Color("#51485d"))
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


func _apply_fortress_stone(root: Node, tint: Color) -> void:
	var material_key := tint.to_html()
	var stone_material: StandardMaterial3D
	if _fortress_material_cache.has(material_key):
		stone_material = _fortress_material_cache[material_key] as StandardMaterial3D
	else:
		stone_material = _map_material(tint)
		_fortress_material_cache[material_key] = stone_material
	for mesh_node in root.find_children("*", "MeshInstance3D", true, false):
		(mesh_node as MeshInstance3D).material_override = stone_material


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
	visual.material_override = _map_material(Color("#c04aff" if current_level == 5 else "#54e0d0"), true)
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
	_add_fortress_route_roots(route)

	# Shadow Guardians patrol the halls.
	var guardian_roles: Array[String] = ["Shadow Knight", "Void Mage", "Abyss Guardian", "Mirror Phantom"]
	var guardian_index := 0
	for fraction: float in [0.15, 0.40, 0.65, 0.85]:
		var index: int = clampi(roundi(float(n - 1) * fraction), 1, n - 2)
		_add_shadow_guardian(route[index] + Vector3(0, 0.6, 0), guardian_roles[guardian_index])
		guardian_index += 1

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
	boss.set("attacks_enabled", false)
	world.add_child(boss)
	boss.call("configure", tree.get_node("TreeCanopy"))
	boss.connect("encounter_phase_changed", Callable(self, "_on_fortress_boss_phase_changed"))
	boss.connect("encounter_completed", Callable(self, "_on_fortress_boss_completed"))
	fortress_boss = boss
	fortress_boss_complete = false

	# Spawn safely on the island terrace, facing the castle approach.
	player.global_position = _castle_spawn + Vector3(0, 0.55, 0)
	player.velocity = Vector3.ZERO
	checkpoint_position = player.global_position
	active_checkpoint = 0

func _add_shadow_guardian(point: Vector3, guardian_type: String = "Shadow Knight") -> void:
	var guardian := Area3D.new()
	guardian.name = guardian_type.replace(" ", "")
	guardian.set_script(SHADOW_GUARDIAN_SCRIPT)
	guardian.position = point
	guardian.set("patrol_radius", 0.68 if guardian_type == "Abyss Guardian" else 0.9)
	guardian.set("patrol_speed", 1.45 if guardian_type == "Abyss Guardian" else 2.0)
	guardian.set("hover_height", 0.95)
	guardian.set_meta("guardian_type", guardian_type)
	guardian.collision_layer = 0
	guardian.collision_mask = 1
	var shape_node := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.58
	shape_node.shape = sphere
	shape_node.position.y = 1.05
	guardian.add_child(shape_node)
	var orb := MeshInstance3D.new()
	var orb_mesh: Mesh
	match guardian_type:
		"Shadow Knight":
			var capsule := CapsuleMesh.new()
			capsule.radius = 0.38
			capsule.height = 1.0
			orb_mesh = capsule
		"Abyss Guardian":
			var armor := BoxMesh.new()
			armor.size = Vector3(0.8, 0.9, 0.8)
			orb_mesh = armor
		_:
			var wisp := SphereMesh.new()
			wisp.radius = 0.46
			wisp.height = 0.92
			orb_mesh = wisp
	orb.mesh = orb_mesh
	orb.position.y = 1.05
	var guardian_tint := Color("#271943")
	if guardian_type == "Void Mage":
		guardian_tint = Color("#5a237a")
	elif guardian_type == "Abyss Guardian":
		guardian_tint = Color("#171322")
	elif guardian_type == "Mirror Phantom":
		guardian_tint = Color("#633ca0")
	orb.material_override = _map_material(guardian_tint, true)
	guardian.add_child(orb)
	if guardian_type == "Shadow Knight":
		var blade := MeshInstance3D.new()
		blade.mesh = _box_mesh(Vector3(0.12, 0.9, 0.12))
		blade.position = Vector3(0.55, 0.9, -0.05)
		blade.rotation.z = deg_to_rad(-22.0)
		blade.material_override = _map_material(Color("#ad8bff"), true)
		guardian.add_child(blade)
	elif guardian_type == "Abyss Guardian":
		var shield := MeshInstance3D.new()
		shield.mesh = _box_mesh(Vector3(0.22, 0.8, 0.72))
		shield.position = Vector3(0.43, 1.0, -0.05)
		shield.material_override = _map_material(Color("#39334a"))
		guardian.add_child(shield)
	var eye := MeshInstance3D.new()
	var eye_mesh := BoxMesh.new()
	eye_mesh.size = Vector3(0.48, 0.1, 0.12)
	eye.mesh = eye_mesh
	eye.position = Vector3(0, 1.12, -0.4)
	eye.material_override = _map_material(Color("#ff315d" if guardian_type != "Void Mage" else "#74f3ff"), true)
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
				_add_torch(column_base + Vector3(0, 4.0, 0), side < 0.0 and row == 0)

	# Banners on the far wall.
	_add_banner(Vector3(cx - 3.0, floor_y + 7.0, cz - half_z + 0.6), 2.2, 3.4)
	_add_banner(Vector3(cx + 3.0, floor_y + 7.0, cz - half_z + 0.6), 2.2, 3.4)

	# Clear interior walkways connect the platform course without forcing precision beams.
	for index: int in [5, 11, 17, 23, 29]:
		if index + 1 < route.size():
			_add_balance_beam(route[index], route[index + 1])
	# Keep a visible dark rift floor under the route, with collision left to the death zone.
	_add_castle_deco(_box_mesh(Vector3(half_x * 1.25, 0.12, half_z * 1.3)), Vector3(cx, floor_y - 0.12, cz), Color("#171322"), true)
	# Tall gallery partitions stop players from skipping the conduit gates around their ends.
	_add_castle_block(Vector3(-2.1, floor_y + 7.0, cz + 1.0), Vector3(0.8, 14.0, half_z * 2.0 - 4.0), Color("#292433"))
	_add_castle_block(Vector3(14.1, floor_y + 7.0, cz + 1.0), Vector3(0.8, 14.0, half_z * 2.0 - 4.0), Color("#292433"))

	# Teleport arrival arch inside the entrance.
	_add_entrance_arch(route[0])

	# Grand gate in the front wall, the outdoor parkour approach, and the arrival point.
	_add_castle_gate(Vector3(cx, floor_y, front_z))
	_add_island_scatter(cx, cz, terrace_y)
	_add_island_waterfalls(cx, cz, terrace_y, 58.0)
	_add_island_grass(cx, cz, terrace_y, front_z)
	_add_approach(cx, front_z, floor_y, terrace_y)
	_add_castle_entry_path(cx, front_z, floor_y)
	_add_island_parkour(cx, cz, terrace_y, half_x, half_z, front_z)
	_add_island_life(cx, cz, terrace_y, half_x, half_z, front_z)
	_add_fortress_life(cx, cz, floor_y, half_x, half_z, front_z)
	_castle_spawn = Vector3(cx, terrace_y + 0.55, front_z - 30.0)
	_add_map_ring(Vector3(cx, terrace_y + 0.2, front_z - 30.0), 2.2, Color("#ff5fd0"))
	_add_fortress_facade(cx, cz, floor_y, half_x, half_z, front_z, wall_h)
	_add_fortress_abyss(cx, cz, floor_y, half_x, half_z)


func _add_throne_room(goal: Vector3) -> void:
	# Raised black-stone dais and ribbed columns frame Malakar's throne.
	_add_castle_block(goal + Vector3(0, 0.12, 0), Vector3(12.0, 0.9, 11.0), Color("#272033"))
	_add_castle_block(goal + Vector3(0, 0.72, 0.5), Vector3(9.5, 0.3, 8.8), Color("#49334f"))
	for offset in [Vector3(-4.8, 0, -3.8), Vector3(4.8, 0, -3.8), Vector3(-4.8, 0, 4.0), Vector3(4.8, 0, 4.0)]:
		_add_castle_pillar(goal + offset + Vector3(0, 0.6, 0), 8.5)
		_add_castle_deco(_box_mesh(Vector3(1.3, 0.65, 1.3)), goal + offset + Vector3(0, 8.7, 0), Color("#8a3168"), true)
	# Spined throne silhouette behind the king.
	_add_castle_block(goal + Vector3(0, 1.7, 4.1), Vector3(3.0, 1.7, 2.0), Color("#17131e"))
	_add_castle_block(goal + Vector3(0, 4.1, 4.8), Vector3(3.6, 3.8, 0.8), Color("#24152f"))
	_add_castle_deco(_box_mesh(Vector3(4.1, 0.35, 1.0)), goal + Vector3(0, 6.15, 4.8), Color("#b43282"), true)
	for side: float in [-1.0, 1.0]:
		var throne_spike := CylinderMesh.new()
		throne_spike.bottom_radius = 0.42
		throne_spike.top_radius = 0.0
		throne_spike.height = 2.7
		_add_castle_deco(throne_spike, goal + Vector3(side * 1.75, 7.0, 4.8), Color("#3d294f"))
	# Vast mirror portal, faceted rim, and drifting corruption shards.
	var mirror := MeshInstance3D.new()
	mirror.name = "MalakarMirror"
	var mirror_mesh := SphereMesh.new()
	mirror_mesh.radius = 1.0
	mirror_mesh.height = 2.0
	mirror.mesh = mirror_mesh
	mirror.scale = Vector3(4.2, 6.0, 0.34)
	mirror.position = goal + Vector3(0, 8.2, 7.2)
	mirror.material_override = _map_material(Color("#38105f"), true)
	world.add_child(mirror)
	var mirror_rim := MeshInstance3D.new()
	var rim := TorusMesh.new()
	rim.inner_radius = 4.0
	rim.outer_radius = 4.35
	mirror_rim.mesh = rim
	mirror_rim.scale = Vector3(1.0, 1.42, 1.0)
	mirror_rim.position = goal + Vector3(0, 8.2, 7.2)
	mirror_rim.rotation.x = PI * 0.5
	mirror_rim.material_override = _map_material(Color("#d72de5"), true)
	world.add_child(mirror_rim)
	for i in range(7):
		var shard := MeshInstance3D.new()
		var shard_mesh := PrismMesh.new()
		shard_mesh.size = Vector3(0.42, 0.9 + float(i % 3) * 0.25, 0.35)
		shard.mesh = shard_mesh
		shard.name = "MirrorShard_%02d" % i
		shard.position = goal + Vector3(-4.0 + float(i) * 1.3, 5.5 + float(i % 3) * 1.1, 5.8 + sin(float(i)) * 0.6)
		shard.rotation.z = deg_to_rad(float(i % 2) * 18.0 - 9.0)
		shard.material_override = _map_material(Color("#bd3cff"), true)
		world.add_child(shard)
		var float_tween := create_tween().set_loops()
		float_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		float_tween.tween_property(shard, "position:y", shard.position.y + 0.55, 1.5 + float(i % 3) * 0.25)
		float_tween.tween_property(shard, "position:y", shard.position.y - 0.25, 1.7 + float(i % 2) * 0.2)
	_add_fortress_roots(goal)


func _add_fortress_facade(cx: float, cz: float, floor_y: float, half_x: float, half_z: float, front_z: float, wall_h: float) -> void:
	# Tall buttresses break up the broad curtain walls and give the gate a Gothic silhouette.
	for side: float in [-1.0, 1.0]:
		for row in range(4):
			var z := front_z + 5.0 + float(row) * ((half_z * 2.0 - 10.0) / 3.0)
			var x := cx + side * (half_x - 0.9)
			_add_castle_deco(_box_mesh(Vector3(1.3, wall_h + 1.0, 1.3)), Vector3(x, floor_y + wall_h * 0.5, z), Color("#332b40"))
			_add_castle_deco(_box_mesh(Vector3(2.1, 0.5, 1.8)), Vector3(x, floor_y + wall_h + 0.25, z), Color("#51445e"))
	# Slit windows and vertical violet runes along the entrance face.
	for side: float in [-1.0, 1.0]:
		for row in range(4):
			var x := cx + side * (7.0 + float(row) * 4.0)
			_add_castle_deco(_box_mesh(Vector3(0.42, 4.8, 0.12)), Vector3(x, floor_y + 7.0, front_z + 0.52), Color("#21182d"))
			_add_castle_deco(_box_mesh(Vector3(0.12, 4.0, 0.08)), Vector3(x, floor_y + 7.0, front_z + 0.43), Color("#9a34cc"), true)
	# A broken crown of masonry floats above the rear towers, held aloft by the mirror rift.
	for i in range(6):
		var fragment := MeshInstance3D.new()
		fragment.name = "FloatingCrenellation_%02d" % i
		fragment.mesh = _box_mesh(Vector3(3.0 + float(i % 2), 0.8, 1.6))
		fragment.position = Vector3(cx - 10.0 + float(i) * 4.0, floor_y + wall_h + 8.0 + float(i % 3), cz + half_z - 2.0)
		fragment.rotation = Vector3(0, float(i) * 0.35, deg_to_rad(float(i % 3) * 5.0 - 5.0))
		fragment.material_override = _map_material(Color("#49364f"))
		world.add_child(fragment)
		var float_tween := create_tween().set_loops()
		float_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		float_tween.tween_property(fragment, "position:y", fragment.position.y + 0.4, 2.0 + float(i % 3) * 0.3)
		float_tween.tween_property(fragment, "position:y", fragment.position.y - 0.2, 2.2 + float(i % 2) * 0.3)


func _add_fortress_roots(center: Vector3) -> void:
	# The Eternal Tree's roots invade the throne dais and climb its corrupted mirror.
	var root_points: Array[Vector3] = [
		center + Vector3(-7.0, 0.15, -3.0), center + Vector3(-4.0, 0.5, -1.5),
		center + Vector3(-2.0, 0.8, 1.0), center + Vector3(0.0, 1.0, 4.0),
		center + Vector3(2.2, 0.6, -0.5), center + Vector3(4.7, 0.25, -2.7),
		center + Vector3(6.8, 0.2, 1.8), center + Vector3(3.0, 2.2, 4.6),
	]
	for i in range(root_points.size() - 1):
		var start: Vector3 = root_points[i]
		var finish_point: Vector3 = root_points[i + 1]
		var direction := finish_point - start
		var segment := MeshInstance3D.new()
		var root_mesh := CylinderMesh.new()
		root_mesh.top_radius = 0.12
		root_mesh.bottom_radius = 0.34 if i % 2 == 0 else 0.25
		root_mesh.height = direction.length()
		segment.mesh = root_mesh
		segment.position = (start + finish_point) * 0.5
		segment.rotation = Quaternion(Vector3.UP, direction.normalized()).get_euler()
		segment.material_override = _map_material(Color("#38203c" if i % 2 == 0 else "#61315f"), i % 3 == 0)
		world.add_child(segment)
	var heart := OmniLight3D.new()
	heart.name = "CorruptedTreeLight"
	heart.position = center + Vector3(-3.4, 4.0, 2.6)
	heart.light_color = Color("#a52fe0")
	heart.light_energy = 1.4
	heart.omni_range = 10.0
	world.add_child(heart)


func _add_fortress_route_roots(route: Array) -> void:
	# Root tendrils creep along the broken gallery edges and lead the eye toward the tree.
	for index in [2, 8, 14, 20, 26, 32]:
		if index + 2 >= route.size():
			continue
		var direction: Vector3 = route[index + 2] - route[index]
		direction.y = 0.0
		var across := Vector3(-direction.z, 0.0, direction.x).normalized()
		var side := 1.0 if index % 4 == 0 else -1.0
		var offset := across * side * 1.05 + Vector3(0, 0.62, 0)
		var start: Vector3 = route[index] + offset
		var end_point: Vector3 = route[index + 2] + offset + Vector3(0, 0.12, 0)
		var length := start.distance_to(end_point)
		var tendril := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.08
		mesh.bottom_radius = 0.23
		mesh.height = length
		tendril.mesh = mesh
		tendril.position = (start + end_point) * 0.5
		tendril.rotation = Quaternion(Vector3.UP, (end_point - start).normalized()).get_euler()
		tendril.material_override = _map_material(Color("#47214e"), index % 2 == 0)
		world.add_child(tendril)


func _configure_fortress_environment(phase: int) -> void:
	var source: Environment = $Environment.environment
	if source == null:
		return
	var env := source.duplicate(true) as Environment
	$Environment.environment = env
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#120b1c")
	env.sky = null
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_density = 0.012
	env.fog_aerial_perspective = 0.35
	match phase:
		1:
			env.ambient_light_color = Color("#75517f")
			env.fog_light_color = Color("#21162e")
			$Sun.light_color = Color("#b58bd5")
			$Sun.light_energy = 0.72
		2:
			env.ambient_light_color = Color("#486c9c")
			env.fog_light_color = Color("#101b38")
			$Sun.light_color = Color("#8ab9ff")
			$Sun.light_energy = 0.66
		_:
			env.ambient_light_color = Color("#8f385d")
			env.fog_light_color = Color("#2c101d")
			$Sun.light_color = Color("#ff568a")
			$Sun.light_energy = 0.8


func _on_fortress_boss_phase_changed(phase: int) -> void:
	if phase == 1:
		hud.show_finish_message("PHASE I — SHADOW MANIPULATION")
		_add_shadow_guardian(finish.global_position + Vector3(-3.0, 0.5, 3.0), "Shadow Knight")
		_add_shadow_guardian(finish.global_position + Vector3(3.0, 0.5, 3.0), "Void Mage")
	elif phase == 2:
		mirror_dimension = true
		shift_active = false
		_apply_dimension_visibility()
		_configure_fortress_environment(2)
		hud.show_finish_message("PHASE II — THE MIRROR DIMENSION")
		_add_shadow_guardian(finish.global_position + Vector3(-4.0, 0.5, -2.0), "Mirror Phantom")
		_add_shadow_guardian(finish.global_position + Vector3(4.0, 0.5, -2.0), "Mirror Phantom")
	else:
		mirror_dimension = false
		_apply_dimension_visibility()
		_configure_fortress_environment(3)
		hud.show_finish_message("PHASE III — ETERNAL CORRUPTION")
		_add_shadow_guardian(finish.global_position + Vector3(0.0, 0.5, 5.0), "Abyss Guardian")


func _on_fortress_boss_completed() -> void:
	fortress_boss_complete = true
	mirror_dimension = false
	_apply_dimension_visibility()
	_configure_fortress_environment(1)
	hud.show_finish_message("THE ETERNAL TREE IS FREE")
	_complete_level()


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
	grass_material.albedo_color = Color("#57445f" if current_level == 5 else "#a7d35d")
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


func _add_torch(point: Vector3, add_light: bool = true) -> void:
	_add_castle_deco(_box_mesh(Vector3(0.12, 0.4, 0.12)), point, Color("#241f2e"))
	_add_castle_deco(_sphere_mesh(0.16), point + Vector3(0, 0.42, 0), Color("#ffb054"), true)
	if add_light:
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
	water_material.albedo_color = Color(0.55, 0.18, 0.72, 0.72) if current_level == 5 else Color(0.24, 0.78, 0.96, 0.72)
	water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	water_material.emission_enabled = true
	water_material.emission = Color("#b63fe4" if current_level == 5 else "#53cfff")
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
	var grass_material := _map_material(Color("#51405a" if current_level == 5 else "#6da943"))
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
		_apply_fortress_stone(step, Color("#51485d"))
		if i % 2 == 1:
			step.scale = Vector3(0.82, 1.0, 0.82)
		world.add_child(step)
	# A ruined archway partway along the climb.
	_add_castle_deco(_box_mesh(Vector3(0.5, 3.0, 0.5)), Vector3(cx - 6.0, terrace_y + 2.5, front_z - 17.5), Color("#4a4458"))
	_add_castle_deco(_box_mesh(Vector3(0.5, 3.0, 0.5)), Vector3(cx + 6.0, terrace_y + 2.5, front_z - 17.5), Color("#4a4458"))
	_add_castle_deco(_box_mesh(Vector3(12.5, 0.6, 0.6)), Vector3(cx, terrace_y + 4.0, front_z - 17.5), Color("#4a4458"))


func _add_castle_entry_path(cx: float, front_z: float, floor_y: float) -> void:
	var gate_lip := _add_castle_block(Vector3(cx, floor_y + 0.88, front_z - 2.4), Vector3(3.0, 0.35, 2.5), Color("#4d4658"))
	gate_lip.name = "GateThreshold_Lip"
	for i in range(5):
		var z := front_z + 1.0 + float(i) * 2.35
		var x := lerpf(cx, 0.0, float(i + 1) / 6.0)
		var slab := _add_castle_block(Vector3(x, floor_y + 0.88, z), Vector3(2.8, 0.35, 2.45), Color("#4d4658"))
		slab.name = "GateThreshold_%02d" % i
		if i % 2 == 1:
			_add_castle_deco(_box_mesh(Vector3(2.2, 0.05, 0.12)), Vector3(x, floor_y + 1.08, z), Color("#a731c4"), true)


func _add_fortress_abyss(cx: float, cz: float, floor_y: float, _half_x: float, half_z: float) -> void:
	var abyss := Area3D.new()
	abyss.name = "CorruptedAbyss"
	abyss.position = Vector3(cx, floor_y - 0.02, cz + 1.0)
	abyss.collision_layer = 0
	abyss.collision_mask = 1
	var shape := CollisionShape3D.new()
	var volume := BoxShape3D.new()
	volume.size = Vector3(15.2, 0.22, half_z * 2.0 - 6.0)
	shape.shape = volume
	abyss.add_child(shape)
	abyss.body_entered.connect(_on_fortress_abyss_body_entered)
	world.add_child(abyss)
	var rift := MeshInstance3D.new()
	rift.name = "AbyssRiftGlow"
	rift.mesh = _box_mesh(Vector3(15.2, 0.04, half_z * 2.0 - 6.0))
	rift.position = Vector3(cx, floor_y - 0.02, cz + 1.0)
	rift.material_override = _map_material(Color("#38134c"), true)
	world.add_child(rift)
	var rift_light := OmniLight3D.new()
	rift_light.name = "AbyssLight"
	rift_light.position = Vector3(cx, floor_y + 0.8, cz)
	rift_light.light_color = Color("#7121a0")
	rift_light.light_energy = 1.1
	rift_light.omni_range = 18.0
	world.add_child(rift_light)


func _on_fortress_abyss_body_entered(body: Node3D) -> void:
	if body.has_method("die"):
		body.call("die")


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
		_apply_fortress_stone(step, Color("#51485d"))
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
		_apply_fortress_stone(step, Color("#51485d"))
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
		_add_island_tree(point, 2.0 + float(i % 3) * 0.25, Color("#513457" if current_level == 5 else ("#5e9a62" if i % 2 == 0 else "#9bbd65")))
		for flower_index in range(4):
			var flower_angle := angle + float(flower_index) * TAU / 4.0
			var flower_point := point + Vector3(cos(flower_angle) * 1.5, 0.14, sin(flower_angle) * 1.5)
			var flower_color: Color = [Color("#b45de0"), Color("#e545aa"), Color("#8f6cff")][(i + flower_index) % 3] if current_level == 5 else [Color("#ffe285"), Color("#ff91bd"), Color("#d5a5ff")][(i + flower_index) % 3]
			_add_castle_deco(_sphere_mesh(0.12), flower_point, flower_color, true)
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
		_add_island_tree(Vector3(x, terrace_y + 0.05, z), 1.7 + float(i % 3) * 0.2, Color("#46304e" if current_level == 5 else "#5e9a62"))
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
		_add_castle_deco(_box_mesh(Vector3(3.6, 0.12, 5.0)), Vector3(cx, floor_y + 0.08, z), Color("#3c254f"))
		_add_castle_deco(_box_mesh(Vector3(2.6, 0.04, 0.16)), Vector3(cx, floor_y + 0.17, z), Color("#d5aa51"), true)
		for side: float in [-1.0, 1.0]:
			var x: float = cx + side * (half_x - 3.3)
			_add_brazier(Vector3(x, floor_y, z + 2.6), row % 2 == 0 and side < 0.0)
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
	_add_castle_deco(_box_mesh(Vector3(7.5, 0.16, 13.0)), Vector3(cx, floor_y + 0.08, front_z + 7.0), Color("#6f315a"))
	for i in range(6):
		var z := cz - half_z + 5.0 + float(i) * 10.0
		_add_wall_sconce(Vector3(cx - half_x + 1.3, floor_y + 4.5, z), -1.0, i % 3 == 0)
		_add_wall_sconce(Vector3(cx + half_x - 1.3, floor_y + 4.5, z), 1.0, false)


func _add_brazier(point: Vector3, add_light: bool = true) -> void:
	_add_castle_deco(_box_mesh(Vector3(1.0, 1.0, 1.0)), point + Vector3(0, 0.5, 0), Color("#332b3d"))
	_add_castle_deco(_box_mesh(Vector3(0.78, 0.16, 0.78)), point + Vector3(0, 1.05, 0), Color("#7f5366"))
	_add_castle_deco(_sphere_mesh(0.38), point + Vector3(0, 1.55, 0), Color("#ff8c40"), true)
	if add_light:
		var light := OmniLight3D.new()
		light.light_color = Color("#ff8b48")
		light.light_energy = 1.6
		light.omni_range = 7.0
		light.position = point + Vector3(0, 1.7, 0)
		world.add_child(light)


func _add_wall_sconce(point: Vector3, facing: float, add_light: bool = true) -> void:
	_add_castle_deco(_box_mesh(Vector3(0.16, 0.6, 0.16)), point, Color("#4a3a4e"))
	_add_castle_deco(_sphere_mesh(0.24), point + Vector3(0, 0.45, 0), Color("#ffba64"), true)
	if add_light:
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
	if level_number == 5:
		for gate_segment in [11, 23, 29]:
			_add_gate(route[gate_segment], route[gate_segment + 1])
		for index in [6, 17, 27]:
			_add_lever(route[index])
			_add_conduit_mirror(switches[switches.size() - 1], route[index], index)
		return
	# Twin-button puzzle: one button near the start, one near the flag, with a
	# locked inner gate in the middle. The first button opens the inner gate,
	# the second opens the final gate to the flag. Complex platforms and hazards
	# fill the whole stretch between the two buttons.
	var inner := _inner_gate_segment(route)
	_add_gate(route[inner], route[inner + 1])
	_add_gate(route[n - 2], route[n - 1])
	for index in _pick_switch_indices(level_number, n):
		_add_lever(route[index])


func _add_conduit_mirror(lever: Node3D, point: Vector3, index: int) -> void:
	lever.name = "EnergyConduit_%02d" % index
	var reflector := Node3D.new()
	reflector.name = "Reflector"
	reflector.position = Vector3(0.0, 0.65, -0.8)
	lever.add_child(reflector)
	var stand := MeshInstance3D.new()
	stand.mesh = _box_mesh(Vector3(0.85, 0.85, 0.5))
	stand.position.y = 0.05
	stand.material_override = _map_material(Color("#34243f"))
	reflector.add_child(stand)
	var mirror_face := MeshInstance3D.new()
	var face_mesh := BoxMesh.new()
	face_mesh.size = Vector3(0.16, 1.2, 1.0)
	mirror_face.mesh = face_mesh
	mirror_face.position.y = 0.7
	mirror_face.rotation.z = deg_to_rad(-14.0 if index % 2 == 0 else 14.0)
	var face_material := _map_material(Color("#5a3480"), true)
	face_material.metallic = 0.82
	mirror_face.material_override = face_material
	reflector.add_child(mirror_face)
	reflector.set_meta("face_material", face_material)
	lever.set_meta("reflector", reflector)
	_add_map_ring(point + Vector3(0, 0.2, 0), 1.05, Color("#b43dff"))
	for beam_index in range(2):
		var beam := MeshInstance3D.new()
		beam.name = "ConduitBeam"
		beam.mesh = _box_mesh(Vector3(0.12, 0.12, 1.4))
		beam.position = point + Vector3(0, 1.0, -1.0 + float(beam_index) * 1.6)
		beam.rotation.y = deg_to_rad(18.0 if beam_index == 0 else -18.0)
		beam.material_override = _map_material(Color("#b638f5"), true)
		world.add_child(beam)


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
	var gate_size := Vector3(3.8, 2.1, 0.35)
	var open_drop := 2.6
	if current_level == 5:
		var route_floor := 1.9
		var route_top := (from_point.y + to_point.y) * 0.5 + 2.0
		gate_size = Vector3(16.5, maxf(route_top - route_floor, 3.0), 0.5)
		mid = Vector3(6.0, route_floor + gate_size.y * 0.5, (from_point.z + to_point.z) * 0.5)
		open_drop = gate_size.y + 1.2
	var gate := StaticBody3D.new()
	gate.name = "PuzzleGate"
	gate.set_script(PUZZLE_GATE_SCRIPT)
	gate.position = mid
	gate.rotation.y = yaw
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = gate_size
	shape.shape = box
	gate.add_child(shape)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = gate_size
	visual.mesh = mesh
	visual.material_override = _map_material(Color("#ff6b8a"), true)
	gate.add_child(visual)
	gate.set("open_drop", open_drop)
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
				if current_level == 5 and switches_pressed < switches.size() and lever != switches[switches_pressed]:
					hud.show_finish_message("THE ENERGY MUST BE REFLECTED IN ORDER")
					return
				_press_switch(lever)
				return


func _press_switch(lever: Node3D) -> void:
	lever.set_meta("pressed", true)
	var material: StandardMaterial3D = lever.get_meta("material")
	material.albedo_color = Color("#65f6ad")
	material.emission = Color("#25ff95")
	var reflector: Node3D = lever.get_meta("reflector", null)
	if reflector != null:
		var face_material: StandardMaterial3D = reflector.get_meta("face_material")
		face_material.albedo_color = Color("#75ffe6")
		face_material.emission = Color("#48ffd4")
		reflector.rotation.y += deg_to_rad(42.0)
	switches_pressed += 1
	# Each button opens the gate that corresponds to it (inner gate first, then
	# the final gate to the flag).
	var gate_index := switches_pressed - 1
	if gate_index >= 0 and gate_index < gates.size():
		gates[gate_index].open()
	if switches_pressed >= switches.size():
		puzzle_solved = true
		hud.show_finish_message("All three conduits aligned. The throne gate is open." if current_level == 5 else "Both buttons pressed! The flag gate is open!")
	else:
		if current_level == 5:
			hud.show_finish_message("Conduit %d of %d aligned. A mirror gate opens." % [switches_pressed, switches.size()])
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
	if frozen_skies != null and frozen_skies.has_method("reset_boss_encounter"):
		frozen_skies.reset_boss_encounter()
	for node in get_tree().get_nodes_in_group("frost_hazards"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("frozen_projectiles"):
		node.queue_free()
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
	marker.material_override = _map_material(Color("#d260ff" if current_level == 5 else "#54f4e8"), true)
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
		# Level 3 uses the dedicated Frozen Skies builder above.
		_serpentine_route(5, 5, 2.4, 0.3),
		# 4 Rising Ruins: 30 platforms.
		_serpentine_route(5, 6, 2.4, 0.3),
		# 5 Malakar's Fortress: a rising 36-platform gallery over the corrupted abyss.
		_fortress_route(),
		# 6 Gimmick Gauntlet: 42 platforms stuffed with new puzzle surfaces.
		_serpentine_route(6, 7, 2.4, 0.28),
	]


func _fortress_route() -> Array:
	var route := _serpentine_route(6, 6, 2.4, 0.28)
	for i in range(route.size()):
		var point: Vector3 = route[i]
		point.y += 2.4
		route[i] = point
	return route


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
	if event.is_action_pressed("interact"):
		if frozen_skies != null and frozen_skies.try_activate_nearby(player):
			return
		if not puzzle_solved:
			_try_press_switch()


func _on_coin_collected(_coins: int) -> void:
	coins_collected += 1
	hud._on_coin_collected(coins_collected)
	if island != null:
		# The island watches its own coin count: it needs 30 for the portal, and
		# the level holds more than that on purpose.
		island.notify_coins(coins_collected)
		return
	if woods != null:
		woods.notify_coins(coins_collected)
		return
	if coins_collected >= coin_goal:
		hud.show_finish_message("All coins collected! Press the switches, then reach the flag!")
	if frozen_skies != null and coins_collected >= coin_goal \
			and frozen_skies.boss_defeated and Progress.third_fragment_recovered:
		_update_frozen_portal_objective()


func _on_finish_body_entered(body: Node3D) -> void:
	if body != player and body != player_two:
		return
	if current_level == 5 and not fortress_boss_complete:
		if fortress_boss != null and is_instance_valid(fortress_boss) and not bool(fortress_boss.get("encounter_started")):
			hud.show_finish_message("SURVIVE THE SHADOW KING — THE TREE IS STILL FIGHTING")
			fortress_boss.call("start_encounter")
		return
	if woods != null and not woods.is_portal_ready():
		if _portal_locked_cooldown <= 0.0:
			_portal_locked_cooldown = 2.5
			hud.show_finish_message("Rescue the forest creatures, defeat the Shadow Wolf, and recover the Second Fragment.")
		return
	if frozen_skies != null and not frozen_skies.is_portal_ready(coins_collected):
		if _portal_locked_cooldown <= 0.0:
			_portal_locked_cooldown = 2.5
			hud.show_finish_message(frozen_skies.portal_blocked_reason(coins_collected))
		return
	if level2_wolf != null and is_instance_valid(level2_wolf):
		if _portal_locked_cooldown <= 0.0:
			_portal_locked_cooldown = 2.5
			hud.show_finish_message("Defeat the Shadow Wolf to open the Level 3 portal.")
		return
	if level2_chest != null and not Progress.second_fragment_recovered:
		if _portal_locked_cooldown <= 0.0:
			_portal_locked_cooldown = 2.5
			hud.show_finish_message("Recover the Second Fragment to open the Level 3 portal.")
		return
	if current_level == 2 and coins_collected < coin_goal:
		if _portal_locked_cooldown <= 0.0:
			_portal_locked_cooldown = 2.5
			hud.show_finish_message("Collect all required coins: %d/%d." % [coins_collected, coin_goal])
		return
	if island != null and not island.is_portal_ready():
		# The portal is dormant until the guardian is gone, the Fragment is
		# recovered and the coins are in.
		if _portal_locked_cooldown <= 0.0:
			_portal_locked_cooldown = 2.5
			hud.show_finish_message(island.portal_blocked_reason())
		return
	# Reaching the flag - or stepping through an open portal - finishes the level.
	_complete_level()


func _complete_level() -> void:
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
	if current_level == 5 and fortress_boss != null and is_instance_valid(fortress_boss):
		fortress_boss.call("reset_encounter")
		mirror_dimension = false
		_apply_dimension_visibility()
		_configure_fortress_environment(1)
	if local_coop:
		# In co-op, drop the fallen player back in rather than stopping the game.
		respawn_player(who)
	elif frozen_skies != null:
		hud.show_finish_message("The frost claims you. Returning to the latest checkpoint...")
		await get_tree().create_timer(0.45).timeout
		if is_instance_valid(who) and bool(who.get("is_dead")):
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
	if not multiplayer.is_server() and multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
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
