extends Node3D

## For each character: the model as it comes, then two points of the stride.
## Tells model detail apart from rig damage.

const ROSTER := preload("res://scripts/roster.gd")

const POSE_A := {"leg": 0.60, "arm": -0.35, "flap": -0.15, "splay": -0.17}
const POSE_B := {"leg": -0.60, "arm": 0.35, "flap": 0.15, "splay": 0.17}


func _ready() -> void:
	var row := 0
	for character_id in ["Nattie", "Jamal"]:
		var x := -1.95
		var variant := 0
		for pose in [null, POSE_A, POSE_B]:
			var character: Node3D = load(ROSTER.scene_for(character_id)).instantiate()
			character.set("player_index", 1)
			if pose == null:
				character.set("limb_rig", false)
			add_child(character)
			character.position = Vector3(x, 0, -row * 2.4)
			character.rotation_degrees = Vector3(0, 18, 0)
			if pose != null:
				character.call("set_pose", pose["leg"], pose["arm"], 0.0, pose["flap"], pose["splay"], 0.0)

			var label := Label3D.new()
			label.text = character_id if pose == null else "stride %d" % variant
			label.font_size = 64
			label.pixel_size = 0.004
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.outline_size = 16
			label.outline_modulate = Color.BLACK
			add_child(label)
			label.global_position = Vector3(x, 1.3, -row * 2.4)
			x += 1.95
			variant += 1
		row += 1

	var cam := Camera3D.new()
	cam.fov = 42.0
	cam.look_at_from_position(Vector3(0, 1.5, 6.4), Vector3(0, 0.6, -1.2), Vector3.UP)
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