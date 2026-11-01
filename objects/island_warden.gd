class_name IslandWarden
extends CharacterBody3D

## THE CORRUPTED ISLAND WARDEN - the guardian of the Forgotten Island's arena.
##
## A heavy stone warden the Shadow King has turned. It holds the far end of the
## arena and fights in three phases:
##
##   1. Wrath          - it slams the ground and rings of corruption sweep out
##                       across the floor. Jump over them.
##   2. Sweep          - it adds a telegraphed charge that crosses the whole
##                       arena. Step aside.
##   3. Desperate Guard- it raises a shield that no slash can pass and calls two
##                       Shadow Slimes to its side. The shield only falls when
##                       both of them are destroyed.
##
## Everything is built from primitives, and it speaks the same language as the
## other enemies (health / take_hit / contact_damage / in "enemies"), so a slash
## and a red reset treat it exactly like a sentry.

signal defeated
signal woke
signal phase_reached(phase: int, phase_text: String)
signal health_changed(health: int, max_health: int, phase: int)

const GRAVITY := 22.0
const SLIME := preload("res://objects/shadow_slime.gd")

const BODY_COLOR := Color("#4a3d63")
const BODY_DEEP := Color("#2a2239")
const RUNE_COLOR := Color("#b06bff")
const CRACK_COLOR := Color("#ff8a5c")
const EYE_COLOR := Color("#ffb066")

const PHASE_NAMES := ["Wrath", "Sweep", "Desperate Guard"]

## How high above the arena floor a player must be for a shockwave to pass under
## them. A player standing rests exactly on the slab (0.0) and a real jump peaks
## at 0.66 - measured, see tools/check_warden - so 0.45 catches anyone on the
## ground and still leaves a jump a quarter of a second of clearance.
const RING_CLEARANCE := 0.45

enum State { DORMANT, WAKE, IDLE, TELEGRAPH, CHARGE, RECOVER, DEAD }

@export var max_health := 12
@export var contact_damage := 1
@export var touch_range := 0.95
@export var wake_range := 11.0
## Where it holds its ground, and how far it may stray from there. The island
## sets both when it places the Warden.
@export var home := Vector3.ZERO
@export var arena_radius := 8.0
@export var ring_speed := 7.0
@export var charge_speed := 8.5

var health := max_health
var phase := 1
var shielded := false
var is_defeated := false

var _state: State = State.DORMANT
var _timer := 0.0
var _idle_wait := 1.4
var _attack_is_sweep := false
var _charge_direction := Vector3.FORWARD
var _touch_cooldown := 0.0
var _hit_flash := 0.0
var _rings: Array = []
var _summons: Array = []
var _summon_watchers := 0
var _phase_three_done := false
var _refuse_cooldown := 0.0
var _bob := 0.0
var _squash := 0.0
var _visual: Node3D
var _body_material: StandardMaterial3D
var _shield_mesh: MeshInstance3D
var _charge_light: OmniLight3D
var _island: Node = null


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("island_warden")
	health = max_health
	if home == Vector3.ZERO:
		home = global_position
	# Without a shape a CharacterBody3D falls straight through the world - the
	# same trap the Shadow Slimes hit. Stone layer, and it stands on the ground.
	collision_layer = 2
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.9, 3.0, 1.4)
	shape.shape = box
	shape.position.y = 1.5
	add_child(shape)
	_build()


## The island hands itself in so the Warden can report through it.
func set_island(island: Node) -> void:
	_island = island


func _build() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)

	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = BODY_COLOR
	_body_material.roughness = 0.85
	var deep := StandardMaterial3D.new()
	deep.albedo_color = BODY_DEEP
	deep.roughness = 0.9
	var rune := StandardMaterial3D.new()
	rune.albedo_color = RUNE_COLOR
	rune.emission_enabled = true
	rune.emission = RUNE_COLOR
	rune.emission_energy_multiplier = 1.4
	var crack_material := StandardMaterial3D.new()
	crack_material.albedo_color = CRACK_COLOR
	crack_material.emission_enabled = true
	crack_material.emission = CRACK_COLOR
	crack_material.emission_energy_multiplier = 1.2

	# A low stone plinth of a body, wide at the shoulders.
	var hips := MeshInstance3D.new()
	var hips_mesh := BoxMesh.new()
	hips_mesh.size = Vector3(1.5, 1.0, 1.15)
	hips.mesh = hips_mesh
	hips.material_override = deep
	hips.position.y = 0.5
	_visual.add_child(hips)

	var torso := MeshInstance3D.new()
	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(1.85, 1.25, 1.25)
	torso.mesh = torso_mesh
	torso.material_override = _body_material
	torso.position.y = 1.55
	_visual.add_child(torso)

	# A cracked core where the corruption entered.
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.42
	core_mesh.height = 0.84
	core.mesh = core_mesh
	core.material_override = crack_material
	core.position = Vector3(0.0, 1.6, 0.6)
	_visual.add_child(core)

	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.95, 0.8, 0.9)
	var head := MeshInstance3D.new()
	head.mesh = head_mesh
	head.material_override = _body_material
	head.position.y = 2.6
	_visual.add_child(head)

	# Two burning eyes facing +Z, the way everything else in this project faces.
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.11
	eye_mesh.height = 0.22
	eye_mesh.radial_segments = 10
	eye_mesh.rings = 5
	var eye_material := StandardMaterial3D.new()
	eye_material.albedo_color = EYE_COLOR
	eye_material.emission_enabled = true
	eye_material.emission = EYE_COLOR
	eye_material.emission_energy_multiplier = 2.0
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = eye_mesh
		eye.material_override = eye_material
		eye.position = Vector3(0.22 * side, 2.66, 0.46)
		_visual.add_child(eye)

	# Heavy arms, ready to come down.
	for side in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var arm_mesh := BoxMesh.new()
		arm_mesh.size = Vector3(0.5, 1.6, 0.55)
		arm.mesh = arm_mesh
		arm.material_override = deep
		arm.position = Vector3(1.25 * side, 1.45, 0.0)
		_visual.add_child(arm)
		var fist := MeshInstance3D.new()
		var fist_mesh := BoxMesh.new()
		fist_mesh.size = Vector3(0.7, 0.6, 0.7)
		fist.mesh = fist_mesh
		fist.material_override = _body_material
		fist.position = Vector3(1.25 * side, 0.55, 0.0)
		_visual.add_child(fist)

	# A crown of rune shards: the corruption's signature.
	for i in 5:
		var angle := TAU * float(i) / 5.0
		var shard := MeshInstance3D.new()
		var shard_mesh := BoxMesh.new()
		shard_mesh.size = Vector3(0.16, 0.6, 0.16)
		shard.mesh = shard_mesh
		shard.material_override = rune
		shard.position = Vector3(cos(angle) * 0.5, 3.25, sin(angle) * 0.5)
		shard.rotation = Vector3(0.25 * sin(angle), angle, 0.25 * cos(angle))
		_visual.add_child(shard)

	# The shield it raises in its last phase, hidden until then.
	_shield_mesh = MeshInstance3D.new()
	var shield_ball := SphereMesh.new()
	shield_ball.radius = 2.6
	shield_ball.height = 5.2
	shield_ball.radial_segments = 24
	shield_ball.rings = 12
	_shield_mesh.mesh = shield_ball
	var shield_material := StandardMaterial3D.new()
	shield_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shield_material.albedo_color = Color(RUNE_COLOR.r, RUNE_COLOR.g, RUNE_COLOR.b, 0.22)
	shield_material.emission_enabled = true
	shield_material.emission = RUNE_COLOR
	shield_material.emission_energy_multiplier = 0.8
	shield_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shield_mesh.material_override = shield_material
	_shield_mesh.position.y = 1.7
	_shield_mesh.visible = false
	_visual.add_child(_shield_mesh)

	_charge_light = OmniLight3D.new()
	_charge_light.light_color = CRACK_COLOR
	_charge_light.light_energy = 0.0
	_charge_light.omni_range = 7.0
	_charge_light.position.y = 2.0
	_visual.add_child(_charge_light)


# --- State -------------------------------------------------------------------

func state_name() -> String:
	match _state:
		State.DORMANT: return "dormant"
		State.WAKE: return "wake"
		State.IDLE: return "idle"
		State.TELEGRAPH: return "telegraph"
		State.CHARGE: return "charge"
		State.RECOVER: return "recover"
		State.DEAD: return "dead"
	return "?"


## Slam right now, skipping the rest of the idle wait. The dev checks use this to
## study a wave without waiting out the telegraph.
func force_slam() -> void:
	if _state == State.DEAD or _state == State.DORMANT or shielded:
		return
	_do_slam()


## The slimes currently holding its guard, for the level and the dev checks.
func summons() -> Array:
	return _summons.duplicate()


func phase_name() -> String:
	return PHASE_NAMES[clampi(phase - 1, 0, PHASE_NAMES.size() - 1)]


func rings_out() -> int:
	return _rings.size()


## How many of its summons are still standing. Counted off their defeat signals
## rather than off the nodes: a slime spends a second dissolving after it dies,
## during which it is still a valid node but no longer any threat.
func summons_alive() -> int:
	return _summon_watchers


func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return
	_hit_flash = maxf(_hit_flash - delta, 0.0)
	_touch_cooldown = maxf(_touch_cooldown - delta, 0.0)
	_refuse_cooldown = maxf(_refuse_cooldown - delta, 0.0)
	_apply_flash()
	_animate(delta)
	_update_rings(delta)
	_move(delta)
	_touch_check()
	if _state == State.DORMANT:
		_watch_for_players()
		return
	_think(delta)


func _watch_for_players() -> void:
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		if player == null or bool(player.get("is_dead")):
			continue
		if global_position.distance_to(player.global_position) <= wake_range:
			_state = State.WAKE
			_timer = 1.3
			_say("THE WARDEN RISES - the corruption will not release its guardian.")
			woke.emit()
			return


func _think(delta: float) -> void:
	var target := _nearest_player()
	_timer -= delta
	match _state:
		State.WAKE:
			if target != null:
				_face(target.global_position, delta * 3.0)
			if _timer <= 0.0:
				_state = State.IDLE
				_idle_wait = 0.9
		State.IDLE:
			if target != null:
				_face(target.global_position, delta * 2.5)
			_idle_wait -= delta
			if _idle_wait <= 0.0 and target != null:
				_choose_attack(target)
		State.TELEGRAPH:
			if target != null:
				_face(target.global_position, delta * (4.0 if _attack_is_sweep else 1.5))
			if _timer <= 0.0:
				if _attack_is_sweep:
					_begin_charge(target)
				else:
					_do_slam()
		State.CHARGE:
			if _timer <= 0.0 or global_position.distance_to(home) > arena_radius:
				_state = State.RECOVER
				_timer = 0.9
				_charge_light.light_energy = 0.0
		State.RECOVER:
			if _timer <= 0.0:
				_state = State.IDLE
				_idle_wait = _idle_period()


## How long it waits between attacks: shorter as the fight goes on.
func _idle_period() -> float:
	if shielded:
		return 1.5
	match phase:
		1: return 1.4
		2: return 1.0
	return 0.7


func _choose_attack(target: Node3D) -> void:
	# Phase 1 only slams. Phase 2 and 3 mix in the charge, and from phase 3 it
	# alternates so the sweep never comes twice in a row.
	if phase == 1:
		_attack_is_sweep = false
	else:
		var distance := global_position.distance_to(target.global_position)
		_attack_is_sweep = not _attack_is_sweep if phase >= 3 else distance > 4.0
	_state = State.TELEGRAPH
	_timer = 0.75 if _attack_is_sweep else 0.85
	if _attack_is_sweep:
		_say("The Warden crouches - it is going to charge.")
	else:
		_say("The Warden raises both arms.")


func _do_slam() -> void:
	_state = State.RECOVER
	_timer = 0.85 if phase < 3 else 0.6
	_squash = 0.7
	Audio.play("res://sounds/land.ogg")
	_spawn_ring(0.6)
	# Higher phases get a second and third wave.
	if phase >= 2:
		_spawn_ring(-1.1)
	if phase >= 3:
		_spawn_ring(-2.2)


func _begin_charge(target: Node3D) -> void:
	var flat := target.global_position - global_position
	flat.y = 0.0
	if flat.length_squared() < 0.01:
		flat = Vector3(0.0, 0.0, 1.0)
	_charge_direction = flat.normalized()
	rotation.y = atan2(_charge_direction.x, _charge_direction.z)
	_state = State.CHARGE
	_timer = 1.3
	_charge_light.light_energy = 2.4
	_play("res://sounds/dash.ogg")


# --- Shockwave rings ---------------------------------------------------------

## A ring starts on the Warden and sweeps outward across the floor. [param delay]
## is negative to hold it back, which is how the later phases stack waves.
func _spawn_ring(delay: float) -> void:
	var mesh := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.89
	torus.outer_radius = 1.0
	torus.rings = 40
	torus.ring_segments = 6
	mesh.mesh = torus
	var material := StandardMaterial3D.new()
	material.albedo_color = RUNE_COLOR
	material.emission_enabled = true
	material.emission = RUNE_COLOR
	material.emission_energy_multiplier = 2.2
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = material
	mesh.position = Vector3(home.x, home.y - 0.35, home.z)
	mesh.scale = Vector3(0.6, 1.0, 0.6)
	get_parent().add_child(mesh)
	_rings.append({"node": mesh, "radius": 0.6, "delay": delay, "hit": {}})


func _update_rings(delta: float) -> void:
	if _rings.is_empty():
		return
	var done: Array = []
	for ring in _rings:
		var node: Node3D = ring["node"]
		if not is_instance_valid(node):
			done.append(ring)
			continue
		if float(ring["delay"]) > 0.0:
			ring["delay"] = float(ring["delay"]) - delta
			continue
		var radius := float(ring["radius"]) + ring_speed * delta
		ring["radius"] = radius
		node.scale = Vector3(radius, 1.0, radius)
		var material := node.material_override as StandardMaterial3D
		material.albedo_color.a = clampf(1.0 - radius / (arena_radius + 3.0), 0.0, 1.0)
		_check_ring_hit(ring, radius)
		if radius > arena_radius + 3.0:
			node.queue_free()
			done.append(ring)
	for entry in done:
		_rings.erase(entry)


## A ring only catches a player who is low when it passes: jumping clears it,
## which is the whole point of the attack. The bar is set at 0.75 above the floor
## because a player standing has their centre 0.55 up and a jump lifts it 1.20 -
## so standing is never safe and a jump gives a third of a second of clearance.
func _check_ring_hit(ring: Dictionary, radius: float) -> void:
	var centre := Vector3(home.x, home.y, home.z)
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Node3D
		if player == null or bool(player.get("is_dead")) or not player.has_method("take_damage"):
			continue
		if ring["hit"].has(player):
			continue
		var offset := player.global_position - centre
		var flat := Vector2(offset.x, offset.z).length()
		if absf(flat - radius) <= 0.75 and offset.y < RING_CLEARANCE:
			ring["hit"][player] = true
			player.call("take_damage", contact_damage, centre)


func _clear_rings() -> void:
	for ring in _rings:
		var node: Node3D = ring["node"]
		if is_instance_valid(node):
			node.queue_free()
	_rings.clear()


# --- Movement ----------------------------------------------------------------

func _move(delta: float) -> void:
	var airborne := not is_on_floor()
	if airborne:
		velocity.y -= GRAVITY * delta
	else:
		if velocity.y < 0.0:
			velocity.y = 0.0
		var flat := Vector3.ZERO
		if _state == State.CHARGE:
			flat = _charge_direction * charge_speed
		elif _state == State.IDLE and shielded:
			# In its guard it edges towards the player instead of standing still.
			var target := _nearest_player()
			if target != null:
				var toward := target.global_position - global_position
				toward.y = 0.0
				if toward.length() > 2.6:
					flat = toward.normalized() * 1.5
		# It never wanders far from where it belongs.
		var from_home := global_position - home
		from_home.y = 0.0
		if from_home.length() > arena_radius and flat.dot(from_home) > 0.0:
			flat = Vector3.ZERO
		velocity.x = flat.x
		velocity.z = flat.z
	move_and_slide()


func _animate(delta: float) -> void:
	if _visual == null:
		return
	_bob += delta * 1.6
	_squash = lerpf(_squash, 0.0, delta * 6.0)
	_visual.scale = Vector3(1.0 + _squash * 0.25, 1.0 - _squash * 0.3, 1.0 + _squash * 0.25)
	if _state == State.TELEGRAPH:
		_visual.position.y = sin(_bob * 8.0) * 0.06
	elif _state == State.CHARGE:
		_visual.position.y = -0.1
	else:
		_visual.position.y = sin(_bob) * 0.05
	if _shield_mesh != null and _shield_mesh.visible:
		_shield_mesh.scale = Vector3.ONE * (1.0 + sin(_bob * 3.0) * 0.03)
	if _charge_light != null and _state == State.TELEGRAPH and _attack_is_sweep:
		_charge_light.light_energy = 1.0 + sin(_bob * 14.0) * 0.5


func _apply_flash() -> void:
	if _body_material == null:
		return
	_body_material.albedo_color = Color(1, 1, 1) if _hit_flash > 0.0 else BODY_COLOR


func _face(spot: Vector3, weight: float) -> void:
	var flat := spot - global_position
	flat.y = 0.0
	if flat.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.z), clampf(weight, 0.0, 1.0))


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


func _touch_check() -> void:
	if _touch_cooldown > 0.0:
		return
	var target := _nearest_player()
	if target == null:
		return
	if global_position.distance_to(target.global_position) < touch_range:
		target.call("take_damage", contact_damage, global_position)
		_touch_cooldown = 1.0


# --- Health, phases and the guard -------------------------------------------

## A slash only lands while the guard is down. Returns true when the hit landed,
## which is what lets the player's down-slash bounce off it.
func take_hit(amount: int, from: Vector3) -> bool:
	if _state == State.DEAD or _state == State.DORMANT:
		return false
	if shielded:
		if _refuse_cooldown <= 0.0:
			_refuse_cooldown = 2.0
			_say("The Warden's guard holds - break its summoned slimes first.")
			_play("res://sounds/land.ogg")
		return false
	health -= amount
	_hit_flash = 0.2
	_burst(5, BODY_COLOR, 3.0)
	Audio.play("res://sounds/break.ogg")
	var away := global_position - from
	away.y = 0.0
	if away.length_squared() > 0.001:
		global_position += away.normalized() * 0.15
	if health <= 0:
		health_changed.emit(0, max_health, phase)
		_die()
		return true
	_check_phase()
	health_changed.emit(health, max_health, phase)
	return true


func _check_phase() -> void:
	var ratio := float(health) / float(max_health)
	var wanted := 1
	if ratio <= 0.34:
		wanted = 3
	elif ratio <= 0.67:
		wanted = 2
	if wanted <= phase:
		return
	# Never skip the guard: the last phase always starts by raising its shield.
	phase = wanted
	phase_reached.emit(phase, phase_name())
	_say("THE WARDEN - PHASE %d: %s" % [phase, phase_name()])
	if phase >= 3 and not _phase_three_done:
		_raise_guard()


func _raise_guard() -> void:
	_phase_three_done = true
	shielded = true
	_clear_rings()
	if _shield_mesh != null:
		_shield_mesh.visible = true
	for side in [-1.0, 1.0]:
		var slime: ShadowSlime = SLIME.new()
		slime.name = "WardenSummon_%d" % (1 if side < 0.0 else 2)
		slime.patrol_radius = 3.2
		if "detect_range" in slime:
			slime.set("detect_range", 12.0)
		get_parent().add_child(slime)
		slime.place_at(home + Vector3(2.8 * side, 0.0, -1.6))
		slime.defeated.connect(_on_summon_defeated)
		_summons.append(slime)
		_summon_watchers += 1
	_say("The Warden raises its guard and calls the shadows it kept: break both slimes to reach it.")


func _on_summon_defeated() -> void:
	_summon_watchers = maxi(_summon_watchers - 1, 0)
	if not shielded:
		return
	if _summon_watchers > 0:
		_say("One shadow falls.  One still holds the guard.")
		return
	shielded = false
	if _shield_mesh != null:
		_shield_mesh.visible = false
	_say("The guard shatters - the Warden is open!")
	Audio.play("res://sounds/break.ogg")


func _die() -> void:
	_state = State.DEAD
	is_defeated = true
	shielded = false
	if _shield_mesh != null:
		_shield_mesh.visible = false
	_clear_rings()
	_burst(28, BODY_COLOR, 7.0)
	_burst(14, RUNE_COLOR, 5.0)
	Audio.play("res://sounds/break.ogg")
	defeated.emit()
	if _island != null and _island.has_method("warden_defeated"):
		_island.call("warden_defeated")
	# The body stays a moment, then sinks away.
	var tween := create_tween()
	tween.tween_property(_visual, "position:y", -3.0, 2.2)
	tween.tween_callback(queue_free)


## Full health, back to its spot, guard down, summons gone, waves cleared. The
## level calls this whenever a player respawns, so the fight starts clean.
func reset_to_home() -> void:
	if _state == State.DEAD:
		return
	_clear_rings()
	for slime in _summons:
		if is_instance_valid(slime):
			slime.queue_free()
	_summons.clear()
	_summon_watchers = 0
	global_position = home
	velocity = Vector3.ZERO
	health = max_health
	phase = 1
	shielded = false
	_phase_three_done = false
	_state = State.DORMANT
	_timer = 0.0
	_idle_wait = 1.4
	_attack_is_sweep = false
	if _shield_mesh != null:
		_shield_mesh.visible = false
	if _charge_light != null:
		_charge_light.light_energy = 0.0
	rotation.y = PI
	health_changed.emit(health, max_health, phase)


## Wake it up now, without waiting for a player to walk in. The dev checks use
## this; the arena itself is woken by a player arriving.
func begin_fight() -> void:
	if _state == State.DORMANT:
		_state = State.WAKE
		_timer = 1.3
		_say("THE WARDEN RISES - the corruption will not release its guardian.")
		woke.emit()


func _say(text: String) -> void:
	if _island != null:
		_island.message.emit(text)


## Play a sound, falling back to the island's landing thud if it is not there.
func _play(path: String) -> void:
	Audio.play(path if ResourceLoader.exists(path) else "res://sounds/land.ogg")


## A one-shot puff of squares, parented to the world so it outlives this node.
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
	quad.size = Vector2(0.2, 0.2)
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0, 1, 0)
	process.spread = 180.0
	process.initial_velocity_min = speed * 0.5
	process.initial_velocity_max = speed
	process.gravity = Vector3(0, 1.5, 0)
	process.damping_min = 2.0
	process.damping_max = 3.0
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = 0.9
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.draw_pass_1 = quad
	particles.material_override = material
	particles.process_material = process
	particles.position = global_position + Vector3(0.0, 1.6, 0.0)
	parent.add_child(particles)
	particles.emitting = true
	var timer := get_tree().create_timer(1.5)
	timer.timeout.connect(func():
		if is_instance_valid(particles):
			particles.queue_free()
	)
