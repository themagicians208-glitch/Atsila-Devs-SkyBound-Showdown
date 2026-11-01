extends CharacterBody3D

signal coin_collected
signal died
signal health_changed(current: float, maximum: float)
signal stamina_changed(current: float, maximum: float)
signal fly_mode_changed(enabled: bool)

@export_subgroup("Components")
@export var view: Node3D

@export_subgroup("Input")
@export var action_left := "move_left"
@export var action_right := "move_right"
@export var action_forward := "move_forward"
@export var action_back := "move_back"
@export var action_jump := "jump"
@export var action_dash := "dash"
@export var action_fly := "fly"
@export var action_time_freeze := "time_freeze"
@export var action_attack := "attack"
@export var action_ice_shield := "ice_shield"
@export var action_frost_dash := "frost_dash"

@export_subgroup("Properties")
@export var movement_speed = 250
@export var jump_strength = 7

# Which player this is (0-3). Drives the character's colour so co-op players and
# online peers look different from each other.
@export var player_index := 0

# Which character this player picked (see res://scripts/roster.gd). Empty means
# "keep whatever character the scene was built with".
@export var character_id := ""

@export_subgroup("Dash Skill")
@export var dash_speed_multiplier := 2.0
@export var dash_duration := 0.35
@export var dash_cooldown := 0.08
@export var dash_min_stamina_pct := 0.25

# --- Fighting, in the spirit of Hollow Knight ---------------------------------
# Slash an enemy for the fun of it; a down-slash on one bounces the player back
# into the air, which is the pogo. Being touched by one is fatal, the same way
# falling off the route is.
@export_subgroup("Combat")
@export var attack_damage := 1
@export var attack_range := 2.1
@export var attack_time := 0.18           # how long the slash stays visible
@export var attack_cooldown := 0.28
@export var pogo_strength := 6.2
@export var hurt_knockback := 5.5

@export_subgroup("Vitals")
@export var max_health: float = 100.0
@export var max_stamina: float = 100.0
@export var dash_stamina_cost: float = 25.0
@export var dash_stamina_drain: float = 20.0
@export var attack_stamina_cost: float = 8.0
@export var stamina_regen_rate: float = 24.0

var movement_velocity: Vector3
var rotation_direction: float
var gravity = 0
var gravity_scale := 1.0
var time_freeze_active := false
var freeze_cooldown := 0.0

var previously_floored = false

var jumps_remaining := 2

var coins = 0
var fly_mode := false

var is_dead := false
var health: float = 100.0
var stamina: float = 100.0
var last_death_cause: String = "fall"

# Floating name tag shown above the player (local co-op / online).
var player_name := ""
var name_label: Label3D

# Resolved animation names (logical -> real clip name), so any rig's naming works.
var _anim_cache: Dictionary = {}
var _pose_state := ""

const ROSTER := preload("res://scripts/roster.gd")

# Dash skill state
var is_dashing := false
var dash_time_left := 0.0
var dash_cooldown_left := 0.0
var dash_lean := 0.0
var dash_bob := 0.0
var model_rest_rotation := Vector3.ZERO
var model_rest_position := Vector3.ZERO

# Surface / gimmick state (set by zones in level 6)
var slippery := false                  # ice / oil slick: little traction
var sticky := false                    # velcro: kills horizontal momentum
var external_velocity := Vector3.ZERO  # conveyor push (log rollers, slides)
var wind_lift := 0.0                   # fan tunnel updraft

# Combat state
var attack_dir := 0                    # 0 forward, 1 up, -1 down
var attack_timer := 0.0
var attack_cooldown_left := 0.0
var knockback := Vector3.ZERO
var _slash: MeshInstance3D
var _slash_material: StandardMaterial3D
var _slash_life := 0.0
var _slash_base := Vector3.ONE
var _swing_amount := 0.0               # 0..1 through an attack, drives the pose
var ice_shield_active := false
var ice_shield_cooldown_left := 0.0
var frost_dash_cooldown_left := 0.0
var frost_dash_time_left := 0.0
var _ice_shield_visual: MeshInstance3D

@onready var particles_trail = $ParticlesTrail
@onready var sound_footsteps = $SoundFootsteps
@onready var model: Node3D = $Character
@onready var animation: AnimationPlayer = _find_animation_player(model)


func _ready() -> void:
	_apply_character_choice()
	var has_controller_jump := false
	for event in InputMap.action_get_events("jump").duplicate():
		if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_A:
			has_controller_jump = true
		elif event is InputEventJoypadButton and event.button_index == JOY_BUTTON_B:
			InputMap.action_erase_event("jump", event)
	if not has_controller_jump:
		var jump_button := InputEventJoypadButton.new()
		jump_button.button_index = JOY_BUTTON_A
		jump_button.device = -1
		InputMap.action_add_event("jump", jump_button)
	if not _jump_has_mouse_binding():
		var mouse_jump := InputEventMouseButton.new()
		mouse_jump.button_index = MOUSE_BUTTON_LEFT
		mouse_jump.device = -1
		InputMap.action_add_event("jump", mouse_jump)
	_ensure_dash_action()
	_ensure_frozen_actions()
	_build_ice_shield_visual()
	model_rest_rotation = model.rotation
	model_rest_position = model.position
	if model.has_method("set_player_index"):
		model.set_player_index(player_index)

	add_to_group("player")
	_ensure_combat_actions()
	_build_slash()
	reset_vitals()


func set_player_index(index: int) -> void:
	player_index = index
	if model != null and model.has_method("set_player_index"):
		model.set_player_index(index)


## Swap in the character this player picked. This runs before anything else touches
## `model`, so the rest of the controller never has to know the difference.
func _apply_character_choice() -> void:
	var chosen := character_id
	if chosen.is_empty():
		chosen = str(get_tree().get_meta("p1_character", ""))
	if chosen.is_empty() or not ROSTER.has(chosen):
		return
	var scene_path := ROSTER.scene_for(chosen)
	if scene_path.is_empty():
		return
	var existing := get_node_or_null("Character")
	if existing != null and existing.scene_file_path == scene_path:
		return
	var replacement: Node3D = load(scene_path).instantiate()
	# Retire the old character first, or it still owns the name and the new one
	# ends up as "@Node3D@15", which anything looking it up by name would miss.
	if existing != null:
		remove_child(existing)
		existing.queue_free()
	add_child(replacement)
	replacement.name = "Character"
	replacement.set("player_index", player_index)
	model = replacement
	animation = _find_animation_player(model)


func _jump_has_mouse_binding() -> bool:
	for event in InputMap.action_get_events("jump"):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			return true
	return false


func _ensure_dash_action() -> void:
	if InputMap.has_action("dash"):
		return
	InputMap.add_action("dash")
	InputMap.action_set_deadzone("dash", 0.5)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_SHIFT
	key.device = -1
	InputMap.action_add_event("dash", key)
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_RIGHT_SHOULDER
	button.device = -1
	InputMap.action_add_event("dash", button)

func _ensure_frozen_actions() -> void:
	for action_name in [action_ice_shield, action_frost_dash]:
		if InputMap.has_action(action_name):
			continue
		InputMap.add_action(action_name)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_K if action_name == action_ice_shield else KEY_L
		key.device = -1
		InputMap.action_add_event(action_name, key)

func _build_ice_shield_visual() -> void:
	_ice_shield_visual = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.9
	mesh.height = 1.8
	_ice_shield_visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.9, 1.0, 0.22)
	material.emission_enabled = true
	material.emission = Color("#65e6ff")
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ice_shield_visual.material_override = material
	_ice_shield_visual.visible = false
	add_child(_ice_shield_visual)

func set_player_name(new_name: String) -> void:
	player_name = new_name
	if new_name.strip_edges().is_empty():
		if name_label != null:
			name_label.visible = false
		return
	if name_label == null:
		name_label = Label3D.new()
		name_label.name = "NameLabel"
		name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_label.no_depth_test = true
		name_label.font_size = 64
		name_label.outline_size = 16
		name_label.modulate = Color.WHITE
		name_label.outline_modulate = Color(0, 0, 0, 0.85)
		name_label.pixel_size = 0.006
		name_label.position = Vector3(0, 1.25, 0)
		add_child(name_label)
	name_label.text = new_name
	name_label.visible = true


# Functions

func _physics_process(delta):
	if is_dead:
		return

	if Input.is_action_just_pressed(action_time_freeze) and freeze_cooldown <= 0.0:
		_activate_time_freeze()

	if Input.is_action_just_pressed(action_dash) and dash_cooldown_left <= 0.0:
		_start_dash()
	if get_tree().get_meta("level_number", 1) == 3:
		if Input.is_action_just_pressed(action_ice_shield):
			_activate_ice_shield()
		if Input.is_action_just_pressed(action_frost_dash) and frost_dash_cooldown_left <= 0.0:
			_start_frost_dash()

	_update_dash(delta)
	_update_frost_dash(delta)
	_update_ice_shield(delta)
	_update_combat(delta)

	# Handle functions

	handle_gravity(delta)
	handle_controls(delta)

	handle_effects(delta)

	# Movement

	var applied_velocity: Vector3

	var control := 3.0 if slippery else 10.0
	applied_velocity = velocity.lerp(movement_velocity, delta * control)
	applied_velocity.y = -gravity
	applied_velocity.x += external_velocity.x + knockback.x
	applied_velocity.z += external_velocity.z + knockback.z
	if sticky:
		applied_velocity.x = 0.0
		applied_velocity.z = 0.0

	velocity = applied_velocity
	move_and_slide()

	# Rotation

	if Vector2(velocity.z, velocity.x).length() > 0:
		rotation_direction = Vector2(velocity.z, velocity.x).angle()

	rotation.y = lerp_angle(rotation.y, rotation_direction, delta * 10)

	# Falling into the void is fatal

	if position.y < -10:
		die("fall")

	# Animation for scale (jumping and landing)

	model.scale = model.scale.lerp(Vector3(1, 1, 1), delta * 10)

	handle_dash_animation(delta)

	# Animation when landing

	if is_on_floor() and gravity > 2 and !previously_floored:
		model.scale = Vector3(1.25, 0.75, 1.25)
		Audio.play("res://sounds/land.ogg")

	previously_floored = is_on_floor()

# Handle animation(s)

func handle_effects(delta):

	particles_trail.emitting = false
	sound_footsteps.stream_paused = true

	if is_on_floor():
		var horizontal_velocity = Vector2(velocity.x, velocity.z)
		var speed_factor = horizontal_velocity.length() / movement_speed / delta
		if speed_factor > 0.05:
			if _pose_state != "walk":
				_set_pose_state("walk")

			if speed_factor > 0.3:
				sound_footsteps.stream_paused = false
				sound_footsteps.pitch_scale = speed_factor

			if speed_factor > 0.75:
				particles_trail.emitting = true

		elif _pose_state != "idle":
			_set_pose_state("idle")

		if animation != null:
			if _pose_state == "walk":
				animation.speed_scale = speed_factor
			else:
				animation.speed_scale = 1.0

	elif _pose_state != "jump":
		_set_pose_state("jump")


# --- Animation helpers: work with whatever the character rig provides ---

func _find_animation_player(root: Node) -> AnimationPlayer:
	if root == null:
		return null
	var direct := root.get_node_or_null("AnimationPlayer")
	if direct is AnimationPlayer:
		return direct
	var found := root.find_children("*", "AnimationPlayer", true, false)
	return found[0] as AnimationPlayer if not found.is_empty() else null


func _current_anim() -> String:
	return String(animation.current_animation) if animation != null else ""


func _resolve_anim(logical: String) -> String:
	if animation == null:
		return ""
	if _anim_cache.has(logical):
		return _anim_cache[logical]
	var aliases: Dictionary = {
		"idle": ["idle", "Idle", "IDLE", "breathing", "Breathing", "idle_breathing"],
		"walk": ["walk", "Walk", "WALK", "run", "Run", "walking", "Walking"],
		"jump": ["jump", "Jump", "JUMP", "fall", "Fall", "air", "Air"],
	}
	var names := animation.get_animation_list()
	var resolved := ""
	for candidate in aliases.get(logical, [logical]):
		if names.has(candidate):
			resolved = candidate
			break
	_anim_cache[logical] = resolved
	return resolved


func _play(logical: String, blend: float = 0.1) -> void:
	if animation == null:
		return
	var anim_name := _resolve_anim(logical)
	if anim_name != "":
		animation.play(anim_name, blend)
		return
	# A rig that only ships a walk cycle: hold its first frame while standing still
	# instead of running on the spot.
	if logical == "idle":
		var walk_name := _resolve_anim("walk")
		if walk_name != "":
			animation.play(walk_name, blend)
			animation.seek(0.0, true)
			animation.pause()


func _set_pose_state(logical: String) -> void:
	_pose_state = logical
	_play(logical)

# Handle movement input

func handle_controls(delta):

	# Movement

	var input := Vector3.ZERO

	input.x = Input.get_axis(action_left, action_right)
	input.z = Input.get_axis(action_forward, action_back)

	input = input.rotated(Vector3.UP, view.rotation.y)

	if input.length() > 1:
		input = input.normalized()

	# Dash: if no direction is held, burst forward in the facing direction.
	if is_dashing and input.length_squared() < 0.0001:
		input = Vector3(sin(rotation.y), 0.0, cos(rotation.y))

	var speed_multiplier := dash_speed_multiplier if is_dashing else 1.0
	movement_velocity = input * movement_speed * speed_multiplier * delta

	# Jumping

	if Input.is_action_just_pressed(action_jump):

		if jumps_remaining > 0 or fly_mode:
			jump()

# Handle gravity

func handle_gravity(delta):

	if wind_lift > 0.0:
		# A fan tunnel overrides gravity and carries the player upward.
		gravity = -wind_lift
		jumps_remaining = 2
		return

	if is_on_floor() and gravity >= 0.0:
		gravity = 0
		jumps_remaining = 2
	else:
		gravity += 25 * gravity_scale * delta
		gravity = clampf(gravity, -5.0, 30.0)

# Jumping

func jump():

	Audio.play("res://sounds/jump.ogg")

	gravity = -jump_strength

	model.scale = Vector3(0.5, 1.5, 0.5)

	if fly_mode:
		jumps_remaining = 2
	else:
		jumps_remaining = maxi(0, jumps_remaining - 1)


func set_fly_mode(enabled: bool) -> void:
	fly_mode = enabled
	if fly_mode:
		jumps_remaining = 2
	fly_mode_changed.emit(fly_mode)


func toggle_fly_mode() -> bool:
	set_fly_mode(not fly_mode)
	return fly_mode


func cloud_bounce() -> void:
	gravity = -9.5
	jumps_remaining = 2
	model.scale = Vector3(0.75, 1.3, 0.75)
	Audio.play("res://sounds/jump.ogg")


# Gimmick surfaces (level 6)

func bounce(strength: float) -> void:
	gravity = -strength
	jumps_remaining = 2
	model.scale = Vector3(0.7, 1.4, 0.7)
	Audio.play("res://sounds/jump.ogg")


func set_slippery(enabled: bool) -> void:
	slippery = enabled


func set_sticky(enabled: bool) -> void:
	sticky = enabled
	if enabled:
		velocity.x = 0.0
		velocity.z = 0.0
		movement_velocity.x = 0.0
		movement_velocity.z = 0.0


func set_conveyor(push: Vector3) -> void:
	external_velocity = push


func set_wind(lift: float) -> void:
	wind_lift = lift

# Dash skill

func _start_dash() -> void:
	# Dashing is blocked when stamina is below 25% of max stamina
	var min_stamina := max_stamina * dash_min_stamina_pct
	if stamina < min_stamina:
		return
	is_dashing = true
	dash_time_left = dash_duration
	dash_cooldown_left = 0.0
	dash_bob = 0.0
	stamina = maxf(0.0, stamina - dash_stamina_cost)
	stamina_changed.emit(stamina, max_stamina)
	Audio.play("res://sounds/jump.ogg")


func _end_dash() -> void:
	is_dashing = false
	dash_time_left = 0.0
	dash_cooldown_left = dash_cooldown

func _start_frost_dash() -> void:
	if not Progress.frost_dash_unlocked or is_dead:
		return
	frost_dash_time_left = 0.3
	frost_dash_cooldown_left = 3.0
	is_dashing = true
	Audio.play("res://sounds/jump.ogg")

func _update_frost_dash(delta: float) -> void:
	if frost_dash_cooldown_left > 0.0:
		frost_dash_cooldown_left = maxf(0.0, frost_dash_cooldown_left - delta)
	if frost_dash_time_left <= 0.0:
		return
	frost_dash_time_left -= delta
	var direction := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	velocity.x = direction.x * movement_speed * 3.0
	velocity.z = direction.z * movement_speed * 3.0
	if frost_dash_time_left <= 0.0:
		is_dashing = false

func _activate_ice_shield() -> void:
	if not Progress.ice_shield_unlocked or ice_shield_cooldown_left > 0.0 or ice_shield_active:
		return
	ice_shield_active = true
	ice_shield_cooldown_left = 8.0
	if _ice_shield_visual != null:
		_ice_shield_visual.visible = true
	get_tree().create_timer(2.0).timeout.connect(func():
		ice_shield_active = false
		if _ice_shield_visual != null:
			_ice_shield_visual.visible = false
	)

func _update_ice_shield(delta: float) -> void:
	if ice_shield_cooldown_left > 0.0:
		ice_shield_cooldown_left = maxf(0.0, ice_shield_cooldown_left - delta)
	if _ice_shield_visual != null and ice_shield_active:
		_ice_shield_visual.rotation.y += delta * 1.8


func _update_dash(delta: float) -> void:
	if is_dashing:
		dash_time_left -= delta
		stamina = maxf(0.0, stamina - dash_stamina_drain * delta)
		stamina_changed.emit(stamina, max_stamina)
		if dash_time_left <= 0.0 or stamina <= 0.0:
			_end_dash()
	else:
		if dash_cooldown_left > 0.0:
			dash_cooldown_left = maxf(dash_cooldown_left - delta, 0.0)
		if stamina < max_stamina:
			stamina = minf(max_stamina, stamina + stamina_regen_rate * delta)
			stamina_changed.emit(stamina, max_stamina)


func handle_dash_animation(delta: float) -> void:
	# Lean into the dash and bob for a speedy look while moving fast.
	var target_lean := 0.35 if is_dashing else 0.0
	dash_lean = lerpf(dash_lean, target_lean, delta * 12.0)
	model.rotation = Vector3(model_rest_rotation.x + dash_lean, model_rest_rotation.y, model_rest_rotation.z)

	if is_dashing:
		dash_bob += delta * 22.0
		model.position.y = model_rest_position.y + sin(dash_bob) * 0.05
	else:
		model.position.y = lerpf(model.position.y, model_rest_position.y, delta * 10.0)

# Collecting coins

func collect_coin():

	coins += 1

	coin_collected.emit(coins)


# Dying

func reset_vitals() -> void:
	health = max_health
	stamina = max_stamina
	last_death_cause = "fall"
	health_changed.emit(health, max_health)
	stamina_changed.emit(stamina, max_stamina)


func die(cause: String = "fall") -> void:
	if is_dead:
		return
	last_death_cause = cause
	health = 0.0
	health_changed.emit(health, max_health)
	is_dead = true
	velocity = Vector3.ZERO
	movement_velocity = Vector3.ZERO
	gravity = 0.0
	is_dashing = false
	dash_time_left = 0.0
	dash_cooldown_left = 0.0
	died.emit()


func _activate_time_freeze() -> void:
	if time_freeze_active:
		return
	time_freeze_active = true
	freeze_cooldown = 9.0
	Engine.time_scale = 0.18
	get_tree().create_timer(1.25, true, false, true).timeout.connect(_end_time_freeze)
	get_tree().create_timer(9.0, true, false, true).timeout.connect(func(): freeze_cooldown = 0.0)


func _end_time_freeze() -> void:
	Engine.time_scale = 1.0
	time_freeze_active = false


# --- Fighting ----------------------------------------------------------------
#
# The slash is a short forward swipe with a forgiving arc in front of the player.
# Holding forward swings it upward, holding back in mid-air swings it down - and a
# down-slash that lands throws the player back up, which is the pogo.

func _update_combat(delta: float) -> void:
	attack_cooldown_left = maxf(attack_cooldown_left - delta, 0.0)
	attack_timer = maxf(attack_timer - delta, 0.0)
	knockback = knockback.lerp(Vector3.ZERO, delta * 7.0)
	_update_slash(delta)
	_update_swing()

	if Input.is_action_just_pressed(action_attack):
		_swing()


## Drive the character's own limb animation through the swing, so it looks like
## the character is doing the attacking and not just a flash in front of them.
func _update_swing() -> void:
	if model == null or not model.has_method("set_swing"):
		return
	if attack_timer <= 0.0:
		if _swing_amount > 0.0:
			_swing_amount = 0.0
			model.call("set_swing", 0.0, attack_dir)
		return
	var progress := 1.0 - attack_timer / maxf(attack_time, 0.01)
	_swing_amount = sin(progress * PI)
	model.call("set_swing", _swing_amount, attack_dir)


func _swing() -> void:
	if is_dead:
		return
	if attack_cooldown_left > 0.0:
		return
	attack_cooldown_left = attack_cooldown
	attack_timer = attack_time
	stamina = maxf(0.0, stamina - attack_stamina_cost)
	stamina_changed.emit(stamina, max_stamina)
	attack_dir = 0
	# In the air, holding back aims the nail straight down; holding forward aims
	# it up. Both are camera-relative, like the movement keys.
	if not is_on_floor() and Input.is_action_pressed(action_back):
		attack_dir = -1
	elif Input.is_action_pressed(action_forward):
		attack_dir = 1
	_show_slash()
	Audio.play("res://sounds/break.ogg")

	var hits := _hit_enemies()
	if hits > 0 and attack_dir == -1 and not is_on_floor():
		# Pogo: the nail bounces the player off the enemy.
		gravity = -pogo_strength
		jumps_remaining = maxi(jumps_remaining, 1)
		model.scale = Vector3(0.8, 1.3, 0.8)
		Audio.play("res://sounds/coin.ogg")


## Everything in the "enemies" group that the swing reaches. Returns how many
## were hit.
func _hit_enemies() -> int:
	var hits := 0
	var facing := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	var origin := global_position + Vector3(0.0, 0.55, 0.0)
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D
		if enemy == null or not enemy.has_method("take_hit"):
			continue
		var offset := enemy.global_position - origin
		var reached := false
		if attack_dir == -1:
			# The downward swing reaches a little further, so landing a pogo on a
			# floating enemy works without pixel-perfect timing.
			reached = offset.y < -0.1 and offset.length() < attack_range + 0.7
		elif attack_dir == 1:
			reached = offset.y > 0.1 and offset.length() < attack_range + 0.3
		else:
			var flat := Vector3(offset.x, 0.0, offset.z)
			reached = flat.length() < attack_range and absf(offset.y) < 1.4 \
					and (flat.length() < 0.4 or facing.dot(flat.normalized()) > 0.3)
		if reached and bool(enemy.call("take_hit", attack_damage, global_position)):
			hits += 1
	if hits > 0:
		knockback -= facing * 1.2
	return hits


func _build_slash() -> void:
	_slash_material = StandardMaterial3D.new()
	_slash_material.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
	_slash_material.emission_enabled = true
	_slash_material.emission = Color(1.0, 1.0, 1.0)
	_slash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_slash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_slash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_slash_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 14
	mesh.rings = 6

	_slash = MeshInstance3D.new()
	_slash.name = "Slash"
	_slash.mesh = mesh
	_slash.material_override = _slash_material
	_slash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_slash.visible = false
	add_child(_slash)


func _show_slash() -> void:
	if _slash == null:
		return
	match attack_dir:
		-1:
			_slash.position = Vector3(0.0, -0.85, 0.35)
			_slash_base = Vector3(1.15, 0.16, 1.15)
		1:
			_slash.position = Vector3(0.0, 1.25, 0.35)
			_slash_base = Vector3(1.0, 0.16, 1.0)
		_:
			_slash.position = Vector3(0.0, 0.62, 1.05)
			_slash_base = Vector3(1.2, 0.5, 0.16)
	_slash.scale = _slash_base
	_slash.visible = true
	_slash_life = 1.0


func _update_slash(delta: float) -> void:
	if _slash_life <= 0.0 or _slash == null:
		return
	_slash_life = maxf(_slash_life - delta / maxf(attack_time, 0.01), 0.0)
	if _slash_life <= 0.0:
		_slash.visible = false
		return
	_slash.scale = _slash_base * lerpf(0.75, 1.25, 1.0 - _slash_life)
	_slash_material.albedo_color.a = _slash_life
	_slash_material.emission = Color(1, 1, 1) * (0.6 + 0.4 * _slash_life)


func _ensure_combat_actions() -> void:
	# main.gd builds the per-slot co-op versions of these; single player and
	# online use them as they are.
	if not InputMap.has_action(action_attack):
		InputMap.add_action(action_attack)
		InputMap.action_set_deadzone(action_attack, 0.5)
		var attack_key := InputEventKey.new()
		attack_key.physical_keycode = KEY_J
		attack_key.device = -1
		InputMap.action_add_event(action_attack, attack_key)
		var attack_button := InputEventJoypadButton.new()
		attack_button.button_index = JOY_BUTTON_B
		attack_button.device = -1
		InputMap.action_add_event(action_attack, attack_button)


## Touched by an enemy: a single Shadow Slime hit takes 4% of the player's max
## HP and knocks them back; other hazards/boss hits take the specified damage
## (or remain fatal when contact_damage is 1).
func take_damage(amount: float = 100.0, from: Vector3 = Vector3.ZERO, source: String = "enemy") -> void:
	if is_dead:
		return
	if ice_shield_active:
		return
	Audio.play("res://sounds/land.ogg")
	var away := global_position - from
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = -Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	knockback = away.normalized() * hurt_knockback
	model.scale = Vector3(1.35, 0.7, 1.35)
	if source in ["slime", "wolf", "phantom", "wolf_boss"]:
		var pct_dmg: float = amount if amount > 0.0 else max_health * 0.04
		health = maxf(0.0, health - pct_dmg)
		health_changed.emit(health, max_health)
		if health <= 0.0:
			knockback = Vector3.ZERO
			die(source)
		return
	var fatal_or_amount: float = max_health if amount <= 1.0 else amount
	health = maxf(0.0, health - fatal_or_amount)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		knockback = Vector3.ZERO
		die(source)


func set_anti_gravity(enabled: bool) -> void:
	gravity_scale = -0.35 if enabled else 1.0
