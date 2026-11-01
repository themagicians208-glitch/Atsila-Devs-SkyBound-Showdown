extends Node3D

## Shows the wired-up player scene in each of the four player colours.


func _ready() -> void:
	var x := -1.8
	for index in [0, 1, 2, 3]:
		var player_scene: PackedScene = load("res://objects/player.tscn")
		var character: CharacterBody3D = player_scene.instantiate()
		character.set("player_index", index)
		var dummy_view := Node3D.new()
		dummy_view.name = "DummyView"
		character.add_child(dummy_view)
		character.set("view", dummy_view)
		character.position = Vector3(x, 0, 0)
		add_child(character)
		character.set_physics_process(false)
		(character.get_node("Shadow") as Node3D).visible = false
		(character.get_node("ParticlesTrail") as Node3D).visible = false
		x += 1.2

	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.75, 3.0)
	cam.rotation_degrees = Vector3(-4, 0, 0)
	cam.current = true
	add_child(cam)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	add_child(light)

	var env := WorldEnvironment.new()
	var world_env := Environment.new()
	world_env.background_mode = Environment.BG_COLOR
	world_env.background_color = Color(0.45, 0.62, 0.86)
	world_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_env.ambient_light_color = Color.WHITE
	world_env.ambient_light_energy = 0.8
	env.environment = world_env
	add_child(env)