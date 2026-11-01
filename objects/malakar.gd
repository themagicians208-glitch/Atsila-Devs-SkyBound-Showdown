extends Node3D
class_name Malakar

const SHADOW_BOLT := preload("res://objects/shadow_bolt.gd")

## Malakar, the Shadow King: a towering mirror-dimension boss assembled entirely
## from primitive meshes. Deep-purple robe, gold-trimmed cape, near-black
## shadowed face, a seven-spike gold crown with matching shoulder spikes, and a
## long staff whose magenta crystal pulses and can project a flickering beam.

@export var hover_amplitude := 0.18
@export var hover_speed := 0.9
@export var crystal_pulse_speed := 3.2
@export var lethal := true
@export var attacks_enabled := true
@export var attack_interval := 2.4
@export var attack_range := 22.0

const PURPLE_DEEP := Color("#3a1666")
const PURPLE_DARK := Color("#241040")
const PURPLE_CAPE := Color("#2a0f52")
const GOLD := Color("#f6c945")
const GOLD_DARK := Color("#b8860b")
const FACE_BLACK := Color("#0b0614")
const MAGENTA := Color("#ff2fd0")

var _crystal: MeshInstance3D
var _crystal_material: StandardMaterial3D
var _crystal_light: OmniLight3D
var _beam: MeshInstance3D
var _beam_material: StandardMaterial3D
var _beam_target: Node3D
var _crystal_offset := Vector3(0.95, 5.1, 0.0)
var _crystal_core: MeshInstance3D
var _shard_pivot: Node3D
var _mote_pivot: Node3D
var _rune_outer: MeshInstance3D
var _rune_inner: MeshInstance3D
var _beam_pulse: MeshInstance3D
var _circle: Node3D
var _circle_inner: Node3D
var _arc_material: StandardMaterial3D
var _attack_timer := 2.0
var _time := 0.0
var _base_y := 0.0
var _base_rot_y := 0.0
var _built := false


func _ready() -> void:
	_base_y = position.y
	_base_rot_y = rotation.y
	_build()


## Point the staff crystal's beam at a node (for example the great tree canopy).
func configure(beam_target: Node3D) -> void:
	_beam_target = beam_target
	if _beam != null:
		_beam.visible = is_instance_valid(beam_target)


func _process(delta: float) -> void:
	_time += delta
	# Slow, ominous hover with a gentle sway.
	position.y = _base_y + sin(_time * hover_speed) * hover_amplitude
	rotation.y = _base_rot_y + sin(_time * 0.35) * 0.07

	var pulse := 0.5 + 0.5 * sin(_time * crystal_pulse_speed)
	if _crystal_material != null:
		_crystal_material.emission_energy_multiplier = 0.8 + pulse * 1.0
	if _crystal != null:
		var s := 1.0 + pulse * 0.14
		_crystal.scale = Vector3(s, s, s)
	if _crystal_light != null:
		_crystal_light.light_energy = 0.9 + pulse * 1.0
	if _crystal_core != null:
		_crystal_core.rotation.y += delta * 1.6
	if _shard_pivot != null:
		_shard_pivot.rotation.y += delta * 1.2
		_shard_pivot.rotation.x = sin(_time * 0.7) * 0.25
	if _mote_pivot != null:
		_mote_pivot.rotation.y -= delta * 0.8
		_mote_pivot.position.y = 2.3 + sin(_time * 0.6) * 0.15
	if _rune_outer != null:
		_rune_outer.rotation.y += delta * 0.6
	if _rune_inner != null:
		_rune_inner.rotation.y -= delta * 0.9
	if _circle != null:
		_circle.rotation.y += delta * 0.5
	if _circle_inner != null:
		_circle_inner.rotation.y -= delta * 0.8
	if _arc_material != null:
		_arc_material.emission_energy_multiplier = 0.8 + 0.9 * absf(sin(_time * 6.0))
	_update_beam(pulse)
	_update_attacks(delta)


func _update_beam(pulse: float) -> void:
	if _beam == null or not is_instance_valid(_beam_target):
		if _beam != null:
			_beam.visible = false
		if _beam_pulse != null:
			_beam_pulse.visible = false
		return
	var from: Vector3 = _crystal.global_position
	var to: Vector3 = _beam_target.global_position
	var direction := to - from
	var distance := direction.length()
	if distance < 0.05:
		_beam.visible = false
		if _beam_pulse != null:
			_beam_pulse.visible = false
		return
	_beam.visible = true
	var y_axis := direction / distance
	var x_axis := y_axis.cross(Vector3.UP)
	if x_axis.length() < 0.001:
		x_axis = y_axis.cross(Vector3.FORWARD)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	var flicker := 0.45 + 0.35 * absf(sin(_time * 9.0)) + pulse * 0.2
	var width := 0.6 + 0.4 * flicker
	_beam.global_transform = Transform3D(Basis(x_axis * width, y_axis * distance, z_axis * width), (from + to) * 0.5)
	if _beam_pulse != null:
		var travel := fmod(_time * 0.9, 1.0)
		_beam_pulse.global_position = from.lerp(to, travel)
		var pulse_scale := 0.7 + 0.5 * sin(_time * 14.0)
		_beam_pulse.scale = Vector3(pulse_scale, pulse_scale, pulse_scale)
		_beam_pulse.visible = true
	if _beam_material != null:
		_beam_material.albedo_color.a = clampf(flicker * 0.45, 0.12, 0.42)
		_beam_material.emission_energy_multiplier = 0.8 + flicker * 0.7


func _build() -> void:
	if _built:
		return
	_built = true

	# --- Robe -----------------------------------------------------------------
	var robe_mesh := CylinderMesh.new()
	robe_mesh.bottom_radius = 0.9
	robe_mesh.top_radius = 0.52
	robe_mesh.height = 2.5
	_add_mesh(robe_mesh, _mat(PURPLE_DEEP), Vector3(0, 1.3, 0), "Robe")

	var hem_mesh := CylinderMesh.new()
	hem_mesh.bottom_radius = 1.0
	hem_mesh.top_radius = 0.9
	hem_mesh.height = 0.45
	_add_mesh(hem_mesh, _mat(PURPLE_DARK), Vector3(0, 0.22, 0), "RobeHem")

	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(0.95, 0.8, 0.6)
	_add_mesh(torso_mesh, _mat(PURPLE_DEEP), Vector3(0, 2.65, 0), "Torso")

	var emblem_mesh := CylinderMesh.new()
	emblem_mesh.top_radius = 0.15
	emblem_mesh.bottom_radius = 0.15
	emblem_mesh.height = 0.08
	var emblem := _add_mesh(emblem_mesh, _mat(GOLD, true), Vector3(0, 2.68, 0.31), "Emblem")
	emblem.rotation = Vector3(PI / 2.0, 0, 0)

	# --- Shoulders ------------------------------------------------------------
	var shoulder_mesh := BoxMesh.new()
	shoulder_mesh.size = Vector3(1.5, 0.34, 0.64)
	_add_mesh(shoulder_mesh, _mat(PURPLE_DARK), Vector3(0, 3.0, 0), "Shoulders")

	# Matching spikes: two per shoulder, gold.
	var spike_index := 0
	for side in [-1.0, 1.0]:
		for step in range(2):
			var spike_mesh := CylinderMesh.new()
			spike_mesh.bottom_radius = 0.1
			spike_mesh.top_radius = 0.0
			spike_mesh.height = 0.52
			_add_mesh(spike_mesh, _mat(GOLD, true), Vector3(side * (0.5 + 0.24 * float(step)), 3.42, 0.0), "ShoulderSpike_%02d" % spike_index)
			spike_index += 1

	# --- Cape with gold trim --------------------------------------------------
	var cape_mesh := BoxMesh.new()
	cape_mesh.size = Vector3(1.9, 3.0, 0.12)
	var cape := _add_mesh(cape_mesh, _mat(PURPLE_CAPE), Vector3(0, 1.7, -0.44), "Cape")
	cape.rotation = Vector3(0.14, 0, 0)
	var trim_index := 0
	for side in [-1.0, 1.0]:
		var trim_mesh := BoxMesh.new()
		trim_mesh.size = Vector3(0.1, 3.0, 0.15)
		var trim := _add_mesh(trim_mesh, _mat(GOLD, true), Vector3(side * 0.9, 1.7, -0.44), "CapeTrim_%02d" % trim_index)
		trim.rotation = Vector3(0.14, 0, 0)
		trim_index += 1
	var hem_trim_mesh := BoxMesh.new()
	hem_trim_mesh.size = Vector3(1.9, 0.12, 0.15)
	var hem_trim := _add_mesh(hem_trim_mesh, _mat(GOLD, true), Vector3(0, 0.24, -0.44), "CapeHemTrim")
	hem_trim.rotation = Vector3(0.14, 0, 0)

	# --- Arms -----------------------------------------------------------------
	var left_arm_mesh := CylinderMesh.new()
	left_arm_mesh.top_radius = 0.12
	left_arm_mesh.bottom_radius = 0.12
	left_arm_mesh.height = 1.25
	var left_arm := _add_mesh(left_arm_mesh, _mat(PURPLE_DEEP), Vector3(-0.62, 2.4, 0.05), "LeftArm")
	left_arm.rotation = Vector3(0, 0, deg_to_rad(9.0))
	var right_arm_mesh := CylinderMesh.new()
	right_arm_mesh.top_radius = 0.12
	right_arm_mesh.bottom_radius = 0.12
	right_arm_mesh.height = 1.15
	var right_arm := _add_mesh(right_arm_mesh, _mat(PURPLE_DEEP), Vector3(0.66, 2.45, 0.05), "RightArm")
	right_arm.rotation = Vector3(0, 0, deg_to_rad(-24.0))

	# --- Head and hood --------------------------------------------------------
	var hood_mesh := SphereMesh.new()
	hood_mesh.radius = 0.42
	hood_mesh.height = 0.84
	_add_mesh(hood_mesh, _mat(PURPLE_DARK), Vector3(0, 3.32, -0.06), "Hood")
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.32
	head_mesh.height = 0.64
	_add_mesh(head_mesh, _mat(FACE_BLACK), Vector3(0, 3.26, 0.05), "Head")

	# --- Crown of seven spikes ------------------------------------------------
	var band_mesh := CylinderMesh.new()
	band_mesh.bottom_radius = 0.37
	band_mesh.top_radius = 0.37
	band_mesh.height = 0.16
	_add_mesh(band_mesh, _mat(GOLD, true), Vector3(0, 3.6, 0), "CrownBand")
	for i in range(7):
		var angle := TAU * float(i) / 7.0
		var spike_mesh := CylinderMesh.new()
		spike_mesh.bottom_radius = 0.1
		spike_mesh.top_radius = 0.0
		spike_mesh.height = 0.82
		_add_mesh(spike_mesh, _mat(GOLD, true), Vector3(sin(angle) * 0.3, 4.11, cos(angle) * 0.3), "CrownSpike_%02d" % i)

	# --- Staff and crystal ----------------------------------------------------
	var staff_mesh := CylinderMesh.new()
	staff_mesh.top_radius = 0.07
	staff_mesh.bottom_radius = 0.07
	staff_mesh.height = 5.2
	_add_mesh(staff_mesh, _mat(GOLD_DARK), Vector3(0.95, 2.7, 0), "Staff")
	var ring_index := 0
	for ring_y in [0.7, 4.5]:
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 0.09
		ring_mesh.outer_radius = 0.15
		_add_mesh(ring_mesh, _mat(GOLD, true), Vector3(0.95, float(ring_y), 0), "StaffRing_%02d" % ring_index)
		ring_index += 1

	_crystal_material = _mat(MAGENTA, true)
	var crystal_mesh := SphereMesh.new()
	crystal_mesh.radius = 0.3
	crystal_mesh.height = 0.6
	_crystal = _add_mesh(crystal_mesh, _crystal_material, _crystal_offset, "Crystal")

	_crystal_light = OmniLight3D.new()
	_crystal_light.name = "CrystalLight"
	_crystal_light.light_color = MAGENTA
	_crystal_light.light_energy = 1.1
	_crystal_light.omni_range = 6.0
	_crystal_light.position = _crystal_offset
	add_child(_crystal_light)

	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.05
	beam_mesh.bottom_radius = 0.05
	beam_mesh.height = 1.0
	_beam_material = _mat(Color(1.0, 0.35, 0.9, 0.7), true)
	_beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam = MeshInstance3D.new()
	_beam.name = "StaffBeam"
	_beam.mesh = beam_mesh
	_beam.material_override = _beam_material
	_beam.visible = false
	add_child(_beam)
	_build_ornaments()
	_build_energy()
	_build_ornaments_extra()
	_build_effects_extra()

	# --- Menacing contact hazard ---------------------------------------------
	if lethal:
		var hitbox := Area3D.new()
		hitbox.name = "BossHitbox"
		hitbox.collision_layer = 0
		hitbox.collision_mask = 1
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.95
		capsule.height = 4.2
		shape.shape = capsule
		shape.position.y = 2.1
		hitbox.add_child(shape)
		hitbox.body_entered.connect(_on_body_entered)
		add_child(hitbox)


func _add_mesh(mesh: Mesh, material: Material, mesh_position: Vector3, node_name: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	node.position = mesh_position
	add_child(node)
	return node


func _mat(color: Color, emissive: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.5
	material.metallic = 0.2
	if emissive:
		material.emission_enabled = true
		material.emission = Color(color.r, color.g, color.b)
		material.emission_energy_multiplier = 1.1
	return material


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("die"):
		body.call("die")


# --- Boss fight: staff bolts -------------------------------------------------

func _update_attacks(delta: float) -> void:
	if not attacks_enabled:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player):
		return
	if global_position.distance_to(player.global_position) > attack_range:
		return
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_attack_timer = attack_interval
		_fire_bolt(player)


func _fire_bolt(player: Node3D) -> void:
	var host := get_parent()
	if host == null:
		return
	var bolt := Area3D.new()
	bolt.name = "ShadowBolt"
	bolt.set_script(SHADOW_BOLT)
	bolt.collision_layer = 0
	bolt.collision_mask = 1
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.32
	shape.shape = sphere
	bolt.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bolt_sphere := SphereMesh.new()
	bolt_sphere.radius = 0.2
	bolt_sphere.height = 0.4
	mesh.mesh = bolt_sphere
	mesh.material_override = _mat(MAGENTA, true)
	bolt.add_child(mesh)
	host.add_child(bolt)
	bolt.global_position = _crystal.global_position
	var aim: Vector3 = player.global_position + Vector3(0, 0.9, 0) - _crystal.global_position
	bolt.set("direction", aim.normalized())
	bolt.set("speed", 13.0)


# --- Jeweled ornaments -------------------------------------------------------

func _build_ornaments() -> void:
	# A front gem and a burning tip on every crown spike.
	_add_mesh(_sphere(0.09), _mat(MAGENTA, true), Vector3(0, 3.6, 0.38), "CrownGem")
	for i in range(7):
		var angle := TAU * float(i) / 7.0
		_add_mesh(_sphere(0.06), _mat(Color("#ff7ae6"), true), Vector3(sin(angle) * 0.3, 4.53, cos(angle) * 0.3), "CrownTip_%02d" % i)

	# Glowing eyes beneath the hood.
	var eye_index := 0
	for side in [-1.0, 1.0]:
		_add_mesh(_sphere(0.05), _mat(Color("#ff7ae6"), true), Vector3(side * 0.12, 3.32, 0.34), "Eye_%02d" % eye_index)
		eye_index += 1

	# Waist belt with a jewel.
	var belt := _add_mesh(_torus(0.5, 0.62), _mat(GOLD, true), Vector3(0, 2.24, 0), "Belt")
	belt.rotation = Vector3(PI / 2.0, 0, 0)
	_add_mesh(_sphere(0.13), _mat(MAGENTA, true), Vector3(0, 2.24, 0.54), "BeltGem")

	# Layered chest plate with a jewel.
	_add_mesh(_box(Vector3(0.82, 0.52, 0.14)), _mat(GOLD_DARK), Vector3(0, 2.72, 0.34), "ChestPlate")
	_add_mesh(_sphere(0.15), _mat(MAGENTA, true), Vector3(0, 2.72, 0.44), "ChestGem")

	# Gold filigree running down the robe front.
	for i in range(4):
		var x := -0.3 + 0.2 * float(i)
		_add_mesh(_box(Vector3(0.05, 1.9, 0.05)), _mat(GOLD, true), Vector3(x, 1.35, 0.66 - absf(x) * 0.35), "RobeFiligree_%02d" % i)

	var hem_ring := _add_mesh(_torus(0.9, 1.06), _mat(GOLD, true), Vector3(0, 0.44, 0), "RobeHemGold")
	hem_ring.rotation = Vector3(PI / 2.0, 0, 0)

	# A glowing magenta edge down each side of the cape.
	for side in [-1.0, 1.0]:
		var strip := _add_mesh(_box(Vector3(0.05, 2.9, 0.04)), _mat(MAGENTA, true), Vector3(side * 0.82, 1.7, -0.5), "CapeGlow_%s" % ("L" if side < 0.0 else "R"))
		strip.rotation = Vector3(0.14, 0, 0)

	# Gold clasps where the cape meets the shoulders.
	var clasp_index := 0
	for side in [-1.0, 1.0]:
		_add_mesh(_sphere(0.11), _mat(GOLD, true), Vector3(side * 0.5, 3.2, -0.34), "CapeClasp_%02d" % clasp_index)
		clasp_index += 1


# --- Energy effects ----------------------------------------------------------

func _build_energy() -> void:
	# Faceted inner core that counter-rotates inside the staff crystal.
	var core_mesh := PrismMesh.new()
	core_mesh.size = Vector3(0.34, 0.52, 0.34)
	_crystal_core = MeshInstance3D.new()
	_crystal_core.name = "CrystalCore"
	_crystal_core.mesh = core_mesh
	_crystal_core.material_override = _mat(Color("#ff7ae6"), true)
	_crystal.add_child(_crystal_core)

	# Orbiting crystal shards.
	_shard_pivot = Node3D.new()
	_shard_pivot.name = "ShardPivot"
	_crystal.add_child(_shard_pivot)
	for i in range(3):
		var angle := TAU * float(i) / 3.0
		var shard := MeshInstance3D.new()
		shard.name = "Shard_%02d" % i
		var shard_mesh := PrismMesh.new()
		shard_mesh.size = Vector3(0.13, 0.3, 0.13)
		shard.mesh = shard_mesh
		shard.material_override = _mat(Color("#ff7ae6"), true)
		shard.position = Vector3(cos(angle) * 0.52, sin(angle * 2.0) * 0.14, sin(angle) * 0.52)
		_shard_pivot.add_child(shard)

	# Soft additive halo wrapped around the beam core.
	var halo_mesh := CylinderMesh.new()
	halo_mesh.top_radius = 0.05
	halo_mesh.bottom_radius = 0.05
	halo_mesh.height = 1.0
	var halo_material := StandardMaterial3D.new()
	halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	halo_material.albedo_color = Color(1.0, 0.4, 0.9, 0.15)
	var halo := MeshInstance3D.new()
	halo.name = "BeamHalo"
	halo.mesh = halo_mesh
	halo.material_override = halo_material
	halo.scale = Vector3(2.8, 1.0, 2.8)
	_beam.add_child(halo)

	# Levitation rune rings beneath the hovering figure.
	_rune_outer = _add_mesh(_torus(0.9, 1.02), _mat(MAGENTA, true), Vector3(0, -0.2, 0), "RuneOuter")
	_rune_outer.rotation = Vector3(PI / 2.0, 0, 0)
	_rune_inner = _add_mesh(_torus(0.55, 0.64), _mat(Color("#ff7ae6"), true), Vector3(0, -0.08, 0), "RuneInner")
	_rune_inner.rotation = Vector3(PI / 2.0, 0, 0)

	# Orbiting energy motes around the torso.
	_mote_pivot = Node3D.new()
	_mote_pivot.name = "MotePivot"
	_mote_pivot.position = Vector3(0, 2.3, 0)
	add_child(_mote_pivot)
	for i in range(8):
		var angle := TAU * float(i) / 8.0
		var mote := MeshInstance3D.new()
		mote.name = "Mote_%02d" % i
		mote.mesh = _sphere(0.07)
		mote.material_override = _mat(Color("#ff7ae6"), true)
		mote.position = Vector3(cos(angle) * 1.3, sin(angle * 3.0) * 0.5, sin(angle) * 1.3)
		mote.rotation = Vector3(angle, angle, 0)
		_mote_pivot.add_child(mote)

	# Rising aura particles.
	var aura := GPUParticles3D.new()
	aura.name = "Aura"
	aura.amount = 36
	aura.lifetime = 2.4
	aura.preprocess = 1.2
	aura.emitting = true
	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_material.emission_sphere_radius = 1.1
	process_material.direction = Vector3(0, 1, 0)
	process_material.spread = 22.0
	process_material.initial_velocity_min = 0.3
	process_material.initial_velocity_max = 0.9
	process_material.gravity = Vector3(0, 0.5, 0)
	process_material.scale_min = 0.4
	process_material.scale_max = 1.2
	process_material.color = Color(1.0, 0.35, 0.9)
	aura.process_material = process_material
	var particle_material := StandardMaterial3D.new()
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	particle_material.albedo_color = Color(1.0, 0.4, 0.9, 0.85)
	particle_material.emission_enabled = true
	particle_material.emission = Color(1.0, 0.35, 0.9)
	var dot := SphereMesh.new()
	dot.radius = 0.06
	dot.height = 0.12
	dot.material = particle_material
	aura.draw_pass_1 = dot
	aura.position = Vector3(0, 2.2, 0)
	add_child(aura)


# --- Small mesh factories ----------------------------------------------------

func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	return mesh


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _torus(inner: float, outer: float) -> TorusMesh:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	return mesh


func _cone(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = 0.0
	mesh.height = height
	return mesh


func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	return mesh


# --- Extra armored ornaments -------------------------------------------------

func _build_ornaments_extra() -> void:
	# Ring of small collar spikes around the neck.
	var collar_index := 0
	for i in range(5):
		var angle := TAU * float(i) / 5.0
		var spike := _add_mesh(_cone(0.07, 0.34), _mat(GOLD, true), Vector3(sin(angle) * 0.46, 3.06, cos(angle) * 0.46), "CollarSpike_%02d" % collar_index)
		spike.rotation = Vector3(cos(angle) * 0.5, 0, -sin(angle) * 0.5)
		collar_index += 1

	# Layered gold bands down the robe.
	var band_radii := [0.74, 0.66, 0.6]
	var band_heights := [0.72, 1.15, 1.6]
	for i in range(band_radii.size()):
		var band_radius: float = band_radii[i]
		var band_height: float = band_heights[i]
		var ring := _add_mesh(_torus(band_radius, band_radius + 0.05), _mat(GOLD, true), Vector3(0, band_height, 0), "RobeBand_%02d" % i)
		ring.rotation = Vector3(PI / 2.0, 0, 0)

	# Gold forearm bracers.
	var left_bracer := _add_mesh(_cylinder(0.17, 0.15, 0.42), _mat(GOLD_DARK), Vector3(-0.72, 2.0, 0.05), "LeftBracer")
	left_bracer.rotation = Vector3(0, 0, deg_to_rad(9.0))
	var right_bracer := _add_mesh(_cylinder(0.17, 0.15, 0.42), _mat(GOLD_DARK), Vector3(0.87, 2.06, 0.05), "RightBracer")
	right_bracer.rotation = Vector3(0, 0, deg_to_rad(-24.0))

	# Chest sigil ring around the jewel.
	var sigil := _add_mesh(_torus(0.18, 0.23), _mat(Color("#ff7ae6"), true), Vector3(0, 2.72, 0.42), "ChestSigil")
	sigil.rotation = Vector3(PI / 2.0, 0, 0)

	# Shoulder cloak scales.
	var scale_index := 0
	for side in [-1.0, 1.0]:
		for step in range(3):
			var scale_node := _add_mesh(_box(Vector3(0.32, 0.34, 0.08)), _mat(PURPLE_CAPE), Vector3(side * (0.5 + 0.3 * float(step)), 2.82 - 0.16 * float(step), -0.22), "CapeScale_%02d" % scale_index)
			scale_node.rotation = Vector3(0.12, 0, 0)
			scale_index += 1

	# Arcs of power bridging the tips of the crown spikes.
	_arc_material = _mat(Color("#ff7ae6"), true)
	for i in range(7):
		var a0 := TAU * float(i) / 7.0
		var a1 := TAU * float(i + 1) / 7.0
		var p0 := Vector3(sin(a0) * 0.3, 4.5, cos(a0) * 0.3)
		var p1 := Vector3(sin(a1) * 0.3, 4.5, cos(a1) * 0.3)
		var chord := p1 - p0
		var arc := MeshInstance3D.new()
		arc.name = "CrownArc_%02d" % i
		arc.mesh = _box(Vector3(0.04, 0.04, chord.length()))
		arc.material_override = _arc_material
		arc.position = (p0 + p1) * 0.5
		arc.rotation = Vector3(0, atan2(chord.x, chord.z), 0)
		add_child(arc)

	# A violet fill light so the figure reads against the sky.
	var fill := OmniLight3D.new()
	fill.name = "AuraLight"
	fill.light_color = Color("#a64bff")
	fill.light_energy = 1.3
	fill.omni_range = 9.0
	fill.position = Vector3(0, 2.0, 0)
	add_child(fill)


# --- Extra effects -----------------------------------------------------------

func _build_effects_extra() -> void:
	# A bright pulse that travels up the beam toward the tree.
	_beam_pulse = MeshInstance3D.new()
	_beam_pulse.name = "BeamPulse"
	_beam_pulse.mesh = _sphere(0.11)
	_beam_pulse.material_override = _mat(Color("#ff8ae8"), true)
	_beam_pulse.visible = false
	add_child(_beam_pulse)

	# Large rotating levitation circle with spokes and rune gems.
	_circle = Node3D.new()
	_circle.name = "MagicCircle"
	_circle.position = Vector3(0, -1.3, 0)
	add_child(_circle)
	var circle_outer := MeshInstance3D.new()
	circle_outer.name = "CircleOuter"
	circle_outer.mesh = _torus(1.7, 1.8)
	circle_outer.material_override = _mat(MAGENTA, true)
	circle_outer.rotation = Vector3(PI / 2.0, 0, 0)
	_circle.add_child(circle_outer)
	var circle_inner := MeshInstance3D.new()
	circle_inner.name = "CircleInner"
	circle_inner.mesh = _torus(1.05, 1.13)
	circle_inner.material_override = _mat(Color("#ff7ae6"), true)
	circle_inner.rotation = Vector3(PI / 2.0, 0, 0)
	_circle.add_child(circle_inner)
	for i in range(8):
		var angle := TAU * float(i) / 8.0
		var spoke := MeshInstance3D.new()
		spoke.name = "Spoke_%02d" % i
		spoke.mesh = _box(Vector3(0.05, 0.04, 1.4))
		spoke.material_override = _mat(MAGENTA, true)
		spoke.rotation = Vector3(0, angle, 0)
		_circle.add_child(spoke)
		var gem := MeshInstance3D.new()
		gem.name = "RuneGem_%02d" % i
		gem.mesh = _sphere(0.09)
		gem.material_override = _mat(Color("#ff7ae6"), true)
		gem.position = Vector3(sin(angle) * 1.75, 0.0, cos(angle) * 1.75)
		_circle.add_child(gem)

	# Counter-rotating inner sigil of spikes.
	_circle_inner = Node3D.new()
	_circle_inner.name = "MagicCircleInner"
	_circle_inner.position = Vector3(0, -1.1, 0)
	add_child(_circle_inner)
	for i in range(6):
		var angle := TAU * float(i) / 6.0
		var spike := MeshInstance3D.new()
		spike.name = "InnerSpike_%02d" % i
		spike.mesh = _cone(0.08, 0.4)
		spike.material_override = _mat(MAGENTA, true)
		spike.position = Vector3(sin(angle) * 0.8, 0, cos(angle) * 0.8)
		spike.rotation = Vector3(cos(angle) * 0.6, 0, -sin(angle) * 0.6)
		_circle_inner.add_child(spike)

	# Swirling veil of energy around the robe.
	var veil := GPUParticles3D.new()
	veil.name = "Veil"
	veil.amount = 28
	veil.lifetime = 3.0
	veil.preprocess = 1.5
	veil.emitting = true
	var veil_process := ParticleProcessMaterial.new()
	veil_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	veil_process.emission_sphere_radius = 1.4
	veil_process.direction = Vector3(0, 0, 1)
	veil_process.spread = 40.0
	veil_process.initial_velocity_min = 0.0
	veil_process.initial_velocity_max = 0.3
	veil_process.gravity = Vector3(0, -0.2, 0)
	veil_process.tangential_accel_min = 2.0
	veil_process.tangential_accel_max = 4.0
	veil_process.scale_min = 0.5
	veil_process.scale_max = 1.0
	veil_process.color = Color(0.7, 0.3, 1.0, 0.8)
	veil.process_material = veil_process
	var veil_material := StandardMaterial3D.new()
	veil_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	veil_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	veil_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	veil_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	veil_material.albedo_color = Color(0.7, 0.35, 1.0, 0.3)
	veil_material.emission_enabled = true
	veil_material.emission = Color(0.6, 0.25, 1.0)
	var veil_dot := SphereMesh.new()
	veil_dot.radius = 0.09
	veil_dot.height = 0.18
	veil_dot.material = veil_material
	veil.draw_pass_1 = veil_dot
	veil.position = Vector3(0, 1.4, 0)
	add_child(veil)

	# Rising embers around the whole figure.
	var embers := GPUParticles3D.new()
	embers.name = "Embers"
	embers.amount = 28
	embers.lifetime = 3.4
	embers.preprocess = 1.5
	embers.emitting = true
	var ember_process := ParticleProcessMaterial.new()
	ember_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	ember_process.emission_sphere_radius = 1.6
	ember_process.direction = Vector3(0, 1, 0)
	ember_process.spread = 30.0
	ember_process.initial_velocity_min = 0.5
	ember_process.initial_velocity_max = 1.4
	ember_process.gravity = Vector3(0, 0.2, 0)
	ember_process.scale_min = 0.2
	ember_process.scale_max = 0.6
	ember_process.color = Color(1.0, 0.6, 0.95)
	embers.process_material = ember_process
	var ember_material := StandardMaterial3D.new()
	ember_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ember_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ember_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	ember_material.albedo_color = Color(1.0, 0.7, 0.98, 0.6)
	ember_material.emission_enabled = true
	ember_material.emission = Color(1.0, 0.6, 0.95)
	var ember_dot := SphereMesh.new()
	ember_dot.radius = 0.05
	ember_dot.height = 0.1
	ember_dot.material = ember_material
	embers.draw_pass_1 = ember_dot
	embers.position = Vector3(0, 0.5, 0)
	add_child(embers)

	# Sparkles crackling around the staff crystal.
	var sparkles := GPUParticles3D.new()
	sparkles.name = "CrystalSparkles"
	sparkles.amount = 18
	sparkles.lifetime = 1.6
	sparkles.preprocess = 0.8
	sparkles.emitting = true
	var sparkle_process := ParticleProcessMaterial.new()
	sparkle_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	sparkle_process.emission_sphere_radius = 0.35
	sparkle_process.direction = Vector3(0, 1, 0)
	sparkle_process.spread = 60.0
	sparkle_process.initial_velocity_min = 0.2
	sparkle_process.initial_velocity_max = 0.7
	sparkle_process.gravity = Vector3(0, 0.3, 0)
	sparkle_process.scale_min = 0.15
	sparkle_process.scale_max = 0.45
	sparkle_process.color = Color(1.0, 0.5, 0.95)
	sparkles.process_material = sparkle_process
	var sparkle_material := StandardMaterial3D.new()
	sparkle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sparkle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sparkle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sparkle_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sparkle_material.albedo_color = Color(1.0, 0.6, 1.0, 0.7)
	sparkle_material.emission_enabled = true
	sparkle_material.emission = Color(1.0, 0.5, 0.95)
	var sparkle_dot := SphereMesh.new()
	sparkle_dot.radius = 0.045
	sparkle_dot.height = 0.09
	sparkle_dot.material = sparkle_material
	sparkles.draw_pass_1 = sparkle_dot
	sparkles.position = _crystal_offset
	add_child(sparkles)