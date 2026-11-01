extends Node

## Dumps everything needed to design a limb rig for a character model: every mesh,
## its parent, whether it is skinned and by which bones, and where its vertices
## actually are.

const ROSTER := preload("res://scripts/roster.gd")


func _ready() -> void:
	var only := OS.get_cmdline_user_args()
	for i in ROSTER.count():
		var id := ROSTER.id_at(i)
		if not only.is_empty() and not only.has(id):
			continue
		print("\n================ %s   (%s)" % [id, ROSTER.scene_for(id)])
		var node: Node3D = load(ROSTER.scene_for(id)).instantiate()
		add_child(node)
		await get_tree().process_frame
		_dump(node, "")
		var skeleton := _skeleton(node)
		if skeleton != null:
			var names: Array[String] = []
			for b in skeleton.get_bone_count():
				names.append(skeleton.get_bone_name(b))
			print("   skeleton '%s': %d bones" % [skeleton.name, names.size()])
			print("      %s" % ", ".join(names))
		node.queue_free()
		await get_tree().process_frame
	get_tree().quit()


func _dump(node: Node, indent: String) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mat := mesh_instance.material_override
		if mat == null and mesh_instance.get_surface_override_material_count() > 0:
			mat = mesh_instance.get_surface_override_material(0)
		var shader_name := "-"
		if mat is ShaderMaterial:
			shader_name = (mat as ShaderMaterial).shader.resource_path.get_file()
		print("%sMESH %s   parent=%s   skinned=%s   shader=%s" % [
			indent, mesh_instance.name, mesh_instance.get_parent().name,
			mesh_instance.skin != null, shader_name])
		print("%s   aabb=%s   skel_path=%s" % [
			indent, mesh_instance.get_aabb(), mesh_instance.skeleton])
		var mesh := mesh_instance.mesh
		if mesh != null:
			for s in mesh.get_surface_count():
				var arrays: Array = mesh.surface_get_arrays(s)
				var verts := PackedVector3Array(arrays[Mesh.ARRAY_VERTEX])
				var bones := PackedInt32Array()
				var weights := PackedFloat32Array()
				if arrays[Mesh.ARRAY_BONES] is PackedInt32Array:
					bones = arrays[Mesh.ARRAY_BONES]
				if arrays[Mesh.ARRAY_WEIGHTS] is PackedFloat32Array:
					weights = arrays[Mesh.ARRAY_WEIGHTS]
				print("%s   surface %d: %d verts, %d bones, %d weights" % [
					indent, s, verts.size(), bones.size(), weights.size()])
				if verts.size() > 0:
					var min_v: Vector3 = verts[0]
					var max_v: Vector3 = verts[0]
					for v in verts:
						min_v = min_v.min(v)
						max_v = max_v.max(v)
					print("%s      bounds  min=%s  max=%s  size=%s" % [
						indent, min_v.snapped(Vector3.ONE * 0.01), max_v.snapped(Vector3.ONE * 0.01),
						(max_v - min_v).snapped(Vector3.ONE * 0.01)])
					_histogram(indent, verts, min_v.y, max_v.y)
				if bones.size() > 0:
					_bones(indent, bones, weights, verts)
	for child in node.get_children():
		_dump(child, indent + "  ")


## How many vertices sit in each slice along Y - the limb masks are y bands.
func _histogram(indent: String, verts: PackedVector3Array, min_y: float, max_y: float) -> void:
	var bins := 10
	var counts: Array[int] = []
	counts.resize(bins)
	counts.fill(0)
	for v in verts:
		var t := (v.y - min_y) / maxf(max_y - min_y, 0.0001)
		counts[clampi(int(t * float(bins)), 0, bins - 1)] += 1
	var line := ""
	for b in bins:
		line += "%.2f:%d  " % [min_y + (max_y - min_y) * float(b) / float(bins), counts[b]]
	print("%s      y histogram: %s" % [indent, line])


## Which bones drive the vertices, how many, and the box those vertices occupy.
func _bones(indent: String, bones: PackedInt32Array, weights: PackedFloat32Array,
		verts: PackedVector3Array) -> void:
	var influence: Dictionary = {}
	var bounds: Dictionary = {}
	var stride := 4
	for index in verts.size():
		for slot in stride:
			var at := index * stride + slot
			if at >= bones.size() or at >= weights.size():
				continue
			if weights[at] <= 0.05:
				continue
			var bone := bones[at]
			influence[bone] = int(influence.get(bone, 0)) + 1
			var v := verts[index]
			if bounds.has(bone):
				var pair: Array = bounds[bone]
				pair[0] = (pair[0] as Vector3).min(v)
				pair[1] = (pair[1] as Vector3).max(v)
			else:
				bounds[bone] = [v, v]
	var ordered: Array = influence.keys()
	ordered.sort_custom(func(a, b): return int(influence[a]) > int(influence[b]))
	for bone in ordered:
		var pair: Array = bounds[bone]
		print("%s      bone %d: %d verts   x[%.2f..%.2f] y[%.2f..%.2f] z[%.2f..%.2f]" % [
			indent, bone, int(influence[bone]),
			(pair[0] as Vector3).x, (pair[1] as Vector3).x,
			(pair[0] as Vector3).y, (pair[1] as Vector3).y,
			(pair[0] as Vector3).z, (pair[1] as Vector3).z])


func _skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _skeleton(child)
		if found != null:
			return found
	return null
