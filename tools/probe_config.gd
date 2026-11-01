extends Node

## Prints the rig a character scene really ends up with: the script fields and the
## shader uniforms on its materials.

const ROSTER := preload("res://scripts/roster.gd")


func _ready() -> void:
	var id := ROSTER.default_id()
	for arg in OS.get_cmdline_user_args():
		if ROSTER.has(str(arg)):
			id = str(arg)
	var character: Node3D = load(ROSTER.scene_for(id)).instantiate()
	add_child(character)
	await get_tree().process_frame
	print("%s  script=%s" % [id, character.get_script().resource_path.get_file()])
	for field in ["limb_rig", "rig_arm_all", "rig_leg_all", "arm_x_in", "arm_x_out", "arm_x_far",
			"arm_drop", "arm_y0", "arm_y3", "shoulder_y", "shoulder_side", "leg_y0", "leg_y1",
			"leg_amp_scale", "arm_amp_scale"]:
		print("   %-16s %s" % [field, character.get(field)])
	print("   side_axis %s   side_origin %s" % [
		character.get("side_axis"), character.get("side_origin")])
	var materials: Array = character.get("_limb_materials")
	print("   limb materials: %d" % materials.size())
	if not materials.is_empty():
		var shader_material := materials[0] as ShaderMaterial
		for name in ["u_arm_x_in", "u_arm_x_out", "u_arm_x_far", "u_arm_drop", "u_arm_y0", "u_arm_y3",
				"u_side_vec", "u_side_off", "u_do_arms", "u_do_legs"]:
			print("      %-14s %s" % [name, shader_material.get_shader_parameter(name)])
	get_tree().quit()
