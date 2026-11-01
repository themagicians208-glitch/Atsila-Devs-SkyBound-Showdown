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
	var body := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.55 if variant == "Frost Wolf" else 0.42
	mesh.height = 1.0 if variant == "Frost Wolf" else 0.78
	body.mesh = mesh
	body.material_override = _body_material
	_visual.add_child(body)
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

func _crystal_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#67e8ff")
	material.emission_enabled = true
	material.emission = Color("#67e8ff")
	return material

func _physics_process(delta: float) -> void:
	if _dead:
		return
	_time += delta
	_touch_cooldown = maxf(_touch_cooldown - delta, 0.0)
	_projectile_cooldown = maxf(_projectile_cooldown - delta, 0.0)
	_visual.position.y = sin(_time * 3.0) * 0.1
	_visual.rotation.y += delta * 0.45
	var target := _nearest_player()
	if target == null:
		return
	var offset := target.global_position - global_position
	var distance := offset.length()
	if distance > detect_range:
		return
	if variant == "Crystal Phantom" and _projectile_cooldown <= 0.0:
		_launch_projectile(target)
	var speed := _movement_speed(target)
	if variant == "Crystal Phantom":
		global_position += offset.normalized() * speed * delta
		global_position.y += sin(_time * 2.0) * delta * 0.4
	else:
		var flat := Vector3(offset.x, 0.0, offset.z)
		if flat.length() > 0.5:
			global_position += flat.normalized() * speed * delta
		rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.z), delta * 5.0)
	if distance < 1.0 and _touch_cooldown <= 0.0 and target.has_method("take_damage"):
		target.call("take_damage", attack_damage, global_position, "frozen_enemy")
		_touch_cooldown = 1.0

func _launch_projectile(target: Node3D) -> void:
	_projectile_cooldown = 2.8
	var projectile: IceProjectile = ICE_PROJECTILE.new()
	projectile.global_position = global_position + Vector3(0.0, 0.2, 0.0)
	get_parent().add_child(projectile)
	projectile.launch(target)

func _movement_speed(target: Node3D) -> float:
	var player_speed := float(target.get("movement_speed")) if target.get("movement_speed") != null else 8.4
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
	health -= amount
	if health <= 0:
		_dead = true
		defeated.emit()
		queue_free()
	return true

