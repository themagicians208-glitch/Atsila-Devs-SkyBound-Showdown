extends Node3D

## A sky sentry - something to fight. It drifts around the spot it was placed on,
## chases the closest player once they come near, and hurts them by touch.
## Nail hits knock it back and three of them destroy it; a down-slash on top of one
## throws the player back into the air.

signal defeated

const BODY_COLOR := Color(0.46, 0.27, 0.72)
const SPIKE_COLOR := Color(0.22, 0.12, 0.38)
const EYE_COLOR := Color(1.0, 0.96, 0.86)

@export var max_health := 3
@export var contact_damage := 1
@export var touch_range := 1.05
@export var chase_range := 9.5
@export var drift_speed := 1.8
@export var wander := 2.2

var health := max_health

var _home := Vector3.ZERO
var _bob := 0.0
var _hit_flash := 0.0
var _touch_cooldown := 0.0
var _knockback := Vector3.ZERO
var _visual: Node3D
var _body_material: StandardMaterial3D
var _dead := false


func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	_home = global_position
	_build()


## Everything is built from primitives, the same way the rest of the sky is.
func _build() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)

	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = BODY_COLOR
	_body_material.roughness = 0.65
	_body_material.emission_enabled = true
	_body_material.emission = BODY_COLOR * 0.3

	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.42
	sphere.height = 0.84
	sphere.radial_segments = 18
	sphere.rings = 9
	body.mesh = sphere
	body.material_override = _body_material
	_visual.add_child(body)

	# A ring of dark spikes around the equator.
	var spike_material := StandardMaterial3D.new()
	spike_material.albedo_color = SPIKE_COLOR
	spike_material.roughness = 0.8
	var spike_mesh := SphereMesh.new()
	spike_mesh.radius = 0.11
	spike_mesh.height = 0.22
	spike_mesh.radial_segments = 8
	spike_mesh.rings = 4
	for i in 9:
		var angle := TAU * float(i) / 9.0
		var spike := MeshInstance3D.new()
		spike.mesh = spike_mesh
		spike.material_override = spike_material
		spike.position = Vector3(cos(angle) * 0.42, 0.0, sin(angle) * 0.42)
		_visual.add_child(spike)

	# Two pale eyes on its front (+Z, the same way the characters face).
	var eye_material := StandardMaterial3D.new()
	eye_material.albedo_color = EYE_COLOR
	eye_material.emission_enabled = true
	eye_material.emission = EYE_COLOR * 0.5
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.09
	eye_mesh.height = 0.18
	eye_mesh.radial_segments = 10
	eye_mesh.rings = 5
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = eye_mesh
		eye.material_override = eye_material
		eye.position = Vector3(0.15 * side, 0.12, 0.34)
		_visual.add_child(eye)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_hit_flash = maxf(_hit_flash - delta, 0.0)
	_touch_cooldown = maxf(_touch_cooldown - delta, 0.0)
	_apply_flash()

	_bob += delta * 2.4
	if _visual != null:
		_visual.position.y = sin(_bob) * 0.13
		_visual.rotation.y += delta * 0.7

	var target := _nearest_player()
	var destination := _home + Vector3(cos(_bob * 0.32), 0.0, sin(_bob * 0.32)) * wander
	if target != null:
		var to_player := target.global_position - global_position
		if to_player.length() <= chase_range:
			destination = target.global_position
			destination.y = _home.y
			var flat := Vector3(to_player.x, 0.0, to_player.z)
			if flat.length_squared() > 0.01:
				rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.z), delta * 4.0)

	var move := destination - global_position
	move.y = 0.0
	if move.length() > 0.25:
		global_position += move.normalized() * drift_speed * delta
	# Knockback from being hit, which fades quickly.
	global_position += _knockback * delta
	_knockback = _knockback.lerp(Vector3.ZERO, delta * 6.0)

	if target != null and _touch_cooldown <= 0.0:
		if global_position.distance_to(target.global_position) < touch_range:
			if target.has_method("take_damage"):
				target.call("take_damage", contact_damage, global_position)
			_touch_cooldown = 1.0


## The closest living player, or null. Remote proxies are skipped, because they
## cannot take damage.
func _nearest_player() -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("player"):
		var candidate := node as Node3D
		if candidate == null or not candidate.has_method("take_damage"):
			continue
		if bool(candidate.get("is_dead")):
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


## Called by a player's slash. Returns true when the hit landed, which is what
## gives the player soul and lets a down-slash bounce off this.
func take_hit(amount: int, from: Vector3) -> bool:
	if _dead:
		return false
	health -= amount
	_hit_flash = 0.18
	var away := global_position - from
	away.y = 0.0
	if away.length_squared() < 0.001:
		away = Vector3(0.0, 0.0, 1.0)
	_knockback = away.normalized() * 5.5
	Audio.play("res://sounds/break.ogg")
	_burst(6, BODY_COLOR, 3.0)
	if health <= 0:
		_die()
	return true


func _apply_flash() -> void:
	if _body_material == null:
		return
	_body_material.albedo_color = Color(1, 1, 1) if _hit_flash > 0.0 else BODY_COLOR


func _die() -> void:
	_dead = true
	_burst(18, BODY_COLOR, 6.0)
	defeated.emit()
	queue_free()


## A one-shot puff of squares. It is parented to the world rather than to this
## node, so the burst outlives the enemy it was spawned by.
func _burst(amount: int, color: Color, speed: float) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.6
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)

	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0, 1, 0)
	process.spread = 180.0
	process.initial_velocity_min = speed * 0.5
	process.initial_velocity_max = speed
	process.gravity = Vector3(0, 1.5, 0)
	process.scale_min = 0.6
	process.scale_max = 1.2
	process.damping_min = 2.0
	process.damping_max = 3.0

	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = 0.8
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.draw_pass_1 = quad
	particles.material_override = material
	particles.process_material = process
	particles.position = global_position
	parent.add_child(particles)
	particles.emitting = true

	var timer := get_tree().create_timer(1.4)
	timer.timeout.connect(_free_node.bind(particles))


func _free_node(node: Node) -> void:
	if is_instance_valid(node):
		node.queue_free()