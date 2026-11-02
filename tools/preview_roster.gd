extends Node3D

## Renders each candidate character at four yaw angles (0, 90, 180, 270), to see
## which way it faces and what it looks like. Row order matches MODELS.

const MODELS := [
	"res://models/characters/Nattie.glb",
]

const COLUMN_GAP := 1.35
const ROW_GAP := 1.12


func _ready() -> void:
	for row in MODELS.size():
		var path: String = MODELS[row]

		# Measure once, then normalise every copy the same way.
		var probe: Node3D = load(path).instantiate()
		add_child(probe)
		var bounds := _aabb(probe)
		var factor := 1.0 / maxf(bounds.size.y, 0.0001)
		var centre := bounds.get_center()
		var offset := Vector3(-centre.x * factor, -bounds.position.y * factor, -centre.z * factor)
		print("%s: size=%s -> scale=%.4f offset=%s" % [path.get_file(), bounds.size, factor, offset])
		probe.queue_free()

		var column := 0
		for angle in [0.0, 90.0, 180.0, 270.0]:
			var holder := Node3D.new()
			holder.position = Vector3(
				(-1.5 + float(column)) * COLUMN_GAP,
				(1.0 - float(row)) * ROW_GAP,
				0.0)
			holder.rotation_degrees = Vector3(0, angle, 0)
			add_child(holder)
			var model: Node3D = load(path).instantiate()
			model.scale = Vector3.ONE * factor
			model.position = offset
			holder.add_child(model)
			column += 1

		var label := Label3D.new()
		label.text = path.get_file().get_basename()
		label.font_size = 64
		label.pixel_size = 0.006
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.outline_size = 16
		label.outline_modulate = Color.BLACK
		add_child(label)
		label.global_position = Vector3(-2.6, (1.0 - float(row)) * ROW_GAP + 0.85, 0.0)

	# Long lens so every column is viewed from the same angle.
	var cam := Camera3D.new()
	cam.fov = 25.0
	cam.look_at_from_position(Vector3(0, 0, 12.0), Vector3(0, 0, 0), Vector3.UP)
	cam.current = true
	add_child(cam)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -25, 0)
	add_child(light)

	var env := WorldEnvironment.new()
	var world_env := Environment.new()
	world_env.background_mode = Environment.BG_COLOR
	world_env.background_color = Color(0.4, 0.58, 0.84)
	world_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_env.ambient_light_color = Color.WHITE
	world_env.ambient_light_energy = 0.9
	env.environment = world_env
	add_child(env)


func _aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var box := (child as MeshInstance3D).get_aabb()
		# composes only transforms below `node`
		var chain: Array = []
		var walk: Node = child
		while walk != null and walk != node:
			chain.append(walk)
			walk = walk.get_parent()
		var xform := Transform3D()
		for i in range(chain.size() - 1, -1, -1):
			xform = xform * (chain[i] as Node3D).transform
		var world := xform * box
		if first:
			result = world
			first = false
		else:
			result = result.merge(world)
	return result