extends Node3D

## Side view of three forced limb poses, to check the shader bends arms and legs
## (and does not tear the mesh).
## Order front-to-back: neutral, legs forward, legs back.

const POSES := [
	[0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
	[0.85, -0.50, 0.0, -0.22, -0.24, 0.45],
	[-0.85, 0.50, 0.0, 0.22, 0.24, -0.45],
]


func _ready() -> void:
	var z := -1.9
	for pose in POSES:
		var player_scene: PackedScene = load("res://objects/player.tscn")
		var character: CharacterBody3D = player_scene.instantiate()
		character.set("player_index", 0)
		var dummy_view := Node3D.new()
		dummy_view.name = "DummyView"
		character.add_child(dummy_view)
		character.set("view", dummy_view)
		character.position = Vector3(0, 0, z)
		add_child(character)
		character.set_physics_process(false)
		# Hide the ground shadow so it cannot cover the legs.
		(character.get_node("Shadow") as Node3D).visible = false
		(character.get_node("ParticlesTrail") as Node3D).visible = false

		var model: Node = character.get_node("Character")
		model.set("animate_motion", false)
		model.call("set_pose", pose[0], pose[1], pose[2], pose[3], pose[4], pose[5])
		_report(model, pose)
		z += 1.9

	# Same distance, FOV and angle as the in-game camera (10 units away, 25 degrees
	# down, 45 degrees round), so this is what a player actually sees.
	var cam := Camera3D.new()
	cam.fov = 42.0
	cam.look_at_from_position(Vector3(7.07, 4.24, 7.07), Vector3(0, 0.55, 0.0), Vector3.UP)
	cam.current = true
	add_child(cam)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -35, 0)
	add_child(light)

	var env := WorldEnvironment.new()
	var world_env := Environment.new()
	world_env.background_mode = Environment.BG_COLOR
	world_env.background_color = Color(0.42, 0.6, 0.85)
	world_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_env.ambient_light_color = Color.WHITE
	world_env.ambient_light_energy = 0.8
	env.environment = world_env
	add_child(env)


func _report(model: Node, pose: Array) -> void:
	var pivot: Node3D = model.get("_tail_pivot")
	var pivot_name := "MISSING"
	var tail_rotation := Vector3.ZERO
	if pivot != null:
		pivot_name = pivot.name
		tail_rotation = pivot.rotation
	print("tail_sway=%.2f  tail_pivot=%s  pivot_rotation=%s" % [
		pose[5], pivot_name, tail_rotation])