extends CharacterBody3D

signal coin_collected
signal died

@export_subgroup("Components")
@export var view: Node3D

@export_subgroup("Input")
@export var action_left := "move_left"
@export var action_right := "move_right"
@export var action_forward := "move_forward"
@export var action_back := "move_back"
@export var action_jump := "jump"
@export var action_dash := "dash"
@export var action_time_freeze := "time_freeze"

@export_subgroup("Properties")
@export var movement_speed = 250
@export var jump_strength = 7

@export_subgroup("Dash Skill")
@export var dash_speed_multiplier := 2.0
@export var dash_duration := 1.0
@export var dash_cooldown := 10.0

var movement_velocity: Vector3
var rotation_direction: float
var gravity = 0
var gravity_scale := 1.0
var time_freeze_active := false
var freeze_cooldown := 0.0

var previously_floored = false

var jumps_remaining := 2

var coins = 0

var is_dead := false

# Floating name tag shown above the player (local co-op / online).
var player_name := ""
var name_label: Label3D

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

@onready var particles_trail = $ParticlesTrail
@onready var sound_footsteps = $SoundFootsteps
@onready var model = $Character
@onready var animation = $Character/AnimationPlayer


func _ready() -> void:
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
	model_rest_rotation = model.rotation
	model_rest_position = model.position


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

	if Input.is_action_just_pressed(action_dash) and dash_cooldown_left <= 0.0 and not is_dashing:
		_start_dash()

	_update_dash(delta)

	# Handle functions

	handle_gravity(delta)
	handle_controls(delta)

	handle_effects(delta)

	# Movement

	var applied_velocity: Vector3

	var control := 3.0 if slippery else 10.0
	applied_velocity = velocity.lerp(movement_velocity, delta * control)
	applied_velocity.y = -gravity
	applied_velocity.x += external_velocity.x
	applied_velocity.z += external_velocity.z
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
		die()

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
			if animation.current_animation != "walk":
				animation.play("walk", 0.1)

			if speed_factor > 0.3:
				sound_footsteps.stream_paused = false
				sound_footsteps.pitch_scale = speed_factor

			if speed_factor > 0.75:
				particles_trail.emitting = true

		elif animation.current_animation != "idle":
			animation.play("idle", 0.1)

		if animation.current_animation == "walk":
			animation.speed_scale = speed_factor
		else:
			animation.speed_scale = 1.0

	elif animation.current_animation != "jump":
		animation.play("jump", 0.1)

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

		if jumps_remaining > 0:
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

	jumps_remaining = maxi(0, jumps_remaining - 1)


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
	is_dashing = true
	dash_time_left = dash_duration
	dash_bob = 0.0
	Audio.play("res://sounds/jump.ogg")


func _end_dash() -> void:
	is_dashing = false
	dash_time_left = 0.0
	dash_cooldown_left = dash_cooldown


func _update_dash(delta: float) -> void:
	if is_dashing:
		dash_time_left -= delta
		if dash_time_left <= 0.0:
			_end_dash()
	elif dash_cooldown_left > 0.0:
		dash_cooldown_left = maxf(dash_cooldown_left - delta, 0.0)


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

func die() -> void:
	if is_dead:
		return
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


func set_anti_gravity(enabled: bool) -> void:
	gravity_scale = -0.35 if enabled else 1.0
