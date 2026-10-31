extends Node3D

@export_group("Properties")
@export var target: Node
@export var input_enabled := true
@export var mouse_look := true

@export_group("Input Actions")
@export var action_cam_left := "camera_left"
@export var action_cam_right := "camera_right"
@export var action_cam_up := "camera_up"
@export var action_cam_down := "camera_down"
@export var action_zoom_in := "zoom_in"
@export var action_zoom_out := "zoom_out"

@export_group("Zoom")
@export var zoom_minimum = 16
@export var zoom_maximum = 4
@export var zoom_speed = 10

@export_group("Rotation")
@export var rotation_speed = 120
@export var mouse_sensitivity = 0.22

var camera_rotation:Vector3
var zoom = 10
var settings: Node

@onready var camera = $Camera

func _ready():

	camera_rotation = rotation_degrees # Initial rotation
	settings = get_node_or_null("/root/Settings")
	pass

func _physics_process(delta):
	
	# Set position and rotation to targets
	
	self.position = self.position.lerp(target.position, delta * 4)
	rotation_degrees = rotation_degrees.lerp(camera_rotation, delta * 6)
	
	camera.position = camera.position.lerp(Vector3(0, 0, zoom), 8 * delta)
	
	handle_input(delta)

# Handle input

func handle_input(delta):
	
	if not input_enabled:
		return
	# Rotation
	
	var input := Vector3.ZERO
	
	input.y = Input.get_axis(action_cam_left, action_cam_right)
	input.x = Input.get_axis(action_cam_up, action_cam_down)
	
	camera_rotation += input.limit_length(1.0) * rotation_speed * delta
	camera_rotation.x = clamp(camera_rotation.x, -80, -10)
	
	# Zooming
	
	zoom += Input.get_axis(action_zoom_in, action_zoom_out) * zoom_speed * delta
	zoom = clamp(zoom, zoom_maximum, zoom_minimum)


func _input(event: InputEvent) -> void:
	if not input_enabled or not mouse_look:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity: float = mouse_sensitivity
		if settings:
			sensitivity = settings.mouse_sensitivity
		camera_rotation.y -= event.relative.x * sensitivity
		camera_rotation.x -= event.relative.y * sensitivity
		camera_rotation.x = clampf(camera_rotation.x, -80.0, -10.0)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom - 1.0, zoom_maximum, zoom_minimum)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom + 1.0, zoom_maximum, zoom_minimum)
		elif event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func add_look(delta: Vector2) -> void:
	## Called by the on-screen touch controls to turn the camera.
	var sensitivity: float = mouse_sensitivity
	if settings:
		sensitivity = settings.mouse_sensitivity
	camera_rotation.y -= delta.x * sensitivity
	camera_rotation.x = clampf(camera_rotation.x - delta.y * sensitivity, -80.0, -10.0)
