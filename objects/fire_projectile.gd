extends Area3D
class_name FireProjectile

## Dodgeable magical fire-energy projectile launched by Lava Phantoms and the Ember Dragon.

@export var speed: float = 7.5
@export var damage: float = 6.0
@export var source_name: String = "lava_phantom"

var target: Node3D
var _direction: Vector3 = Vector3.FORWARD
var _life: float = 4.2
var _time: float = 0.0
var _core: MeshInstance3D
var _ring: MeshInstance3D

func _init() -> void:
	collision_layer = 0
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.24
	shape.shape = sphere
	add_child(shape)

func _ready() -> void:

	_core = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.22
	mesh.height = 0.44
	_core.mesh = mesh
	_core.material_override = _fire_material(Color("#ff5a1f"), Color("#ff9824"), 2.4)
	add_child(_core)

	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.24
	torus.outer_radius = 0.31
	_ring.mesh = torus
	_ring.material_override = _fire_material(Color("#ffd23f"), Color("#ff6a18"), 2.0)
	add_child(_ring)

	body_entered.connect(_on_body_entered)

func launch(destination: Node3D) -> void:
	target = destination
	if is_instance_valid(target):
		var offset := (target.global_position + Vector3(0.0, 0.5, 0.0)) - global_position
		if offset.length_squared() > 0.001:
			_direction = offset.normalized()

func launch_at_point(point: Vector3) -> void:
	var offset := point - global_position
	if offset.length_squared() > 0.001:
		_direction = offset.normalized()

func _physics_process(delta: float) -> void:
	_life -= delta
	_time += delta
	if _life <= 0.0:
		queue_free()
		return
	if _ring != null:
		_ring.rotate_x(delta * 6.0)
		_ring.rotate_z(delta * 4.5)
	if is_instance_valid(target):
		var desired := (target.global_position + Vector3(0.0, 0.45, 0.0)) - global_position
		if desired.length() < 0.42:
			if target.has_method("take_damage"):
				target.call("take_damage", damage, global_position, source_name)
			queue_free()
			return
		# Subtle tracking early in flight, dodgeable by moving or jumping
		if _time < 0.65 and desired.length_squared() > 0.01:
			_direction = _direction.lerp(desired.normalized(), delta * 2.2).normalized()
	global_position += _direction * speed * delta

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("take_damage"):
		body.call("take_damage", damage, global_position, source_name)
	queue_free()

func _fire_material(albedo: Color, emit: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.emission_enabled = true
	mat.emission = emit
	mat.emission_energy_multiplier = energy
	mat.roughness = 0.25
	return mat
