extends Node3D
class_name EmberDragon

## THE EMBER DRAGON - GUARDIAN OF EMBER HEIGHTS
## Ancient volcanic dragon corrupted by Malakar, guarding the Fourth Fragment of the Eternal Tree.
## Features 4 distinct boss phases:
##   Phase 1 - The Volcanic Guardian
##   Phase 2 - Rising Inferno
##   Phase 3 - Molten Fury
##   Phase 4 - Dragon's Awakening

const FIRE_PROJECTILE := preload("res://objects/fire_projectile.gd")

signal woke
signal defeated
signal health_changed(health: int, maximum: int, phase: int)

const PHASE_NAMES := [
	"The Volcanic Guardian",
	"Rising Inferno",
	"Molten Fury",
	"Dragon's Awakening",
]

@export var max_health: int = 48
@export var contact_damage: float = 3.0
@export var locked: bool = true
@export var wake_range: float = 14.0
@export var base_move_speed: float = 4.8

var health: int = 48
var phase: int = 1
var _home: Vector3 = Vector3.ZERO
var _time: float = 0.0
var _dead: bool = false
var _attack_cooldown: float = 2.4
var _recover_time: float = 0.0
var _flight_time: float = 0.0
var _charge_time: float = 0.0
var _charge_dir: Vector3 = Vector3.ZERO
var _tail_sweep_time: float = 0.0

var _visual: Node3D
var _neck_pivot: Node3D
var _head_pivot: Node3D
var _wing_l: Node3D
var _wing_r: Node3D
var _tail_pivot: Node3D
var _chest_core: MeshInstance3D
var _legs: Array[Node3D] = []
var _warning: MeshInstance3D

var _scale_mat: StandardMaterial3D
var _crack_mat: StandardMaterial3D
var _wing_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("ember_dragon")
	health = max_health
	_home = global_position
	_build()
	health_changed.emit(health, max_health, phase)

func phase_name(p: int = -1) -> String:
	var idx := clampi((phase if p < 0 else p) - 1, 0, PHASE_NAMES.size() - 1)
	return PHASE_NAMES[idx]

func unlock() -> void:
	if not locked:
		return
	locked = false
	woke.emit()
	health_changed.emit(health, max_health, phase)
	# Entrance roar & wing spread animation
	if _visual != null:
		_visual.scale = Vector3.ONE * 0.72
		var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(_visual, "scale", Vector3.ONE, 0.55)
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		audio.play("res://sounds/land.ogg")

func _build() -> void:
	_visual = Node3D.new()
	_visual.name = "DragonVisual"
	add_child(_visual)

	_scale_mat = StandardMaterial3D.new()
	_scale_mat.albedo_color = Color("#120f17")
	_scale_mat.roughness = 0.52
	_scale_mat.metallic = 0.18
	_scale_mat.emission_enabled = true
	_scale_mat.emission = Color("#54140a")
	_scale_mat.emission_energy_multiplier = 0.32

	_crack_mat = StandardMaterial3D.new()
	_crack_mat.albedo_color = Color("#ff4411")
	_crack_mat.emission_enabled = true
	_crack_mat.emission = Color("#ff6e18")
	_crack_mat.emission_energy_multiplier = 2.6
	_crack_mat.roughness = 0.2

	_wing_mat = StandardMaterial3D.new()
	_wing_mat.albedo_color = Color("#5a120d")
	_wing_mat.emission_enabled = true
	_wing_mat.emission = Color("#c72814")
	_wing_mat.emission_energy_multiplier = 0.95
	_wing_mat.roughness = 0.42

	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = Color("#fff066")
	_eye_mat.emission_enabled = true
	_eye_mat.emission = Color("#ffa324")
	_eye_mat.emission_energy_multiplier = 3.2

	# Anatomical Armored Dragon Body: Chest & Abdomen sections with tapering
	var chest := MeshInstance3D.new()
	var chest_mesh := CapsuleMesh.new()
	chest_mesh.radius = 1.22
	chest_mesh.height = 2.4
	chest.mesh = chest_mesh
	chest.rotation.x = PI * 0.48
	chest.position = Vector3(0.0, 1.78, 0.45)
	chest.material_override = _scale_mat
	_visual.add_child(chest)

	var abdomen := MeshInstance3D.new()
	var abd_mesh := CapsuleMesh.new()
	abd_mesh.radius = 0.98
	abd_mesh.height = 2.1
	abdomen.mesh = abd_mesh
	abdomen.rotation.x = PI * 0.54
	abdomen.position = Vector3(0.0, 1.55, -0.95)
	abdomen.material_override = _scale_mat
	_visual.add_child(abdomen)

	# Volcanic ventral belly plates (segmented armor underbelly)
	for b in 4:
		var plate := MeshInstance3D.new()
		var p_box := BoxMesh.new()
		p_box.size = Vector3(1.15 - float(b) * 0.12, 0.18, 0.62)
		plate.mesh = p_box
		plate.position = Vector3(0.0, 0.88 + float(b) * 0.08, 0.85 - float(b) * 0.58)
		plate.rotation.x = 0.18
		plate.material_override = _crack_mat
		_visual.add_child(plate)

	# Glowing molten chest core (pulsing volcanic heart chamber)
	_chest_core = MeshInstance3D.new()
	var chest_sphere := SphereMesh.new()
	chest_sphere.radius = 0.72
	chest_sphere.height = 1.35
	_chest_core.mesh = chest_sphere
	_chest_core.position = Vector3(0.0, 1.62, 0.92)
	_chest_core.material_override = _crack_mat
	_visual.add_child(_chest_core)

	# Segmented dorsal magma spines running down the spine
	for i in 7:
		var spine := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.02
		cone.bottom_radius = 0.18 - float(i) * 0.015
		cone.height = 0.88 - float(i) * 0.06
		spine.mesh = cone
		spine.position = Vector3(0.0, 2.72 - float(i) * 0.12, 1.15 - float(i) * 0.42)
		spine.rotation.x = -0.32
		spine.material_override = _crack_mat
		_visual.add_child(spine)

	# Articulated Multi-Segment Neck & Realistic Dragon Skull
	_neck_pivot = Node3D.new()
	_neck_pivot.name = "NeckPivot"
	_neck_pivot.position = Vector3(0.0, 2.35, 1.35)
	_visual.add_child(_neck_pivot)

	var neck_base := MeshInstance3D.new()
	var n_base_mesh := CylinderMesh.new()
	n_base_mesh.top_radius = 0.52
	n_base_mesh.bottom_radius = 0.72
	n_base_mesh.height = 0.85
	neck_base.mesh = n_base_mesh
	neck_base.position = Vector3(0.0, 0.32, 0.28)
	neck_base.rotation.x = 0.42
	neck_base.material_override = _scale_mat
	_neck_pivot.add_child(neck_base)

	var neck_upper := MeshInstance3D.new()
	var n_upper_mesh := CylinderMesh.new()
	n_upper_mesh.top_radius = 0.42
	n_upper_mesh.bottom_radius = 0.54
	n_upper_mesh.height = 0.85
	neck_upper.mesh = n_upper_mesh
	neck_upper.position = Vector3(0.0, 0.78, 0.58)
	neck_upper.rotation.x = 0.58
	neck_upper.material_override = _scale_mat
	_neck_pivot.add_child(neck_upper)

	_head_pivot = Node3D.new()
	_head_pivot.name = "HeadPivot"
	_head_pivot.position = Vector3(0.0, 1.25, 0.95)
	_neck_pivot.add_child(_head_pivot)

	# Cranium with realistic sloping snout & brow ridges
	var skull := MeshInstance3D.new()
	var skull_mesh := BoxMesh.new()
	skull_mesh.size = Vector3(0.92, 0.68, 0.95)
	skull.mesh = skull_mesh
	skull.position = Vector3(0.0, 0.12, 0.0)
	skull.material_override = _scale_mat
	_head_pivot.add_child(skull)

	var snout := MeshInstance3D.new()
	var snout_mesh := BoxMesh.new()
	snout_mesh.size = Vector3(0.68, 0.46, 1.1)
	snout.mesh = snout_mesh
	snout.position = Vector3(0.0, -0.02, 0.82)
	snout.material_override = _scale_mat
	_head_pivot.add_child(snout)

	# Articulated Lower Jaw (opens realistically during breath & roars)
	var jaw := MeshInstance3D.new()
	var jaw_mesh := BoxMesh.new()
	jaw_mesh.size = Vector3(0.62, 0.26, 1.05)
	jaw.mesh = jaw_mesh
	jaw.position = Vector3(0.0, -0.32, 0.78)
	jaw.material_override = _crack_mat
	_head_pivot.add_child(jaw)

	# Glowing magma eyes & sharp volcanic crystal horns
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.14
		eye_mesh.height = 0.28
		eye.mesh = eye_mesh
		eye.position = Vector3(side * 0.38, 0.22, 0.42)
		eye.material_override = _eye_mat
		_head_pivot.add_child(eye)

		# Crown horns curving backward
		var horn := MeshInstance3D.new()
		var horn_cone := CylinderMesh.new()
		horn_cone.top_radius = 0.02
		horn_cone.bottom_radius = 0.18
		horn_cone.height = 1.25
		horn.mesh = horn_cone
		horn.position = Vector3(side * 0.42, 0.68, -0.28)
		horn.rotation = Vector3(-0.68, 0.0, side * -0.24)
		horn.material_override = _crack_mat
		_head_pivot.add_child(horn)

		# Secondary brow horns
		var sub_horn := MeshInstance3D.new()
		var sub_cone := CylinderMesh.new()
		sub_cone.top_radius = 0.01
		sub_cone.bottom_radius = 0.11
		sub_cone.height = 0.58
		sub_horn.mesh = sub_cone
		sub_horn.position = Vector3(side * 0.46, 0.38, 0.22)
		sub_horn.rotation = Vector3(-0.42, 0.0, side * -0.45)
		sub_horn.material_override = _crack_mat
		_head_pivot.add_child(sub_horn)

	# Realistic Articulated Dual-Jointed Wings (Humerus Arm + Radius + Wing Webbing)
	for side in [-1.0, 1.0]:
		var wing_pivot := Node3D.new()
		wing_pivot.name = "WingLeft" if side < 0.0 else "WingRight"
		wing_pivot.position = Vector3(side * 1.05, 2.35, 0.25)
		_visual.add_child(wing_pivot)

		# Wing arm (proximal spar)
		var arm := MeshInstance3D.new()
		var arm_box := BoxMesh.new()
		arm_box.size = Vector3(1.85, 0.28, 0.34)
		arm.mesh = arm_box
		arm.position = Vector3(side * 0.95, 0.32, 0.08)
		arm.rotation.z = side * 0.28
		arm.material_override = _scale_mat
		wing_pivot.add_child(arm)

		# Outer wing finger (distal spar)
		var outer_spar := MeshInstance3D.new()
		var o_box := BoxMesh.new()
		o_box.size = Vector3(2.35, 0.20, 0.26)
		outer_spar.mesh = o_box
		outer_spar.position = Vector3(side * 2.45, 0.65, -0.22)
		outer_spar.rotation.z = side * 0.12
		outer_spar.material_override = _scale_mat
		wing_pivot.add_child(outer_spar)

		# Realistic multi-creased wing membrane
		var membrane := MeshInstance3D.new()
		var mem_box := BoxMesh.new()
		mem_box.size = Vector3(3.2, 0.07, 2.35)
		membrane.mesh = mem_box
		membrane.position = Vector3(side * 1.85, 0.28, -0.85)
		membrane.rotation.z = side * 0.22
		membrane.material_override = _wing_mat
		wing_pivot.add_child(membrane)

		if side < 0.0:
			_wing_l = wing_pivot
		else:
			_wing_r = wing_pivot

	# Multi-Segmented Articulated Tail with Spiked Magma Club
	_tail_pivot = Node3D.new()
	_tail_pivot.name = "TailPivot"
	_tail_pivot.position = Vector3(0.0, 1.48, -1.65)
	_visual.add_child(_tail_pivot)

	var tail_seg1 := MeshInstance3D.new()
	var t_cyl1 := CylinderMesh.new()
	t_cyl1.top_radius = 0.36
	t_cyl1.bottom_radius = 0.62
	t_cyl1.height = 1.65
	tail_seg1.mesh = t_cyl1
	tail_seg1.position = Vector3(0.0, -0.12, -0.75)
	tail_seg1.rotation.x = -1.18
	tail_seg1.material_override = _scale_mat
	_tail_pivot.add_child(tail_seg1)

	var tail_seg2 := MeshInstance3D.new()
	var t_cyl2 := CylinderMesh.new()
	t_cyl2.top_radius = 0.18
	t_cyl2.bottom_radius = 0.36
	t_cyl2.height = 1.85
	tail_seg2.mesh = t_cyl2
	tail_seg2.position = Vector3(0.0, -0.42, -2.15)
	tail_seg2.rotation.x = -1.38
	tail_seg2.material_override = _scale_mat
	_tail_pivot.add_child(tail_seg2)

	# Tail club with lateral volcanic spikes
	var tail_club := MeshInstance3D.new()
	var club_sphere := SphereMesh.new()
	club_sphere.radius = 0.38
	club_sphere.height = 0.72
	tail_club.mesh = club_sphere
	tail_club.position = Vector3(0.0, -0.62, -3.2)
	tail_club.material_override = _crack_mat
	_tail_pivot.add_child(tail_club)

	for side in [-1.0, 1.0]:
		var club_spike := MeshInstance3D.new()
		var sp_cone := CylinderMesh.new()
		sp_cone.top_radius = 0.01
		sp_cone.bottom_radius = 0.15
		sp_cone.height = 0.65
		club_spike.mesh = sp_cone
		club_spike.position = Vector3(side * 0.38, -0.62, -3.2)
		club_spike.rotation = Vector3(0.0, 0.0, side * (PI * 0.5))
		club_spike.material_override = _crack_mat
		_tail_pivot.add_child(club_spike)

	# 4 Muscular Anatomical Legs with Thighs, Shins, and Taloned Feet
	_legs.clear()
	var leg_coords := [
		Vector3(-0.95, 1.15, 0.95),
		Vector3(0.95, 1.15, 0.95),
		Vector3(-1.05, 1.15, -0.95),
		Vector3(1.05, 1.15, -0.95),
	]
	for idx in leg_coords.size():
		var pos: Vector3 = leg_coords[idx]
		var is_hind := idx >= 2
		var leg_p := Node3D.new()
		leg_p.position = pos
		_visual.add_child(leg_p)

		# Muscular upper leg / thigh
		var thigh := MeshInstance3D.new()
		var thigh_mesh := CapsuleMesh.new()
		thigh_mesh.radius = 0.38 if is_hind else 0.32
		thigh_mesh.height = 1.25
		thigh.mesh = thigh_mesh
		thigh.position = Vector3(0.0, -0.22, 0.08 if is_hind else -0.05)
		thigh.rotation.x = 0.22 if is_hind else -0.15
		thigh.material_override = _scale_mat
		leg_p.add_child(thigh)

		# Lower leg / shin
		var shin := MeshInstance3D.new()
		var shin_mesh := CylinderMesh.new()
		shin_mesh.top_radius = 0.26
		shin_mesh.bottom_radius = 0.22
		shin_mesh.height = 0.92
		shin.mesh = shin_mesh
		shin.position = Vector3(0.0, -0.78, -0.08 if is_hind else 0.08)
		shin.rotation.x = -0.22 if is_hind else 0.18
		shin.material_override = _scale_mat
		leg_p.add_child(shin)

		# Volcanic Talons / Claws
		var foot := MeshInstance3D.new()
		var foot_box := BoxMesh.new()
		foot_box.size = Vector3(0.52, 0.22, 0.68)
		foot.mesh = foot_box
		foot.position = Vector3(0.0, -1.18, 0.16)
		foot.material_override = _crack_mat
		leg_p.add_child(foot)

		_legs.append(leg_p)

	# Ground Telegraph Warning Ring
	_warning = MeshInstance3D.new()
	_warning.name = "WarningRing"
	var w_torus := TorusMesh.new()
	w_torus.inner_radius = 2.4
	w_torus.outer_radius = 2.65
	_warning.mesh = w_torus
	_warning.position.y = 0.12
	_warning.material_override = _crack_mat
	_warning.visible = false
	add_child(_warning)

	# Floating Embers & Smoke around the dragon
	var particles := GPUParticles3D.new()
	particles.name = "EmberParticles"
	particles.amount = 28
	particles.lifetime = 1.8
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	quad.material = _crack_mat
	particles.draw_pass_1 = quad
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 2.0
	proc.direction = Vector3(0.0, 1.0, 0.0)
	proc.spread = 45.0
	proc.initial_velocity_min = 0.5
	proc.initial_velocity_max = 1.6
	proc.gravity = Vector3(0.0, 0.4, 0.0)
	particles.process_material = proc
	particles.position.y = 1.8
	add_child(particles)

func _physics_process(delta: float) -> void:
	if _dead:
		return
	var target := get_tree().get_first_node_in_group("player") as Node3D

	# If locked, passively animate and wake up when the player approaches the arena
	if locked:
		_time += delta
		_animate_dragon(delta)
		if target != null and global_position.distance_to(target.global_position) <= wake_range:
			unlock()
		return

	_time += delta
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_recover_time = maxf(0.0, _recover_time - delta)

	_animate_dragon(delta)

	if target == null:
		return

	var offset := target.global_position - global_position
	var flat := Vector3(offset.x, 0.0, offset.z)
	var dist := offset.length()

	if _charge_time > 0.0:
		_charge_time -= delta
		global_position += _charge_dir * (base_move_speed * 2.5) * delta
		if dist < 3.2 and target.has_method("take_damage"):
			target.call("take_damage", 10.0, global_position, "ember_dragon")
		if _charge_time <= 0.0:
			_recover_time = 0.45
		return

	# Face and actively stalk/charge the player across the arena
	if flat.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.z), delta * 5.5)

	# Active pursuit: move toward player whenever further than close combat range
	var move_mult := 1.0 + float(phase - 1) * 0.22
	if flat.length() > 2.0 and _recover_time <= 0.0:
		global_position += flat.normalized() * (base_move_speed * move_mult) * delta

	if dist < 2.8 and target.has_method("take_damage"):
		target.call("take_damage", contact_damage, global_position, "ember_dragon")

	if _attack_cooldown <= 0.0:
		_perform_phase_attack(target)
	elif _warning != null:
		_warning.visible = _attack_cooldown < 0.65
		_warning.scale = Vector3.ONE * (1.0 + sin(_time * 14.0) * 0.1)

func _animate_dragon(delta: float) -> void:
	if _visual == null:
		return
	var wing_speed := 7.2 if _flight_time > 0.0 else (4.2 if phase >= 3 else 2.6)
	var wing_amp := 0.58 if _flight_time > 0.0 else 0.32
	if _wing_l != null and _wing_r != null:
		var flap := sin(_time * wing_speed) * wing_amp
		# Dynamic wing banking and feathering
		_wing_l.rotation.z = -0.18 + flap
		_wing_l.rotation.x = sin(_time * wing_speed * 0.5) * 0.12
		_wing_r.rotation.z = 0.18 - flap
		_wing_r.rotation.x = sin(_time * wing_speed * 0.5) * 0.12

	if _flight_time > 0.0:
		_flight_time = maxf(0.0, _flight_time - delta)
		_visual.position.y = lerpf(_visual.position.y, 2.45, delta * 5.5)
	else:
		_visual.position.y = lerpf(_visual.position.y, sin(_time * 2.2) * 0.14, delta * 6.0)

	# Dragon four-legged stalking gait
	if _legs.size() == 4 and _flight_time <= 0.0:
		var walk_speed := 5.5 if phase >= 3 else 3.8
		var step_amp := 0.24
		var p1 := sin(_time * walk_speed) * step_amp
		var p2 := sin(_time * walk_speed + PI) * step_amp
		_legs[0].rotation.x = p1
		_legs[3].rotation.x = p1
		_legs[1].rotation.x = p2
		_legs[2].rotation.x = p2
	elif _legs.size() == 4:
		# Airborne tucked talons
		for l in _legs:
			l.rotation.x = lerp_angle(l.rotation.x, -0.45, delta * 4.0)

	if _tail_pivot != null:
		if _tail_sweep_time > 0.0:
			_tail_sweep_time = maxf(0.0, _tail_sweep_time - delta)
			_tail_pivot.rotation.y += delta * 15.5
		else:
			_tail_pivot.rotation.y = sin(_time * 2.6) * 0.42
			_tail_pivot.rotation.x = sin(_time * 1.8) * 0.12

	if _neck_pivot != null:
		_neck_pivot.rotation.x = sin(_time * 2.2) * 0.12
		_neck_pivot.rotation.y = sin(_time * 1.4) * 0.08
	if _head_pivot != null:
		# Realistic predatory head tracking
		_head_pivot.rotation.x = -0.12 + sin(_time * 2.8) * 0.08
	if _chest_core != null:
		var pulse := 1.0 + sin(_time * 5.2) * 0.12
		_chest_core.scale = Vector3.ONE * pulse

func _perform_phase_attack(target: Node3D) -> void:
	_attack_cooldown = 2.8 if phase == 1 else (2.2 if phase == 2 else (1.75 if phase == 3 else 1.35))
	_recover_time = 0.55
	if _warning != null:
		_warning.visible = false
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		audio.play("res://sounds/land.ogg")

	var dist := global_position.distance_to(target.global_position)

	if phase == 1:
		# Phase 1 - The Volcanic Guardian: tail sweep + wing gust + controlled fire energy
		_tail_sweep_time = 0.45
		_launch_fire_volley(target, 1)
		if dist < 5.8 and target.has_method("take_damage"):
			target.call("take_damage", 8.0, global_position, "ember_dragon")
	elif phase == 2:
		# Phase 2 - Rising Inferno: brief flight + fire projectiles + lava hazard + landing shockwave
		_flight_time = 0.85
		_spawn_lava_hazard(target.global_position)
		_launch_fire_volley(target, 2)
		_spawn_shockwave_ring()
		if dist < 8.5 and target.has_method("take_damage"):
			target.call("take_damage", 9.0, global_position, "ember_dragon")
	elif phase == 3:
		# Phase 3 - Molten Fury: faster movement, glowing magma formations, forward charge + tail sweep
		_tail_sweep_time = 0.5
		_spawn_lava_hazard(target.global_position)
		var flat := Vector3(target.global_position.x - global_position.x, 0.0, target.global_position.z - global_position.z)
		_charge_dir = flat.normalized() if flat.length_squared() > 0.01 else Vector3.FORWARD
		_charge_time = 0.35
		_launch_fire_volley(target, 2)
		if dist < 10.0 and target.has_method("take_damage"):
			target.call("take_damage", 11.0, global_position, "ember_dragon")
	else:
		# Final Phase 4 - Dragon's Awakening: aerial + ground combo + multiple hazards + shockwave
		_flight_time = 0.65
		_tail_sweep_time = 0.55
		_spawn_lava_hazard(target.global_position)
		_spawn_lava_hazard(target.global_position + Vector3(1.8, 0.0, -1.2))
		_launch_fire_volley(target, 3)
		_spawn_shockwave_ring()
		if dist < 12.0 and target.has_method("take_damage"):
			target.call("take_damage", 13.0, global_position, "ember_dragon")

func _launch_fire_volley(target: Node3D, count: int) -> void:
	if get_parent() == null or not is_instance_valid(target):
		return
	for i in count:
		var proj: FireProjectile = FIRE_PROJECTILE.new()
		proj.damage = 7.0
		proj.speed = 8.2
		proj.source_name = "ember_dragon"
		get_parent().add_child(proj)
		var spread := float(i - (count - 1) * 0.5) * 0.85
		proj.global_position = global_position + Vector3(spread, 1.8, 0.0)
		proj.launch(target)

func _spawn_lava_hazard(at: Vector3) -> void:
	if get_parent() == null:
		return
	var hazard := Area3D.new()
	hazard.name = "EmberDragonLavaHazard"
	hazard.add_to_group("ember_dragon_hazards")
	hazard.collision_layer = 0
	hazard.collision_mask = 1
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.95
	shape.shape = sphere
	hazard.add_child(shape)

	var visual := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.85
	cyl.bottom_radius = 0.98
	cyl.height = 0.22
	visual.mesh = cyl
	visual.material_override = _crack_mat
	hazard.add_child(visual)

	var spike := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.42
	cone.height = 1.25
	spike.mesh = cone
	spike.position.y = 0.6
	spike.material_override = _crack_mat
	hazard.add_child(spike)

	hazard.body_entered.connect(func(body: Node3D):
		if body.has_method("take_damage"):
			body.call("take_damage", 6.0, hazard.global_position, "ember_hazard")
	)
	get_parent().add_child(hazard)
	hazard.global_position = at
	get_tree().create_timer(3.2).timeout.connect(func():
		if is_instance_valid(hazard):
			hazard.queue_free()
	)

func _spawn_shockwave_ring() -> void:
	if get_parent() == null:
		return
	var ring := MeshInstance3D.new()
	ring.name = "DragonShockwave"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.05
	ring.mesh = torus
	ring.material_override = _eye_mat
	get_parent().add_child(ring)
	ring.global_position = global_position + Vector3(0.0, 0.2, 0.0)
	var tween := ring.create_tween()
	tween.tween_property(ring, "scale", Vector3(5.2, 1.0, 5.2), 0.55)
	tween.tween_callback(ring.queue_free)

func reset_to_home() -> void:
	if _dead:
		return
	global_position = _home
	_charge_time = 0.0
	_flight_time = 0.0
	_recover_time = 0.0
	if _warning != null:
		_warning.visible = false

func take_hit(amount: int, _from: Vector3) -> bool:
	if _dead or locked:
		return false
	health -= amount
	phase = 1 if health > max_health * 0.75 else (2 if health > max_health * 0.50 else (3 if health > max_health * 0.25 else 4))
	health_changed.emit(maxi(health, 0), max_health, phase)
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		audio.play("res://sounds/land.ogg")
	if health <= 0:
		_dead = true
		defeated.emit()
		if audio != null:
			audio.play("res://sounds/break.ogg")
		_dissolve_into_embers()
	return true

func _dissolve_into_embers() -> void:
	if get_parent() != null:
		var burst := GPUParticles3D.new()
		burst.amount = 36
		burst.lifetime = 1.1
		burst.one_shot = true
		burst.explosiveness = 1.0
		var quad := QuadMesh.new()
		quad.size = Vector2(0.22, 0.22)
		quad.material = _eye_mat
		burst.draw_pass_1 = quad
		var proc := ParticleProcessMaterial.new()
		proc.direction = Vector3(0.0, 1.0, 0.0)
		proc.spread = 180.0
		proc.initial_velocity_min = 1.8
		proc.initial_velocity_max = 4.5
		proc.gravity = Vector3(0.0, -1.8, 0.0)
		burst.process_material = proc
		burst.position = position + Vector3(0.0, 1.5, 0.0)
		get_parent().add_child(burst)
		burst.emitting = true
	var tween := create_tween()
	if _visual != null:
		tween.tween_property(_visual, "scale", Vector3.ZERO, 0.7)
	tween.tween_callback(queue_free)
