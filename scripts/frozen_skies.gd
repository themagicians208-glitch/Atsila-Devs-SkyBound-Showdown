extends Node3D
class_name FrozenSkies

const PLATFORM := preload("res://objects/platform_medium.tscn")
const COIN := preload("res://objects/coin.tscn")
const FROZEN_ENEMY := preload("res://objects/frozen_enemy.gd")
const FROST_TITAN := preload("res://objects/frost_titan.gd")

@export var coins_required := 50
var route: Array = []
var coins_placed := 0
var boss_defeated := false
var fragment_recovered := false
var _world: Node3D
var _main: Node

func build(main: Node) -> Array:
	_main = main
	_world = main.get("world")
	route = _make_route()
	_build_islands()
	_place_coins()
	_place_enemies()
	return route

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
	titan.defeated.connect(_on_boss_defeated)
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
	fragment_recovered = true

func is_portal_ready(coins: int) -> bool:
	return boss_defeated and Progress.third_fragment_recovered and coins >= coins_required

func portal_blocked_reason(coins: int) -> String:
	if not boss_defeated:
		return "Defeat the Frost Titan to unlock the portal."
	if not Progress.third_fragment_recovered:
		return "Recover the Third Fragment of the Eternal Tree."
	return "%d more coins are needed to unlock the portal." % maxi(0, coins_required - coins)

