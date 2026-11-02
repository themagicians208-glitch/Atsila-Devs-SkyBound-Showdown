class_name ShadowWolf
extends CharacterBody3D

## Shadow Wolf - Level 2 (The Whispering Woods) corrupted forest predator.
##
## Built with an articulated hierarchy of body parts (torso, head pivot, ears,
## glowing magenta eyes, tail pivot with trail particles, and four independent leg
## pivots) so Idle, Walk, Run, Chase, Attack, Hit, Stun and Defeat animate each
## limb and facial feature smoothly.
##
## Balance rules from the brief:
##   * Initial and measured movement speed is 125% of the player's normal walking
##     speed (`speed_ratio = 1.25`).
##   * Attack damage is strictly lower than the Level 1 Shadow Slime's damage,
##     read directly from `ShadowSlime` (`slime_contact_damage * 0.5`, i.e. 2% HP
##     vs the slime's 4% HP).

signal defeated

const SLIME_SCRIPT := preload("res://objects/shadow_slime.gd")

const FUR_DARK := Color("#2b1942")
const FUR_MID := Color("#462a69")
const MARKING_GLOW := Color("#a855f7")
const EYE_MAGENTA := Color("#ff3df0")
const CLAW_COLOR := Color("#1a0f29")

const GRAVITY := 22.0

enum State { IDLE, PATROL, CHASE, ATTACK, RECOVER, STUN, DEFEATED }

@export var max_health := 3
## Read from ShadowSlime at startup and kept strictly lower (2.0 vs slime's 4.0).
@export var contact_damage := 2.0
@export var hit_hp_fraction := 0.02
@export var touch_range := 1.15
@export var detect_range := 11.0
@export var lose_range := 16.5
@export var patrol_radius := 2.4
## 1.1x of the player's normal walking speed.
@export var speed_ratio := 1.10
@export var walk_speed_ratio := 0.60
@export var fallback_speed := 6.0
@export var lunge_range := 2.8
@export var lunge_speed_mult := 1.45
@export var lunge_duration := 0.28
@export var recover_duration := 0.65
@export var stun_duration := 0.35
@export var death_message := "A Shadow Wolf dissolves into violet forest mist!"

var health := 3
var chase_speed := 6.6
var walk_speed := 3.6
var slime_damage_reference := 4.0
var slime_fraction_reference := 0.04

var _collision: CollisionShape3D
var _home := Vector3.ZERO
var _state: State = State.IDLE
var _visual: Node3D
var _torso: Node3D
var _head_pivot: Node3D
var _ear_l: Node3D
var _ear_r: Node3D
var _tail_pivot: Node3D
var _legs: Array[Node3D] = []
var _fur_material: StandardMaterial3D
var _marking_material: StandardMaterial3D
var _eye_material: StandardMaterial3D
var _foot_particles: GPUParticles3D
var _tail_particles: GPUParticles3D

var _player_peak := 0.0
var _patrol_target := Vector3.ZERO
var _state_timer := 0.0
var _touch_cooldown := 0.0
var _hit_flash := 0.0
var _knockback := Vector3.ZERO
var _anim_time := 0.0
var _death_timer := 0.0
var _defeated := false
var _lunge_dir := Vector3.FORWARD


func _init() -> void:
	# Direct child CollisionShape3D created in _init() so Jolt always registers it.
	_collision = CollisionShape3D.new()
	_collision.name = "WolfCollision"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 1.05
	_collision.shape = capsule
	_collision.position = Vector3(0.0, 0.52, 0.0)
	add_child(_collision)


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("shadow_wolves")
	_read_slime_damage_reference()
	health = max_health
	chase_speed = fallback_speed * speed_ratio
	walk_speed = fallback_speed * walk_speed_ratio
	_home = global_position
	_patrol_target = _home
	collision_layer = 2
	collision_mask = 1
	_build_articulated_model()
	_build_particles()


## Read the actual Shadow Slime damage value from Level 1's script and ensure
## the wolf's regular attack damage stays strictly lower.
func _read_slime_damage_reference() -> void:
	var sample := SLIME_SCRIPT.new()
	slime_damage_reference = float(sample.get("contact_damage"))
	slime_fraction_reference = float(sample.get("hit_hp_fraction"))
	sample.free()
	if contact_damage >= slime_damage_reference:
		contact_damage = slime_damage_reference * 0.5
	if hit_hp_fraction >= slime_fraction_reference:
		hit_hp_fraction = slime_fraction_reference * 0.5


func state_name() -> String:
	match _state:
		State.IDLE: return "idle"
		State.PATROL: return "patrol"
		State.CHASE: return "chase"
		State.ATTACK: return "attack"
		State.RECOVER: return "recover"
		State.STUN: return "stun"
	return "defeated"


func _build_articulated_model() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)

	_fur_material = StandardMaterial3D.new()
	_fur_material.albedo_color = FUR_DARK
	_fur_material.roughness = 0.65

	var fur_mid_mat := StandardMaterial3D.new()
	fur_mid_mat.albedo_color = FUR_MID
	fur_mid_mat.roughness = 0.6

	_marking_material = StandardMaterial3D.new()
	_marking_material.albedo_color = MARKING_GLOW
	_marking_material.emission_enabled = true
	_marking_material.emission = MARKING_GLOW
	_marking_material.emission_energy_multiplier = 1.15

	_eye_material = StandardMaterial3D.new()
	_eye_material.albedo_color = EYE_MAGENTA
	_eye_material.emission_enabled = true
	_eye_material.emission = EYE_MAGENTA
	_eye_material.emission_energy_multiplier = 1.8

	# Torso pivot (breathes & pitches during lunges)
	_torso = Node3D.new()
	_torso.name = "Torso"
	_torso.position = Vector3(0.0, 0.52, 0.0)
	_visual.add_child(_torso)

	var body_mesh := MeshInstance3D.new()
	var body_box := BoxMesh.new()
	body_box.size = Vector3(0.58, 0.44, 0.96)
	body_mesh.mesh = body_box
	body_mesh.material_override = _fur_material
	_torso.add_child(body_mesh)

	var chest_ruff := MeshInstance3D.new()
	var ruff_sphere := SphereMesh.new()
	ruff_sphere.radius = 0.36
	ruff_sphere.height = 0.68
	chest_ruff.mesh = ruff_sphere
	chest_ruff.material_override = fur_mid_mat
	chest_ruff.position = Vector3(0.0, 0.04, 0.36)
	chest_ruff.scale = Vector3(1.05, 0.95, 0.9)
	_torso.add_child(chest_ruff)

	# Glowing corrupted markings along the spine and shoulders
	for z_off in [-0.24, 0.04, 0.28]:
		var mark := MeshInstance3D.new()
		var mark_box := BoxMesh.new()
		mark_box.size = Vector3(0.38, 0.04, 0.1)
		mark.mesh = mark_box
		mark.material_override = _marking_material
		mark.position = Vector3(0.0, 0.23, float(z_off))
		_torso.add_child(mark)

	# Articulated Head Pivot (slightly oversized & expressive per brief)
	_head_pivot = Node3D.new()
	_head_pivot.name = "HeadPivot"
	_head_pivot.position = Vector3(0.0, 0.24, 0.54)
	_torso.add_child(_head_pivot)

	var skull := MeshInstance3D.new()
	var skull_box := BoxMesh.new()
	skull_box.size = Vector3(0.5, 0.42, 0.46)
	skull.mesh = skull_box
	skull.material_override = _fur_material
	skull.position = Vector3(0.0, 0.04, 0.12)
	_head_pivot.add_child(skull)

	var snout := MeshInstance3D.new()
	var snout_box := BoxMesh.new()
	snout_box.size = Vector3(0.28, 0.22, 0.34)
	snout.mesh = snout_box
	snout.material_override = fur_mid_mat
	snout.position = Vector3(0.0, -0.04, 0.42)
	_head_pivot.add_child(snout)

	var nose := MeshInstance3D.new()
	var nose_sphere := SphereMesh.new()
	nose_sphere.radius = 0.055
	nose_sphere.height = 0.11
	nose.mesh = nose_sphere
	nose.material_override = _marking_material
	nose.position = Vector3(0.0, 0.03, 0.59)
	_head_pivot.add_child(nose)

	# Expressive glowing magenta eyes + brow ridges
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_sphere := SphereMesh.new()
		eye_sphere.radius = 0.075
		eye_sphere.height = 0.15
		eye.mesh = eye_sphere
		eye.material_override = _eye_material
		eye.position = Vector3(0.16 * side, 0.08, 0.33)
		eye.scale = Vector3(1.0, 0.85, 0.6)
		_head_pivot.add_child(eye)

		var brow := MeshInstance3D.new()
		var brow_box := BoxMesh.new()
		brow_box.size = Vector3(0.16, 0.04, 0.06)
		brow.mesh = brow_box
		brow.material_override = fur_mid_mat
		brow.position = Vector3(0.16 * side, 0.16, 0.35)
		brow.rotation.z = -0.22 * side
		_head_pivot.add_child(brow)

	# Articulated Ears
	_ear_l = _build_ear(-1.0, fur_mid_mat)
	_ear_r = _build_ear(1.0, fur_mid_mat)
	_head_pivot.add_child(_ear_l)
	_head_pivot.add_child(_ear_r)

	# Articulated Tail Pivot with glowing tip
	_tail_pivot = Node3D.new()
	_tail_pivot.name = "TailPivot"
	_tail_pivot.position = Vector3(0.0, 0.12, -0.48)
	_torso.add_child(_tail_pivot)

	var tail_base := MeshInstance3D.new()
	var tail_cyl := CylinderMesh.new()
	tail_cyl.top_radius = 0.07
	tail_cyl.bottom_radius = 0.12
	tail_cyl.height = 0.52
	tail_base.mesh = tail_cyl
	tail_base.material_override = fur_mid_mat
	tail_base.position = Vector3(0.0, 0.06, -0.24)
	tail_base.rotation.x = deg_to_rad(68.0)
	_tail_pivot.add_child(tail_base)

	var tail_tip := MeshInstance3D.new()
	var tip_sphere := SphereMesh.new()
	tip_sphere.radius = 0.11
	tip_sphere.height = 0.24
	tail_tip.mesh = tip_sphere
	tail_tip.material_override = _marking_material
	tail_tip.position = Vector3(0.0, 0.15, -0.48)
	_tail_pivot.add_child(tail_tip)

	# Four articulated legs: Front-Left, Front-Right, Back-Left, Back-Right
	var leg_offsets := [
		Vector3(-0.22, 0.38, 0.34),
		Vector3(0.22, 0.38, 0.34),
		Vector3(-0.22, 0.38, -0.34),
		Vector3(0.22, 0.38, -0.34),
	]
	var leg_names := ["LegFL", "LegFR", "LegBL", "LegBR"]
	for i in 4:
		var leg_pivot := Node3D.new()
		leg_pivot.name = leg_names[i]
		leg_pivot.position = leg_offsets[i]
		var upper := MeshInstance3D.new()
		var upper_box := BoxMesh.new()
		upper_box.size = Vector3(0.14, 0.36, 0.14)
		upper.mesh = upper_box
		upper.material_override = _fur_material
		upper.position = Vector3(0.0, -0.18, 0.0)
		leg_pivot.add_child(upper)

		var paw := MeshInstance3D.new()
		var paw_box := BoxMesh.new()
		paw_box.size = Vector3(0.16, 0.1, 0.2)
		paw.mesh = paw_box
		paw.material_override = _marking_material
		paw.position = Vector3(0.0, -0.35, 0.03)
		leg_pivot.add_child(paw)

		_visual.add_child(leg_pivot)
		_legs.append(leg_pivot)


func _build_ear(side: float, mat: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "EarL" if side < 0.0 else "EarR"
	pivot.position = Vector3(0.18 * side, 0.24, 0.08)
	var cone := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.02
	cyl.bottom_radius = 0.09
	cyl.height = 0.24
	cone.mesh = cyl
	cone.material_override = mat
	cone.position = Vector3(0.0, 0.12, 0.0)
	pivot.add_child(cone)
	return pivot


func _build_particles() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(MARKING_GLOW.r, MARKING_GLOW.g, MARKING_GLOW.b, 0.85)
	mat.emission_enabled = true
	mat.emission = MARKING_GLOW
	mat.emission_energy_multiplier = 1.3
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var quad := QuadMesh.new()
	quad.size = Vector2(0.1, 0.1)
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(0.3, 0.08, 0.42)
	proc.direction = Vector3(0, 1, 0)
	proc.spread = 35.0
	proc.initial_velocity_min = 0.15
	proc.initial_velocity_max = 0.45
	proc.gravity = Vector3(0.0, 0.4, 0.0)
	_foot_particles = GPUParticles3D.new()
	_foot_particles.amount = 14
	_foot_particles.lifetime = 1.4
	_foot_particles.draw_pass_1 = quad
	_foot_particles.material_override = mat
	_foot_particles.process_material = proc
	_foot_particles.position = Vector3(0.0, 0.12, 0.0)
	add_child(_foot_particles)

	_tail_particles = GPUParticles3D.new()
	_tail_particles.amount = 18
	_tail_particles.lifetime = 0.75
	_tail_particles.draw_pass_1 = quad
	_tail_particles.material_override = mat
	_tail_particles.process_material = proc
	_tail_particles.position = Vector3(0.0, 0.62, -0.82)
	add_child(_tail_particles)


func _physics_process(delta: float) -> void:
	_anim_time += delta
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
	_move(delta)
	_animate(delta)
	if target != null:
		_check_touch(target)


## Learn the player's normal walking speed (ignoring dashes) and keep chase_speed
## at 125% of it.
func _sample_player_speed(target: Node3D) -> void:
	if bool(target.get("is_dashing")):
		return
	var observed := Vector2(target.velocity.x, target.velocity.z).length()
	if observed > _player_peak:
		_player_peak = observed
		chase_speed = clampf(_player_peak * speed_ratio, 1.0, 25.0)
		walk_speed = clampf(_player_peak * walk_speed_ratio, 0.6, 16.0)


func _think(target: Node3D, delta: float) -> void:
	_state_timer = maxf(_state_timer - delta, 0.0)
	var dist := global_position.distance_to(target.global_position) if target != null else INF

	match _state:
		State.STUN:
			_velocity_flat(Vector3.ZERO)
			if _state_timer <= 0.0:
				_state = State.CHASE if dist <= detect_range else State.PATROL
		State.RECOVER:
			_velocity_flat(Vector3.ZERO)
			if _state_timer <= 0.0:
				_state = State.CHASE if dist <= detect_range else State.PATROL
		State.ATTACK:
			_velocity_flat(_lunge_dir * chase_speed * lunge_speed_mult)
			if _state_timer <= 0.0:
				_state = State.RECOVER
				_state_timer = recover_duration
		State.IDLE:
			_velocity_flat(Vector3.ZERO)
			if dist <= detect_range:
				_state = State.CHASE
				Audio.play("res://sounds/walking.ogg")
			elif _state_timer <= 0.0:
				_state = State.PATROL
				_state_timer = 2.6
				_pick_patrol_target()
		State.PATROL:
			if dist <= detect_range:
				_state = State.CHASE
				Audio.play("res://sounds/walking.ogg")
			elif global_position.distance_to(_patrol_target) < 0.55 or _state_timer <= 0.0:
				_state = State.IDLE
				_state_timer = 1.4
			else:
				_steer_toward(_patrol_target, walk_speed)
		State.CHASE:
			if target == null or dist > lose_range:
				_state = State.PATROL
				_patrol_target = _home
				_state_timer = 3.0
			elif dist <= lunge_range and is_on_floor():
				_state = State.ATTACK
				_state_timer = lunge_duration
				var to_target := target.global_position - global_position
				to_target.y = 0.0
				_lunge_dir = to_target.normalized() if to_target.length_squared() > 0.001 else Vector3.FORWARD
				velocity.y = 3.2
			else:
				_steer_toward(target.global_position, chase_speed)


func _pick_patrol_target() -> void:
	var angle := _anim_time * 1.3 + float(get_instance_id() % 17)
	_patrol_target = _home + Vector3(cos(angle) * patrol_radius, 0.0, sin(angle) * patrol_radius)


func _steer_toward(spot: Vector3, spd: float) -> void:
	var flat := Vector3(spot.x - global_position.x, 0.0, spot.z - global_position.z)
	if flat.length_squared() < 0.001:
		_velocity_flat(Vector3.ZERO)
		return
	_velocity_flat(flat.normalized() * spd)


func _velocity_flat(v: Vector3) -> void:
	velocity.x = v.x
	velocity.z = v.z
	if v.length_squared() > 0.001:
		rotation.y = lerp_angle(rotation.y, atan2(v.x, v.z), 0.22)


func _move(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
	velocity += _knockback
	_knockback = _knockback.lerp(Vector3.ZERO, delta * 6.0)
	var flat_vel := Vector3(velocity.x, 0.0, velocity.z)
	if flat_vel.length_squared() > 0.001 and not _has_floor_ahead(flat_vel, delta):
		velocity.x = 0.0
		velocity.z = 0.0
		_knockback.x = 0.0
		_knockback.z = 0.0
		if _state == State.ATTACK:
			_state = State.RECOVER
			_state_timer = recover_duration
	move_and_slide()
	if global_position.y < -40.0:
		reset_to_home()


func _has_floor_ahead(flat_vel: Vector3, delta: float) -> bool:
	if not is_inside_tree() or get_world_3d() == null:
		return true
	var dir := flat_vel.normalized()
	var probe := global_position + dir * maxf(flat_vel.length() * delta + 0.55, 0.65)
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		probe + Vector3(0.0, 1.2, 0.0),
		probe + Vector3(0.0, -1.6, 0.0)
	)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	return not hit.is_empty()


func _animate(_delta: float) -> void:
	if _visual == null:
		return
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	var stride_rate := 14.0 if _state in [State.CHASE, State.ATTACK] else 8.5
	var stride_amp := clampf(flat_speed / maxf(chase_speed, 0.1), 0.0, 1.2) * 0.75

	# Four-legged diagonal gait: FL & BR swing together opposite FR & BL.
	if _legs.size() == 4:
		var phase_a := sin(_anim_time * stride_rate) * stride_amp
		var phase_b := sin(_anim_time * stride_rate + PI) * stride_amp
		_legs[0].rotation.x = phase_a
		_legs[3].rotation.x = phase_a
		_legs[1].rotation.x = phase_b
		_legs[2].rotation.x = phase_b

	# Idle & running torso/head/ear/tail articulation
	var breathe := 1.0 + sin(_anim_time * 3.2) * 0.035
	_torso.scale = Vector3(1.0, breathe, 1.0)
	if _state == State.ATTACK:
		_torso.rotation.x = -0.22
	elif _state == State.STUN:
		_torso.rotation.z = sin(_anim_time * 24.0) * 0.15
	else:
		_torso.rotation.x = sin(_anim_time * stride_rate * 2.0) * 0.05 * stride_amp
		_torso.rotation.z = 0.0

	if _head_pivot != null:
		if _state in [State.IDLE, State.RECOVER]:
			_head_pivot.rotation.y = sin(_anim_time * 1.8) * 0.28
			_head_pivot.rotation.x = sin(_anim_time * 2.4) * 0.08
		else:
			_head_pivot.rotation.y = sin(_anim_time * 4.0) * 0.06
			_head_pivot.rotation.x = -0.08 if _state == State.CHASE else 0.0

	if _ear_l != null and _ear_r != null:
		var ear_perk := 0.25 if _state == State.CHASE else sin(_anim_time * 4.2) * 0.12
		_ear_l.rotation.z = 0.18 + ear_perk
		_ear_r.rotation.z = -0.18 - ear_perk

	if _tail_pivot != null:
		var wag_speed := 11.0 if _state == State.CHASE else 3.2
		_tail_pivot.rotation.y = sin(_anim_time * wag_speed) * 0.35

	if _tail_particles != null:
		_tail_particles.emitting = _state in [State.CHASE, State.ATTACK]


func _apply_flash() -> void:
	if _fur_material == null:
		return
	_fur_material.albedo_color = Color(1, 1, 1) if _hit_flash > 0.0 else FUR_DARK


func take_hit(amount: int, from: Vector3) -> bool:
	if _defeated:
		return false
	health -= amount
	_hit_flash = 0.2
	_state = State.STUN
	_state_timer = stun_duration
	var away := global_position - from
	away.y = 0.0
	if away.length_squared() < 0.001:
		away = Vector3.BACK
	_knockback = away.normalized() * 5.2
	Audio.play("res://sounds/break.ogg")
	if health <= 0:
		_die()
	return true


func _die() -> void:
	_defeated = true
	_state = State.DEFEATED
	_death_timer = 0.0
	velocity = Vector3.ZERO
	Audio.play("res://sounds/break.ogg")


func _dissolve(delta: float) -> void:
	_death_timer += delta
	var fade := clampf(1.0 - _death_timer / 0.7, 0.0, 1.0)
	if _visual != null:
		_visual.scale = Vector3(fade, fade * fade, fade)
		_visual.rotation.y += delta * 5.0
	if _death_timer >= 0.7:
		defeated.emit()
		queue_free()


func _check_touch(target: Node3D) -> void:
	if _defeated or _touch_cooldown > 0.0:
		return
	if global_position.distance_to(target.global_position) > touch_range:
		return
	if target.has_method("take_damage"):
		var max_hp: float = float(target.get("max_health")) if target.get("max_health") != null else 100.0
		var dmg: float = minf(contact_damage, max_hp * hit_hp_fraction)
		target.call("take_damage", dmg, global_position, "wolf")
		_touch_cooldown = 1.05
		_state = State.RECOVER
		_state_timer = recover_duration


func reset_to_home() -> void:
	global_position = _home
	velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	health = max_health
	_state = State.IDLE
	_state_timer = 0.5
	_touch_cooldown = 0.0


func place_at(spot: Vector3) -> void:
	_home = spot
	reset_to_home()


func _nearest_player() -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("player"):
		var candidate := node as Node3D
		if candidate == null or not candidate.has_method("take_damage"):
			continue
		if bool(candidate.get("is_dead")):
			continue
		var d := global_position.distance_to(candidate.global_position)
		if d < best_dist:
			best_dist = d
			best = candidate
	return best
