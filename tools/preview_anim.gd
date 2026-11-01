extends Node3D

## Renders one character from the roster in the three poses that matter for the
## animation style, using its real config: mid-step either way and mid-slash.
##
## Args: <character id> [yaw]

const ROSTER := preload("res://scripts/roster.gd")

const SPACING := 1.05


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var id := ROSTER.default_id()
	var yaw := 0.0
	for arg in args:
		var text := str(arg)
		if ROSTER.has(text):
			id = text
		elif text.is_valid_float():
			yaw = text.to_float()

	_pose_column(0, id, yaw, "idle")            # standing still: the rig s rest pose
	_pose_column(1, id, yaw, "walk A", 0.85, -0.50)
	_pose_column(2, id, yaw, "walk B", -0.85, 0.50)
	_pose_column(3, id, yaw, "slash", 0.0, 0.0, true)
	_pose_column(4, id, yaw, "no rig", 0.85, -0.50, false, true)

	var camera := Camera3D.new()
	var centre := Vector3(SPACING * 2.0, 0.62, 0)
	camera.position = centre + Vector3(0, 0, 4.9)
	camera.look_at_from_position(camera.position, centre + Vector3(0, -0.1, 0), Vector3.UP)
	camera.fov = 44.0
	add_child(camera)
	_light(Vector3(-50, 35, 0), 1.4)
	_light(Vector3(-25, -140, 0), 0.6)


func _pose_column(index: int, id: String, yaw: float, caption: String, leg: float = 0.0, arm: float = 0.0,
		slash: bool = false, no_rig: bool = false) -> void:
	var character: Node3D = load(ROSTER.scene_for(id)).instantiate()
	if no_rig:
		character.set("limb_rig", false)
		character.set("rig_bone_arms", PackedStringArray())
		character.set("rig_bone_hold", PackedStringArray())
	add_child(character)
	character.position = Vector3(SPACING * float(index), 0, 0)
	character.rotation_degrees = Vector3(0, yaw, 0)
	if slash:
		character.call("set_swing", 1.0, 0)
	else:
		character.call("set_pose", leg, arm, 0.0, arm * 0.45, -0.24, 0.0)

	var label := Label3D.new()
	label.text = caption
	label.font_size = 44
	label.pixel_size = 0.003
	label.position = Vector3(SPACING * float(index), -0.16, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 14
	label.outline_modulate = Color.BLACK
	add_child(label)


func _light(rotation_degrees_value: Vector3, energy: float) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = rotation_degrees_value
	light.light_energy = energy
	add_child(light)
