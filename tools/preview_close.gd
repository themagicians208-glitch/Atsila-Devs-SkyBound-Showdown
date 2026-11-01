extends Node3D

## Close-up of one character: the model as it comes, then three points of the
## stride, filling the frame so the limbs can actually be seen.

const CHARACTER := "Jamal"
const ROSTER := preload("res://scripts/roster.gd")

const POSES := [
	null,
	{"leg": 0.70, "arm": -0.40, "flap": -0.18, "splay": -0.20},
	{"leg": 0.0, "arm": 0.0, "flap": 0.0, "splay": 0.0},
	{"leg": -0.70, "arm": 0.40, "flap": 0.18, "splay": 0.20},
]


func _ready() -> void:
	var x := -1.35
	for pose in POSES:
		var character: Node3D = load(ROSTER.scene_for(CHARACTER)).instantiate()
		character.set("player_index", 1)
		if pose == null:
			character.set("limb_rig", false)
		add_child(character)
		character.position = Vector3(x, 0, 0)
		if pose != null:
			character.call("set_pose", pose["leg"], pose["arm"], 0.0, pose["flap"], pose["splay"], 0.0)

		var label := Label3D.new()
		label.text = "as is" if pose == null else "%+.1f" % pose["leg"]
		label.font_size = 64
		label.pixel_size = 0.0035
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.outline_size = 16
		label.outline_modulate = Color.BLACK
		add_child(label)
		label.global_position = Vector3(x, 1.1, 0)
		x += 0.9

	var cam := Camera3D.new()
	cam.fov = 42.0
	cam.look_at_from_position(Vector3(0, 0.55, 2.4), Vector3(0, 0.45, 0), Vector3.UP)
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