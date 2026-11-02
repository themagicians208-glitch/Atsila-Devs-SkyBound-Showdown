class_name ShadowWolfBoss
extends CharacterBody3D

## THE SHADOW WOLF - GUARDIAN OF THE WHISPERING WOODS (Level 2 Final Boss).
##
## Giant corrupted forest guardian with an articulated quadrupedal body, glowing
## forehead rune, large magical claws, purple aura, and four distinct phases:
##   Phase 1 - Forest Hunter (fast movement, telegraphed charge, sweeping claw)
##   Phase 2 - Shadow Disappearance (vanishes into shadow particles, reappears
##             with a visible warning ring before lunging)
##   Phase 3 - Corrupted Forest Magic (summons shadow roots from the ground +
##             jumpable magical energy waves across the arena)
##   Phase 4 - Guardian's Fury (combines vanish, fast charges, roots and waves)

signal woke
signal defeated
signal phase_reached(phase: int, phase_text: String)
signal health_changed(health: int, max_health: int, phase: int)

const PHASE_NAMES := [
	"Forest Hunter",
	"Shadow Disappearance",
	"Corrupted Forest Magic",
	"Guardian's Fury",
]

const RING_CLEARANCE := 0.45
const GRAVITY := 22.0

const FUR_BLACK := Color("#1a1029")
const FUR_DEEP := Color("#311b4f")
const RUNE_MAGENTA := Color("#ff3df0")
const AURA_VIOLET := Color("#9d4edd")
const CLAW_GLOW := Color("#d946ef")

enum State { DORMANT, WAKE, IDLE, TELEGRAPH_CHARGE, CHARGE, SWEEP, VANISH, REAPPEAR_WARN, ROOT_CAST, RECOVER, DEAD }

@export var max_health := 16
@export var contact_damage := 4.0
@export var hit_hp_fraction := 0.04
@export var home := Vector3(0.0, 9.0, 224.0)
@export var arena_radius := 9.0
@export var wake_range := 12.0
@export var move_speed := 6.0
@export var charge_speed := 10.2
@export var ring_speed := 7.2
@export var touch_range := 1.65

var health := 16
var phase := 1
var is_defeated := false

var _woods: Node = null
var _collision: CollisionShape3D
var _state: State = State.DORMANT
var _timer := 0.0
var _anim_time := 0.0
var _hit_flash := 0.0
var _touch_cooldown := 0.0
var _charge_dir := Vector3.FORWARD
var _teleport_target := Vector3.ZERO
var _combo_step := 0

var _visual: Node3D
var _torso: Node3D
var _head_pivot: Node3D
var _tail_pivot: Node3D
var _forehead_rune: MeshInstance3D
var _aura_ring: MeshInstance3D
var _telegraph_marker: MeshInstance3D
var _legs: Array[Node3D] = []
var _fur_material: StandardMaterial3D
var _rune_material: StandardMaterial3D
var _rings: Array[Dictionary] = []
var _root_hazards: Array[Node3D] = []


func _init() -> void:
	_collision = CollisionShape3D.new()
	_collision.name = "BossCollision"
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 2.1, 2.4)
	_collision.shape = box
	_collision.position = Vector3(0.0, 1.05, 0.0)
	add_child(_collision)


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("woods_boss")
	health = max_health
	collision_layer = 2
	collision_mask = 1
	_build_boss_model()


func set_woods(woods_node: Node) -> void:
	_woods = woods_node


func phase_name() -> String:
	return PHASE_NAMES[clampi(phase - 1, 0, PHASE_NAMES.size() - 1)]


func state_name() -> String:
	match _state:
		State.DORMANT: return "dormant"
		State.WAKE: return "wake"
		State.IDLE: return "idle"
		State.TELEGRAPH_CHARGE: return "telegraph"
		State.CHARGE: return "charge"
		State.SWEEP: return "sweep"
		State.VANISH: return "vanish"
		State.REAPPEAR_WARN: return "reappear_warn"
		State.ROOT_CAST: return "root_cast"
		State.RECOVER: return "recover"
	return "dead"


func rings_out() -> int:
	return _rings.size()


func active_roots() -> int:
	return _root_hazards.size()


func _build_boss_model() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	_visual.scale = Vector3.ONE * 2.2
	add_child(_visual)

	_fur_material = StandardMaterial3D.new()
	_fur_material.albedo_color = FUR_BLACK
	_fur_material.roughness = 0.55

	var mane_mat := StandardMaterial3D.new()
	mane_mat.albedo_color = FUR_DEEP
	mane_mat.roughness = 0.5

	_rune_material = StandardMaterial3D.new()
	_rune_material.albedo_color = RUNE_MAGENTA
	_rune_material.emission_enabled = true
	_rune_material.emission = RUNE_MAGENTA
	_rune_material.emission_energy_multiplier = 2.1

	_torso = Node3D.new()
	_torso.name = "Torso"
	_torso.position = Vector3(0.0, 0.56, 0.0)
	_visual.add_child(_torso)

	var body := MeshInstance3D.new()
	var body_box := BoxMesh.new()
	body_box.size = Vector3(0.68, 0.52, 1.12)
	body.mesh = body_box
	body.material_override = _fur_material
	_torso.add_child(body)

	var mane := MeshInstance3D.new()
	var mane_sphere := SphereMesh.new()
	mane_sphere.radius = 0.46
	mane_sphere.height = 0.88
	mane.mesh = mane_sphere
	mane.material_override = mane_mat
	mane.position = Vector3(0.0, 0.08, 0.38)
	_torso.add_child(mane)

	# Glowing purple markings along the back
	for z_off in [-0.34, -0.06, 0.22, 0.44]:
		var stripe := MeshInstance3D.new()
		var stripe_box := BoxMesh.new()
		stripe_box.size = Vector3(0.48, 0.05, 0.11)
		stripe.mesh = stripe_box
		stripe.material_override = _rune_material
		stripe.position = Vector3(0.0, 0.28, float(z_off))
		_torso.add_child(stripe)

	_head_pivot = Node3D.new()
	_head_pivot.name = "HeadPivot"
	_head_pivot.position = Vector3(0.0, 0.28, 0.62)
	_torso.add_child(_head_pivot)

	var head := MeshInstance3D.new()
	var head_box := BoxMesh.new()
	head_box.size = Vector3(0.56, 0.48, 0.52)
	head.mesh = head_box
	head.material_override = _fur_material
	head.position = Vector3(0.0, 0.05, 0.14)
	_head_pivot.add_child(head)

	var snout := MeshInstance3D.new()
	var snout_box := BoxMesh.new()
	snout_box.size = Vector3(0.32, 0.24, 0.38)
	snout.mesh = snout_box
	snout.material_override = mane_mat
	snout.position = Vector3(0.0, -0.04, 0.48)
	_head_pivot.add_child(snout)

	# Unique glowing diamond symbol on its forehead
	_forehead_rune = MeshInstance3D.new()
	_forehead_rune.name = "ForeheadSymbol"
	var rune_box := BoxMesh.new()
	rune_box.size = Vector3(0.16, 0.16, 0.05)
	_forehead_rune.mesh = rune_box
	_forehead_rune.material_override = _rune_material
	_forehead_rune.position = Vector3(0.0, 0.18, 0.41)
	_forehead_rune.rotation.z = PI * 0.25
	_head_pivot.add_child(_forehead_rune)

	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_sphere := SphereMesh.new()
		eye_sphere.radius = 0.085
		eye_sphere.height = 0.17
		eye.mesh = eye_sphere
		eye.material_override = _rune_material
		eye.position = Vector3(0.18 * side, 0.08, 0.38)
		_head_pivot.add_child(eye)

		var ear := MeshInstance3D.new()
		var ear_cyl := CylinderMesh.new()
		ear_cyl.top_radius = 0.02
		ear_cyl.bottom_radius = 0.11
		ear_cyl.height = 0.28
		ear.mesh = ear_cyl
		ear.material_override = mane_mat
		ear.position = Vector3(0.2 * side, 0.38, 0.08)
		_head_pivot.add_child(ear)

	_tail_pivot = Node3D.new()
	_tail_pivot.name = "TailPivot"
	_tail_pivot.position = Vector3(0.0, 0.14, -0.56)
	_torso.add_child(_tail_pivot)

	var tail := MeshInstance3D.new()
	var tail_cyl := CylinderMesh.new()
	tail_cyl.top_radius = 0.09
	tail_cyl.bottom_radius = 0.15
	tail_cyl.height = 0.65
	tail.mesh = tail_cyl
	tail.material_override = mane_mat
	tail.position = Vector3(0.0, 0.08, -0.28)
	tail.rotation.x = deg_to_rad(66.0)
	_tail_pivot.add_child(tail)

	# Four articulated legs with large magical claws
	var leg_spots := [
		Vector3(-0.26, 0.42, 0.38),
		Vector3(0.26, 0.42, 0.38),
		Vector3(-0.26, 0.42, -0.38),
		Vector3(0.26, 0.42, -0.38),
	]
	for i in 4:
		var leg := Node3D.new()
		leg.name = "BossLeg_%d" % i
		leg.position = leg_spots[i]
		var limb := MeshInstance3D.new()
		var limb_box := BoxMesh.new()
		limb_box.size = Vector3(0.17, 0.4, 0.17)
		limb.mesh = limb_box
		limb.material_override = _fur_material
		limb.position = Vector3(0.0, -0.2, 0.0)
		leg.add_child(limb)

		var claw := MeshInstance3D.new()
		var claw_box := BoxMesh.new()
		claw_box.size = Vector3(0.22, 0.11, 0.28)
		claw.mesh = claw_box
		claw.material_override = _rune_material
		claw.position = Vector3(0.0, -0.38, 0.06)
		leg.add_child(claw)
		_visual.add_child(leg)
		_legs.append(leg)

	# Magical aura ring around its feet
	_aura_ring = MeshInstance3D.new()
	_aura_ring.name = "BossAura"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.72
	torus.outer_radius = 0.88
	_aura_ring.mesh = torus
	var aura_mat := StandardMaterial3D.new()
	aura_mat.albedo_color = Color(AURA_VIOLET.r, AURA_VIOLET.g, AURA_VIOLET.b, 0.7)
	aura_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	aura_mat.emission_enabled = true
	aura_mat.emission = AURA_VIOLET
	aura_mat.emission_energy_multiplier = 1.5
	_aura_ring.material_override = aura_mat
	_aura_ring.position = Vector3(0.0, 0.05, 0.0)
	_visual.add_child(_aura_ring)

	# Telegraph warning marker on the arena floor for shadow reappearances
	_telegraph_marker = MeshInstance3D.new()
	_telegraph_marker.name = "TelegraphMarker"
	var warn_torus := TorusMesh.new()
	warn_torus.inner_radius = 1.2
	warn_torus.outer_radius = 1.55
	_telegraph_marker.mesh = warn_torus
	_telegraph_marker.material_override = _rune_material
	_telegraph_marker.visible = false
	add_child(_telegraph_marker)


func begin_fight() -> void:
	if _state != State.DORMANT or is_defeated:
		return
	_state = State.WAKE
	_timer = 1.1
	if _woods != null and _woods.has_method("set_arena_locked"):
		_woods.call("set_arena_locked", true)
	woke.emit()
	health_changed.emit(health, max_health, phase)
	phase_reached.emit(phase, phase_name())
	_say("The Shadow Wolf Guardian awakens - the entrance to the grove seals behind you!")


func force_wave() -> void:
	_spawn_energy_wave()


func force_vanish() -> void:
	_start_vanish()


func _physics_process(delta: float) -> void:
	_anim_time += delta
	_hit_flash = maxf(_hit_flash - delta, 0.0)
	_touch_cooldown = maxf(_touch_cooldown - delta, 0.0)
	if _fur_material != null:
		_fur_material.albedo_color = Color(1, 1, 1) if _hit_flash > 0.0 else FUR_BLACK
	_update_rings(delta)

	if is_defeated:
		return

	var target := _nearest_player()
	if _state == State.DORMANT:
		if target != null and global_position.distance_to(target.global_position) <= wake_range:
			begin_fight()
		return

	_step_state(target, delta)
	if _state != State.VANISH and _state != State.REAPPEAR_WARN:
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		elif velocity.y < 0.0:
			velocity.y = 0.0
		move_and_slide()
		var from_home := global_position - home
		from_home.y = 0.0
		if from_home.length() > arena_radius:
			var clamped := home + from_home.normalized() * arena_radius
			global_position.x = clamped.x
			global_position.z = clamped.z
		_touch_check(target)
	_animate_boss()


func _step_state(target: Node3D, delta: float) -> void:
	_timer -= delta
	match _state:
		State.WAKE:
			velocity = Vector3.ZERO
			if _timer <= 0.0:
				_state = State.IDLE
				_timer = 0.6
		State.IDLE:
			if target != null:
				_face(target.global_position, 0.2)
				var to_p := target.global_position - global_position
				to_p.y = 0.0
				if to_p.length() > 2.4:
					var spd := move_speed * (1.2 if phase == 4 else 1.0)
					velocity.x = to_p.normalized().x * spd
					velocity.z = to_p.normalized().z * spd
				else:
					velocity.x = 0.0
					velocity.z = 0.0
			if _timer <= 0.0:
				_choose_next_attack(target)
		State.TELEGRAPH_CHARGE:
			velocity.x = 0.0
			velocity.z = 0.0
			if target != null:
				_face(target.global_position, 0.35)
				var aim := target.global_position - global_position
				aim.y = 0.0
				_charge_dir = aim.normalized() if aim.length_squared() > 0.001 else Vector3.FORWARD
			if _timer <= 0.0:
				_state = State.CHARGE
				_timer = 0.65
				Audio.play("res://sounds/jump.ogg")
		State.CHARGE:
			var c_spd := charge_speed * (1.18 if phase == 4 else 1.0)
			velocity.x = _charge_dir.x * c_spd
			velocity.z = _charge_dir.z * c_spd
			if _timer <= 0.0:
				_state = State.SWEEP
				_timer = 0.35
				_perform_sweep()
		State.SWEEP:
			velocity.x = 0.0
			velocity.z = 0.0
			if _timer <= 0.0:
				if phase >= 3:
					_spawn_energy_wave()
				_state = State.RECOVER
				_timer = 0.65 if phase == 4 else 0.95
		State.VANISH:
			velocity = Vector3.ZERO
			_visual.visible = false
			if _timer <= 0.0:
				var angle := _anim_time * 2.3 + float(_combo_step) * 1.7
				var offset := Vector3(cos(angle) * 4.2, 0.0, sin(angle) * 4.2)
				if target != null:
					var behind := (target.global_position - home)
					behind.y = 0.0
					if behind.length() > arena_radius - 1.5:
						behind = behind.normalized() * (arena_radius - 1.5)
					_teleport_target = home + behind + Vector3(cos(angle) * 2.0, 0.0, sin(angle) * 2.0)
				else:
					_teleport_target = home + offset
				_telegraph_marker.global_position = _teleport_target + Vector3(0.0, 0.08, 0.0)
				_telegraph_marker.visible = true
				_state = State.REAPPEAR_WARN
				_timer = 0.75
		State.REAPPEAR_WARN:
			velocity = Vector3.ZERO
			_telegraph_marker.scale = Vector3.ONE * (0.85 + sin(_anim_time * 20.0) * 0.2)
			if _timer <= 0.0:
				_telegraph_marker.visible = false
				global_position = _teleport_target
				_visual.visible = true
				if phase >= 3:
					_spawn_energy_wave()
				_state = State.TELEGRAPH_CHARGE
				_timer = 0.42
		State.ROOT_CAST:
			velocity = Vector3.ZERO
			if _timer <= 0.0:
				_summon_shadow_roots(target)
				_spawn_energy_wave()
				_state = State.RECOVER
				_timer = 0.85
		State.RECOVER:
			velocity.x = 0.0
			velocity.z = 0.0
			if _timer <= 0.0:
				_state = State.IDLE
				_timer = 0.55 if phase == 4 else 0.85


func _choose_next_attack(_target: Node3D) -> void:
	_combo_step += 1
	if phase == 1:
		_state = State.TELEGRAPH_CHARGE
		_timer = 0.55
	elif phase == 2:
		if _combo_step % 2 == 0:
			_start_vanish()
		else:
			_state = State.TELEGRAPH_CHARGE
			_timer = 0.5
	elif phase == 3:
		if _combo_step % 2 == 0:
			_state = State.ROOT_CAST
			_timer = 0.55
		else:
			_start_vanish()
	else:
		match _combo_step % 3:
			0:
				_start_vanish()
			1:
				_state = State.ROOT_CAST
				_timer = 0.45
			_:
				_state = State.TELEGRAPH_CHARGE
				_timer = 0.4


func _start_vanish() -> void:
	_state = State.VANISH
	_timer = 0.45
	_visual.visible = false
	Audio.play("res://sounds/jump.ogg")


func _perform_sweep() -> void:
	var target := _nearest_player()
	if target == null:
		return
	if global_position.distance_to(target.global_position) <= touch_range + 1.1:
		var max_hp: float = float(target.get("max_health")) if target.get("max_health") != null else 100.0
		target.call("take_damage", minf(contact_damage, max_hp * hit_hp_fraction), global_position, "wolf_boss")


func _summon_shadow_roots(target: Node3D) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var base_spot := target.global_position if target != null else home
	base_spot.y = home.y
	for i in 3:
		var angle := TAU * float(i) / 3.0 + _anim_time
		var spot := base_spot + Vector3(cos(angle) * 2.2, 0.0, sin(angle) * 2.2)
		if Vector2(spot.x - home.x, spot.z - home.z).length() > arena_radius - 0.8:
			spot = home + Vector3(cos(angle) * 3.5, 0.0, sin(angle) * 3.5)
		var root_node := Node3D.new()
		root_node.name = "ShadowRootHazard"
		root_node.position = spot
		var spike := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.08
		cyl.bottom_radius = 0.42
		cyl.height = 1.8
		spike.mesh = cyl
		spike.material_override = _rune_material
		spike.position.y = -0.9
		root_node.add_child(spike)
		parent.add_child(root_node)
		_root_hazards.append(root_node)
		var tween := root_node.create_tween()
		tween.tween_interval(0.55)
		tween.tween_property(spike, "position:y", 0.9, 0.2)
		tween.tween_callback(func():
			if not is_instance_valid(root_node):
				return
			for node in get_tree().get_nodes_in_group("player"):
				var p := node as Node3D
				if p == null or bool(p.get("is_dead")) or not p.has_method("take_damage"):
					continue
				if Vector2(p.global_position.x - spot.x, p.global_position.z - spot.z).length() < 0.85 and p.global_position.y - home.y < 1.5:
					var max_hp: float = float(p.get("max_health")) if p.get("max_health") != null else 100.0
					p.call("take_damage", minf(contact_damage, max_hp * hit_hp_fraction), spot, "wolf_boss")
		)
		tween.tween_interval(0.55)
		tween.tween_property(spike, "position:y", -0.9, 0.25)
		tween.tween_callback(func():
			_root_hazards.erase(root_node)
			if is_instance_valid(root_node):
				root_node.queue_free()
		)


func _spawn_energy_wave() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var ring_mesh := MeshInstance3D.new()
	ring_mesh.name = "BossEnergyWave"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.88
	torus.outer_radius = 1.04
	ring_mesh.mesh = torus
	ring_mesh.material_override = _rune_material
	ring_mesh.position = Vector3(home.x, home.y + 0.18, home.z)
	parent.add_child(ring_mesh)
	_rings.append({"node": ring_mesh, "radius": 1.0, "hit": {}})


func _update_rings(delta: float) -> void:
	var done: Array = []
	for ring in _rings:
		var node: Node3D = ring["node"]
		if not is_instance_valid(node):
			done.append(ring)
			continue
		var r := float(ring["radius"]) + ring_speed * delta
		ring["radius"] = r
		node.scale = Vector3(r, 1.0, r)
		_check_ring_hit(ring, r)
		if r > arena_radius + 3.0:
			node.queue_free()
			done.append(ring)
	for entry in done:
		_rings.erase(entry)


func _check_ring_hit(ring: Dictionary, radius: float) -> void:
	var centre := Vector3(home.x, home.y, home.z)
	for node in get_tree().get_nodes_in_group("player"):
		var p := node as Node3D
		if p == null or bool(p.get("is_dead")) or not p.has_method("take_damage"):
			continue
		if ring["hit"].has(p):
			continue
		var offset := p.global_position - centre
		var flat := Vector2(offset.x, offset.z).length()
		if absf(flat - radius) <= 0.75 and offset.y < RING_CLEARANCE:
			ring["hit"][p] = true
			var max_hp: float = float(p.get("max_health")) if p.get("max_health") != null else 100.0
			p.call("take_damage", minf(contact_damage, max_hp * hit_hp_fraction), centre, "wolf_boss")


func _clear_hazards() -> void:
	for ring in _rings:
		var n: Node3D = ring["node"]
		if is_instance_valid(n):
			n.queue_free()
	_rings.clear()
	for root_node in _root_hazards:
		if is_instance_valid(root_node):
			root_node.queue_free()
	_root_hazards.clear()
	if _telegraph_marker != null:
		_telegraph_marker.visible = false


func _animate_boss() -> void:
	if _visual == null or not _visual.visible:
		return
	var flat_spd := Vector2(velocity.x, velocity.z).length()
	var amp := clampf(flat_spd / maxf(charge_speed, 0.1), 0.08, 1.0) * 0.7
	if _legs.size() == 4:
		var a := sin(_anim_time * 13.0) * amp
		var b := sin(_anim_time * 13.0 + PI) * amp
		_legs[0].rotation.x = a
		_legs[3].rotation.x = a
		_legs[1].rotation.x = b
		_legs[2].rotation.x = b
	if _tail_pivot != null:
		_tail_pivot.rotation.y = sin(_anim_time * 7.5) * 0.35
	if _aura_ring != null:
		_aura_ring.rotation.y = _anim_time * 1.8


func take_hit(amount: int, _from: Vector3) -> bool:
	if is_defeated or _state == State.VANISH or _state == State.REAPPEAR_WARN:
		return false
	if _state == State.DORMANT:
		begin_fight()
	health = maxi(0, health - amount)
	_hit_flash = 0.2
	Audio.play("res://sounds/break.ogg")
	_advance_phase_if_needed()
	health_changed.emit(health, max_health, phase)
	if health <= 0:
		_die()
	return true


func _advance_phase_if_needed() -> void:
	var ratio := float(health) / float(maxf(max_health, 1))
	var target_phase := 1
	if ratio <= 0.25:
		target_phase = 4
	elif ratio <= 0.50:
		target_phase = 3
	elif ratio <= 0.75:
		target_phase = 2
	if target_phase > phase:
		phase = target_phase
		phase_reached.emit(phase, phase_name())
		_say("Shadow Wolf Guardian - Phase %d: %s!" % [phase, phase_name()])
		if phase == 2:
			_start_vanish()
		elif phase >= 3:
			_spawn_energy_wave()


func _die() -> void:
	is_defeated = true
	_state = State.DEAD
	velocity = Vector3.ZERO
	_clear_hazards()
	if _collision != null:
		_collision.set_deferred("disabled", true)
	if _woods != null:
		if _woods.has_method("set_arena_locked"):
			_woods.call("set_arena_locked", false)
		if _woods.has_method("boss_defeated"):
			_woods.call("boss_defeated")
	defeated.emit()
	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector3.ZERO, 0.75)
	tween.tween_callback(func(): visible = false)


func reset_to_home() -> void:
	if is_defeated:
		return
	_clear_hazards()
	global_position = home
	velocity = Vector3.ZERO
	health = max_health
	phase = 1
	_state = State.DORMANT
	_visual.visible = true
	_visual.scale = Vector3.ONE * 2.2
	if _woods != null and _woods.has_method("set_arena_locked"):
		_woods.call("set_arena_locked", false)


func _touch_check(target: Node3D) -> void:
	if target == null or _touch_cooldown > 0.0:
		return
	if global_position.distance_to(target.global_position) < touch_range:
		var max_hp: float = float(target.get("max_health")) if target.get("max_health") != null else 100.0
		target.call("take_damage", minf(contact_damage, max_hp * hit_hp_fraction), global_position, "wolf_boss")
		_touch_cooldown = 1.0


func _face(spot: Vector3, weight: float) -> void:
	var flat := spot - global_position
	flat.y = 0.0
	if flat.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.z), clampf(weight, 0.0, 1.0))


func _nearest_player() -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("player"):
		var candidate := node as Node3D
		if candidate == null or not candidate.has_method("take_damage"):
			continue
		if bool(candidate.get("is_dead")):
			continue
		var d := global_position.distance_to(candidate.global_position)
		if d < best_dist:
			best_dist = d
			best = candidate
	return best


func _say(text: String) -> void:
	if _woods != null and _woods.has_signal("message"):
		_woods.emit_signal("message", text)
