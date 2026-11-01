class_name SkyPhantom
extends CharacterBody3D

## Sky Phantom - Level 2 (The Whispering Woods) flying forest spirit enemy.
##
## Flies freely above ground and across gaps with an articulated translucent body,
## expressive glowing eyes, floating arm wisps, and a chain of flowing lower body
## wisps. Patrols between aerial points, chases players within range, telegraphs
## attacks with a visible warning ring, and launches dodgeable magical energy orbs.

signal defeated
signal projectile_fired(orb: Node3D)

const SPIRIT_VIOLET := Color("#7a5cff")
const SPIRIT_CYAN := Color("#5ceeff")
const EYE_GLOW := Color("#ffffff")

enum State { IDLE, PATROL, CHASE, TELEGRAPH, ATTACK, REPOSITION, DEFEATED }

@export var max_health := 2
@export var contact_damage := 3.0
@export var hit_hp_fraction := 0.03
@export var fly_speed := 3.6
@export var detect_range := 12.5
@export var lose_range := 18.0
@export var preferred_distance := 5.2
@export var hover_height := 2.2
@export var patrol_radius := 3.2
@export var telegraph_duration := 0.65
@export var attack_cooldown := 2.4
@export var projectile_speed := 7.2
@export var touch_range := 1.0

var health := 2
var _collision: CollisionShape3D
var _home := Vector3.ZERO
var _state: State = State.PATROL
var _visual: Node3D
var _head_node: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _wisps: Array[Node3D] = []
var _warning_ring: MeshInstance3D
var _body_material: StandardMaterial3D
var _wisp_material: StandardMaterial3D
var _particles: GPUParticles3D

var _patrol_index := 0
var _patrol_points: Array[Vector3] = []
var _reposition_spot := Vector3.ZERO
var _state_timer := 0.0
var _cooldown_timer := 1.0
var _touch_cooldown := 0.0
var _hit_flash := 0.0
var _knockback := Vector3.ZERO
var _anim_time := 0.0
var _death_timer := 0.0
var _defeated := false


func _init() -> void:
	_collision = CollisionShape3D.new()
	_collision.name = "PhantomCollision"
	var sphere := SphereShape3D.new()
	sphere.radius = 0.48
	_collision.shape = sphere
	_collision.position = Vector3(0.0, 0.55, 0.0)
	add_child(_collision)


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("sky_phantoms")
	health = max_health
	_home = global_position
	_rebuild_patrol_points()
	collision_layer = 2
	collision_mask = 0
	_build_articulated_model()
	_build_particles()


func _rebuild_patrol_points() -> void:
	_patrol_points = [
		_home + Vector3(patrol_radius, 0.0, 0.0),
		_home + Vector3(0.0, 0.4, patrol_radius),
		_home + Vector3(-patrol_radius, 0.0, 0.0),
		_home + Vector3(0.0, -0.3, -patrol_radius),
	]


func state_name() -> String:
	match _state:
		State.IDLE: return "idle"
		State.PATROL: return "patrol"
		State.CHASE: return "chase"
		State.TELEGRAPH: return "telegraph"
		State.ATTACK: return "attack"
		State.REPOSITION: return "reposition"
	return "defeated"


func _build_articulated_model() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	_visual.position.y = 0.55
	add_child(_visual)

	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = Color(SPIRIT_VIOLET.r, SPIRIT_VIOLET.g, SPIRIT_VIOLET.b, 0.78)
	_body_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_body_material.emission_enabled = true
	_body_material.emission = SPIRIT_VIOLET
	_body_material.emission_energy_multiplier = 0.95
	_body_material.roughness = 0.25

	_wisp_material = StandardMaterial3D.new()
	_wisp_material.albedo_color = Color(SPIRIT_CYAN.r, SPIRIT_CYAN.g, SPIRIT_CYAN.b, 0.72)
	_wisp_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_wisp_material.emission_enabled = true
	_wisp_material.emission = SPIRIT_CYAN
	_wisp_material.emission_energy_multiplier = 1.25

	_head_node = Node3D.new()
	_head_node.name = "HeadBell"
	_visual.add_child(_head_node)

	var dome := MeshInstance3D.new()
	var dome_sphere := SphereMesh.new()
	dome_sphere.radius = 0.44
	dome_sphere.height = 0.88
	dome.mesh = dome_sphere
	dome.material_override = _body_material
	dome.scale = Vector3(1.0, 1.08, 1.0)
	_head_node.add_child(dome)

	var inner_core := MeshInstance3D.new()
	var core_sphere := SphereMesh.new()
	core_sphere.radius = 0.26
	core_sphere.height = 0.52
	inner_core.mesh = core_sphere
	inner_core.material_override = _wisp_material
	_head_node.add_child(inner_core)

	# Expressive glowing eyes
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = EYE_GLOW
	eye_mat.emission_enabled = true
	eye_mat.emission = SPIRIT_CYAN
	eye_mat.emission_energy_multiplier = 2.0
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_sphere := SphereMesh.new()
		eye_sphere.radius = 0.085
		eye_sphere.height = 0.19
		eye.mesh = eye_sphere
		eye.material_override = eye_mat
		eye.position = Vector3(0.16 * side, 0.06, 0.37)
		eye.scale = Vector3(1.0, 1.25, 0.6)
		_head_node.add_child(eye)

	# Articulated floating arm wisps
	_arm_l = _build_arm_wisp(-1.0)
	_arm_r = _build_arm_wisp(1.0)
	_visual.add_child(_arm_l)
	_visual.add_child(_arm_r)

	# Articulated flowing lower body wisps
	for i in 4:
		var wisp_pivot := Node3D.new()
		wisp_pivot.name = "TailWisp_%d" % i
		var angle := TAU * float(i) / 4.0 + 0.4
		wisp_pivot.position = Vector3(cos(angle) * 0.22, -0.24, sin(angle) * 0.22)
		var wisp_mesh := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.12
		cyl.bottom_radius = 0.02
		cyl.height = 0.48
		wisp_mesh.mesh = cyl
		wisp_mesh.material_override = _wisp_material if i % 2 == 0 else _body_material
		wisp_mesh.position = Vector3(0.0, -0.22, 0.0)
		wisp_pivot.add_child(wisp_mesh)
		_visual.add_child(wisp_pivot)
		_wisps.append(wisp_pivot)

	# Visible warning ring shown during TELEGRAPH before firing an energy orb
	_warning_ring = MeshInstance3D.new()
	_warning_ring.name = "WarningRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.48
	torus.outer_radius = 0.62
	_warning_ring.mesh = torus
	var warn_mat := StandardMaterial3D.new()
	warn_mat.albedo_color = Color("#ff6be8")
	warn_mat.emission_enabled = true
	warn_mat.emission = Color("#ff6be8")
	warn_mat.emission_energy_multiplier = 2.4
	_warning_ring.material_override = warn_mat
	_warning_ring.rotation.x = PI * 0.5
	_warning_ring.position = Vector3(0.0, 0.0, 0.45)
	_warning_ring.visible = false
	_visual.add_child(_warning_ring)


func _build_arm_wisp(side: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "ArmL" if side < 0.0 else "ArmR"
	pivot.position = Vector3(0.42 * side, -0.02, 0.08)
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.11
	sphere.height = 0.34
	mesh.mesh = sphere
	mesh.material_override = _wisp_material
	mesh.position = Vector3(0.08 * side, -0.1, 0.0)
	pivot.add_child(mesh)
	return pivot


func _build_particles() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(SPIRIT_CYAN.r, SPIRIT_CYAN.g, SPIRIT_CYAN.b, 0.85)
	mat.emission_enabled = true
	mat.emission = SPIRIT_CYAN
	mat.emission_energy_multiplier = 1.4
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 0.45
	proc.direction = Vector3(0, 1, 0)
	proc.spread = 90.0
	proc.initial_velocity_min = 0.1
	proc.initial_velocity_max = 0.35
	proc.gravity = Vector3(0.0, 0.25, 0.0)
	_particles = GPUParticles3D.new()
	_particles.amount = 14
	_particles.lifetime = 1.8
	_particles.draw_pass_1 = quad
	_particles.material_override = mat
	_particles.process_material = proc
	_particles.position.y = 0.5
	add_child(_particles)


func _physics_process(delta: float) -> void:
	_anim_time += delta
	_hit_flash = maxf(_hit_flash - delta, 0.0)
	_touch_cooldown = maxf(_touch_cooldown - delta, 0.0)
	_cooldown_timer = maxf(_cooldown_timer - delta, 0.0)
	_apply_flash()

	if _defeated:
		_dissolve(delta)
		return

	var target := _nearest_player()
	_think(target, delta)
	velocity += _knockback
	_knockback = _knockback.lerp(Vector3.ZERO, delta * 6.0)
	move_and_slide()
	_animate(delta)
	if target != null:
		_check_touch(target)


func _think(target: Node3D, delta: float) -> void:
	_state_timer = maxf(_state_timer - delta, 0.0)
	var dist := global_position.distance_to(target.global_position) if target != null else INF

	match _state:
		State.IDLE:
			velocity = velocity.lerp(Vector3.ZERO, delta * 6.0)
			if dist <= detect_range:
				_state = State.CHASE
			elif _state_timer <= 0.0:
				_state = State.PATROL
		State.PATROL:
			if _warning_ring != null:
				_warning_ring.visible = false
			if dist <= detect_range:
				_state = State.CHASE
				return
			if _patrol_points.is_empty():
				_rebuild_patrol_points()
			var goal := _patrol_points[_patrol_index % _patrol_points.size()]
			if global_position.distance_to(goal) < 0.65:
				_patrol_index = (_patrol_index + 1) % _patrol_points.size()
				_state = State.IDLE
				_state_timer = 0.7
			else:
				_fly_toward(goal, fly_speed * 0.8)
		State.CHASE:
			if _warning_ring != null:
				_warning_ring.visible = false
			if target == null or dist > lose_range:
				_state = State.PATROL
				return
			_face_point(target.global_position)
			var desired := target.global_position + Vector3(0.0, hover_height, 0.0)
			var flat_away := global_position - target.global_position
			flat_away.y = 0.0
			if flat_away.length_squared() < 0.01:
				flat_away = Vector3.BACK
			desired += flat_away.normalized() * preferred_distance
			_fly_toward(desired, fly_speed)
			if _cooldown_timer <= 0.0 and dist <= detect_range:
				_state = State.TELEGRAPH
				_state_timer = telegraph_duration
				if _warning_ring != null:
					_warning_ring.visible = true
		State.TELEGRAPH:
			velocity = velocity.lerp(Vector3.ZERO, delta * 8.0)
			if target != null:
				_face_point(target.global_position)
			if _warning_ring != null:
				_warning_ring.visible = true
				var pulse := 0.8 + sin(_anim_time * 22.0) * 0.25
				_warning_ring.scale = Vector3.ONE * pulse
			if _state_timer <= 0.0:
				if _warning_ring != null:
					_warning_ring.visible = false
				_state = State.ATTACK
				if target != null:
					_fire_projectile(target.global_position + Vector3(0.0, 0.55, 0.0))
				_cooldown_timer = attack_cooldown
				var angle := _anim_time * 2.1
				_reposition_spot = _home + Vector3(cos(angle) * patrol_radius, 0.5, sin(angle) * patrol_radius)
				_state = State.REPOSITION
				_state_timer = 1.2
		State.REPOSITION:
			_fly_toward(_reposition_spot, fly_speed * 1.1)
			if _state_timer <= 0.0 or global_position.distance_to(_reposition_spot) < 0.7:
				_state = State.CHASE if dist <= detect_range else State.PATROL


func _fly_toward(goal: Vector3, spd: float) -> void:
	var diff := goal - global_position
	if diff.length_squared() < 0.001:
		velocity = Vector3.ZERO
		return
	velocity = diff.normalized() * spd
	_face_point(goal)


func _face_point(spot: Vector3) -> void:
	var flat := Vector3(spot.x - global_position.x, 0.0, spot.z - global_position.z)
	if flat.length_squared() > 0.001:
		rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.z), 0.18)


func _fire_projectile(target_pos: Vector3) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var orb := Node3D.new()
	orb.name = "PhantomOrb"
	var start := global_position + Vector3(0.0, 0.55, 0.0)
	orb.position = start
	var mesh_inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	mesh_inst.mesh = sphere
	mesh_inst.material_override = _wisp_material
	orb.add_child(mesh_inst)
	parent.add_child(orb)

	var dir := (target_pos - start).normalized()
	if dir.length_squared() < 0.001:
		dir = Vector3.FORWARD
	var dmg := contact_damage
	var frac := hit_hp_fraction
	var spd := projectile_speed
	var tween := orb.create_tween()
	var life := 2.4
	var steps := 48
	for step in steps:
		tween.tween_callback(func():
			if not is_instance_valid(orb):
				return
			orb.global_position += dir * spd * (life / float(steps))
			for node in get_tree().get_nodes_in_group("player"):
				var p := node as Node3D
				if p == null or bool(p.get("is_dead")) or not p.has_method("take_damage"):
					continue
				if orb.global_position.distance_to(p.global_position + Vector3(0.0, 0.55, 0.0)) < 0.78:
					var max_hp: float = float(p.get("max_health")) if p.get("max_health") != null else 100.0
					p.call("take_damage", minf(dmg, max_hp * frac), orb.global_position, "phantom")
					orb.queue_free()
					return
		)
		tween.tween_interval(life / float(steps))
	tween.tween_callback(func():
		if is_instance_valid(orb):
			orb.queue_free()
	)
	projectile_fired.emit(orb)


func _animate(_delta: float) -> void:
	if _visual == null:
		return
	_visual.position.y = 0.55 + sin(_anim_time * 3.0) * 0.14
	if _head_node != null:
		_head_node.rotation.z = sin(_anim_time * 2.2) * 0.08
	if _arm_l != null and _arm_r != null:
		var flap := sin(_anim_time * 4.5) * 0.28
		_arm_l.rotation.z = 0.25 + flap
		_arm_r.rotation.z = -0.25 - flap
	for i in _wisps.size():
		var w := _wisps[i]
		w.rotation.x = sin(_anim_time * 5.2 + float(i) * 1.1) * 0.32
		w.rotation.z = cos(_anim_time * 4.4 + float(i) * 0.9) * 0.24


func _apply_flash() -> void:
	if _body_material == null:
		return
	_body_material.albedo_color = Color(1, 1, 1, 0.95) if _hit_flash > 0.0 else Color(SPIRIT_VIOLET.r, SPIRIT_VIOLET.g, SPIRIT_VIOLET.b, 0.78)


func take_hit(amount: int, from: Vector3) -> bool:
	if _defeated:
		return false
	health -= amount
	_hit_flash = 0.22
	var away := global_position - from
	away.y = 0.2
	if away.length_squared() < 0.001:
		away = Vector3.BACK
	_knockback = away.normalized() * 5.5
	Audio.play("res://sounds/break.ogg")
	if health <= 0:
		_die()
	return true


func _die() -> void:
	_defeated = true
	_state = State.DEFEATED
	_death_timer = 0.0
	velocity = Vector3.ZERO
	if _warning_ring != null:
		_warning_ring.visible = false
	Audio.play("res://sounds/break.ogg")


func _dissolve(delta: float) -> void:
	_death_timer += delta
	var fade := clampf(1.0 - _death_timer / 0.7, 0.0, 1.0)
	if _visual != null:
		_visual.scale = Vector3.ONE * fade
		_visual.position.y += delta * 0.8
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
		target.call("take_damage", minf(contact_damage, max_hp * hit_hp_fraction), global_position, "phantom")
		_touch_cooldown = 1.1


func reset_to_home() -> void:
	global_position = _home
	velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	health = max_health
	_state = State.PATROL
	_touch_cooldown = 0.0
	if _warning_ring != null:
		_warning_ring.visible = false


func place_at(spot: Vector3) -> void:
	_home = spot
	_rebuild_patrol_points()
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
