extends Node3D

## The three slash poses at full extension, twice: in profile (where reach reads)
## and from behind (where the game camera sits, so flap and the lean read).
## Rendered windowed via tools/capture_shots.tscn.

const CHARACTER := "res://objects/character.tscn"

# label, direction (0 forward, 1 up, -1 down)
const POSES := [
	["forward", 0],
	["up", 1],
	["down", -1],
]


func _ready() -> void:
	# Top row in profile, bottom row turned away from the camera.
	_row(0.75, 90.0)
	_row(-0.95, 180.0)

	var camera := Camera3D.new()
	camera.position = Vector3(0, 0.15, 4.0)
	camera.look_at_from_position(Vector3(0, 0.15, 4.0), Vector3(0, 0.0, 0), Vector3.UP)
	camera.fov = 42.0
	add_child(camera)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52, 38, 0)
	key.light_energy = 1.35
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-28, -140, 0)
	fill.light_energy = 0.55
	add_child(fill)

	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#232a3d")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#6d7ea8")
	environment.ambient_light_energy = 0.85
	world.environment = environment
	add_child(world)


func _row(y: float, yaw: float) -> void:
	var x := -1.55
	for pose in POSES:
		var character: Node3D = load(CHARACTER).instantiate()
		character.set("player_index", 0)
		add_child(character)
		character.position = Vector3(x, y, 0)
		character.rotation_degrees = Vector3(0, yaw, 0)
		# Freeze the walk cycle, then hold the slash at its peak.
		character.call("set_pose", 0.12, 0.0, 0.0, 0.0, 0.0, 0.0)
		character.call("set_swing", 1.0, pose[1])

		var label := Label3D.new()
		label.text = pose[0]
		label.font_size = 64
		label.pixel_size = 0.0045
		label.position = Vector3(x, y - 0.42, 0.7)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.outline_size = 16
		label.outline_modulate = Color.BLACK
		add_child(label)
		x += 1.55
