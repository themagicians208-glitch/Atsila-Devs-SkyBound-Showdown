class_name ShadowSlime
extends CharacterBody3D

## A Shadow Slime: a bouncy, jelly-like blob of the Shadow King's magic.
##
## It hops around the spot it was placed on, chases a player who comes close,
## loses interest when they get far away, and ends the run by touching them -
## the same rule every other enemy in this project follows.
##
## Its speed is **exactly half of the player's normal walking speed**, measured
## from the player rather than hard-coded, so the two stay in step if the
## player's speed is ever retuned. It never dashes: chasing only changes where it
## hops, never how fast. That is deliberate - the brief asks for an enemy that is
## dangerous because of where it stands, not because it can outrun anyone.
##
## Matches the sky sentry's interface on purpose, so slashes, pogo hits, the
## chain's "enemies" group and the level's spawner all work unchanged:
## `health`, `max_health`, `contact_damage`, `take_hit(amount, from)`, `defeated`.

signal defeated

const BODY_COLOR := Color("#4a2d70")
const BODY_DEEP := Color("#2c1c3f")
const BELLY_COLOR := Color("#6d4fa8")
const EYE_COLOR := Color("#e0ccff")
const GLOW := Color("#9b6bff")

const GRAVITY := 22.0

enum State { PATROL, CHASE, WINDUP, RECOVER, DEFEATED }

@export var max_health := 2
@export var contact_damage := 1
@export var touch_range := 0.95
## Distance at which it notices a player, and the larger distance at which it
## gives up and goes home.
@export var detect_range := 9.0
@export var lose_range := 15.0
@export var patrol_radius := 1.8
## Half the player's normal speed. The brief's number: do not raise it.
@export var speed_ratio := 0.5
## Used until the player has actually been seen walking.
@export var fallback_speed := 4.2
@export var hop_power := 4.6
@export var attack_range := 3.2
@export var windup_time := 0.4

var health := max_health
## The speed it actually moves at, recomputed from the player as they walk.
var chase_speed := 2.1

var _home := Vector3.ZERO
var _state := State.PATROL
var _visual: Node3D
var _body_material: StandardMaterial3D
var _eye_material: StandardMaterial3D
var _particles: GPUParticles3D
var _patrol_target := Vector3.ZERO
var _player_peak := 0.0
var _hop_timer := 0.0
var _windup := 0.0
var _touch_cooldown := 0.0
var _hit_flash := 0.0
var _knockback := Vector3.ZERO
var _squash := 1.0
var _squash_velocity := 0.0
var _defeated := false
var _death_timer := 0.0
var _was_airborne := false


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("shadow_slimes")
	health = max_health
	chase_speed = fallback_speed * speed_ratio
	_home = global_position
	_patrol_target = _home
	# Slimes are ethereal: they stand on the island but the players walk through
	# them, so a touch is a decision the level makes, not a physics accident.
	collision_layer = 2
	collision_mask = 1
	_build()
	_build_particles()


## Everything is built from primitives, like the rest of the sky.
func _build() -> void:
	# The body itself: a capsule, so it stands on a ledge without its rounded
	# shape letting it roll off the way a bare sphere would.
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.36
	capsule.height = 0.8
	shape.shape = capsule
	shape.position.y = 0.4
	add_child(shape)

	_visual = Node3D.new()
	_visual.name = "Visual"
	# The jelly sits on the ground, so the body is lifted clear of the origin and
	# every squash happens about that point.
	_visual.position.y = 0.42
	add_child(_visual)

	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = BODY_COLOR
	_body_material.roughness = 0.35
	_body_material.emission_enabled = true
	_body_material.emission = GLOW
	_body_material.emission_energy_multiplier = 0.25

	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.42
	sphere.height = 0.84
	sphere.radial_segments = 22
	sphere.rings = 12
	body.mesh = sphere
	body.material_override = _body_material
	body.scale = Vector3(1.0, 0.88, 1.0)
	_visual.add_child(body)

	# A darker, translucent core so the jelly reads as jelly rather than stone.
	var core_material := StandardMaterial3D.new()
	core_material.albedo_color = Color(BODY_DEEP.r, BODY_DEEP.g, BODY_DEEP.b, 0.55)
	core_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core_material.roughness = 0.2
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.26
	core_mesh.height = 0.52
	core_mesh.radial_segments = 16
	core_mesh.rings = 8
	core.mesh = core_mesh
	core.material_override = core_material
	core.position = Vector3(0.0, -0.06, 0.0)
	_visual.add_child(core)

	# A soft, paler belly, and blobs around the base for the drippy silhouette.
	var belly := MeshInstance3D.new()
	var belly_mesh := SphereMesh.new()
	belly_mesh.radius = 0.24
	belly_mesh.height = 0.48
	belly_mesh.radial_segments = 12
	belly_mesh.rings = 6
	belly.mesh = belly_mesh
	belly.material_override = _material(BELLY_COLOR, 0.0)
	belly.position = Vector3(0.0, -0.2, 0.1)
	belly.scale = Vector3(1.0, 0.7, 0.7)
	_visual.add_child(belly)
	for i in 5:
		var angle := TAU * float(i) / 5.0 + 0.3
		var blob := MeshInstance3D.new()
		var blob_mesh := SphereMesh.new()
		blob_mesh.radius = 0.13 + 0.03 * float(i % 2)
		blob_mesh.height = blob_mesh.radius * 2.0
		blob_mesh.radial_segments = 10
		blob_mesh.rings = 5
		blob.mesh = blob_mesh
		blob.material_override = _material(BODY_DEEP, 0.0)
		blob.position = Vector3(cos(angle) * 0.34, -0.3, sin(angle) * 0.34)
		blob.scale = Vector3(1.0, 0.6, 1.0)
		_visual.add_child(blob)

	# Face on +Z, the way the characters face: two glowing eyes and a small smile,
	# which is what makes it read as cute rather than as another spiky sentry.
	_eye_material = StandardMaterial3D.new()
	_eye_material.albedo_color = EYE_COLOR
	_eye_material.emission_enabled = true
	_eye_material.emission = EYE_COLOR
	_eye_material.emission_energy_multiplier = 0.9
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.1
	eye_mesh.height = 0.2
	eye_mesh.radial_segments = 12
	eye_mesh.rings = 6
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = eye_mesh
		eye.material_override = _eye_material
		eye.position = Vector3(0.16 * side, 0.14, 0.3)
		eye.scale = Vector3(1.0, 1.15, 0.8)
		_visual.add_child(eye)
		var pupil := MeshInstance3D.new()
		var pupil_mesh := SphereMesh.new()
		pupil_mesh.radius = 0.045
		pupil_mesh.height = 0.09
		pupil_mesh.radial_segments = 8
		pupil_mesh.rings = 4
		pupil.mesh = pupil_mesh
		pupil.material_override = _material(BODY_DEEP, 0.0)
		pupil.position = Vector3(0.16 * side, 0.15, 0.39)
		_visual.add_child(pupil)
	for i in 5:
		var mouth := MeshInstance3D.new()
		var mouth_mesh := BoxMesh.new()
		mouth_mesh.size = Vector3(0.05, 0.03, 0.02)
		mouth.mesh = mouth_mesh
		mouth.material_override = _material(BODY_DEEP, 0.0)
		mouth.position = Vector3(-0.08 + 0.04 * float(i), -0.06 - absf(float(i) - 2.0) * 0.03, 0.37)
		_visual.add_child(mouth)


func _material(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.4
	if energy > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = energy
	return mat


## The purple motes it gives off, which brighten while it is on the move.
func _build_particles() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(GLOW.r, GLOW.g, GLOW.b, 0.8)
	material.emission_enabled = true
	material.emission = GLOW
	material.emission_energy_multiplier = 1.1
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var quad := QuadMesh.new()
	quad.size = Vector2(0.11, 0.11)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.4
	process.direction = Vector3(0, 1, 0)
	process.spread = 30.0
	process.initial_velocity_min = 0.1
	process.initial_velocity_max = 0.4
	process.gravity = Vector3(0.0, 0.5, 0.0)
	process.scale_min = 0.6
	process.scale_max = 1.3
	_particles = GPUParticles3D.new()
	_particles.amount = 14
	_particles.lifetime = 2.2
	_particles.preprocess = 1.5
	_particles.draw_pass_1 = quad
	_particles.material_override = material
	_particles.process_material = process
	_particles.position.y = 0.5
	add_child(_particles)


func state_name() -> String:
	match _state:
		State.PATROL: return "patrol"
		State.CHASE: return "chase"
		State.WINDUP: return "windup"
		State.RECOVER: return "recover"
	return "defeated"


func _physics_process(delta: float) -> void:
	_hit_flash = maxf(_hit_flash - delta, 0.0)
	_touch_cooldown = maxf(_touch_cooldown - delta, 0.0)
	_apply_flash()

	if _defeated:
		_dissolve(delta)
		return

	var target := _nearest_player()
	if target != null:
		_sample_player_speed(target)
		_think(target, delta)
	else:
		_state = State.PATROL

	_move(delta)
	_animate(delta)
	if target != null:
		# After the move, so the touch uses where the slime ended up.
		_check_touch(target)


## Learn what "walking" means for this player, so chasing is always half of it.
## Dashing is ignored: the brief asks for half of the player's *normal* speed.
func _sample_player_speed(target: Node3D) -> void:
	if bool(target.get("is_dashing")):
		return
	var observed := Vector2(target.velocity.x, target.velocity.z).length()
	if observed > _player_peak:
		_player_peak = observed
		chase_speed = clampf(_player_peak * speed_ratio, 0.4, 20.0)


func _think(target: Node3D, delta: float) -> void:
	var to_player := target.global_position - global_position
	var distance := to_player.length()
	match _state:
		State.PATROL:
			if distance <= detect_range:
				_state = State.CHASE
				Audio.play("res://sounds/walking.ogg")
		State.CHASE:
			if distance > lose_range:
				_state = State.PATROL
				_patrol_target = _home
			elif distance <= attack_range:
				_state = State.WINDUP
				_windup = windup_time
				_velocity_flat(Vector3.ZERO)
		State.WINDUP:
			_windup -= delta
			if _windup <= 0.0:
				# The magical bounce attack: a big hop straight at the player.
				_velocity_flat(Vector3(to_player.x, 0.0, to_player.z).normalized() * chase_speed)
				velocity.y = hop_power * 1.35
				_state = State.RECOVER
		State.RECOVER:
			if is_on_floor() and _hop_timer <= 0.0:
				_state = State.CHASE
	if _state == State.PATROL or _state == State.CHASE:
		_steer(target, distance)


## Where it wants to be next. Chasing aims at the player on the ground plane;
## patrolling wanders around the spot it was placed on.
func _steer(target: Node3D, distance: float) -> void:
	if _state == State.PATROL:
		if Vector2(global_position.x - _home.x, global_position.z - _home.z).length() > patrol_radius \
				or global_position.distance_to(_patrol_target) < 0.6:
			_patrol_target = _home + Vector3(
				sin(float(Time.get_ticks_msec()) * 0.0007) * patrol_radius,
				0.0,
				cos(float(Time.get_ticks_msec()) * 0.0004) * patrol_radius)
		_aim_at(_patrol_target)
		return
	var to_player := target.global_position - global_position
	if distance > 1.2:
		_aim_at(target.global_position)
	else:
		_velocity_flat(Vector3.ZERO)


func _aim_at(spot: Vector3) -> void:
	var to_spot := Vector3(spot.x - global_position.x, 0.0, spot.z - global_position.z)
	if to_spot.length_squared() < 0.0001:
		_velocity_flat(Vector3.ZERO)
		return
	_velocity_flat(to_spot.normalized() * chase_speed)


func _velocity_flat(value: Vector3) -> void:
	velocity.x = value.x
	velocity.z = value.z
	if value.length_squared() > 0.0001:
		rotation.y = lerp_angle(rotation.y, atan2(value.x, value.z), 0.2)


func _move(delta: float) -> void:
	var airborne := not is_on_floor()
	if airborne:
		velocity.y -= GRAVITY * delta
	else:
		if velocity.y < 0.0:
			velocity.y = 0.0
		_hop_timer -= delta
		if _hop_timer <= 0.0 and _state != State.WINDUP and _state != State.RECOVER:
			# Hop, and hold still for a beat on landing: a slime moves in bounces.
			velocity.y = hop_power
			_hop_timer = 0.55 if _state == State.CHASE else 1.15
		if _was_airborne:
			_squash = 0.62
			_squash_velocity = 0.0
	_was_airborne = airborne
	velocity += _knockback
	_knockback = _knockback.lerp(Vector3.ZERO, delta * 5.0)
	move_and_slide()
	if global_position.y < -40.0:
		# It fell off the island; put it back where it belongs rather than losing it.
		reset_to_home()


func _animate(delta: float) -> void:
	if _visual == null:
		return
	# Spring back towards round: `_squash` is the body's height, so landing (which
	# sets it below 1) flattens the slime and it wobbles back up again.
	_squash_velocity += (1.0 - _squash) * 90.0 * delta
	_squash_velocity *= 1.0 - minf(1.0, 9.0 * delta)
	_squash += _squash_velocity * delta
	# Falling fast stretches it thin; volume is kept, so it narrows as it stretches.
	var stretch := 1.0 + clampf(-velocity.y / 14.0, 0.0, 0.35)
	var height := clampf(_squash, 0.45, 1.5) * stretch
	var width := 1.0 / sqrt(maxf(height, 0.2))
	_visual.scale = Vector3(width, height, width)
	_visual.rotation.y = sin(Time.get_ticks_msec() * 0.002) * 0.06
	# The glow rises while it is moving, so it is brighter mid-chase than at rest.
	var moving := Vector2(velocity.x, velocity.z).length()
	var lift := minf(moving / maxf(chase_speed, 0.1), 1.0)
	if _body_material != null:
		_body_material.emission_energy_multiplier = 0.25 + lift * 0.55
	if _eye_material != null:
		_eye_material.emission_energy_multiplier = 0.9 + lift * 0.5
	if _particles != null:
		_particles.amount_ratio = 0.4 + lift * 0.6


func _apply_flash() -> void:
	if _body_material == null:
		return
	_body_material.albedo_color = Color(1, 1, 1) if _hit_flash > 0.0 else BODY_COLOR


## Called by a player's slash. Same contract as the sky sentry's.
func take_hit(amount: int, from: Vector3) -> bool:
	if _defeated:
		return false
	health -= amount
	_hit_flash = 0.18
	var away := global_position - from
	away.y = 0.0
	if away.length_squared() < 0.001:
		away = Vector3(0.0, 0.0, 1.0)
	_knockback = away.normalized() * 4.5
	_squash = 1.35
	Audio.play("res://sounds/break.ogg")
	_burst(8, GLOW, 2.6, 0.2)
	if health <= 0:
		_die()
	return true


## Back to the patrol spot at full health. The level calls this when a player
## respawns at a checkpoint, so a half-beaten slime is not left hunting them.
func reset_to_home() -> void:
	global_position = _home
	velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	health = max_health
	_state = State.PATROL
	_squash = 1.0
	_touch_cooldown = 0.0


## Move its patrol spot. Used when a level places it (and by the dev tools).
func place_at(spot: Vector3) -> void:
	_home = spot
	reset_to_home()


func _die() -> void:
	_defeated = true
	_death_timer = 0.0
	velocity = Vector3.ZERO
	_burst(22, GLOW, 5.0, 0.3)
	Audio.play("res://sounds/break.ogg")
	if _particles != null:
		_particles.amount_ratio = 1.0


## Shrinks and sinks away, then goes. The level's other enemies pop out of
## existence; the slime is meant to dissolve.
func _dissolve(delta: float) -> void:
	_death_timer += delta
	var fade := clampf(1.0 - _death_timer / 0.75, 0.0, 1.0)
	if _visual != null:
		_visual.scale = Vector3(fade, fade * fade, fade)
		_visual.rotation.y += delta * 4.0
		_visual.position.y = 0.42 + (1.0 - fade) * 0.5
	if _squash >= 0.0:
		_squash -= delta * 2.0
	if _death_timer >= 0.75:
		defeated.emit()
		queue_free()


## The touch that ends a run, the same way the sentry's does.
func _check_touch(target: Node3D) -> void:
	if _defeated or _touch_cooldown > 0.0:
		return
	if global_position.distance_to(target.global_position) > touch_range:
		return
	if target.has_method("take_damage"):
		target.call("take_damage", contact_damage, global_position)
		_touch_cooldown = 1.0


func _nearest_player() -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("player"):
		var candidate := node as Node3D
		if candidate == null or not candidate.has_method("take_damage"):
			continue
		if bool(candidate.get("is_dead")):
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


func _burst(amount: int, color: Color, speed: float, size: float) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.6
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16 * size, 0.16 * size)
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0, 1, 0)
	process.spread = 180.0
	process.initial_velocity_min = speed * 0.5
	process.initial_velocity_max = speed
	process.gravity = Vector3(0, 1.5, 0)
	process.scale_min = 0.6
	process.scale_max = 1.2
	process.damping_min = 2.0
	process.damping_max = 3.0
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = 0.8
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.draw_pass_1 = quad
	particles.material_override = material
	particles.process_material = process
	particles.position = global_position + Vector3(0.0, 0.4, 0.0)
	parent.add_child(particles)
	particles.emitting = true
	var timer := get_tree().create_timer(1.4)
	timer.timeout.connect(func():
		if is_instance_valid(particles):
			particles.queue_free()
	)
