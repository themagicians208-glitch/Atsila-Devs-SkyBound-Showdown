extends Node3D

## Left: hand-built character (pivot -90, untinted).
## Right: the real res://objects/character.tscn (tinted). Both viewed from +Z.
## If they differ, something in the scene file / script is turning the model.

const MODEL_PATH := "res://models/racoon.glb"
const SCALE := 0.279483
const OFFSET := Vector3(0.14011, 0.047, -0.001878)


func _ready() -> void:
	# Left: manual
	var holder := Node3D.new()
	holder.position = Vector3(-0.9, 0, 0)
	add_child(holder)
	var pivot := Node3D.new()
	pivot.rotation_degrees = Vector3(0, -90, 0)
	holder.add_child(pivot)
	var model: Node3D = load(MODEL_PATH).instantiate()
	model.scale = Vector3.ONE * SCALE
	model.position = OFFSET
	pivot.add_child(model)

	# Right: the real scene
	var scene: PackedScene = load("res://objects/character.tscn")
	var real: Node3D = scene.instantiate()
	real.set("player_index", 0)
	real.position = Vector3(0.9, 0, 0)
	add_child(real)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.7, 3.4)
	cam.rotation_degrees = Vector3(-3, 0, 0)
	cam.current = true
	add_child(cam)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	add_child(light)

	var env := WorldEnvironment.new()
	var world_env := Environment.new()
	world_env.background_mode = Environment.BG_COLOR
	world_env.background_color = Color(0.45, 0.62, 0.86)
	world_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_env.ambient_light_color = Color.WHITE
	world_env.ambient_light_energy = 0.8
	env.environment = world_env
	add_child(env)