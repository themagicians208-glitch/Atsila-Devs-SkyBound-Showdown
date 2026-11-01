extends Node3D
class_name FrostTitan

signal defeated
signal health_changed(health: int, maximum: int, phase: int)

@export var max_health := 32
@export var contact_damage := 2.0
@export var locked := true
var health := 32
var phase := 1
var _time := 0.0
var _dead := false
var _visual: Node3D
var _material: StandardMaterial3D
var _attack_cooldown := 2.0
var _attack_flash := 0.0

func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	_build()
	health_changed.emit(health, max_health, phase)

func _build() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color("#bdeeff")
	_material.emission_enabled = true
	_material.emission = Color("#4ecbff") * 0.45
	_material.roughness = 0.2
	var body := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 1.45
	mesh.height = 4.2
	body.mesh = mesh
	body.material_override = _material
	_visual.add_child(body)
	for side in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var arm_mesh := BoxMesh.new()
		arm_mesh.size = Vector3(0.8, 2.5, 0.8)
		arm.mesh = arm_mesh
		arm.material_override = _material
		arm.position = Vector3(side * 1.75, 0.0, 0.0)
		_visual.add_child(arm)
	for i in 6:
		var crystal := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.28
		cone.height = 1.2
		crystal.mesh = cone
		crystal.material_override = _crystal_material()
		crystal.position = Vector3((i % 3 - 1) * 0.7, 1.2 + (i / 3) * 0.7, 0.9)
		crystal.rotation.x = -0.35
		_visual.add_child(crystal)

func _crystal_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#67e8ff")
	material.emission_enabled = true
	material.emission = Color("#67e8ff")
	return material

func _physics_process(delta: float) -> void:
	if _dead:
		return
	if locked:
		return
	_time += delta
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_attack_flash = maxf(0.0, _attack_flash - delta)
	_visual.position.y = sin(_time * 1.4) * 0.08
	_visual.rotation.y += delta * 0.18
	var target := get_tree().get_first_node_in_group("player") as Node3D
	if target == null:
		return
	if global_position.distance_to(target.global_position) < 2.4 and target.has_method("take_damage"):
		target.call("take_damage", contact_damage, global_position, "frost_titan")
	if _attack_cooldown <= 0.0:
		_perform_phase_attack(target)

func _perform_phase_attack(target: Node3D) -> void:
	_attack_cooldown = 3.0 if phase == 1 else (2.2 if phase == 2 else 1.6)
	_attack_flash = 0.3
	Audio.play("res://sounds/land.ogg")
	var distance := global_position.distance_to(target.global_position)
	if phase == 1:
		if distance < 7.0 and target.has_method("take_damage"):
			target.call("take_damage", 10.0, global_position, "frost_titan_shockwave")
	elif phase == 2:
		if distance < 11.0 and target.has_method("take_damage"):
			target.call("take_damage", 7.0, global_position, "frost_titan_crystal_storm")
	else:
		if distance < 13.0 and target.has_method("take_damage"):
			target.call("take_damage", 12.0, global_position, "frost_titan_absolute_frost")

func take_hit(amount: int, from: Vector3) -> bool:
	if _dead or locked:
		return false
	health -= amount
	phase = 1 if health > max_health * 0.7 else (2 if health > max_health * 0.35 else 3)
	health_changed.emit(maxi(health, 0), max_health, phase)
	if health <= 0:
		_dead = true
		defeated.emit()
		queue_free()
	return true

func unlock() -> void:
	locked = false
	health_changed.emit(health, max_health, phase)

