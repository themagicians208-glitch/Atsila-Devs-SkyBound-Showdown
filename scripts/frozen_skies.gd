extends Node3D
class_name FrozenSkies

const PLATFORM := preload("res://objects/platform_medium.tscn")
const COIN := preload("res://objects/coin.tscn")
const FROZEN_ENEMY := preload("res://objects/frozen_enemy.gd")
const FROST_TITAN := preload("res://objects/frost_titan.gd")
const FRAGMENT_CHEST := preload("res://objects/frozen_fragment_chest.gd")
const SLIPPERY := preload("res://scripts/slippery_zone.gd")

@export var coins_required := 50
var route: Array = []
var coins_placed := 0
var boss_defeated := false
var fragment_recovered := false
var _world: Node3D
var _main: Node
var _chest: FrozenFragmentChest

func build(main: Node) -> Array:
	_main = main
	_world = main.get("world")
	route = _make_route()
	_build_islands()
	_build_frozen_mechanics()
	_build_boss_arena()
	_place_coins()
	_place_enemies()
	return route

func _build_frozen_mechanics() -> void:
	# Reuse the main level's switch/gate implementation for the first frozen seal.
	_main.call("_build_puzzle", 3, route)
	for index in [10, 20, 30]:
		_main.call("_add_zone", route[index], Vector3(2.5, 1.2, 2.5), SLIPPERY, Color("#8fe7ff"))
		_add_ice_bridge(route[index])

func _add_ice_bridge(point: Vector3) -> void:
	var bridge := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(3.4, 0.12, 1.0)
	bridge.mesh = mesh
	bridge.position = point + Vector3(0.0, 0.58, 1.8)
	bridge.material_override = _material(Color("#a8efff"), 0.8)
	_world.add_child(bridge)

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
	_add_portal(route[route.size() - 1] + Vector3(0.0, 0.0, 1.8), Color("#c4f3ff"))

func _place_coins() -> void:
	for index in range(1, route.size() - 1):
		var coin: Area3D = COIN.instantiate()
		coin.position = route[index] + Vector3(0.0, 1.05 + float(index % 3) * 0.25, 0.0)
		_world.add_child(coin)
		coins_placed += 1
	for index in [3, 5, 8, 12, 14, 19, 21, 27, 28, 34, 35, 39]:
		var hidden: Area3D = COIN.instantiate()
		hidden.position = route[index] + Vector3(2.3, 1.6, 0.8)
		_world.add_child(hidden)
		coins_placed += 1

func _place_enemies() -> void:
	for index in [6, 15, 24, 31]:
		_spawn_enemy("Frost Slime", route[index] + Vector3(0.0, 1.0, 0.0))
	for index in [11, 22, 30]:
		_spawn_enemy("Frost Wolf", route[index] + Vector3(0.0, 1.0, 0.0))
	for index in [18, 28, 36]:
		_spawn_enemy("Crystal Phantom", route[index] + Vector3(0.0, 3.0, 0.0))
	var titan: Node3D = FROST_TITAN.new()
	titan.name = "FrostTitan"
	titan.position = route[route.size() - 3] + Vector3(0.0, 2.2, 3.0)
	_world.add_child(titan)
	_chest = FRAGMENT_CHEST.new()
	_chest.name = "ThirdFragmentChest"
	_chest.position = route[route.size() - 3] + Vector3(2.5, 0.0, 2.5)
	_world.add_child(_chest)
	titan.defeated.connect(_on_boss_defeated)
	_chest.fragment_recovered.connect(func():
		if _main.has_method("_on_frozen_fragment_recovered"):
			_main.call("_on_frozen_fragment_recovered")
	)
	if _main.has_method("_bind_frozen_boss"):
		_main.call("_bind_frozen_boss", titan)

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
		crown.material_override = _material(Color("#b9efff"), 0.3)
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

func _add_portal(point: Vector3, color: Color) -> void:
	var portal := Node3D.new()
	portal.name = "FrozenPortal"
	portal.position = point + Vector3(0.0, 1.4, 0.0)
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.95
	ring_mesh.outer_radius = 1.12
	ring.mesh = ring_mesh
	ring.rotation.x = PI * 0.5
	ring.material_override = _material(color, 1.2)
	portal.add_child(ring)
	var surface := MeshInstance3D.new()
	var surface_mesh := QuadMesh.new()
	surface_mesh.size = Vector2(1.9, 2.8)
	surface.mesh = surface_mesh
	surface.rotation.x = PI * 0.5
	surface.material_override = _material(Color(color, 0.18), 0.7)
	portal.add_child(surface)
	_world.add_child(portal)

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
	if _chest != null:
		_chest.unlock()

func is_portal_ready(coins: int) -> bool:
	return boss_defeated and Progress.third_fragment_recovered and coins >= coins_required

func portal_blocked_reason(coins: int) -> String:
	if not boss_defeated:
		return "Defeat the Frost Titan to unlock the portal."
	if not Progress.third_fragment_recovered:
		return "Recover the Third Fragment of the Eternal Tree."
	return "%d more coins are needed to unlock the portal." % maxi(0, coins_required - coins)

