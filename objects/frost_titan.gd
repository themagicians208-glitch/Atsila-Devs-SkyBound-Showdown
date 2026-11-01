extends Node3D
class_name FrostTitan

const ICE_PROJECTILE := preload("res://objects/ice_projectile.gd")

signal defeated
signal health_changed(health: int, maximum: int, phase: int)

@export var max_health := 40
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
var _warning: MeshInstance3D

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
	_warning = MeshInstance3D.new()
	var warning_mesh := TorusMesh.new()
	warning_mesh.inner_radius = 2.1
	warning_mesh.outer_radius = 2.25
	_warning.mesh = warning_mesh
	_warning.position.y = -2.0
	_warning.rotation.x = PI / 2.0
	_warning.material_override = _crystal_material()
	_warning.visible = false
	add_child(_warning)

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
	elif _warning != null:
		_warning.visible = _attack_cooldown < 0.55
		_warning.scale = Vector3.ONE * (1.0 + sin(_time * 12.0) * 0.08)

func _perform_phase_attack(target: Node3D) -> void:
	_attack_cooldown = 3.0 if phase == 1 else (2.2 if phase == 2 else (1.8 if phase == 3 else 1.35))
	_attack_flash = 0.3
	_warning.visible = false
	Audio.play("res://sounds/land.ogg")
	var distance := global_position.distance_to(target.global_position)
	if phase == 1:
		if distance < 7.0 and target.has_method("take_damage"):
			target.call("take_damage", 10.0, global_position, "frost_titan_shockwave")
	elif phase == 2:
		_spawn_ice_hazard(target.global_position)
		var projectile: IceProjectile = ICE_PROJECTILE.new()
		projectile.damage = 6.0
		projectile.speed = 7.0
		get_parent().add_child(projectile)
		projectile.global_position = global_position + Vector3(0.0, 1.0, 0.0)
		projectile.launch(target)
		if distance < 11.0 and target.has_method("take_damage"):
			target.call("take_damage", 7.0, global_position, "frost_titan_crystal_storm")
	elif phase == 3:
		# The warning ring marks the disappearance window before the Titan shifts.
		global_position = target.global_position + Vector3(0.0, 0.0, 5.0)
		if distance < 13.0 and target.has_method("take_damage"):
			target.call("take_damage", 12.0, global_position, "frost_titan_disappearance")
	else:
		_spawn_ice_hazard(target.global_position + Vector3(1.5, 0.0, 0.0))
		if distance < 15.0 and target.has_method("take_damage"):
			target.call("take_damage", 14.0, global_position, "frost_titan_absolute_frost")

func take_hit(amount: int, from: Vector3) -> bool:
	if _dead or locked:
		return false
	health -= amount
	phase = 1 if health > max_health * 0.75 else (2 if health > max_health * 0.5 else (3 if health > max_health * 0.25 else 4))
	health_changed.emit(maxi(health, 0), max_health, phase)
	if health <= 0:
		_dead = true
		defeated.emit()
		Audio.play("res://sounds/break.ogg")
		_burst_crystals()
		var tween := create_tween()
		tween.tween_property(_visual, "scale", Vector3.ZERO, 0.65)
		tween.tween_callback(queue_free)
	return true

func _burst_crystals() -> void:
	var particles := GPUParticles3D.new()
	particles.amount = 28
	particles.lifetime = 0.9
	particles.one_shot = true
	particles.explosiveness = 1.0
	var shard := QuadMesh.new()
	shard.size = Vector2(0.18, 0.18)
	var material := _crystal_material()
	shard.material = material
	particles.draw_pass_1 = shard
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 180.0
	process.initial_velocity_min = 1.5
	process.initial_velocity_max = 4.0
	process.gravity = Vector3(0.0, -2.0, 0.0)
	particles.process_material = process
	particles.position = global_position + Vector3(0.0, 1.0, 0.0)
	get_parent().add_child(particles)
	particles.emitting = true

func _spawn_ice_hazard(at: Vector3) -> void:
	var hazard := Area3D.new()
	hazard.name = "FrostTitanIceHazard"
	hazard.add_to_group("frost_hazards")
	hazard.collision_layer = 0
	hazard.collision_mask = 1
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.8
	shape.shape = sphere
	hazard.add_child(shape)
	var visual := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 0.55
	mesh.height = 1.3
	visual.mesh = mesh
	visual.material_override = _crystal_material()
	hazard.add_child(visual)
	hazard.body_entered.connect(func(body: Node3D):
		if body.has_method("take_damage"):
			body.call("take_damage", 5.0, hazard.global_position, "frost_hazard")
	)
	get_parent().add_child(hazard)
	hazard.global_position = at + Vector3(0.0, 0.65, 0.0)
	get_tree().create_timer(4.0).timeout.connect(func():
		if is_instance_valid(hazard):
			hazard.queue_free()
	)

func unlock() -> void:
	locked = false
	health_changed.emit(health, max_health, phase)

