extends Node3D

## Empirical scale test: Nattie at four scales beside a 1x1x1 reference cube, so we
## can read off the scale that makes it one unit tall and see where its feet land.

const MODEL := "res://models/characters/Nattie.glb"
const SCALES := [1.0, 0.5, 0.33, 0.25]


func _ready() -> void:
	var x := -2.1
	for factor in SCALES:
		# Reference cube: 1 unit tall, sitting on y = 0.
		var cube := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1, 1, 1)
		cube.mesh = box
		var cube_material := StandardMaterial3D.new()
		cube_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cube_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cube_material.albedo_color = Color(1, 1, 1, 0.22)
		cube.material_override = cube_material
		add_child(cube)
		cube.position = Vector3(x, 0.5, 0)

		var model: Node3D = load(MODEL).instantiate()
		model.scale = Vector3.ONE * factor
		add_child(model)
		model.position = Vector3(x, 0, 0)

		var label := Label3D.new()
		label.text = "x%.2f" % factor
		label.font_size = 64
		label.pixel_size = 0.005
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.outline_size = 14
		label.outline_modulate = Color.BLACK
		add_child(label)
		label.global_position = Vector3(x, 1.5, 0)
		x += 1.4

	var cam := Camera3D.new()
	cam.fov = 26.0
	cam.look_at_from_position(Vector3(0, 0.7, 9.0), Vector3(0, 0.6, 0), Vector3.UP)
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