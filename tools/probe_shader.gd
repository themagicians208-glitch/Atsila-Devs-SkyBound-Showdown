extends Node

## Takes a character's live limb material and applies its own uniforms to real
## vertices on the CPU, to see what the shader will actually do to them.

const ROSTER := preload("res://scripts/roster.gd")


func _ready() -> void:
	var id := ROSTER.default_id()
	for arg in OS.get_cmdline_user_args():
		if ROSTER.has(str(arg)):
			id = str(arg)
	var character: Node3D = load(ROSTER.scene_for(id)).instantiate()
	add_child(character)
	await get_tree().process_frame

	for node in character.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var material := mesh_instance.material_override
		if not (material is ShaderMaterial):
			continue
		var shader_material := material as ShaderMaterial
		if float(shader_material.get_shader_parameter("u_do_arms")) < 0.5:
			continue
		var y_vec: Vector3 = shader_material.get_shader_parameter("u_y_vec")
		var y_off: float = shader_material.get_shader_parameter("u_y_off")
		var side_vec: Vector3 = shader_material.get_shader_parameter("u_side_vec")
		var side_off: float = shader_material.get_shader_parameter("u_side_off")
		var band: PackedFloat32Array = PackedFloat32Array([
			shader_material.get_shader_parameter("u_arm_y0"),
			shader_material.get_shader_parameter("u_arm_y1"),
			shader_material.get_shader_parameter("u_arm_y2"),
			shader_material.get_shader_parameter("u_arm_y3"),
			shader_material.get_shader_parameter("u_arm_x_in"),
			shader_material.get_shader_parameter("u_arm_x_out"),
			shader_material.get_shader_parameter("u_arm_x_far"),
			shader_material.get_shader_parameter("u_arm_drop"),
			shader_material.get_shader_parameter("u_arm_flap_mirror"),
			shader_material.get_shader_parameter("u_arm_swing"),
			shader_material.get_shader_parameter("u_arm_reach"),
		])
		var axis_front: Vector3 = shader_material.get_shader_parameter("u_axis_front_back")
		var pivot_l: Vector3 = shader_material.get_shader_parameter("u_arm_pivot_l")
		var pivot_r: Vector3 = shader_material.get_shader_parameter("u_arm_pivot_r")
		var arrays: Array = mesh_instance.mesh.surface_get_arrays(0)
		var verts := PackedVector3Array(arrays[Mesh.ARRAY_VERTEX])
		var best_weight := 0.0
		var best := Vector3.ZERO
		var caught := 0
		for i in range(0, verts.size(), 3):
			var weight := _weight(verts[i], y_vec, y_off, side_vec, side_off, band)
			if weight > 0.05:
				caught += 1
			if weight > best_weight:
				best_weight = weight
				best = verts[i]
		print("%s: drop %.2f mirror %.1f  caught %d  strongest %.2f at %s" % [
			mesh_instance.name, band[7], band[8], caught, best_weight, best.snapped(Vector3.ONE * 0.1)])
		if best_weight > 0.05:
			var side := best.dot(side_vec) + side_off
			var sign := 1.0 if side < 0.0 else -1.0
			var pivot := pivot_l if side < 0.0 else pivot_r
			var angle := (band[7] + 0.0 + band[9] * 0.0) * sign
			if side >= 0.0:
				angle = -(band[7]) * sign * band[8]
			var moved := _rotate(best, pivot, axis_front, angle * best_weight)
			print("     side %+.2f  pivot %s  angle %.2f  %s -> %s  (%.2f units)" % [
				side, pivot.snapped(Vector3.ONE * 0.1), angle, best.snapped(Vector3.ONE * 0.1),
				moved.snapped(Vector3.ONE * 0.1), (moved - best).length()])
	get_tree().quit()


func _weight(point: Vector3, y_vec: Vector3, y_off: float, side_vec: Vector3, side_off: float,
		band: PackedFloat32Array) -> float:
	var y := point.dot(y_vec) + y_off
	var side := point.dot(side_vec) + side_off
	var b := smoothstep(band[0], band[1], y) * (1.0 - smoothstep(band[2], band[3], y))
	var far := 1.0
	if band[6] > 0.0:
		far = 1.0 - smoothstep(band[6] - 2.5, band[6], absf(side))
	var left := 1.0 - smoothstep(-band[5], -band[4], side)
	var right := smoothstep(band[4], band[5], side)
	return maxf(left, right) * b * far


func _rotate(point: Vector3, pivot: Vector3, axis: Vector3, angle: float) -> Vector3:
	var q := point - pivot
	var c := cos(angle)
	var s := sin(angle)
	return q * c + axis.cross(q) * s + axis * axis.dot(q) * (1.0 - c) + pivot
