extends Node3D
class_name VolcanicEnemy

## Volcanic monster variants for Level 4: Ember Heights:
##   * "Magma Slime"  - 50% of player speed, preserves Level 1 Shadow Slime damage (4.0)
##   * "Magma Wolf"   - 110% of player speed (Player Speed x 1.10), articulated 4-legged rig,
##                      attack damage strictly lower than Level 1 Shadow Slime (< 4.0)
##   * "Lava Phantom" - flying volcanic phantom with smoke wisps, molten crystal fragments,
##                      warning telegraph ring, and dodgeable FireProjectile attacks.

const FIRE_PROJECTILE := preload("res://objects/fire_projectile.gd")
const SHADOW_SLIME_SCRIPT := preload("res://objects/shadow_slime.gd")

signal defeated

@export_enum("Magma Slime", "Magma Wolf", "Lava Phantom") var variant: String = "Magma Slime"
@export var max_health: int = 3
@export var contact_damage: float = 4.0
@export var attack_damage: float = 4.0
@export var detect_range: float = 11.0
@export var chase_range: float = 14.0
@export var speed_ratio: float = 0.50
@export var base_player_world_speed: float = 6.0
@export var lunge_duration: float = 0.24
@export var recover_duration: float = 0.65
@export var stun_duration: float = 0.35

var health: int = 3
var chase_speed: float = 3.0
var walk_speed: float = 3.0
var slime_damage_reference: float = 4.0

var _home: Vector3 = Vector3.ZERO
var _visual: Node3D
var _torso: Node3D
var _head_pivot: Node3D
var _ear_l: Node3D
var _ear_r: Node3D
var _tail_pivot: Node3D
var _legs: Array[Node3D] = []
var _wisps: Array[Node3D] = []
var _orbit_pivot: Node3D
var _warning_ring: MeshInstance3D

var _body_material: StandardMaterial3D
var _crack_material: StandardMaterial3D
var _eye_material: StandardMaterial3D

var _dead: bool = false
var _time: float = 0.0
var _walk_phase: float = 0.0
var _touch_cooldown: float = 0.0
var _projectile_cooldown: float = 2.0
var _lunge_time: float = 0.0
var _lunge_cooldown: float = 0.0
var _recover_time: float = 0.0
var _stun_time: float = 0.0
var _hit_flash: float = 0.0
var _lunge_direction: Vector3 = Vector3.ZERO
var _reposition_offset: Vector3 = Vector3.ZERO

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("volcanic_enemies")

	# Read the actual Level 1 Shadow Slime damage from the project
	var ref_slime: Node = SHADOW_SLIME_SCRIPT.new()
	if ref_slime != null:
		if ref_slime.get("contact_damage") != null:
			slime_damage_reference = float(ref_slime.get("contact_damage"))
		ref_slime.free()

	if variant == "Magma Wolf":
		add_to_group("magma_wolves")
		speed_ratio = 1.10
		# Normal attack damage must be strictly lower than Level 1 Shadow Slime damage
		if attack_damage >= slime_damage_reference or is_equal_approx(attack_damage, 4.0):
			attack_damage = maxf(1.0, slime_damage_reference * 0.5)
		max_health = maxi(max_health, 3)
	elif variant == "Lava Phantom":
		add_to_group("lava_phantoms")
		speed_ratio = 0.75
		if is_equal_approx(attack_damage, 4.0):
			attack_damage = 5.0
		max_health = maxi(max_health, 3)
	else:
		add_to_group("magma_slimes")
		speed_ratio = 0.50
		attack_damage = slime_damage_reference
		max_health = maxi(max_health, 2)

	contact_damage = attack_damage
	chase_speed = base_player_world_speed * speed_ratio
	walk_speed = chase_speed
	health = max_health
	_home = global_position
	_build()

func _build() -> void:
	_visual = Node3D.new()
	_visual.name = "VolcanicVisual"
	add_child(_visual)

	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = Color("#18151c")
	_body_material.roughness = 0.78
	_body_material.emission_enabled = true
	_body_material.emission = Color("#5a1208")
	_body_material.emission_energy_multiplier = 0.25

	_crack_material = StandardMaterial3D.new()
	_crack_material.albedo_color = Color("#ff4d1a")
	_crack_material.emission_enabled = true
	_crack_material.emission = Color("#ff6e1f")
	_crack_material.emission_energy_multiplier = 2.1
	_crack_material.roughness = 0.25

	_eye_material = StandardMaterial3D.new()
	_eye_material.albedo_color = Color("#ffdf4a")
	_eye_material.emission_enabled = true
	_eye_material.emission = Color("#ff7b1c")
	_eye_material.emission_energy_multiplier = 2.6

	if variant == "Magma Wolf":
		_build_magma_wolf()
	elif variant == "Lava Phantom":
		_build_lava_phantom()
	else:
		_build_magma_slime()

	_build_ember_particles()

func _build_magma_slime() -> void:
	# Rounded jelly-like charcoal body with glowing magma cracks and upper molten formations
	var body := MeshInstance3D.new()
	body.name = "SlimeBody"
	var sphere := SphereMesh.new()
	sphere.radius = 0.46
	sphere.height = 0.82
	body.mesh = sphere
	body.position.y = 0.38
	body.material_override = _body_material
	_visual.add_child(body)

	# Glowing magma crack bands across the body
	for i in 3:
		var crack := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.36 - float(i) * 0.05
		torus.outer_radius = 0.42 - float(i) * 0.05
		crack.mesh = torus
		crack.position = Vector3(0.0, 0.28 + float(i) * 0.14, 0.0)
		crack.rotation = Vector3(0.25 * float(i - 1), float(i) * 0.7, -0.2 * float(i))
		crack.material_override = _crack_material
		_visual.add_child(crack)

	# Small molten formations on upper surface
	for i in 4:
		var angle := TAU * float(i) / 4.0 + 0.4
		var lump := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.03
		cone.bottom_radius = 0.11
		cone.height = 0.24
		lump.mesh = cone
		lump.position = Vector3(cos(angle) * 0.2, 0.78, sin(angle) * 0.2)
		lump.rotation.z = -cos(angle) * 0.28
		lump.material_override = _crack_material
		_visual.add_child(lump)

	# Bright expressive eyes
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.075
		eye_mesh.height = 0.15
		eye.mesh = eye_mesh
		eye.position = Vector3(side * 0.15, 0.44, 0.38)
		eye.material_override = _eye_material
		_visual.add_child(eye)

func _build_magma_wolf() -> void:
	# Articulated quadrupedal wolf with separate torso, head, ears, tail, and 4 legs
	_torso = Node3D.new()
	_torso.name = "Torso"
	_torso.position = Vector3(0.0, 0.56, 0.0)
	_visual.add_child(_torso)

	var chest := MeshInstance3D.new()
	var chest_mesh := CapsuleMesh.new()
	chest_mesh.radius = 0.30
	chest_mesh.height = 0.96
	chest.mesh = chest_mesh
	chest.rotation.x = PI * 0.5
	chest.material_override = _body_material
	_torso.add_child(chest)

	# Glowing red magma cracks along the torso
	for i in 3:
		var seam := MeshInstance3D.new()
		var seam_mesh := BoxMesh.new()
		seam_mesh.size = Vector3(0.62, 0.06, 0.09)
		seam.mesh = seam_mesh
		seam.position = Vector3(0.0, 0.12, -0.24 + float(i) * 0.24)
		seam.material_override = _crack_material
		_torso.add_child(seam)

	# Volcanic crystal formations along its back
	for i in 3:
		var spine := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.09
		cone.height = 0.34
		spine.mesh = cone
		spine.position = Vector3(0.0, 0.36, -0.22 + float(i) * 0.22)
		spine.rotation.x = -0.25
		spine.material_override = _crack_material
		_torso.add_child(spine)

	# Articulated Head Pivot + Ears + Snout + Eyes
	_head_pivot = Node3D.new()
	_head_pivot.name = "HeadPivot"
	_head_pivot.position = Vector3(0.0, 0.22, 0.52)
	_torso.add_child(_head_pivot)

	var skull := MeshInstance3D.new()
	var skull_mesh := SphereMesh.new()
	skull_mesh.radius = 0.25
	skull_mesh.height = 0.48
	skull.mesh = skull_mesh
	skull.material_override = _body_material
	_head_pivot.add_child(skull)

	var snout := MeshInstance3D.new()
	var snout_mesh := CylinderMesh.new()
	snout_mesh.top_radius = 0.09
	snout_mesh.bottom_radius = 0.16
	snout_mesh.height = 0.32
	snout.mesh = snout_mesh
	snout.rotation.x = PI * 0.5
	snout.position = Vector3(0.0, -0.04, 0.24)
	snout.material_override = _body_material
	_head_pivot.add_child(snout)

	for side in [-1.0, 1.0]:
		var ear_pivot := Node3D.new()
		ear_pivot.position = Vector3(side * 0.16, 0.20, -0.02)
		_head_pivot.add_child(ear_pivot)
		var ear := MeshInstance3D.new()
		var ear_cone := CylinderMesh.new()
		ear_cone.top_radius = 0.0
		ear_cone.bottom_radius = 0.08
		ear_cone.height = 0.24
		ear.mesh = ear_cone
		ear.position.y = 0.12
		ear.material_override = _crack_material
		ear_pivot.add_child(ear)
		if side < 0.0:
			_ear_l = ear_pivot
		else:
			_ear_r = ear_pivot

		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.055
		eye_mesh.height = 0.11
		eye.mesh = eye_mesh
		eye.position = Vector3(side * 0.11, 0.05, 0.19)
		eye.material_override = _eye_material
		_head_pivot.add_child(eye)

	# Articulated Fiery Tail Pivot
	_tail_pivot = Node3D.new()
	_tail_pivot.name = "TailPivot"
	_tail_pivot.position = Vector3(0.0, 0.12, -0.48)
	_torso.add_child(_tail_pivot)

	var tail := MeshInstance3D.new()
	var tail_mesh := CylinderMesh.new()
	tail_mesh.top_radius = 0.04
	tail_mesh.bottom_radius = 0.13
	tail_mesh.height = 0.68
	tail.mesh = tail_mesh
	tail.position = Vector3(0.0, 0.14, -0.26)
	tail.rotation.x = -0.85
	tail.material_override = _crack_material
	_tail_pivot.add_child(tail)

	# 4 Articulated Legs with glowing molten paws
	_legs.clear()
	var leg_offsets := [
		Vector3(-0.22, -0.12, 0.30), # Front Left
		Vector3(0.22, -0.12, 0.30),  # Front Right
		Vector3(-0.22, -0.12, -0.30),# Back Left
		Vector3(0.22, -0.12, -0.30), # Back Right
	]
	for idx in leg_offsets.size():
		var leg_pivot := Node3D.new()
		leg_pivot.name = "Leg_%d" % idx
		leg_pivot.position = leg_offsets[idx]
		_torso.add_child(leg_pivot)

		var limb := MeshInstance3D.new()
		var limb_mesh := CapsuleMesh.new()
		limb_mesh.radius = 0.085
		limb_mesh.height = 0.44
		limb.mesh = limb_mesh
		limb.position.y = -0.20
		limb.material_override = _body_material
		leg_pivot.add_child(limb)

		var paw := MeshInstance3D.new()
		var paw_mesh := SphereMesh.new()
		paw_mesh.radius = 0.095
		paw_mesh.height = 0.14
		paw.mesh = paw_mesh
		paw.position = Vector3(0.0, -0.40, 0.03)
		paw.material_override = _crack_material
		leg_pivot.add_child(paw)

		_legs.append(leg_pivot)

func _build_lava_phantom() -> void:
	# Floating ghost-like charcoal body with glowing magma cracks and smoke wisps
	var cloak := MeshInstance3D.new()
	cloak.name = "PhantomCloak"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.24
	cyl.bottom_radius = 0.54
	cyl.height = 1.22
	cloak.mesh = cyl
	cloak.position.y = 0.65
	var cloak_mat := _body_material.duplicate() as StandardMaterial3D
	cloak_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloak_mat.albedo_color = Color(0.11, 0.09, 0.13, 0.88)
	cloak.material_override = cloak_mat
	_visual.add_child(cloak)

	var hood := MeshInstance3D.new()
	var hood_mesh := SphereMesh.new()
	hood_mesh.radius = 0.34
	hood_mesh.height = 0.68
	hood.mesh = hood_mesh
	hood.position.y = 1.18
	hood.material_override = _body_material
	_visual.add_child(hood)

	# Glowing magma crack collar
	var collar := MeshInstance3D.new()
	var collar_torus := TorusMesh.new()
	collar_torus.inner_radius = 0.32
	collar_torus.outer_radius = 0.40
	collar.mesh = collar_torus
	collar.position.y = 0.96
	collar.material_override = _crack_material
	_visual.add_child(collar)

	# Glowing eyes
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.065
		eye_mesh.height = 0.13
		eye.mesh = eye_mesh
		eye.position = Vector3(side * 0.12, 1.18, 0.28)
		eye.material_override = _eye_material
		_visual.add_child(eye)

	# Flowing lower body smoke wisps
	_wisps.clear()
	for i in 4:
		var wisp_pivot := Node3D.new()
		var angle := TAU * float(i) / 4.0
		wisp_pivot.position = Vector3(cos(angle) * 0.32, 0.15, sin(angle) * 0.32)
		_visual.add_child(wisp_pivot)
		var wisp := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.12
		cone.bottom_radius = 0.02
		cone.height = 0.52
		wisp.mesh = cone
		wisp.position.y = -0.22
		wisp.material_override = _crack_material if i % 2 == 0 else _body_material
		wisp_pivot.add_child(wisp)
		_wisps.append(wisp_pivot)

	# Floating molten crystal fragments orbiting the phantom
	_orbit_pivot = Node3D.new()
	_orbit_pivot.name = "MoltenOrbit"
	_orbit_pivot.position.y = 0.85
	_visual.add_child(_orbit_pivot)
	for i in 3:
		var angle := TAU * float(i) / 3.0
		var shard := MeshInstance3D.new()
		var shard_mesh := CylinderMesh.new()
		shard_mesh.top_radius = 0.0
		shard_mesh.bottom_radius = 0.11
		shard_mesh.height = 0.42
		shard.mesh = shard_mesh
		shard.position = Vector3(cos(angle) * 0.72, (i % 2) * 0.14, sin(angle) * 0.72)
		shard.rotation.z = 0.35
		shard.material_override = _crack_material
		_orbit_pivot.add_child(shard)

	# Telegraph warning ring shown before launching a FireProjectile
	_warning_ring = MeshInstance3D.new()
	_warning_ring.name = "WarningRing"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.65
	ring_mesh.outer_radius = 0.78
	_warning_ring.mesh = ring_mesh
	_warning_ring.position.y = 0.85
	_warning_ring.material_override = _eye_material
	_warning_ring.visible = false
	add_child(_warning_ring)

func _build_ember_particles() -> void:
	var particles := GPUParticles3D.new()
	particles.name = "EmberParticles"
	particles.amount = 14
	particles.lifetime = 1.5
	particles.preprocess = 0.6
	var quad := QuadMesh.new()
	quad.size = Vector2(0.08, 0.08)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#ff7b24")
	mat.emission_enabled = true
	mat.emission = Color("#ff5118")
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = mat
	particles.draw_pass_1 = quad
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 0.45
	proc.direction = Vector3(0.0, 1.0, 0.0)
	proc.spread = 38.0
	proc.initial_velocity_min = 0.25
	proc.initial_velocity_max = 0.75
	proc.gravity = Vector3(0.0, 0.35, 0.0)
	particles.process_material = proc
	particles.position.y = 0.5
	add_child(particles)

func _physics_process(delta: float) -> void:
	if _dead:
		return
	_time += delta
	_touch_cooldown = maxf(_touch_cooldown - delta, 0.0)
	_projectile_cooldown = maxf(_projectile_cooldown - delta, 0.0)
	_lunge_cooldown = maxf(_lunge_cooldown - delta, 0.0)
	_recover_time = maxf(_recover_time - delta, 0.0)
	_stun_time = maxf(_stun_time - delta, 0.0)
	if _hit_flash > 0.0:
		_hit_flash = maxf(_hit_flash - delta, 0.0)
		_crack_material.emission_energy_multiplier = 2.1 + _hit_flash * 6.0

	if _stun_time > 0.0:
		_animate_stun(delta)
		return

	var target := _nearest_player()
	if target == null:
		_animate_idle_or_patrol(delta, false)
		return

	var offset := target.global_position - global_position
	var distance := offset.length()

	if variant == "Magma Wolf" and _lunge_time > 0.0:
		_lunge_time -= delta
		var lunge_speed := _world_speed(target) * 1.45
		_try_ground_move(_lunge_direction * lunge_speed * delta)
		_animate_wolf(delta, true, true)
		_check_contact_hit(target, distance)
		if _lunge_time <= 0.0:
			_recover_time = recover_duration
			_lunge_cooldown = 1.25
		return

	if _recover_time > 0.0:
		if variant != "Lava Phantom":
			_snap_to_ground()
		_animate_idle_or_patrol(delta, false)
		return

	if distance > detect_range:
		if variant != "Lava Phantom":
			_snap_to_ground()
		_animate_idle_or_patrol(delta, false)
		return

	# Active chase / combat inside detect_range
	if variant == "Lava Phantom":
		_update_phantom_combat(delta, target, offset, distance)
	elif variant == "Magma Wolf":
		_update_wolf_combat(delta, target, offset, distance)
	else:
		_update_slime_combat(delta, target, offset, distance)

func _update_slime_combat(delta: float, target: Node3D, offset: Vector3, distance: float) -> void:
	var flat := Vector3(offset.x, 0.0, offset.z)
	var spd := _world_speed(target)
	if flat.length() > 0.45:
		_try_ground_move(flat.normalized() * spd * delta)
		rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.z), delta * 6.0)
	else:
		_snap_to_ground()
	# Heavy lava-like bounce animation
	var bounce := absf(sin(_time * 6.5))
	_visual.position.y = bounce * 0.24
	_visual.scale = Vector3(1.0 + (0.14 - bounce * 0.22), 0.88 + bounce * 0.28, 1.0 + (0.14 - bounce * 0.22))
	_check_contact_hit(target, distance)

func _update_wolf_combat(delta: float, target: Node3D, offset: Vector3, distance: float) -> void:
	var flat := Vector3(offset.x, 0.0, offset.z)
	if flat.length_squared() > 0.001:
		rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.z), delta * 8.0)
	if distance < 2.5 and _lunge_cooldown <= 0.0:
		_lunge_direction = flat.normalized() if flat.length() > 0.01 else Vector3(sin(rotation.y), 0.0, cos(rotation.y))
		_lunge_time = lunge_duration
		var audio := get_node_or_null("/root/Audio")
		if audio != null:
			audio.play("res://sounds/jump.ogg")
		return
	var spd := _world_speed(target)
	if flat.length() > 0.48:
		_try_ground_move(flat.normalized() * spd * delta)
	else:
		_snap_to_ground()
	_animate_wolf(delta, true, false)
	_check_contact_hit(target, distance)

func _try_ground_move(step: Vector3) -> void:
	var candidate := global_position + Vector3(step.x, 0.0, step.z)
	var dir := Vector3(step.x, 0.0, step.z).normalized()
	var lead := candidate + dir * 0.44
	var lead_floor_y := _probe_ground_y(lead)
	if is_nan(lead_floor_y) or Vector2(candidate.x - _home.x, candidate.z - _home.z).length() > 1.05:
		# Stop at the platform edge: never walk or lunge off into the air
		_snap_to_ground()
		return
	var cur_floor_y := _probe_ground_y(candidate)
	if not is_nan(cur_floor_y):
		candidate.y = cur_floor_y
	global_position = candidate

func _snap_to_ground() -> void:
	var floor_y := _probe_ground_y(global_position)
	if not is_nan(floor_y):
		global_position.y = floor_y

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

func _update_phantom_combat(delta: float, target: Node3D, offset: Vector3, distance: float) -> void:
	var spd := _world_speed(target)
	var desired_pos := target.global_position + Vector3(0.0, 2.2, 0.0) + _reposition_offset
	var to_desired := desired_pos - global_position
	if to_desired.length() > 0.6:
		global_position += to_desired.normalized() * spd * delta
	global_position.y += sin(_time * 2.6) * delta * 0.45
	var flat := Vector3(offset.x, 0.0, offset.z)
	if flat.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.z), delta * 5.5)

	if _projectile_cooldown <= 0.55 and _projectile_cooldown > 0.0:
		if _warning_ring != null:
			_warning_ring.visible = true
			_warning_ring.scale = Vector3.ONE * (0.8 + sin(_time * 18.0) * 0.2)
	elif _projectile_cooldown <= 0.0:
		if _warning_ring != null:
			_warning_ring.visible = false
		_launch_fire_projectile(target)
		# Occasionally shift aerial position after firing
		var angle := _time * 2.1
		_reposition_offset = Vector3(cos(angle) * 2.2, sin(angle) * 0.4, sin(angle) * 2.2)

	_animate_phantom(delta)
	_check_contact_hit(target, distance)

func _animate_idle_or_patrol(delta: float, moving: bool) -> void:
	if variant == "Lava Phantom":
		_patrol_phantom()
		_animate_phantom(delta)
	elif variant == "Magma Wolf":
		_animate_wolf(delta, moving, false)
	else:
		# Gentle idle wobble for Magma Slime
		var wobble := sin(_time * 3.2)
		_visual.position.y = maxf(0.0, wobble * 0.08)
		_visual.scale = Vector3(1.0 + wobble * 0.05, 1.0 - wobble * 0.05, 1.0 + wobble * 0.05)

func _animate_wolf(delta: float, running: bool, lunging: bool) -> void:
	if _torso == null:
		return
	var rate := 12.0 if running else 3.2
	_walk_phase += delta * rate
	if lunging:
		_torso.rotation.x = -0.25
		_torso.position.y = 0.64
	elif running:
		_torso.position.y = 0.56 + absf(sin(_walk_phase)) * 0.07
		_torso.rotation.x = sin(_walk_phase) * 0.06
	else:
		# Expressive Animal Crossing-inspired idle breathing & head look
		_torso.position.y = 0.56 + sin(_time * 2.6) * 0.025
		_torso.rotation.x = 0.0
		if _head_pivot != null:
			_head_pivot.rotation.y = sin(_time * 1.5) * 0.22
			_head_pivot.rotation.z = cos(_time * 1.1) * 0.08
	if _ear_l != null and _ear_r != null:
		_ear_l.rotation.z = 0.12 + sin(_time * 3.4) * 0.08
		_ear_r.rotation.z = -0.12 - cos(_time * 3.4) * 0.08
	if _tail_pivot != null:
		_tail_pivot.rotation.y = sin(_time * (8.0 if running else 3.2)) * 0.35

	var swing_amp := 0.58 if running else 0.08
	for i in _legs.size():
		var phase_offset := 0.0 if (i == 0 or i == 3) else PI
		_legs[i].rotation.x = sin(_walk_phase + phase_offset) * swing_amp

func _animate_phantom(delta: float) -> void:
	_visual.position.y = sin(_time * 2.8) * 0.14
	if _orbit_pivot != null:
		_orbit_pivot.rotation.y += delta * 2.1
	for i in _wisps.size():
		_wisps[i].rotation.x = sin(_time * 4.0 + float(i)) * 0.22
		_wisps[i].rotation.z = cos(_time * 3.5 + float(i)) * 0.22

func _animate_stun(_delta: float) -> void:
	# Shake off embers when stunned
	_visual.rotation.z = sin(_time * 28.0) * 0.16
	if variant == "Magma Wolf" and _head_pivot != null:
		_head_pivot.rotation.y = sin(_time * 32.0) * 0.35

func _patrol_phantom() -> void:
	global_position = _home + Vector3(
		sin(_time * 0.75) * 2.4,
		sin(_time * 1.5) * 0.65,
		cos(_time * 0.75) * 1.8
	)

func _launch_fire_projectile(target: Node3D) -> void:
	_projectile_cooldown = 2.6
	if get_parent() == null:
		return
	var projectile: FireProjectile = FIRE_PROJECTILE.new()
	projectile.damage = attack_damage
	projectile.source_name = "lava_phantom"
	get_parent().add_child(projectile)
	projectile.global_position = global_position + Vector3(0.0, 0.85, 0.0)
	projectile.launch(target)

func _check_contact_hit(target: Node3D, distance: float) -> void:
	if distance < 1.05 and _touch_cooldown <= 0.0 and target.has_method("take_damage"):
		var src := "magma_slime"
		if variant == "Magma Wolf":
			src = "magma_wolf"
		elif variant == "Lava Phantom":
			src = "lava_phantom"
		target.call("take_damage", attack_damage, global_position, src)
		_touch_cooldown = 0.95

## Formula required by spec:
##   Magma Wolf Speed = Player Speed * 1.10
##   Magma Slime Speed = Player Speed * 0.50
func _movement_speed(target: Node3D) -> float:
	var player_speed := float(target.get("movement_speed")) if (target != null and target.get("movement_speed") != null) else 250.0
	return player_speed * speed_ratio

func _world_speed(target: Node3D) -> float:
	if target != null and target.get("movement_speed") != null:
		var raw := float(target.get("movement_speed"))
		# Player movement_speed=250 with delta damping corresponds to 6.0 m/s world walk speed
		var world_base := (raw / 250.0) * base_player_world_speed if raw > 20.0 else raw
		chase_speed = world_base * speed_ratio
		walk_speed = chase_speed
		return chase_speed
	return chase_speed

func _nearest_player() -> Node3D:
	var nearest: Node3D = null
	var best := INF
	for candidate in get_tree().get_nodes_in_group("player"):
		if not (candidate is Node3D) or not candidate.has_method("take_damage") or bool(candidate.get("is_dead")):
			continue
		var dist := global_position.distance_to((candidate as Node3D).global_position)
		if dist < best:
			best = dist
			nearest = candidate as Node3D
	return nearest

func reset_to_home() -> void:
	if _dead:
		return
	global_position = _home
	_lunge_time = 0.0
	_recover_time = 0.0
	_stun_time = 0.0
	if _warning_ring != null:
		_warning_ring.visible = false

func take_hit(amount: int, from: Vector3) -> bool:
	if _dead:
		return false
	health -= amount
	_hit_flash = 0.35
	_stun_time = stun_duration
	var away := global_position - from
	away.y = 0.0
	if away.length_squared() > 0.001:
		global_position += away.normalized() * 0.45
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		audio.play("res://sounds/land.ogg")
	if health <= 0:
		_dead = true
		defeated.emit()
		_spawn_defeat_burst()
		queue_free()
	return true

func _spawn_defeat_burst() -> void:
	if get_parent() == null:
		return
	var burst := GPUParticles3D.new()
	burst.amount = 22
	burst.lifetime = 0.75
	burst.one_shot = true
	burst.explosiveness = 0.95
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#ff5b1f")
	mat.emission_enabled = true
	mat.emission = Color("#ff8e24")
	mat.emission_energy_multiplier = 2.4
	quad.material = mat
	burst.draw_pass_1 = quad
	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0.0, 1.0, 0.0)
	proc.spread = 180.0
	proc.initial_velocity_min = 1.2
	proc.initial_velocity_max = 3.4
	proc.gravity = Vector3(0.0, -2.2, 0.0)
	burst.process_material = proc
	burst.position = position + Vector3(0.0, 0.6, 0.0)
	get_parent().add_child(burst)
	burst.emitting = true
	get_tree().create_timer(1.1).timeout.connect(func():
		if is_instance_valid(burst):
			burst.queue_free()
	)
