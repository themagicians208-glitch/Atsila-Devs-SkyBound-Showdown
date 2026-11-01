extends Node3D

## Debug view: every mesh part tinted differently with a floating name label, so
## we can tell which piece is a leg / arm / head / tail.

const COLOURS := [
	Color(1, 0.2, 0.2), Color(0.2, 1, 0.2), Color(0.3, 0.4, 1), Color(1, 1, 0.2),
	Color(1, 0.3, 1), Color(0.2, 1, 1), Color(1, 0.6, 0.1), Color(0.6, 0.2, 1),
	Color(0.1, 0.7, 0.4), Color(1, 0.5, 0.6), Color(0.5, 0.5, 0.5), Color(0.9, 0.9, 0.9),
	Color(0.4, 0.2, 0.1), Color(0.2, 0.2, 0.6),
]


func _ready() -> void:
	var model: Node3D = load("res://models/racoon.glb").instantiate()
	add_child(model)

	var index := 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var material := StandardMaterial3D.new()
		material.albedo_color = COLOURS[index % COLOURS.size()]
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh_instance.material_override = material

		var centre: Vector3 = mesh_instance.global_transform * mesh_instance.get_aabb().get_center()
		var label := Label3D.new()
		label.text = mesh_instance.name
		label.font_size = 48
		label.outline_size = 14
		label.pixel_size = 0.006
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = Color.WHITE
		label.outline_modulate = Color.BLACK
		add_child(label)
		label.global_position = centre + Vector3(0.0, 0.42, 0.0)
		index += 1

	# The model's face points -X, so view it from -X.
	var cam := Camera3D.new()
	cam.look_at_from_position(Vector3(-7.5, 1.9, 0.0), Vector3(0, 1.8, 0), Vector3.UP)
	cam.current = true
	add_child(cam)

	var env := WorldEnvironment.new()
	var world_env := Environment.new()
	world_env.background_mode = Environment.BG_COLOR
	world_env.background_color = Color(0.15, 0.17, 0.22)
	env.environment = world_env
	add_child(env)