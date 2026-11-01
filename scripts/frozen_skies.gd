extends Node3D
class_name FrozenSkies

const PLATFORM := preload("res://objects/platform_medium.tscn")
const COIN := preload("res://objects/coin.tscn")
const FROZEN_ENEMY := preload("res://objects/frozen_enemy.gd")
const FROST_TITAN := preload("res://objects/frost_titan.gd")
const FRAGMENT_CHEST := preload("res://objects/frozen_fragment_chest.gd")
const FROZEN_MECHANISM := preload("res://objects/frozen_mechanism.gd")
const UNSTABLE_ICE := preload("res://objects/unstable_ice_platform.gd")
const CRYSTAL_LIGHT := preload("res://objects/crystal_light_puzzle.gd")
const PUZZLE_GATE := preload("res://objects/puzzle_gate.gd")
const SLIPPERY := preload("res://scripts/slippery_zone.gd")

@export var coins_required := 50
var route: Array = []
var region_names := [
	"Frozen Arrival",
	"Crystal Snowfields",
	"Slippery Ice Valley",
	"Frozen Crystal Caves",
	"The Shattered Ice Fortress",
	"Frost Titan's Sanctuary",
]
var coins_placed := 0
var boss_defeated := false
var fragment_recovered := false
var _world: Node3D
var _main: Node
var _chest: FrozenFragmentChest
var _titan: FrostTitan
var mechanisms: Array[FrozenMechanism] = []
var frozen_seals_complete := false
var _moving_platforms: Array[Node3D] = []
var _time := 0.0
var _crystal_light: Node3D
var _ice_bridges: Array[StaticBody3D] = []
var _snowfall: GPUParticles3D
var _frozen_tree_materials: Array[StandardMaterial3D] = []
var environment_thawed := false
var _crystal_gate: StaticBody3D
var _boss_gate: StaticBody3D
var boss_arena_locked := false
var _exit_portal_ring: MeshInstance3D
var _exit_portal_material: StandardMaterial3D
var _portal_energy := 0.0
var portal_count := 0

func build(main: Node) -> Array:
	_main = main
	_world = main.get("world")
	route = _make_route()
	_build_islands()
	_build_frozen_mechanics()
	_build_boss_arena()
	_build_snowfall()
	_place_coins()
	_place_enemies()
	_build_moving_ice_platforms()
	_build_unstable_ice()
	_build_crystal_light_puzzle()
	_build_crystal_gate()
	if Progress.third_fragment_recovered:
		thaw_environment()
	return route

func _build_crystal_light_puzzle() -> void:
	_crystal_light = CRYSTAL_LIGHT.new()
	_crystal_light.name = "CrystalLightPuzzle"
	_crystal_light.position = route[18] + Vector3(0.0, 0.65, 1.8)
	_world.add_child(_crystal_light)
	_crystal_light.solved.connect(func():
		if _crystal_gate != null:
			_crystal_gate.open()
		if _main.has_method("_on_frozen_crystal_light_solved"):
			_main.call("_on_frozen_crystal_light_solved")
	)

func _build_crystal_gate() -> void:
	_crystal_gate = StaticBody3D.new()
	_crystal_gate.name = "CrystalLightGate"
	_crystal_gate.set_script(PUZZLE_GATE)
	var from_point: Vector3 = route[18]
	var to_point: Vector3 = route[19]
	_crystal_gate.position = (from_point + to_point) * 0.5 + Vector3(0.0, 1.5, 0.0)
	var direction := to_point - from_point
	direction.y = 0.0
	_crystal_gate.rotation.y = atan2(direction.x, direction.z)
	var size := Vector3(3.5, 2.2, 0.3)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	_crystal_gate.add_child(shape)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = _material(Color("#62e8ff"), 1.4)
	_crystal_gate.add_child(visual)
	_world.add_child(_crystal_gate)

func region_name_for_checkpoint(checkpoint_index: int) -> String:
	var region_index := 0
	if checkpoint_index >= 38:
		region_index = 5
	elif checkpoint_index >= 29:
		region_index = 4
	elif checkpoint_index >= 18:
		region_index = 3
	elif checkpoint_index >= 9:
		region_index = 1
	return region_names[region_index]

func _process(delta: float) -> void:
	_time += delta
	if _exit_portal_ring != null and _main != null:
		var current_coins := int(_main.get("coins_collected"))
		var target_energy := 1.0 if is_portal_ready(current_coins) else 0.0
		_portal_energy = move_toward(_portal_energy, target_energy, delta * 0.8)
		_exit_portal_ring.rotate_y(delta * (0.45 + _portal_energy * 1.4))
		_exit_portal_material.emission_energy_multiplier = 0.35 + _portal_energy * 1.8
	for index in _moving_platforms.size():
		var platform := _moving_platforms[index]
		if not is_instance_valid(platform):
			continue
		var origin: Vector3 = platform.get_meta("origin")
		var phase: float = platform.get_meta("phase")
		platform.position = origin + Vector3(sin(_time * 1.1 + phase) * 1.8, sin(_time * 1.7 + phase) * 0.35, 0.0)

func _build_moving_ice_platforms() -> void:
	for entry in [[14, -1.4], [17, 1.2], [26, -1.6], [33, 1.5], [37, -1.0]]:
		var platform: Node3D = PLATFORM.instantiate()
		platform.name = "MovingIcePlatform_%02d" % int(entry[0])
		var origin: Vector3 = route[int(entry[0])] + Vector3(float(entry[1]), 1.0, 1.4)
		platform.position = origin
		platform.scale = Vector3(0.72, 0.42, 0.72)
		platform.set_meta("origin", origin)
		platform.set_meta("phase", float(entry[0]) * 0.6)
		_world.add_child(platform)
		_moving_platforms.append(platform)
		_add_ice_cap(origin)

func _build_unstable_ice() -> void:
	for index in [23, 25, 27, 29]:
		var platform: Node3D = UNSTABLE_ICE.new()
		platform.name = "UnstableIce_%02d" % index
		platform.position = route[index] + Vector3(0.0, 0.65, 1.5)
		_world.add_child(platform)

func _build_frozen_mechanics() -> void:
	# Reuse the main level's switch/gate implementation for the first frozen seal.
	_main.call("_build_puzzle", 3, route)
	for index in [10, 20, 30]:
		_main.call("_add_zone", route[index], Vector3(2.5, 1.2, 2.5), SLIPPERY, Color("#8fe7ff"))
		_add_ice_bridge(route[index])
	if Progress.frozen_seals_activated > 0:
		for bridge in _ice_bridges:
			_open_ice_bridge(bridge)
	for entry in [["Frozen Switch", 5], ["Crystal Generator", 18], ["Frozen Seal", 31]]:
		var mechanism: FrozenMechanism = FROZEN_MECHANISM.new()
		mechanism.name = str(entry[0]).replace(" ", "")
		mechanism.mechanism_name = str(entry[0])
		mechanism.position = route[int(entry[1])] + Vector3(0.0, 0.55, 1.25)
		_world.add_child(mechanism)
		mechanisms.append(mechanism)
		mechanism.activated.connect(_on_mechanism_activated.bind(mechanism))
	for index in range(mini(Progress.frozen_seals_activated, mechanisms.size())):
		mechanisms[index].activate()
	frozen_seals_complete = Progress.frozen_seals_activated >= mechanisms.size()

func try_activate_nearby(player: Node3D) -> bool:
	if _crystal_light != null and _crystal_light.try_interact(player):
		return true
	for index in mechanisms.size():
		var mechanism := mechanisms[index]
		if not mechanism.is_activated and mechanism.global_position.distance_to(player.global_position) <= 2.4:
			if index == 1 and not Progress.crystal_light_solved:
				if _main.has_method("_on_frozen_mechanism_blocked"):
					_main.call("_on_frozen_mechanism_blocked", "Align the crystal light first.")
				return true
			if index > 0 and not mechanisms[index - 1].is_activated:
				if _main.has_method("_on_frozen_mechanism_blocked"):
					_main.call("_on_frozen_mechanism_blocked", "Activate the previous frozen seal first.")
				return true
			return mechanism.activate()
	return false

func _on_mechanism_activated(_mechanism: FrozenMechanism) -> void:
	var activated_count := 0
	for mechanism in mechanisms:
		if mechanism.is_activated:
			activated_count += 1
	Progress.set_frozen_seals_activated(activated_count)
	if activated_count == 1:
		Progress.unlock_ice_shield()
		if not _ice_bridges.is_empty():
			_open_ice_bridge(_ice_bridges[0])
	if activated_count == 2:
		Progress.unlock_frost_dash()
	if activated_count == 3:
		Progress.unlock_crystal_activation()
		frozen_seals_complete = true
		if _titan != null:
			_titan.unlock()
		_lock_boss_arena()
	if _main.has_method("_on_frozen_mechanism_progress"):
		_main.call("_on_frozen_mechanism_progress", activated_count, mechanisms.size())

func _add_ice_bridge(point: Vector3) -> void:
	var bridge := StaticBody3D.new()
	bridge.name = "IceBridge"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(3.4, 0.12, 1.0)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = _material(Color("#a8efff"), 0.8)
	bridge.add_child(visual)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = mesh.size
	shape.shape = box
	bridge.add_child(shape)
	bridge.position = point + Vector3(0.0, 0.58, 1.8)
	_world.add_child(bridge)
	_ice_bridges.append(bridge)
	if _ice_bridges.size() == 1 and Progress.frozen_seals_activated < 1:
		shape.set_deferred("disabled", true)
		visual.visible = false

func _open_ice_bridge(bridge: StaticBody3D) -> void:
	if not is_instance_valid(bridge):
		return
	for shape in bridge.find_children("*", "CollisionShape3D", true, false):
		(shape as CollisionShape3D).disabled = false
	for visual in bridge.find_children("*", "MeshInstance3D", true, false):
		(visual as MeshInstance3D).visible = true

func _make_route() -> Array:
	var points: Array = []
	for index in 42:
		var region := index / 7
		var local := index % 7
		var x := sin(float(index) * 0.78) * (2.4 + region * 0.35)
		var z := float(index) * 3.2
		var y := float(region) * 0.65 + float(local % 3) * 0.18
		points.append(Vector3(x, y, z))
	return points

func _build_islands() -> void:
	for index in route.size():
		var platform: Node3D = PLATFORM.instantiate()
		platform.name = "FrozenPlatform_%02d" % index
		platform.position = route[index]
		platform.scale = Vector3(1.18, 0.7, 1.18)
		_world.add_child(platform)
		_add_ice_cap(route[index])
		if index % 4 == 0:
			_add_crystals(route[index], 0.55 + float(index % 3) * 0.15)
		if index % 7 == 0:
			_add_frozen_tree(route[index] + Vector3(1.0, 0.0, 0.6))
	for region in 6:
		_add_mountain(Vector3(-7.0 + region * 2.8, 2.0 + region * 0.6, region * 22.0))
	_add_portal(route[0] + Vector3(0.0, 0.0, -2.3), Color("#72dfff"))
	_add_portal(route[route.size() - 1] + Vector3(0.0, 0.0, 1.8), Color("#c4f3ff"), true)

func _place_coins() -> void:
	for index in range(1, route.size() - 1):
		_add_coin(route[index] + Vector3(0.0, 1.05 + float(index % 3) * 0.25, 0.0), "frozen_%02d" % index)
		coins_placed += 1
	for hidden_index in [3, 5, 8, 12, 14, 19, 21, 27, 28, 34, 35, 39]:
		_add_coin(route[hidden_index] + Vector3(2.3, 1.6, 0.8), "frozen_hidden_%02d" % hidden_index)
		coins_placed += 1

func _add_coin(where: Vector3, persistent_id: String) -> void:
	var coin: Area3D = COIN.instantiate()
	coin.position = where
	coin.set_meta("persistent_coin_id", persistent_id)
	_world.add_child(coin)

func _place_enemies() -> void:
	for index in [6, 15, 24, 31]:
		_spawn_enemy("Frost Slime", route[index] + Vector3(0.0, 1.0, 0.0))
	for index in [11, 22, 30]:
		_spawn_enemy("Frost Wolf", route[index] + Vector3(0.0, 1.0, 0.0))
	for index in [18, 28, 36]:
		_spawn_enemy("Crystal Phantom", route[index] + Vector3(0.0, 3.0, 0.0))
	_titan = FROST_TITAN.new()
	_titan.name = "FrostTitan"
	_titan.position = route[route.size() - 3] + Vector3(0.0, 2.2, 3.0)
	_world.add_child(_titan)
	_chest = FRAGMENT_CHEST.new()
	_chest.name = "ThirdFragmentChest"
	_chest.position = route[route.size() - 3] + Vector3(2.5, 0.0, 2.5)
	_world.add_child(_chest)
	_titan.defeated.connect(_on_boss_defeated)
	if Progress.frost_titan_defeated:
		boss_defeated = true
	if frozen_seals_complete or boss_defeated:
		_titan.unlock()
	if frozen_seals_complete and not boss_defeated:
		_lock_boss_arena()
	if boss_defeated:
		_titan.set_process(false)
		_titan.set_physics_process(false)
		_chest.unlock()
		_unlock_boss_arena()
	_chest.fragment_recovered.connect(func():
		if _main.has_method("_on_frozen_fragment_recovered"):
			_main.call("_on_frozen_fragment_recovered")
	)
	if _main.has_method("_bind_frozen_boss"):
		_main.call("_bind_frozen_boss", _titan)

func _spawn_enemy(kind: String, where: Vector3) -> void:
	var enemy: FrozenEnemy = FROZEN_ENEMY.new()
	enemy.variant = kind
	enemy.name = kind.replace(" ", "")
	enemy.position = where
	_world.add_child(enemy)

func _add_ice_cap(point: Vector3) -> void:
	var cap := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.8, 0.08, 2.8)
	cap.mesh = mesh
	cap.position = point + Vector3(0.0, 0.48, 0.0)
	cap.material_override = _material(Color("#dffaff"), 0.35)
	_world.add_child(cap)

func _add_crystals(point: Vector3, scale: float) -> void:
	for side in [-1.0, 1.0]:
		var crystal := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.0
		mesh.bottom_radius = 0.22 * scale
		mesh.height = 1.2 * scale
		crystal.mesh = mesh
		crystal.position = point + Vector3(side * 0.8, 0.7 * scale, 0.4)
		crystal.rotation.z = side * 0.25
		crystal.material_override = _material(Color("#65e6ff"), 1.0)
		_world.add_child(crystal)

func _add_frozen_tree(point: Vector3) -> void:
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.22
	trunk_mesh.bottom_radius = 0.35
	trunk_mesh.height = 2.4
	trunk.mesh = trunk_mesh
	trunk.position = point + Vector3(0.0, 1.2, 0.0)
	trunk.material_override = _material(Color("#d9edff"), 0.2)
	_world.add_child(trunk)
	for height in [2.0, 2.55, 3.0]:
		var crown := MeshInstance3D.new()
		var crown_mesh := SphereMesh.new()
		crown_mesh.radius = 0.9 - (height - 2.0) * 0.2
		crown_mesh.height = crown_mesh.radius * 1.8
		crown.mesh = crown_mesh
		crown.position = point + Vector3(0.0, height, 0.0)
		var crown_material := _material(Color("#b9efff"), 0.3)
		crown.material_override = crown_material
		_frozen_tree_materials.append(crown_material)
		_world.add_child(crown)

func _add_mountain(point: Vector3) -> void:
	var mountain := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.3
	mesh.bottom_radius = 4.2
	mesh.height = 6.0
	mountain.mesh = mesh
	mountain.position = point
	mountain.material_override = _material(Color("#8bc9ed"), 0.15)
	_world.add_child(mountain)

func _add_portal(point: Vector3, color: Color, is_exit := false) -> void:
	portal_count += 1
	var portal := Node3D.new()
	portal.name = "FrozenPortal"
	portal.position = point + Vector3(0.0, 1.4, 0.0)
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.95
	ring_mesh.outer_radius = 1.12
	ring.mesh = ring_mesh
	ring.rotation.x = PI * 0.5
	var ring_material := _material(color, 1.2)
	ring.material_override = ring_material
	if is_exit:
		_exit_portal_ring = ring
		_exit_portal_material = ring_material
	portal.add_child(ring)
	var surface := MeshInstance3D.new()
	var surface_mesh := QuadMesh.new()
	surface_mesh.size = Vector2(1.9, 2.8)
	surface.mesh = surface_mesh
	surface.rotation.x = PI * 0.5
	surface.material_override = _material(Color(color, 0.18), 0.7)
	portal.add_child(surface)
	_world.add_child(portal)

func _build_snowfall() -> void:
	var particles := GPUParticles3D.new()
	_snowfall = particles
	particles.name = "FrozenSnowfall"
	particles.amount = 180
	particles.lifetime = 5.0
	particles.visibility_aabb = AABB(Vector3(-18.0, -2.0, -4.0), Vector3(36.0, 16.0, 140.0))
	var flake := QuadMesh.new()
	flake.size = Vector2(0.08, 0.08)
	particles.draw_pass_1 = flake
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#effcff")
	material.emission_enabled = true
	material.emission = Color("#dffaff")
	flake.material = material
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.1, -1.0, 0.0)
	process.spread = 12.0
	process.initial_velocity_min = 1.0
	process.initial_velocity_max = 2.4
	process.gravity = Vector3(0.0, -0.2, 0.0)
	process.scale_min = 0.5
	process.scale_max = 1.4
	particles.process_material = process
	particles.position = Vector3(0.0, 9.0, 55.0)
	_world.add_child(particles)

func _build_boss_arena() -> void:
	var centre: Vector3 = route[route.size() - 3] + Vector3(0.0, 0.0, 3.0)
	for i in 8:
		var angle := TAU * float(i) / 8.0
		var pillar := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.25
		mesh.bottom_radius = 0.55
		mesh.height = 3.6
		pillar.mesh = mesh
		pillar.position = centre + Vector3(cos(angle) * 5.0, 1.8, sin(angle) * 5.0)
		pillar.material_override = _material(Color("#b8eaff"), 0.55)
		_world.add_child(pillar)
	var sigil := MeshInstance3D.new()
	var sigil_mesh := TorusMesh.new()
	sigil_mesh.inner_radius = 2.6
	sigil_mesh.outer_radius = 2.75
	sigil.mesh = sigil_mesh
	sigil.position = centre + Vector3(0.0, 0.08, 0.0)
	sigil.material_override = _material(Color("#8cddff"), 1.0)
	_world.add_child(sigil)
	_boss_gate = StaticBody3D.new()
	_boss_gate.name = "FrostTitanArenaGate"
	_boss_gate.position = route[route.size() - 4] + Vector3(0.0, 1.3, 1.4)
	var gate_shape := CollisionShape3D.new()
	var gate_box := BoxShape3D.new()
	gate_box.size = Vector3(3.8, 2.5, 0.3)
	gate_shape.shape = gate_box
	_boss_gate.add_child(gate_shape)
	var gate_visual := MeshInstance3D.new()
	var gate_mesh := BoxMesh.new()
	gate_mesh.size = gate_box.size
	gate_visual.mesh = gate_mesh
	gate_visual.material_override = _material(Color("#89eaff"), 1.0)
	_boss_gate.add_child(gate_visual)
	_world.add_child(_boss_gate)

func _lock_boss_arena() -> void:
	if boss_arena_locked or _boss_gate == null:
		return
	boss_arena_locked = true
	for shape in _boss_gate.find_children("*", "CollisionShape3D", true, false):
		(shape as CollisionShape3D).set_deferred("disabled", false)

func _unlock_boss_arena() -> void:
	if _boss_gate == null:
		return
	boss_arena_locked = false
	for shape in _boss_gate.find_children("*", "CollisionShape3D", true, false):
		(shape as CollisionShape3D).set_deferred("disabled", true)
	var tween := _boss_gate.create_tween()
	tween.tween_property(_boss_gate, "position:y", _boss_gate.position.y - 2.5, 0.7)

func _material(color: Color, emission: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.32
	material.emission_enabled = emission > 0.0
	material.emission = color
	material.emission_energy_multiplier = emission
	return material

func _on_boss_defeated() -> void:
	boss_defeated = true
	Progress.mark_frost_titan_defeated()
	_unlock_boss_arena()
	if _chest != null:
		_chest.unlock()

func thaw_environment() -> void:
	if environment_thawed:
		return
	environment_thawed = true
	for material in _frozen_tree_materials:
		material.albedo_color = Color("#8de6b0")
		material.emission = Color("#5de69a")
		material.emission_energy_multiplier = 0.8
	if _snowfall != null:
		_snowfall.amount = 45
	Audio.play("res://sounds/coin.ogg")

func is_portal_ready(coins: int) -> bool:
	return boss_defeated and Progress.third_fragment_recovered and coins >= coins_required

func portal_blocked_reason(coins: int) -> String:
	if not boss_defeated:
		return "Defeat the Frost Titan to unlock the portal."
	if not Progress.third_fragment_recovered:
		return "Recover the Third Fragment of the Eternal Tree."
	return "%d more coins are needed to unlock the portal." % maxi(0, coins_required - coins)

