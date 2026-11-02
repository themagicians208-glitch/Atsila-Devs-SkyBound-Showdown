extends Node

## Prints an ASCII front view of each mesh of a model, in the model's own space,
## with the model-space axis numbers beside it. Used to work out where a
## character's arms and legs actually are before writing a limb rig.

const COLS := 46
const ROWS := 30
const RAMP := " .:-=+*#%@"

const ROSTER := preload("res://scripts/roster.gd")


func _ready() -> void:
	var wanted := OS.get_cmdline_user_args()
	var id := wanted[0] if not wanted.is_empty() else ROSTER.default_id()
	var node: Node3D = load(ROSTER.scene_for(id)).instantiate()
	add_child(node)
	await get_tree().process_frame
	print("=== %s ===" % id)

	var meshes: Array[MeshInstance3D] = []
	_collect(node, meshes)

	# Model space is reached through the "model" node, like the rig does.
	var boxes: Array[AABB] = []
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for mesh_instance in meshes:
		var box := _model_box(mesh_instance)
		boxes.append(box)
		low = low.min(box.position)
		high = high.max(box.position + box.size)
	print("model space x[%.2f..%.2f]  y[%.2f..%.2f]  z[%.2f..%.2f]" % [
		low.x, high.x, low.y, high.y, low.z, high.z])
	print("(x = left/right, y = up, z = front/back)")

	for i in meshes.size():
		if i % 2 == 1:
			continue
		_show(meshes, boxes, low, high, "all meshes 0..%d" % i)
	for i in meshes.size():
		_show([meshes[i]], [boxes[i]], low, high,
			"%s (parent %s)" % [meshes[i].name, meshes[i].get_parent().name])


func _collect(node: Node, into: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		into.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect(child, into)


## One ASCII front view: x across, y up, cells shaded by vertex count.
func _show(meshes: Array, boxes: Array, low: Vector3, high: Vector3, caption: String) -> void:
	var counts: Array[int] = []
	counts.resize(COLS * ROWS)
	counts.fill(0)
	var total := 0
	for i in meshes.size():
		var mesh_instance: MeshInstance3D = meshes[i]
		var box: AABB = boxes[i]
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		var xform := _transform_to_model_root(mesh_instance)
		for s in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(s)
			for v in PackedVector3Array(arrays[Mesh.ARRAY_VERTEX]):
				var point := xform * v
				var tx := (point.x - low.x) / maxf(high.x - low.x, 0.001)
				var ty := (point.y - low.y) / maxf(high.y - low.y, 0.001)
				var cx := clampi(int(tx * float(COLS)), 0, COLS - 1)
				var cy := clampi(int(ty * float(ROWS)), 0, ROWS - 1)
				counts[cy * COLS + cx] += 1
				total += 1
	if total == 0:
		return
	var peak := 1
	for count in counts:
		peak = maxi(peak, count)
	print("\n--- %s   (%d verts, peak cell %d)" % [caption, total, peak])
	var y_step := (high.y - low.y) / float(ROWS)
	for row in range(ROWS - 1, -1, -1):
		var line := ""
		for col in COLS:
			var count := counts[row * COLS + col]
			if count == 0:
				line += " "
				continue
			var level := int(round(log(float(count) + 1.0) / log(float(peak) + 1.0) * 9.0))
			line += RAMP[clampi(level, 0, 9)]
		print("  %7.1f |%s" % [low.y + y_step * float(row) + y_step * 0.5, line])
	var x_step := (high.x - low.x) / float(COLS)
	var ruler := "          "
	for col in COLS:
		ruler += str(int(low.x + x_step * float(col)) % 10) if col % 5 == 0 else " "
	print("%s   x from %.0f to %.0f" % [ruler, low.x, high.x])


func _transform_to_model_root(node: Node3D) -> Transform3D:
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


func _model_box(mesh_instance: MeshInstance3D) -> AABB:
	var xform := _transform_to_model_root(mesh_instance)
	var box := mesh_instance.get_aabb()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for corner_index in 8:
		var corner := box.position + Vector3(
			box.size.x * float(corner_index & 1),
			box.size.y * float((corner_index >> 1) & 1),
			box.size.z * float((corner_index >> 2) & 1))
		var point := xform * corner
		lo = lo.min(point)
		hi = hi.max(point)
	return AABB(lo, hi - lo)
