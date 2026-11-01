extends Node

## Runs the limb-mask maths on the CPU over a real model, so a rig can be tuned by
## numbers: which meshes get caught, where those vertices are, and where the pose
## moves them. Mirrors racoon_body.gdshader.
##
## Args: <character id> <arm_y0> <arm_y1> <arm_y2> <arm_y3> <arm_x_in> <arm_x_out>
##       <arm_drop> <arm_swing> <arm_reach> <shoulder_y> <shoulder_side>

const ROSTER := preload("res://scripts/roster.gd")

var _side_axis := Vector3(-1.0, 0.0, 0.0)
var _side_origin := Vector3(-2.5, 0.0, 38.0)
var _band: Array[float] = [26.0, 29.0, 34.0, 37.0]
var _x: Array[float] = [9.5, 11.0]
var _far := 0.0
var _drop := -1.2
var _swing := 0.0
var _reach := 0.0
var _shoulder: Array[float] = [36.0, 9.5]


func _ready() -> void:
	var id := ROSTER.default_id()
	var numbers: Array[float] = []
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		if text.begins_with("res://"):
			continue
		if ROSTER.has(text):
			id = text
		elif text.is_valid_float():
			numbers.append(text.to_float())
	if numbers.size() >= 6:
		_band.assign(numbers.slice(0, 4))
		_x.assign(numbers.slice(4, 6))
	if numbers.size() >= 9:
		_drop = numbers[6]
		_swing = numbers[7]
		_reach = numbers[8]
	if numbers.size() >= 11:
		_shoulder.assign(numbers.slice(9, 11))
	if numbers.size() >= 12:
		_far = numbers[11]

	print("simulating %s: band [%.1f %.1f %.1f %.1f]  x [%.1f %.1f]  drop %.2f swing %.2f reach %.2f" % [
		id, _band[0], _band[1], _band[2], _band[3], _x[0], _x[1], _drop, _swing, _reach])
	print("   shoulder y %.1f side %.1f" % [_shoulder[0], _shoulder[1]])

	var node: Node3D = load(ROSTER.scene_for(id)).instantiate()
	add_child(node)
	await get_tree().process_frame

	var total_weighted := 0
	var side_bins: Array[int] = []
	side_bins.resize(10)
	side_bins.fill(0)
	var y_bins: Array[int] = []
	y_bins.resize(10)
	y_bins.fill(0)
	for mesh_instance in _meshes(node):
		var to_model := _to_model(mesh_instance)
		var report := _measure(mesh_instance, to_model)
		if report["verts"] == 0:
			continue
		print("%-12s %-42s verts %6d  caught %6d (%.1f%%)  move max %.2f mean %.2f" % [
			mesh_instance.name, mesh_instance.get_parent().name, report["verts"],
			report["caught"], 100.0 * float(report["caught"]) / float(maxi(report["verts"], 1)),
			report["max_move"], report["mean_move"]])
		print("             caught box %s -> %s" % [report["from"], report["to"]])
		total_weighted += report["caught"]
		for side in report["sides"]:
			side_bins[clampi(int(side / 3.0), 0, 9)] += 1
		for y in report["ys"]:
			y_bins[clampi(int((y - 15.0) / 2.5), 0, 9)] += 1
	print("total caught vertices: %d" % total_weighted)
	var side_line := ""
	for b in 10:
		side_line += "%.0f-%.0f:%d  " % [b * 3.0, b * 3.0 + 3.0, side_bins[b]]
	print("|side| histogram: %s" % side_line)
	var y_line := ""
	for b in 10:
		y_line += "%.0f-%.0f:%d  " % [15.0 + b * 2.5, 17.5 + b * 2.5, y_bins[b]]
	print("y histogram:     %s" % y_line)
	get_tree().quit()


## Mask weights and displacement for one mesh, in model space.
func _measure(mesh_instance: MeshInstance3D, to_model: Transform3D) -> Dictionary:
	var verts := 0
	var caught := 0
	var max_move := 0.0
	var sum_move := 0.0
	var sides: Array[float] = []
	var ys: Array[float] = []
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	var low_after := Vector3(INF, INF, INF)
	var high_after := Vector3(-INF, -INF, -INF)
	var mesh := mesh_instance.mesh
	if mesh == null:
		return {"verts": 0}
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		for vertex in PackedVector3Array(arrays[Mesh.ARRAY_VERTEX]):
			# Vertex position in model space.
			var model_point := to_model * vertex
			verts += 1
			var weight := _arm_weight(model_point)
			if weight <= 0.05:
				continue
			caught += 1
			var side_coord := (model_point - _side_origin).dot(_side_axis)
			sides.append(absf(side_coord))
			ys.append(model_point.y)
			# The shader mirrors the sign per arm, so both arms move the same way.
			var lead := 1.0 if side_coord < 0.0 else -1.0
			var moved := _rotate(model_point, Vector3.UP.cross(_side_axis).normalized(),
				(_drop * lead - _swing * lead - _reach) * weight)
			var distance := (moved - model_point).length()
			max_move = maxf(max_move, distance)
			sum_move += distance
			low = low.min(model_point)
			high = high.max(model_point)
			low_after = low_after.min(moved)
			high_after = high_after.max(moved)
	if caught == 0:
		return {"verts": verts, "caught": 0, "max_move": 0.0, "mean_move": 0.0, "from": "-", "to": "-", "sides": [], "ys": []}
	return {
		"verts": verts, "caught": caught, "max_move": max_move,
		"mean_move": sum_move / float(caught),
		"from": _box(low, high), "to": _box(low_after, high_after),
		"sides": sides, "ys": ys,
	}


## The arm mask of racoon_body.gdshader, for a point in model space.
func _arm_weight(model_point: Vector3) -> float:
	var model_y := model_point.y
	var model_side := (model_point - _side_origin).dot(_side_axis)
	var band := smoothstep(_band[0], _band[1], model_y) * (1.0 - smoothstep(_band[2], _band[3], model_y))
	if band <= 0.001:
		return 0.0
	var far := 1.0
	if _far > 0.0:
		far = 1.0 - smoothstep(_far - 2.5, _far, absf(model_side))
	var left := 1.0 - smoothstep(-_x[1], -_x[0], model_side)
	var right := smoothstep(_x[0], _x[1], model_side)
	return maxf(left, right) * band * far


func _rotate(point: Vector3, axis: Vector3, angle: float) -> Vector3:
	# The pivot sits on the model's centre line, at shoulder height, offset to one side.
	var side := signf((point - _side_origin).dot(_side_axis))
	if is_zero_approx(side):
		side = 1.0
	var pivot := Vector3(_side_origin.x, _shoulder[0], _side_origin.z) + _side_axis * (_shoulder[1] * side)
	var q := point - pivot
	var c := cos(angle)
	var s := sin(angle)
	return q * c + axis.cross(q) * s + axis * axis.dot(q) * (1.0 - c) + pivot


func _box(low: Vector3, high: Vector3) -> String:
	return "x[%.1f..%.1f] y[%.1f..%.1f] z[%.1f..%.1f]" % [low.x, high.x, low.y, high.y, low.z, high.z]


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)
	for child in node.get_children():
		found.append_array(_meshes(child))
	return found


func _to_model(node: Node3D) -> Transform3D:
	var chain: Array[Node3D] = []
	var walk: Node = node
	while walk != null and walk.name != "model":
		if walk is Node3D:
			chain.append(walk as Node3D)
		walk = walk.get_parent()
	var result := Transform3D()
	for i in range(chain.size() - 1, -1, -1):
		result = result * chain[i].transform
	return result
