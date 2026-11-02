extends Node3D

## Renders every character held in a mid-stride pose, so the limb rigs can be
## compared side by side. The pose is forced with set_pose(), which also stops
## the walk cycle from overwriting it (there is no CharacterBody3D parent here).

const ROSTER := preload("res://scripts/roster.gd")

const POSE := {
	"leg_swing": 0.85,
	"arm_swing": -0.50,
	"crouch": 0.0,
	"arm_flap": -0.22,
	"leg_splay": -0.24,
	"tail_sway": 0.45,
}


func _ready() -> void:
	var x := -2.55
	for i in ROSTER.count():
		var character_id := ROSTER.id_at(i)
		var character: Node3D = load(ROSTER.scene_for(character_id)).instantiate()
		character.set("player_index", 0)
		add_child(character)
		character.position = Vector3(x, 0, 0)
		character.rotation_degrees = Vector3(0, 30, 0)
		character.call("set_pose",
			POSE["leg_swing"], POSE["arm_swing"], POSE["crouch"],
			POSE["arm_flap"], POSE["leg_splay"], POSE["tail_sway"])

		var label := Label3D.new()
		label.text = character_id
		label.font_size = 64
		label.pixel_size = 0.0045
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.outline_size = 16
		label.outline_modulate = Color.BLACK
		add_child(label)
		label.global_position = Vector3(x, 1.35, 0)
		x += 1.7

	var cam := Camera3D.new()
	cam.fov = 42.0
	cam.look_at_from_position(Vector3(0, 0.85, 5.4), Vector3(0, 0.55, 0), Vector3.UP)
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