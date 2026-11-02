extends Node3D
class_name FrozenEnemy

const ICE_PROJECTILE := preload("res://objects/ice_projectile.gd")

signal defeated

@export_enum("Frost Slime", "Frost Wolf", "Crystal Phantom") var variant := "Frost Slime"
@export var max_health := 2
@export var contact_damage := 1.0
@export var attack_damage := 1.0
@export var detect_range := 10.0
@export var speed_ratio := 0.5

var health := 1
var _home := Vector3.ZERO
var _visual: Node3D
var _body_material: StandardMaterial3D
var _dead := false
var _time := 0.0
var _touch_cooldown := 0.0
var _projectile_cooldown := 1.8
var _projectile_warning_time := 0.0
var _projectile_target: Node3D
var _attack_warning: MeshInstance3D
var _lunge_time := 0.0
var _lunge_cooldown := 0.0
var _lunge_direction := Vector3.ZERO
var _hit_time := 0.0
var _wolf_legs: Array[Node3D] = []
var _wolf_head: Node3D

func _ready() -> void:
	add_to_group("enemies")
	if variant == "Frost Wolf":
		speed_ratio = 1.10
		attack_damage = 1.0
	elif variant == "Crystal Phantom":
		speed_ratio = 0.72
		attack_damage = 5.0
	else:
		speed_ratio = 0.50
		attack_damage = 4.0
	contact_damage = attack_damage
	health = max_health
	_home = global_position
	_build()

func _build() -> void:
	_visual = Node3D.new()
	_visual.name = "FrozenVisual"
	add_child(_visual)
	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = Color("#d9f6ff")
	_body_material.emission_enabled = true
	_body_material.emission = Color("#48c9ff") * 0.35
	_body_material.roughness = 0.28
	if variant == "Crystal Phantom":
		_body_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_body_material.albedo_color = Color(0.85, 0.98, 1.0, 0.68)
	var body := MeshInstance3D.new()
	var mesh: PrimitiveMesh
	if variant == "Crystal Phantom":
		mesh = CylinderMesh.new()
		(mesh as CylinderMesh).top_radius = 0.18
		(mesh as CylinderMesh).bottom_radius = 0.5
		(mesh as CylinderMesh).height = 1.15
	else:
		mesh = SphereMesh.new()
		# The wolf's sphere is its torso, not its whole body.
		(mesh as SphereMesh).radius = 0.42
		(mesh as SphereMesh).height = 0.84 if variant == "Frost Wolf" else 0.78
	body.mesh = mesh
	body.material_override = _body_material
	_visual.add_child(body)
	if variant == "Frost Wolf":
		# Not a blob with legs: an elongated torso, a head you can read from the
		# front, and the ice growths along the spine.
		body.scale = Vector3(1.0, 0.88, 1.55)
		body.position = Vector3(0.0, -0.05, -0.05)
		_build_wolf_limbs()
		_build_wolf_head()
	if variant == "Crystal Phantom":
		for index in 3:
			var shard := MeshInstance3D.new()
			var shard_mesh := CylinderMesh.new()
			shard_mesh.top_radius = 0.0
			shard_mesh.bottom_radius = 0.1
			shard_mesh.height = 0.42
			shard.mesh = shard_mesh
			shard.position = Vector3((index - 1) * 0.42, 0.35 + (index % 2) * 0.25, 0.0)
			shard.material_override = _crystal_material()
			_visual.add_child(shard)
		_attack_warning = MeshInstance3D.new()
		_attack_warning.name = "AttackWarning"
		var warning_mesh := TorusMesh.new()
		warning_mesh.inner_radius = 0.48
		warning_mesh.outer_radius = 0.56
		_attack_warning.mesh = warning_mesh
		_attack_warning.rotation.x = PI / 2.0
		_attack_warning.position.y = -0.5
		_attack_warning.material_override = _crystal_material()
		_attack_warning.visible = false
		_visual.add_child(_attack_warning)
	if variant != "Frost Wolf":
		for i in 3:
			var crystal := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.12
			cone.height = 0.42
			crystal.mesh = cone
			crystal.material_override = _crystal_material()
			crystal.position = Vector3((i - 1) * 0.22, 0.4 + (i % 2) * 0.12, 0.0)
			crystal.rotation.z = (i - 1) * 0.25
			_visual.add_child(crystal)
		for side in [-1.0, 1.0]:
			var eye := MeshInstance3D.new()
			var eye_mesh := SphereMesh.new()
			eye_mesh.radius = 0.08
			eye_mesh.height = 0.16
			eye.mesh = eye_mesh
			eye.material_override = _crystal_material()
			eye.position = Vector3(0.14 * side, 0.1, 0.34)
			_visual.add_child(eye)
	_build_frost_particles()


## The wolf's four legs, the ice spikes down its spine and its single tail. The
## enemy's origin sits 0.42 above the floor (see _snap_to_ground), so the feet
## reach down to about -0.44 and stand in the snow.
func _build_wolf_limbs() -> void:
	for side in [-1.0, 1.0]:
		for front in [-1.0, 1.0]:
			var leg := MeshInstance3D.new()
			var leg_mesh := CapsuleMesh.new()
			leg_mesh.radius = 0.12
			leg_mesh.height = 0.44
			leg.mesh = leg_mesh
			leg.position = Vector3(side * 0.28, -0.24, front * 0.3)
			leg.material_override = _body_material
			_visual.add_child(leg)
			_wolf_legs.append(leg)
	var spikes := [
		Vector3(0.0, 0.3, 0.12),
		Vector3(0.0, 0.33, -0.12),
		Vector3(0.0, 0.29, -0.36),
	]
	for index in spikes.size():
		var spike := MeshInstance3D.new()
		var spike_mesh := CylinderMesh.new()
		spike_mesh.top_radius = 0.0
		spike_mesh.bottom_radius = 0.1 - float(index) * 0.012
		spike_mesh.height = 0.3 - float(index) * 0.045
		spike.mesh = spike_mesh
		spike.position = spikes[index]
		spike.rotation.x = -0.32
		spike.material_override = _crystal_material()
		_visual.add_child(spike)
	var tail := MeshInstance3D.new()
	var tail_mesh := CylinderMesh.new()
	tail_mesh.top_radius = 0.04
	tail_mesh.bottom_radius = 0.14
	tail_mesh.height = 0.8
	tail.mesh = tail_mesh
	tail.position = Vector3(0.0, 0.14, -0.72)
	tail.rotation.x = -0.85
	tail.material_override = _crystal_material()
	_visual.add_child(tail)


## Skull, snout, jaw, brows, ears and glowing eyes: the face the Frost Wolf was
## missing. Everything sits at +Z, which is the direction the wolf runs.
func _build_wolf_head() -> void:
	_wolf_head = Node3D.new()
	_wolf_head.name = "WolfHead"
	_wolf_head.position = Vector3(0.0, 0.34, 0.6)
	_visual.add_child(_wolf_head)
	var skull := MeshInstance3D.new()
	var skull_mesh := SphereMesh.new()
	skull_mesh.radius = 0.24
	skull_mesh.height = 0.48
	skull.mesh = skull_mesh
	skull.scale = Vector3(1.0, 0.94, 1.12)
	skull.material_override = _body_material
	_wolf_head.add_child(skull)
	var snout := MeshInstance3D.new()
	var snout_mesh := CylinderMesh.new()
	snout_mesh.top_radius = 0.085
	snout_mesh.bottom_radius = 0.16
	snout_mesh.height = 0.34
	snout.mesh = snout_mesh
	snout.rotation.x = PI * 0.5
	snout.position = Vector3(0.0, -0.04, 0.26)
	snout.material_override = _body_material
	_wolf_head.add_child(snout)
	var jaw := MeshInstance3D.new()
	var jaw_mesh := BoxMesh.new()
	jaw_mesh.size = Vector3(0.17, 0.07, 0.26)
	jaw.mesh = jaw_mesh
	jaw.position = Vector3(0.0, -0.14, 0.22)
	jaw.material_override = _body_material
	_wolf_head.add_child(jaw)
	var nose := MeshInstance3D.new()
	var nose_mesh := SphereMesh.new()
	nose_mesh.radius = 0.06
	nose_mesh.height = 0.12
	nose.mesh = nose_mesh
	nose.position = Vector3(0.0, 0.02, 0.41)
	nose.material_override = _nose_material()
	_wolf_head.add_child(nose)
	for side in [-1.0, 1.0]:
		var ear := MeshInstance3D.new()
		var ear_mesh := CylinderMesh.new()
		ear_mesh.top_radius = 0.0
		ear_mesh.bottom_radius = 0.1
		ear_mesh.height = 0.32
		ear.mesh = ear_mesh
		ear.position = Vector3(side * 0.14, 0.26, -0.03)
		ear.rotation = Vector3(-0.1, 0.0, -side * 0.22)
		ear.material_override = _crystal_material()
		_wolf_head.add_child(ear)
		var brow := MeshInstance3D.new()
		var brow_mesh := BoxMesh.new()
		brow_mesh.size = Vector3(0.13, 0.04, 0.1)
		brow.mesh = brow_mesh
		brow.position = Vector3(side * 0.12, 0.15, 0.17)
		brow.rotation.z = -side * 0.18
		brow.material_override = _crystal_material()
		_wolf_head.add_child(brow)
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.055
		eye_mesh.height = 0.11
		eye.mesh = eye_mesh
		eye.position = Vector3(side * 0.12, 0.07, 0.19)
		eye.material_override = _eye_material()
		_wolf_head.add_child(eye)

func _build_frost_particles() -> void:
	var particles := GPUParticles3D.new()
	particles.name = "FrostParticles"
	particles.amount = 12
	particles.lifetime = 1.6
	particles.preprocess = 0.8
	var flake := QuadMesh.new()
	flake.size = Vector2(0.09, 0.09)
	var material := _crystal_material()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flake.material = material
	particles.draw_pass_1 = flake
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.45
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 35.0
	process.initial_velocity_min = 0.15
	process.initial_velocity_max = 0.5
	process.gravity = Vector3(0.0, 0.2, 0.0)
	particles.process_material = process
	particles.position.y = 0.45
	add_child(particles)

func _crystal_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#67e8ff")
	material.emission_enabled = true
	material.emission = Color("#67e8ff")
	return material


## Wolf eyes glow hard enough for the face to read from a distance.
func _eye_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#f2ffff")
	material.emission_enabled = true
	material.emission = Color("#5ff0ff")
	material.emission_energy_multiplier = 2.4
	return material


## Dark slate muzzle tip - the one part of the face that does not glow.
func _nose_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#2f4f66")
	material.roughness = 0.5
	return material

func _physics_process(delta: float) -> void:
	if _dead:
		return
	_time += delta
	_touch_cooldown = maxf(_touch_cooldown - delta, 0.0)
	_projectile_cooldown = maxf(_projectile_cooldown - delta, 0.0)
	_projectile_warning_time = maxf(_projectile_warning_time - delta, 0.0)
	_hit_time = maxf(_hit_time - delta, 0.0)
	_lunge_cooldown = maxf(_lunge_cooldown - delta, 0.0)
	_visual.position.y = sin(_time * 3.0) * (0.06 if variant == "Frost Wolf" else 0.1)
	if variant == "Frost Wolf":
		# A wolf has to look where it is running: the node carries the turn (see the
		# lerp_angle below) and the head only nods. The blob enemies keep their spin.
		_visual.rotation.y = 0.0
		if _wolf_head != null:
			_wolf_head.rotation.x = sin(_time * 7.0) * 0.05
	else:
		_visual.rotation.y += delta * 0.45
	_visual.scale = _visual.scale.lerp(Vector3.ONE, delta * 12.0)
	if variant == "Frost Wolf":
		for index in _wolf_legs.size():
			_wolf_legs[index].rotation.x = sin(_time * 8.0 + float(index) * PI) * 0.22
	if _body_material != null:
		_body_material.emission_energy_multiplier = 1.8 if _hit_time > 0.0 else 0.35
	var target := _nearest_player()
	if target == null:
		if variant == "Crystal Phantom":
			_patrol_phantom()
		return
	var offset := target.global_position - global_position
	var distance := offset.length()
	if variant == "Frost Wolf" and _lunge_time > 0.0:
		_lunge_time -= delta
		_try_ground_move(_lunge_direction * 2.2 * delta)
		if _lunge_time <= 0.0:
			_lunge_cooldown = 1.1
		return
	if distance > detect_range:
		if variant == "Crystal Phantom":
			_projectile_warning_time = 0.0
			if _attack_warning != null:
				_attack_warning.visible = false
			_patrol_phantom()
		else:
			_snap_to_ground()
		return
	if variant == "Crystal Phantom":
		if _projectile_warning_time > 0.0 and _projectile_target != null and is_instance_valid(_projectile_target):
			if _attack_warning != null:
				_attack_warning.visible = true
				_attack_warning.scale = Vector3.ONE * (1.0 + sin(_time * 18.0) * 0.15)
		elif _projectile_warning_time <= 0.0 and _projectile_target != null and _attack_warning != null and _attack_warning.visible:
			_attack_warning.visible = false
			_launch_projectile(_projectile_target)
			_projectile_target = null
		elif _projectile_cooldown <= 0.0:
			_projectile_target = target
			_projectile_warning_time = 0.3
			_attack_warning.visible = true
	if variant == "Frost Wolf" and distance < 2.4 and _lunge_cooldown <= 0.0:
		_lunge_direction = Vector3(offset.x, 0.0, offset.z).normalized()
		_lunge_time = 0.18
		var audio := get_node_or_null("/root/Audio")
		if audio != null:
			audio.play("res://sounds/jump.ogg")
		return
	var speed := _movement_speed(target)
	if variant == "Crystal Phantom":
		global_position += offset.normalized() * speed * delta
		global_position.y += sin(_time * 2.0) * delta * 0.4
	else:
		var flat := Vector3(offset.x, 0.0, offset.z)
		var world_spd := (speed / 250.0) * 6.0 if speed > 20.0 else speed
		if flat.length() > 0.5:
			_try_ground_move(flat.normalized() * world_spd * delta)
		else:
			_snap_to_ground()
		rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.z), delta * 5.0)
	if distance < 1.0 and _touch_cooldown <= 0.0 and target.has_method("take_damage"):
		target.call("take_damage", attack_damage, global_position, "frozen_enemy")
		_touch_cooldown = 1.0

func _try_ground_move(step: Vector3) -> void:
	var candidate := global_position + Vector3(step.x, 0.0, step.z)
	var dir := Vector3(step.x, 0.0, step.z).normalized()
	var lead := candidate + dir * 0.42
	var floor_y := _probe_ground_y(lead)
	if is_nan(floor_y):
		# No ground ahead: refuse horizontal step so wolf/slime never walks onto air
		_snap_to_ground()
		return
	var cur_floor_y := _probe_ground_y(candidate)
	if not is_nan(cur_floor_y):
		candidate.y = cur_floor_y + 0.42
	global_position = candidate

func _snap_to_ground() -> void:
	var floor_y := _probe_ground_y(global_position)
	if not is_nan(floor_y):
		global_position.y = floor_y + 0.42

func _probe_ground_y(pos: Vector3) -> float:
	if not is_inside_tree() or get_world_3d() == null:
		return NAN
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		pos + Vector3(0.0, 1.6, 0.0),
		pos + Vector3(0.0, -2.0, 0.0)
	)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return NAN
	return float((hit["position"] as Vector3).y)

func _patrol_phantom() -> void:
	global_position = _home + Vector3(
		sin(_time * 0.7) * 2.2,
		sin(_time * 1.4) * 0.7,
		cos(_time * 0.7) * 1.6)

func _launch_projectile(target: Node3D) -> void:
	_projectile_cooldown = 2.8
	var projectile: IceProjectile = ICE_PROJECTILE.new()
	get_parent().add_child(projectile)
	projectile.global_position = global_position + Vector3(0.0, 0.2, 0.0)
	projectile.launch(target)

func _movement_speed(target: Node3D) -> float:
	var player_speed := float(target.call("get_normal_movement_speed")) if target.has_method("get_normal_movement_speed") else 0.0
	return player_speed * speed_ratio

func _nearest_player() -> Node3D:
	var nearest: Node3D
	var best := INF
	for candidate in get_tree().get_nodes_in_group("player"):
		if not candidate.has_method("take_damage") or bool(candidate.get("is_dead")):
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance < best:
			best = distance
			nearest = candidate
	return nearest

func take_hit(amount: int, from: Vector3) -> bool:
	if _dead:
		return false
	_hit_time = 0.16
	_visual.scale = Vector3(1.18, 0.82, 1.18)
	health -= amount
	if health <= 0:
		_dead = true
		defeated.emit()
		_burst_crystals()
		queue_free()
	return true

func _burst_crystals() -> void:
	var particles := GPUParticles3D.new()
	particles.name = "FrozenDefeatBurst"
	particles.amount = 16
	particles.lifetime = 0.75
	particles.one_shot = true
	particles.explosiveness = 1.0
	var shard := QuadMesh.new()
	shard.size = Vector2(0.12, 0.12)
	shard.material = _crystal_material()
	particles.draw_pass_1 = shard
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 150.0
	process.initial_velocity_min = 0.8
	process.initial_velocity_max = 2.5
	process.gravity = Vector3(0.0, -1.5, 0.0)
	particles.process_material = process
	var parent := get_parent()
	if parent == null:
		return
	parent.add_child(particles)
	particles.global_position = global_position + Vector3(0.0, 0.45, 0.0)
	particles.emitting = true
	get_tree().create_timer(0.9).timeout.connect(particles.queue_free)

func reset_to_home() -> void:
	if _dead:
		return
	health = max_health
	global_position = _home
	_lunge_time = 0.0
	_lunge_cooldown = 0.0
	_projectile_cooldown = 1.8
	_touch_cooldown = 0.0
	_projectile_warning_time = 0.0
	_projectile_target = null
	_hit_time = 0.0
	if _attack_warning != null:
		_attack_warning.visible = false
	_visual.scale = Vector3.ONE

