extends Area3D
class_name EmberFragmentChest

## The Ancient Magma Chest inside the Ember Dragon's volcanic temple.
## Holds the Fourth Fragment of the Eternal Tree and triggers the discovery
## of Malakar's Fortress projection.

signal fragment_recovered
signal fortress_discovered

var unlocked: bool = false
var opened: bool = false
var magma_cooled: bool = false

var _lid: MeshInstance3D
var _fragment: MeshInstance3D
var _magma_ring: MeshInstance3D
var _magma_mat: StandardMaterial3D
var _projection: Node3D
var _time: float = 0.0

func _init() -> void:
	monitoring = true
	collision_layer = 0
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.0
	shape.shape = sphere
	add_child(shape)

func _ready() -> void:
	_build()

	var prog := get_node_or_null("/root/Progress")
	if prog != null and bool(prog.get("fourth_fragment_recovered")):
		unlocked = true
		opened = true
		magma_cooled = true
		_apply_cooled_magma()
		_lid.rotation.x = deg_to_rad(-65.0)
		_fragment.visible = true
		_fragment.position.y = 1.85
		_fragment.scale = Vector3.ONE * 1.38
		if _projection != null:
			_projection.visible = true

	body_entered.connect(_on_body_entered)

func _build() -> void:
	# Glowing magma ring around the chest that cools into dark volcanic stone upon boss defeat
	_magma_ring = MeshInstance3D.new()
	_magma_ring.name = "MagmaRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 1.15
	torus.outer_radius = 1.45
	_magma_ring.mesh = torus
	_magma_ring.position.y = 0.08
	_magma_mat = _material(Color("#ff4718"), 2.1)
	_magma_ring.material_override = _magma_mat
	add_child(_magma_ring)

	# Chest Base
	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(1.55, 0.72, 1.05)
	base.mesh = base_mesh
	base.position.y = 0.36
	base.material_override = _material(Color("#241b28"), 0.25)
	add_child(base)

	# Chest Lid
	_lid = MeshInstance3D.new()
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(1.62, 0.20, 1.10)
	_lid.mesh = lid_mesh
	_lid.position = Vector3(0.0, 0.82, -0.08)
	_lid.material_override = _material(Color("#ff6a1f"), 1.1)
	add_child(_lid)

	# Fourth Fragment of the Eternal Tree (golden, blue, and green magical energy)
	_fragment = MeshInstance3D.new()
	_fragment.name = "FourthFragment"
	var frag_mesh := SphereMesh.new()
	frag_mesh.radius = 0.26
	frag_mesh.height = 0.52
	_fragment.mesh = frag_mesh
	_fragment.position = Vector3(0.0, 0.95, 0.0)
	_fragment.material_override = _material(Color("#ffe86b"), 2.8)
	_fragment.visible = false
	add_child(_fragment)

	for idx in 2:
		var halo := MeshInstance3D.new()
		var h_torus := TorusMesh.new()
		h_torus.inner_radius = 0.34 + float(idx) * 0.1
		h_torus.outer_radius = 0.39 + float(idx) * 0.1
		halo.mesh = h_torus
		halo.rotation.x = 0.6 if idx == 0 else -0.6
		halo.material_override = _material(Color("#54f4e8") if idx == 0 else Color("#65f6ad"), 2.2)
		_fragment.add_child(halo)

	_build_fortress_projection()

func _build_fortress_projection() -> void:
	# Ancient magical map / energy projection revealing Malakar's Fortress
	_projection = Node3D.new()
	_projection.name = "MalakarFortressProjection"
	_projection.position = Vector3(0.0, 2.35, -1.6)
	_projection.visible = false
	add_child(_projection)

	var map_disc := MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 1.35
	disc_mesh.bottom_radius = 1.35
	disc_mesh.height = 0.06
	map_disc.mesh = disc_mesh
	var disc_mat := _material(Color("#8c4dff"), 1.6)
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_mat.albedo_color = Color(0.55, 0.3, 1.0, 0.45)
	map_disc.material_override = disc_mat
	_projection.add_child(map_disc)

	# Projected miniature dark fortress with huge shadow towers and energy barrier
	var citadel := MeshInstance3D.new()
	var cit_cone := CylinderMesh.new()
	cit_cone.top_radius = 0.22
	cit_cone.bottom_radius = 0.52
	cit_cone.height = 1.3
	citadel.mesh = cit_cone
	citadel.position.y = 0.68
	citadel.material_override = _material(Color("#2a1248"), 1.2)
	_projection.add_child(citadel)

	for i in 4:
		var angle := TAU * float(i) / 4.0
		var tower := MeshInstance3D.new()
		var t_cyl := CylinderMesh.new()
		t_cyl.top_radius = 0.06
		t_cyl.bottom_radius = 0.14
		t_cyl.height = 0.95
		tower.mesh = t_cyl
		tower.position = Vector3(cos(angle) * 0.65, 0.48, sin(angle) * 0.65)
		tower.material_override = _material(Color("#b04dff"), 1.8)
		_projection.add_child(tower)

	var barrier := MeshInstance3D.new()
	var b_sphere := SphereMesh.new()
	b_sphere.radius = 1.05
	b_sphere.height = 2.1
	barrier.mesh = b_sphere
	barrier.position.y = 0.65
	var b_mat := _material(Color("#d94dff"), 1.5)
	b_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	b_mat.albedo_color = Color(0.75, 0.25, 1.0, 0.24)
	barrier.material_override = b_mat
	_projection.add_child(barrier)

func _process(delta: float) -> void:
	_time += delta
	if _fragment != null and _fragment.visible:
		_fragment.rotation.y += delta * 1.8
	if _projection != null and _projection.visible:
		_projection.rotation.y += delta * 0.65
		_projection.position.y = 2.35 + sin(_time * 2.0) * 0.08

func unlock() -> void:
	unlocked = true
	magma_cooled = true
	_apply_cooled_magma()
	if _lid != null:
		_lid.material_override = _material(Color("#ffe266"), 1.8)

func _apply_cooled_magma() -> void:
	if _magma_mat != null:
		_magma_mat.albedo_color = Color("#231f29")
		_magma_mat.emission = Color("#3a2e42")
		_magma_mat.emission_energy_multiplier = 0.2

func _on_body_entered(body: Node3D) -> void:
	if opened or not unlocked or not body.is_in_group("player"):
		return
	opened = true
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		audio.play("res://sounds/coin.ogg")
	var prog := get_node_or_null("/root/Progress")
	if prog != null:
		prog.call("recover_fourth_fragment")
		prog.call("discover_malakar_fortress")

	_fragment.visible = true
	var tween := create_tween()
	tween.tween_property(_lid, "rotation:x", deg_to_rad(-65.0), 0.42)
	tween.parallel().tween_property(_fragment, "position:y", 1.85, 0.65)
	tween.parallel().tween_property(_fragment, "scale", Vector3.ONE * 1.38, 0.65)
	tween.tween_callback(func():
		fragment_recovered.emit()
		if _projection != null:
			_projection.visible = true
			_projection.scale = Vector3.ONE * 0.2
			var ptween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			ptween.tween_property(_projection, "scale", Vector3.ONE, 0.5)
		fortress_discovered.emit()
	)

func _material(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.roughness = 0.3
	return mat
