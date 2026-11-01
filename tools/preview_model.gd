extends Node3D

@export var model_path := "res://models/racoon.glb"
@export var target_height := 1.0


func _ready() -> void:
	# Normalise once so every copy is the same size with feet at y = 0.
	var probe: Node3D = load(model_path).instantiate()
	add_child(probe)
	var aabb := _aabb(probe)
	var s := target_height / maxf(aabb.size.y, 0.0001)
	var center := aabb.get_center()
	var offset := Vector3(-center.x * s, -aabb.position.y * s, -center.z * s)
	probe.queue_free()
	print("scale=", s, " offset=", offset)

	# Four copies side by side, viewed from +Z: 0, 90, 180, 270 degrees.
	var angles := [0.0, 90.0, 180.0, 270.0]
	var x := -2.7
	for a in angles:
		var holder := Node3D.new()
		holder.position = Vector3(x, 0, 0)
		holder.rotation_degrees = Vector3(0, a, 0)
		add_child(holder)
		var model: Node3D = load(model_path).instantiate()
		model.scale = Vector3.ONE * s
		model.position = offset
		holder.add_child(model)
		x += 1.8

	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.75, 3.4)
	cam.rotation_degrees = Vector3(-3, 0, 0)
	cam.current = true
	add_child(cam)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -35, 0)
	add_child(light)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.45, 0.62, 0.86)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)


func _aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var world: AABB = mi.global_transform * mi.get_aabb()
		if first:
			result = world
			first = false
		else:
			result = result.merge(world)
	return result