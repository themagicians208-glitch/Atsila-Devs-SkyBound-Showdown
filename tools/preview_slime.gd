extends Node3D

## Close look at two Shadow Slimes on a plain floor, so the jelly body, the
## glowing eyes and the squash-and-stretch can be judged without the island's
## clutter. Two of them hop on their own; the camera waits long enough to catch
## at least one mid-bounce.
##
## Run: godot --path . tools/capture_shots.tscn -- res://tools/preview_slime.tscn

const SLIME := preload("res://objects/shadow_slime.gd")


func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(14.0, 0.5, 14.0)
	shape.shape = box
	floor_body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(14.0, 0.5, 14.0)
	mesh.mesh = box_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#83d95c")
	material.roughness = 0.95
	mesh.material_override = material
	floor_body.add_child(mesh)
	add_child(floor_body)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46.0, -38.0, 0.0)
	sun.light_color = Color("#fff0cf")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)
	var world_environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#cbd8f5")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#e6ecff")
	env.ambient_light_energy = 1.1
	env.glow_enabled = true
	env.glow_intensity = 1.4
	world_environment.environment = env
	add_child(world_environment)

	for i in 3:
		var slime: ShadowSlime = SLIME.new()
		slime.name = "Slime_%d" % i
		slime.position = Vector3(-1.9 + 1.9 * float(i), 0.02, 0.0)
		slime.set("max_health", 2)
		add_child(slime)

	var camera := Camera3D.new()
	camera.fov = 45.0
	camera.position = Vector3(0.0, 1.5, 5.6)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.62, 0.0), Vector3.UP)
	add_child(camera)
	camera.current = true

	# Let them hop, then report where each one is and how squashed it looks.
	await get_tree().create_timer(1.35).timeout
	for child in get_children():
		if child is ShadowSlime:
			var slime := child as ShadowSlime
			var visual: Node3D = slime.get("_visual")
			print("preview_slime: %s at %s  scale %s  state %s" % [
				slime.name, slime.global_position, visual.scale, slime.state_name()])