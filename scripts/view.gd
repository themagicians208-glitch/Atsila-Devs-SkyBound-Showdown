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

@export_group("Collision")
## Scenery between the camera and the player is what a player sees as "the camera
## is inside a rock": the view ends up on the wrong side of the ground and the
## character vanishes behind it. So the boom is shortened whenever anything solid
## would come between the two, and eased back out when the way is clear.
@export var avoid_geometry := true
## The camera's own girth, so a thin post or the corner of a ledge still stops it.
@export var avoid_radius := 0.4
@export var avoid_mask := 1
## Casts start at head height: casting from the player's feet would be inside the
## floor they are standing on and pin the camera to their back.
@export var avoid_head_height := 1.1
## Never quite zero, so the view does not end up inside the player's head.
@export var avoid_floor := 0.4
## With the boom this short the camera is inside the player's own model, so the
## model is hidden rather than shown through it. 0 disables it.
@export var hide_target_when_close := 1.0
## ...and a jammed camera lifts this far above the player, tipping down a little,
## so it looks over their shoulder instead of sitting inside the scenery behind
## them. 0 disables the lift.
@export var close_lift := 2.4
@export var close_tip := 16.0

var camera_rotation:Vector3
var zoom = 10
var settings: Node
var _avoid_sphere := SphereShape3D.new()

@onready var camera = $Camera

func _ready():

	camera_rotation = rotation_degrees # Initial rotation
	settings = get_node_or_null("/root/Settings")
	_avoid_sphere.radius = avoid_radius
	pass

func _physics_process(delta):
	
	# Set position and rotation to targets
	
	self.position = self.position.lerp(target.position, delta * 4)
	rotation_degrees = rotation_degrees.lerp(camera_rotation, delta * 6)
	
	settle_camera(delta)
	
	handle_input(delta)


## Keep the boom as long as the way behind the player is clear, and no longer.
func settle_camera(delta: float) -> void:
	var wanted := float(zoom)
	var clear := clear_boom(wanted)
	var current: float = camera.position.z
	if clear < current:
		current = clear # in at once: a wall must never show through
	else:
		current = lerpf(current, minf(clear, wanted), 8.0 * delta)
	camera.position = Vector3(0.0, 0.0, current)
	var squeeze := 0.0
	var lift := 0.0
	var tip := 0.0
	if hide_target_when_close > 0.0 and current < hide_target_when_close * 2.2:
		squeeze = clampf((hide_target_when_close * 2.2 - current) / (hide_target_when_close * 2.2), 0.0, 1.0)
		lift = close_lift * squeeze
		tip = close_tip * squeeze
		# A lifted camera can reach into a ceiling, so it is tested like the boom
		# itself - and a shallow lift is better than one inside the roof.
		if lift > 0.0 and not _lifted_fits(lift, current):
			lift *= 0.5
			tip *= 0.5
	camera.position = Vector3(0.0, lift, current)
	camera.rotation.x = -deg_to_rad(tip)
	if hide_target_when_close > 0.0 and target is Node3D:
		(target as Node3D).visible = current > hide_target_when_close


## Would a camera lifted this far above the player be clear of the world?
func _lifted_fits(lift: float, back: float) -> bool:
	if not avoid_geometry or target == null:
		return true
	var space := get_world_3d().direct_space_state
	if space == null:
		return true
	var spot := global_position + global_transform.basis.y * lift + global_transform.basis.z * back
	return _camera_fits(space, spot)


## How far back the camera can sit before something is in the way, measured by
## pushing the camera's own girth from the player's head towards where it wants
## to be. The physics world reports the fraction of that move that is clear.
func clear_boom(wanted: float) -> float:
	if not avoid_geometry or target == null:
		return wanted
	var space := get_world_3d().direct_space_state
	if space == null:
		return wanted
	var origin := global_position + Vector3(0.0, avoid_head_height, 0.0)
	var boom := global_transform.basis.z
	var boom_end := global_position + boom * wanted
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _avoid_sphere
	query.transform = Transform3D(Basis(), origin)
	query.motion = boom_end - origin
	query.collision_mask = avoid_mask
	query.collide_with_areas = false
	query.exclude = _avoid_exclusions()
	var fractions := space.cast_motion(query)
	var distance := wanted
	if fractions.size() == 2:
		distance = wanted * fractions[0]
	# A swept sphere can slide past a thin box that a plain ray walks straight
	# into, so the ray gets a say as well. Both keep the camera's own radius clear
	# of what they find, which also stops the near plane poking through a wall.
	var ray := PhysicsRayQueryParameters3D.create(origin, boom_end)
	ray.collision_mask = avoid_mask
	ray.collide_with_areas = false
	ray.exclude = _avoid_exclusions()
	var ray_hit := space.intersect_ray(ray)
	if not ray_hit.is_empty():
		var along := ((ray_hit["position"] as Vector3) - origin).length() - avoid_radius
		distance = minf(distance, along)
	distance = clampf(distance, avoid_floor, wanted)
	# That cast starts at the player's head, so the point it reports free sits a
	# little above the line the camera actually rides - enough to leave the camera
	# inside a ledge the sphere just slid past. Walk the end of the boom back until
	# the camera's own footprint is clear as well.
	var steps := 8
	while steps > 0 and distance > avoid_floor:
		if _camera_fits(space, global_position + boom * distance):
			break
		distance = maxf(distance - avoid_radius, avoid_floor)
		steps -= 1
	return distance


## Would the camera's own girth sit clear of the world at this spot?
func _camera_fits(space: PhysicsDirectSpaceState3D, at: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _avoid_sphere
	query.transform = Transform3D(Basis(), at)
	query.collision_mask = avoid_mask
	query.collide_with_areas = false
	query.exclude = _avoid_exclusions()
	return space.intersect_shape(query, 1).is_empty()


## The one body the camera must never hide behind: the player it is following.
func _avoid_exclusions() -> Array[RID]:
	var out: Array[RID] = []
	if target is CollisionObject3D:
		out.append((target as CollisionObject3D).get_rid())
	return out

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
