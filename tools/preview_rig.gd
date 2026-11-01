extends Node3D

## Tunes a limb rig against a real model: the model's own pose, the pose it takes
## mid-walk, the pose it takes mid-slash, and the same model with the masks painted
## on. Four columns, one picture.
##
## Args: <character id> <yaw> <arm_y0> <arm_y1> <arm_y2> <arm_y3> <arm_x_in>
##       <arm_x_out> <arm_drop> <leg_y0> <leg_y1> <leg_amp> [<arm_x_far>]

const ROSTER := preload("res://scripts/roster.gd")
const DEBUG_SHADER := preload("res://tools/mask_debug.gdshader")

const SPACING := 0.78

var _id := ROSTER.default_id()
var _yaw := 0.0
var _arm := [26.0, 29.0, 34.0, 37.0, 9.5, 11.0, -1.5]
var _leg := [0.0, 0.0, 0.0]
var _far := 17.0


func _ready() -> void:
	var numbers: Array[float] = []
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		if text.begins_with("res://"):
			continue
		if ROSTER.has(text):
			_id = text
		elif text.is_valid_float():
			numbers.append(text.to_float())
	if numbers.size() >= 9:
		_yaw = numbers[0]
		_arm = numbers.slice(1, 8)
	if numbers.size() >= 12:
		_leg = numbers.slice(8, 11)
	if numbers.size() >= 13:
		_far = numbers[11]

	print("rig preview: %s  yaw %.0f" % [_id, _yaw])
	print("   arm   band [%.0f %.0f %.0f %.0f]  x in/out/far [%.1f %.1f %.1f]  drop %.2f" % [
		_arm[0], _arm[1], _arm[2], _arm[3], _arm[4], _arm[5], _far, _arm[6]])
	print("   legs  y0/y1 [%.1f %.1f]  amp %.2f   (amp 0 = no leg rig)" % [
		_leg[0], _leg[1], _leg[2]])

	_column(0, "model pose", true, 0)
	_column(1, "walk pose", true, 1)
	_column(2, "slash pose", true, 2)
	_column(3, "masks", false, 0)

	var camera := Camera3D.new()
	camera.position = Vector3(SPACING * 1.5, 0.62, 3.0)
	camera.look_at_from_position(Vector3(SPACING * 1.5, 0.62, 3.0), Vector3(SPACING * 1.5, 0.5, 0), Vector3.UP)
	camera.fov = 44.0
	add_child(camera)
	_light(Vector3(-50, 35, 0), 1.4)
	_light(Vector3(-25, -140, 0), 0.6)


## pose: 0 = as the model came, 1 = mid-walk, 2 = mid-slash.
func _column(index: int, caption: String, real_shader: bool, pose: int) -> void:
	var character: Node3D = load(ROSTER.scene_for(_id)).instantiate()
	# These are read when the character enters the tree, so set them before that.
	character.set("limb_rig", true)
	character.set("rig_arm_all", true)
	character.set("side_axis", Vector3(-1.0, 0.0, 0.0))
	character.set("side_origin", Vector3(-2.5, 0.0, 38.0))
	character.set("arm_y0", _arm[0])
	character.set("arm_y1", _arm[1])
	character.set("arm_y2", _arm[2])
	character.set("arm_y3", _arm[3])
	character.set("arm_x_in", _arm[4])
	character.set("arm_x_out", _arm[5])
	character.set("arm_x_far", _far)
	character.set("arm_drop", _arm[6])
	character.set("shoulder_y", _arm[3] - 3.0)
	character.set("shoulder_side", _arm[4])
	character.set("rig_leg_all", _leg[2] != 0.0)
	character.set("leg_y0", _leg[0])
	character.set("leg_y1", _leg[1])
	character.set("leg_side", maxf(_leg[1] * 0.8, 1.0))
	character.set("hip_y", _leg[1] + 1.0)
	character.set("leg_amp_scale", _leg[2])
	add_child(character)
	character.position = Vector3(SPACING * float(index), 0, 0)
	character.rotation_degrees = Vector3(0, _yaw, 0)

	if pose == 1:
		# A walking moment: legs and arms at opposite ends of their swing.
		character.call("set_pose", 0.85, -0.50, 0.0, -0.22, -0.24, 0.0)
	elif pose == 2:
		character.call("set_swing", 1.0, 0)

	if not real_shader:
		for node in character.find_children("*", "MeshInstance3D", true, false):
			var material := (node as MeshInstance3D).material_override
			if material is ShaderMaterial:
				(material as ShaderMaterial).shader = DEBUG_SHADER

	var label := Label3D.new()
	label.text = caption
	label.font_size = 44
	label.pixel_size = 0.003
	label.position = Vector3(SPACING * float(index), -0.14, 0)
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
