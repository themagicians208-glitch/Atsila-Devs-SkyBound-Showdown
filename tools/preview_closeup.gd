extends Node3D

## Two copies of a character, close up: one as the rig leaves it, one with the rig
## switched off. For judging small changes like the rest angle of short arms.
##
## Args: <character id> <yaw>

const ROSTER := preload("res://scripts/roster.gd")


func _ready() -> void:
	var id := ROSTER.default_id()
	var yaw := 0.0
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		if ROSTER.has(text):
			id = text
		elif text.is_valid_float():
			yaw = text.to_float()

	_column(0, id, yaw, "rig", false)
	_column(1, id, yaw, "rig off", true)

	var camera := Camera3D.new()
	camera.position = Vector3(0.42, 0.30, 1.85)
	camera.look_at_from_position(camera.position, Vector3(0.42, 0.24, 0), Vector3.UP)
	camera.fov = 40.0
	add_child(camera)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-45, 25, 0)
	key.light_energy = 1.5
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -150, 0)
	fill.light_energy = 0.7
	add_child(fill)


func _column(index: int, id: String, yaw: float, caption: String, no_rig: bool) -> void:
	var character: Node3D = load(ROSTER.scene_for(id)).instantiate()
	if no_rig:
		character.set("limb_rig", false)
		character.set("rig_bone_arms", PackedStringArray())
		character.set("rig_bone_hold", PackedStringArray())
		character.set("rig_bone_offsets", {})
	add_child(character)
	character.position = Vector3(0.42 * float(index), 0, 0)
	character.rotation_degrees = Vector3(0, yaw, 0)
	var label := Label3D.new()
	label.text = caption
	label.font_size = 40
	label.pixel_size = 0.0018
	label.position = Vector3(0.42 * float(index), 0.12, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 12
	label.outline_modulate = Color.BLACK
	add_child(label)
