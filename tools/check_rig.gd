extends Node3D

## Numeric check of the limb rigs: for every character, evaluates each rigged
## mesh's vertices through the exact shader maths using the uniforms the script
## actually set, and reports which geometry each mask catches and where it moves.
##
## Prints only; nothing is drawn.

const ROSTER := preload("res://scripts/roster.gd")
const STRIDE := 4  # sample every Nth vertex of the heavyweight models


func _ready() -> void:
	for i in ROSTER.count():
		var character_id := ROSTER.id_at(i)
		var character: Node3D = load(ROSTER.scene_for(character_id)).instantiate()
		character.set("player_index", 0)
		add_child(character)
		print("\n=== %s ===" % character_id)
		var rigged := 0
		for node in character.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			var material := mesh_instance.material_override as ShaderMaterial
			if material == null:
				continue
			rigged += 1
			_report(character, mesh_instance, material)
		if rigged == 0:
			print("  no rigged meshes")
		character.queue_free()
	get_tree().quit()


func _report(character: Node3D, mesh_instance: MeshInstance3D, material: ShaderMaterial) -> void:
	var y_vec: Vector3 = material.get_shader_parameter("u_y_vec")
	var y_off: float = material.get_shader_parameter("u_y_off")
	var s_vec: Vector3 = material.get_shader_parameter("u_side_vec")
	var s_off: float = material.get_shader_parameter("u_side_off")
	var arm_y0: float = material.get_shader_parameter("u_arm_y0")
	var arm_y1: float = material.get_shader_parameter("u_arm_y1")
	var arm_y2: float = material.get_shader_parameter("u_arm_y2")
	var arm_y3: float = material.get_shader_parameter("u_arm_y3")
	var arm_x_in: float = material.get_shader_parameter("u_arm_x_in")
	var arm_x_out: float = material.get_shader_parameter("u_arm_x_out")
	var arm_x_far: float = material.get_shader_parameter("u_arm_x_far")
	var leg_y0: float = material.get_shader_parameter("u_leg_y0")
	var leg_y1: float = material.get_shader_parameter("u_leg_y1")
	var leg_split: float = material.get_shader_parameter("u_leg_split")
	var do_arms: float = material.get_shader_parameter("u_do_arms")
	var do_legs: float = material.get_shader_parameter("u_do_legs")

	print("  mesh %s (arms %.0f legs %.0f) parent=%s" % [
		mesh_instance.name, do_arms, do_legs, mesh_instance.get_parent().name])

	var to_model := _to_model(character, mesh_instance)
	var side_axis: Vector3 = character.get("side_axis")
	var side_origin: Vector3 = character.get("side_origin")
	var side_centre: float = side_origin.dot(side_axis)
	var front: Vector3 = Vector3.UP.cross(side_axis)
	var shoulder_y: float = character.get("shoulder_y")
	var shoulder_side: float = character.get("shoulder_side")
	var hip_y: float = character.get("hip_y")
	var leg_side_value: float = character.get("leg_side")
	var arm_drop: float = material.get_shader_parameter("u_arm_drop")
	var arm_swing: float = material.get_shader_parameter("u_arm_swing")
	var leg_swing: float = material.get_shader_parameter("u_leg_swing")
	var leg_splay: float = material.get_shader_parameter("u_leg_splay")

	var arm_points: Array[Vector3] = []
	var side_lo := INF
	var side_hi := -INF
	var y_lo := INF
	var y_hi := -INF
	var leg_points: Array[Vector3] = []
	var moved: Array[Vector3] = []
	var stray := 0

	for surface in mesh_instance.mesh.get_surface_count():
		var points: PackedVector3Array = mesh_instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for index in range(0, points.size(), STRIDE):
			var vertex: Vector3 = points[index]
			var model := to_model * vertex
			# The uniforms have to reproduce model-space y and side exactly.
			var model_y := vertex.dot(y_vec) + y_off
			var model_side := vertex.dot(s_vec) + s_off
			if absf(model_y - model.dot(Vector3.UP)) > 0.002 \
					or absf(model_side - (model.dot(side_axis) - side_centre)) > 0.002:
				stray += 1
				continue
			side_lo = minf(side_lo, model_side)
			side_hi = maxf(side_hi, model_side)
			y_lo = minf(y_lo, model_y)
			y_hi = maxf(y_hi, model_y)
			var arm := _arm_weight(model_y, model_side, arm_y0, arm_y1, arm_y2, arm_y3, arm_x_in, arm_x_out, arm_x_far) * do_arms
			var leg := _leg_weight(model_y, leg_y0, leg_y1) * do_legs
			if arm > 0.5:
				arm_points.append(model)
			if leg > 0.5:
				leg_points.append(model)
			if arm > 0.001 or leg > 0.001:
				# arm_l / leg_l are the negative-side limbs and take the raw
				# angle; the positive side mirrors it (see the shader).
				var side_sign := 1.0 if model_side < 0.0 else -1.0
				var p := model
				if arm > 0.001:
					var shoulder := Vector3(side_origin.x, shoulder_y, side_origin.z) \
							+ side_axis * (side_sign * -shoulder_side)
					p = _rotate(p, shoulder, front, arm_drop * side_sign * arm)
				if leg > 0.001:
					var hip := Vector3(side_origin.x, hip_y, side_origin.z) \
							+ side_axis * (side_sign * -leg_side_value)
					p = _rotate(p, hip, side_axis, leg_swing * side_sign * leg)
					p = _rotate(p, hip, front, leg_splay * side_sign * leg)
				moved.append(p)

	print("    uniform check: %d of %d samples off" % [stray, stray + moved.size()])
	print("    sampled model space: y %.1f..%.1f   side %.1f..%.1f   (arm band y %.1f-%.1f, x %.1f-%.1f)" % [
		y_lo, y_hi, side_lo, side_hi, arm_y0, arm_y3, arm_x_in, arm_x_out])
	_span("arms", arm_points)
	_span("legs", leg_points)
	_span("after drop+swing", moved)


func _rotate(point: Vector3, pivot: Vector3, axis: Vector3, angle: float) -> Vector3:
	var q := point - pivot
	return q * cos(angle) + axis.cross(q) * sin(angle) + axis * axis.dot(q) * (1.0 - cos(angle)) + pivot


func _arm_weight(model_y: float, model_side: float, y0: float, y1: float, y2: float, y3: float,
		x_in: float, x_out: float, x_far: float = 0.0) -> float:
	var band := smoothstep(y0, y1, model_y) * (1.0 - smoothstep(y2, y3, model_y))
	var far := 1.0
	if x_far > 0.0:
		far = 1.0 - smoothstep(x_far - 2.5, x_far, absf(model_side))
	var left := 1.0 - smoothstep(-x_out, -x_in, model_side)
	var right := smoothstep(x_in, x_out, model_side)
	return maxf(left, right) * band * far


func _leg_weight(model_y: float, y0: float, y1: float) -> float:
	return 1.0 - smoothstep(y0, y1, model_y)


func _span(label: String, points: Array[Vector3]) -> void:
	if points.is_empty():
		print("    %s: nothing" % label)
		return
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for point in points:
		low = low.min(point)
		high = high.max(point)
	print("    %s: %d verts, x [%.2f, %.2f] y [%.2f, %.2f] z [%.2f, %.2f]" % [
		label, points.size(), low.x, high.x, low.y, high.y, low.z, high.z])


func _extreme(points: Array[Vector3]) -> Vector3:
	var best := points[0]
	for point in points:
		best = point if absf(point.x) > absf(best.x) else best
	return best


func _to_model(character: Node3D, node: Node3D) -> Transform3D:
	# Up to (but not including) the GLB root, which is the space the joint
	# measurements and therefore the shader uniforms are expressed in.
	var chain: Array[Node3D] = []
	var walk: Node = node
	while walk != null and walk.name != "model":
		chain.append(walk as Node3D)
		walk = walk.get_parent()
	var result := Transform3D()
	for i in range(chain.size() - 1, -1, -1):
		result = result * chain[i].transform
	return result