extends Node3D

## Shows ONLY one mesh part of the model, large, to see its true shape.

@export var keep_name := "Object_6"
@export var view_from_x := -8.0


func _ready() -> void:
	var model: Node3D = load("res://models/racoon.glb").instantiate()
	add_child(model)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.name == keep_name:
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(1, 0.72, 0.24)
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mesh_instance.material_override = material
		else:
			mesh_instance.visible = false

	var label := Label3D.new()
	label.text = "ONLY %s" % keep_name
	label.font_size = 64
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 18
	label.outline_modulate = Color.BLACK
	add_child(label)
	label.global_position = Vector3(0, 4.1, 0)

	var cam := Camera3D.new()
	cam.look_at_from_position(Vector3(view_from_x, 1.8, 0.0), Vector3(0, 1.7, 0), Vector3.UP)
	cam.current = true
	add_child(cam)

	var env := WorldEnvironment.new()
	var world_env := Environment.new()
	world_env.background_mode = Environment.BG_COLOR
	world_env.background_color = Color(0.14, 0.16, 0.2)
	env.environment = world_env
	add_child(env)