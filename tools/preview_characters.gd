extends Node3D

## Renders the four playable character SCENES (not the raw models), front on, with
## their names as the character select will show them.

const ROSTER := preload("res://scripts/roster.gd")


func _ready() -> void:
	var x := -2.4
	for i in ROSTER.count():
		var character_id := ROSTER.id_at(i)
		var scene_path := ROSTER.scene_for(character_id)
		var character: Node3D = load(scene_path).instantiate()
		character.set("player_index", 0)
		add_child(character)
		character.position = Vector3(x, 0, 0)

		var label := Label3D.new()
		label.text = character_id
		label.font_size = 64
		label.pixel_size = 0.006
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.outline_size = 16
		label.outline_modulate = Color.BLACK
		add_child(label)
		label.global_position = Vector3(x, 1.35, 0)
		x += 1.6

	var cam := Camera3D.new()
	cam.fov = 42.0
	cam.look_at_from_position(Vector3(0, 0.9, 6.0), Vector3(0, 0.5, 0), Vector3.UP)
	cam.current = true
	add_child(cam)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -25, 0)
	add_child(light)

	var env := WorldEnvironment.new()
	var world_env := Environment.new()
	world_env.background_mode = Environment.BG_COLOR
	world_env.background_color = Color(0.42, 0.6, 0.85)
	world_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_env.ambient_light_color = Color.WHITE
	world_env.ambient_light_energy = 0.9
	env.environment = world_env
	add_child(env)