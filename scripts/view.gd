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

@export_group("Obstacle Fading")
## Smoothly fades obstacles (walls, pillars, trees, canopies, gates, arches) that
## sit in front of the camera angle of the main player so the player stays visible.
@export var fade_obstacles: bool = true
## Target GeometryInstance3D.transparency when an obstacle blocks the view (0 = opaque, 1 = invisible).
@export var fade_transparency: float = 0.78
## How quickly obstacles fade out when blocking the view and fade back in when clear.
@export var fade_speed: float = 10.0
## Radius around the camera-to-player sightline within which obstacles fade.
@export var fade_corridor_radius: float = 0.85

var camera_rotation:Vector3
var zoom = 10
var settings: Node
var _avoid_sphere := SphereShape3D.new()
var _faded_meshes: Dictionary = {}
var _env_meshes_cache: Array[int] = []
var _env_cache_clock: float = 0.0

@onready var camera = $Camera

func _ready():

	camera_rotation = rotation_degrees # Initial rotation
	settings = get_node_or_null("/root/Settings")
	_avoid_sphere.radius = avoid_radius
	pass

func _physics_process(delta):
	
	# A view built in code (the battle arena's duel camera) may be added a frame
	# before its target is wired up; nothing to follow until then.
	if target == null:
		return
	
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
	_update_obstacle_fading(delta)


## Number of meshes currently faded because they sit in front of the camera angle.
func faded_obstacle_count() -> int:
	return _faded_meshes.size()


## True if `mesh` is currently faded by the camera's obstacle fader.
func is_mesh_faded(mesh: MeshInstance3D) -> bool:
	if mesh == null:
		return false
	return _faded_meshes.has(mesh.get_instance_id())


func _update_obstacle_fading(delta: float) -> void:
	if not fade_obstacles or target == null or not is_instance_valid(target) or not (target is Node3D):
		_clear_all_faded_meshes()
		return
	var target_node := target as Node3D
	var target_pos := target_node.global_position
	var head := target_pos + Vector3(0.0, avoid_head_height, 0.0)
	var chest := target_pos + Vector3(0.0, 0.65, 0.0)
	var eye: Vector3 = global_transform * (camera.position as Vector3)
	var wanted_eye := global_position + global_transform.basis.z * float(zoom)
	var blocking_meshes: Dictionary = {}

	var space := get_world_3d().direct_space_state if get_world_3d() != null else null
	if space != null:
		var right := global_transform.basis.x * 0.35
		_collect_ray_blockers(space, eye, head, target_pos, blocking_meshes)
		_collect_ray_blockers(space, eye, chest, target_pos, blocking_meshes)
		_collect_ray_blockers(space, head, wanted_eye, target_pos, blocking_meshes)
		_collect_ray_blockers(space, eye + right, head, target_pos, blocking_meshes)
		_collect_ray_blockers(space, eye - right, head, target_pos, blocking_meshes)

	_env_cache_clock -= delta
	if _env_cache_clock <= 0.0 or _env_meshes_cache.is_empty():
		_env_cache_clock = 0.45
		_refresh_env_meshes_cache()

	for mesh_id in _env_meshes_cache:
		if not is_instance_id_valid(mesh_id):
			continue
		var obj: Object = instance_from_id(mesh_id)
		if not (obj is MeshInstance3D):
			continue
		var mesh_inst: MeshInstance3D = obj as MeshInstance3D
		if not mesh_inst.is_inside_tree() or not mesh_inst.is_visible_in_tree() or mesh_inst.mesh == null:
			continue
		var world_box: AABB = mesh_inst.global_transform * mesh_inst.get_aabb()
		if _is_ground_or_backdrop_box(world_box, target_pos):
			continue
		var grown := world_box.grow(fade_corridor_radius)
		if grown.intersects_segment(eye, chest) or grown.intersects_segment(eye, head) \
				or world_box.grow(fade_corridor_radius * 0.65).intersects_segment(wanted_eye, head):
			blocking_meshes[mesh_id] = true

	for id in blocking_meshes.keys():
		if not _faded_meshes.has(id) and is_instance_id_valid(id):
			var obj: Object = instance_from_id(id)
			if obj is MeshInstance3D:
				var m: MeshInstance3D = obj as MeshInstance3D
				_faded_meshes[id] = {
					"base": m.transparency,
					"current": m.transparency,
				}

	var step := maxf(delta, 0.016) * fade_speed
	for id in _faded_meshes.keys():
		if not is_instance_id_valid(id):
			_faded_meshes.erase(id)
			continue
		var obj: Object = instance_from_id(id)
		if not (obj is MeshInstance3D):
			_faded_meshes.erase(id)
			continue
		var m: MeshInstance3D = obj as MeshInstance3D
		if not m.is_inside_tree():
			_faded_meshes.erase(id)
			continue
		var entry: Dictionary = _faded_meshes[id]
		var base_t := float(entry["base"])
		var is_blocking := blocking_meshes.has(id)
		var goal := maxf(base_t, fade_transparency) if is_blocking else base_t
		var cur := move_toward(float(entry["current"]), goal, step)
		entry["current"] = cur
		m.transparency = cur
		if not is_blocking and is_equal_approx(cur, base_t):
			m.transparency = base_t
			_faded_meshes.erase(id)


func _clear_all_faded_meshes() -> void:
	if _faded_meshes.is_empty():
		return
	for id in _faded_meshes.keys():
		if not is_instance_id_valid(id):
			continue
		var obj: Object = instance_from_id(id)
		if obj is MeshInstance3D:
			var entry: Dictionary = _faded_meshes[id]
			(obj as MeshInstance3D).transparency = float(entry["base"])
	_faded_meshes.clear()


func _collect_ray_blockers(
	space: PhysicsDirectSpaceState3D,
	from: Vector3,
	to: Vector3,
	target_pos: Vector3,
	out_meshes: Dictionary
) -> void:
	var excluded := _avoid_exclusions()
	for _pass in 5:
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = avoid_mask
		query.collide_with_areas = false
		query.exclude = excluded
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		var rid: RID = hit["rid"]
		excluded.append(rid)
		var collider_obj: Variant = hit.get("collider")
		if collider_obj == null or not is_instance_valid(collider_obj) or not (collider_obj is Node3D):
			continue
		var collider := collider_obj as Node3D
		if not _is_fading_candidate_node(collider):
			continue
		_gather_obstacle_meshes(collider, target_pos, out_meshes)


func _gather_obstacle_meshes(root_node: Node3D, target_pos: Vector3, out_meshes: Dictionary) -> void:
	var candidates: Array = []
	if root_node is MeshInstance3D:
		candidates.append(root_node)
	for child in root_node.find_children("*", "MeshInstance3D", true, false):
		candidates.append(child)
	for item in candidates:
		if not is_instance_valid(item) or not (item is MeshInstance3D):
			continue
		var mesh_inst := item as MeshInstance3D
		if not mesh_inst.is_inside_tree() or not mesh_inst.is_visible_in_tree() or mesh_inst.mesh == null:
			continue
		var world_box: AABB = mesh_inst.global_transform * mesh_inst.get_aabb()
		if _is_ground_or_backdrop_box(world_box, target_pos):
			continue
		out_meshes[mesh_inst.get_instance_id()] = true


func _is_ground_or_backdrop_box(world_box: AABB, target_pos: Vector3) -> bool:
	# Never fade floor slabs or ground beneath the player's knees.
	if world_box.end.y <= target_pos.y + 0.48:
		return true
	var span := maxf(world_box.size.x, world_box.size.z)
	# Never fade huge island ground slabs or water/sky planes.
	if span > 15.0 and world_box.size.y < 2.0:
		return true
	return false


func _is_fading_candidate_node(node: Node) -> bool:
	var walk: Node = node
	while walk != null and is_instance_valid(walk):
		if walk == target:
			return false
		if walk.is_in_group("player") or walk.is_in_group("enemies") or walk.is_in_group("collectible_coins"):
			return false
		var nm := String(walk.name)
		if nm.begins_with("Player") or nm.begins_with("Coin"):
			return false
		walk = walk.get_parent()
	return true


func _refresh_env_meshes_cache() -> void:
	_env_meshes_cache.clear()
	var tree := get_tree()
	if tree == null:
		return
	var root_node: Node = tree.current_scene if tree.current_scene != null else tree.root
	if root_node == null:
		return
	for child in root_node.find_children("*", "MeshInstance3D", true, false):
		if not is_instance_valid(child) or not (child is MeshInstance3D):
			continue
		var mesh_inst := child as MeshInstance3D
		if mesh_inst.mesh == null:
			continue
		if not _is_fading_candidate_node(mesh_inst):
			continue
		_env_meshes_cache.append(mesh_inst.get_instance_id())


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
