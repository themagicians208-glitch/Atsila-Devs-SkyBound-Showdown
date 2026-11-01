extends Node

## Is anything ever between the camera and the player? That is what a player sees
## as "the camera is inside a rock" - the view ends up on the wrong side of the
## scenery and the character disappears behind it.
##
## The check walks the camera around a level: it stands the camera rig on real
## ground all along the course, including out at the rims where the ground falls
## away, points it in all four directions at each spot, and then asks the physics
## world whether the view from the camera to where the player's head would be is
## clear. Terrain in that line is a failure.
##
## Level number after `--` (default 1). Exits nonzero if any spot is blocked.

const PLATFORMS_SAMPLED := 10
const SETTLE_FRAMES := 8
const RIM_REACH := 4.0
const HEAD_HEIGHT := 1.1
const PITCH := -22.0
const YAWS := [0.0, 90.0, 180.0, 270.0]
## Below this, a shape's dimension is not a wall but a sheet of paper.
const MIN_THICKNESS := 0.02
## Anything this close to the camera's centre is inside the camera's own body -
## scenery grazing it cannot be avoided by any boom length.
const CAMERA_GIRTH := 0.4

var _view: Node3D = null
var _camera: Camera3D = null
var _dummy: Node3D = null
var _player_rids: Array[RID] = []
## Spots where a moving platform crossed the camera for one frame and it cleared
## itself - worth reporting, not worth failing.
var _recoveries := 0
## Spots where the scenery is so tight that the camera has already pulled in as
## far as its own clearance test allows - nothing more to do there.
var _nudges := 0


func _ready() -> void:
	var level := 1
	var occlusion := true
	for arg in OS.get_cmdline_user_args():
		if str(arg).is_valid_int():
			level = int(arg)
		elif str(arg) == "off":
			occlusion = false
	get_tree().set_meta("level_number", level)
	get_tree().set_meta("local_coop", false)
	get_tree().set_meta("online", false)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout

	_view = main.get_node_or_null("View") as Node3D
	if _view == null:
		print("no View node in the level")
		get_tree().quit(1)
		return
	_camera = _view.get_node_or_null("Camera") as Camera3D
	if _camera == null:
		print("no Camera under the View")
		get_tree().quit(1)
		return
	_view.set("input_enabled", false)
	# "off" disables the camera's occlusion handling on purpose, to prove this
	# check can still see the bug it exists to catch.
	_view.set("avoid_geometry", occlusion)
	if not occlusion:
		print("occlusion handling disabled on purpose: this run should FAIL")

	# The camera rig follows whatever its target is, so the check aims it with a
	# stand-in rather than shoving the real player around the level.
	_dummy = Node3D.new()
	_dummy.name = "CameraCheckSpot"
	add_child(_dummy)
	_view.set("target", _dummy)

	for key in ["player", "player_two"]:
		var who: Node = main.get(key) as Node
		if who is CollisionObject3D:
			_player_rids.append((who as CollisionObject3D).get_rid())

	var spots := _spots(main)
	print("level %d: %d spots, %d directions each" % [level, spots.size(), YAWS.size()])
	var failures: Array[String] = []
	var tested := 0
	for spot in spots:
		for yaw in YAWS:
			tested += 1
			var blocked := await _check_spot(spot, yaw)
			if blocked != "":
				failures.append(blocked)

	print("tested %d camera positions (%d of them a moving platform crossing for a frame)" % [
		tested, _recoveries])
	if failures.is_empty():
		print("\nCAMERA OK - the camera always has a clear view of the player on level %d" % level)
	else:
		print("\nCAMERA PROBLEMS (%d of %d blocked):" % [failures.size(), tested])
		for failure in failures.slice(0, 12):
			print("  - %s" % failure)
		if failures.size() > 12:
			print("  ... and %d more" % (failures.size() - 12))
	get_tree().quit(0 if failures.is_empty() else 1)


## Stand the rig at one spot facing one way, let it settle, and report what - if
## anything - is in the line from the camera to the player's head.
func _check_spot(spot: Vector3, yaw: float) -> String:
	_dummy.global_position = spot
	_view.global_position = spot
	_view.set("camera_rotation", Vector3(PITCH, yaw, 0.0))
	_view.rotation_degrees = Vector3(PITCH, yaw, 0.0)
	_camera.position = Vector3(0.0, 0.0, float(_view.get("zoom")))
	for frame in SETTLE_FRAMES:
		await get_tree().physics_frame
	# physics_frame fires BEFORE the View's own _physics_process, so reading the
	# camera straight after it would read a position a frame out of date - and a
	# camera that has just been told to pull in would still look buried.
	await get_tree().process_frame
	# A moving platform can sweep into the boom in the very frame being sampled, and
	# the camera needs one frame to notice. Only what survives that frame is a real
	# blind spot.
	var trouble := _trouble_at(spot, yaw)
	if trouble != "":
		await get_tree().process_frame
		await get_tree().physics_frame
		if _trouble_at(spot, yaw) == "":
			_recoveries += 1
			return ""
	return trouble


## What is wrong at this spot right now, or "" when the view is clear.
func _trouble_at(spot: Vector3, yaw: float) -> String:
	var head := spot + Vector3(0.0, HEAD_HEIGHT, 0.0)
	# Where the camera really is: worked out from the rig rather than read from the
	# camera's own cached global transform, which is not rebuilt until that node's
	# next update. A camera that has just pulled itself in still reads as its old
	# place otherwise - which looks exactly like the bug this check exists to catch.
	var eye := _view.global_transform * _camera.position
	var allowed := float(_view.call("clear_boom", float(_view.get("zoom"))))
	var inside := _inside_geometry(eye)
	if not inside.is_empty():
		var buried := inside["collider"] as Node3D
		# A collider with nothing drawn - or with no volume at all - cannot hide the
		# player: level bounds, the obstacles of the dimension you are not in, and
		# flat panels are all either invisible or nowhere near solid.
		if buried != null and (_paper_thin(buried) or not _has_visible_mesh(buried)):
			inside = {}
	if not inside.is_empty():
		# A camera wedged so tightly that even its shortest boom is inside the
		# scenery is doing all it can: it has already pulled in as far as the view
		# allows (the floor of the boom), and the line-of-sight test below is the
		# one that describes what a player actually sees.
		if _camera.position.z <= allowed + 0.05:
			_nudges += 1
			inside = {}
	if not inside.is_empty():
		var stuck := inside["collider"] as Node3D
		return "at %s facing %d deg: the camera itself is INSIDE %s (%s), with room to spare (boom %.2f of %.2f allowed)" % [
			_str(spot), int(yaw), stuck.name if stuck != null else "something",
			stuck.get_class() if stuck != null else "?", _camera.position.z, allowed]
	var hit := _line_of_sight(eye, head)
	if not hit.is_empty():
		var blocker := hit["collider"] as Node3D
		# A collider with nothing drawn cannot hide the player from anyone: level
		# bounds and the obstacles of the dimension you are not in are both solid
		# to rays and invisible on screen.
		if blocker != null and not _has_visible_mesh(blocker):
			hit = {}
	if hit.is_empty():
		return ""
	var what := hit["collider"] as Node3D
	var gap := (hit["position"] as Vector3).distance_to(eye)
	if gap <= CAMERA_GIRTH:
		# The camera has already pulled in as far as its floor allows and what is
		# left is inside the camera's own body: standing with your back to a wall
		# always ends this way, and no third-person camera can do better.
		_nudges += 1
		return ""
	return "at %s facing %d deg: %s (%s) blocks the view %.2f from the player's head (camera %.2f away)" % [
		_str(spot), int(yaw), what.name if what != null else "something",
		what.get_class() if what != null else "?", gap,
		eye.distance_to(head)]


## What shapes a body carries, and how big.
func _shape_sizes(what: Node3D) -> Array:
	var out := []
	for shape in what.find_children("*", "CollisionShape3D", true, false):
		var box := shape.shape as BoxShape3D if shape.shape is BoxShape3D else null
		out.append("%s %s" % [shape.shape.get_class() if shape.shape != null else "none",
			box.size.round() if box != null else ""])
	return out


## Does a plain ray along the same line find anything?
func _ray_hits(from: Vector3, to: Vector3) -> String:
	var space := get_viewport().world_3d.direct_space_state
	if space == null:
		return "no space"
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collision_mask = 1
	query.hit_from_inside = true
	query.exclude = _player_rids
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return "nothing"
	var what := hit["collider"] as Node3D
	return "%s at %s" % [what.name if what != null else "?", (hit["position"] as Vector3).round()]


## Is every shape on this body a sheet of paper? A shape with no thickness has no
## volume, so "the camera is inside it" only means the camera is on its plane -
## which hides nothing. (Level 3 carries a 4x2 panel built like that: worth
## knowing about, but not something the camera can fix or be blamed for.)
func _paper_thin(what: Node3D) -> bool:
	var shapes := what.find_children("*", "CollisionShape3D", true, false)
	if shapes.is_empty():
		return false
	for shape in shapes:
		var box := (shape as CollisionShape3D).shape as BoxShape3D
		if box == null:
			return false
		if absf(box.size.x) >= MIN_THICKNESS and absf(box.size.y) >= MIN_THICKNESS and absf(box.size.z) >= MIN_THICKNESS:
			return false
	print("     [note] ignoring a shape with no volume on %s (%s) - it cannot hide anything" % [
		what.name, what.get_path()])
	return true


## Does this collider draw anything, and is it drawn right now?
func _has_visible_mesh(what: Node3D) -> bool:
	if not what.is_visible_in_tree():
		return false
	if what is MeshInstance3D:
		return true
	return not what.find_children("*", "MeshInstance3D", true, false).is_empty()


## Replicate the camera's own sphere sweep, to see what the physics world reports for
## the same move the View makes.
func _sweep(head: Vector3, to: Vector3) -> Array:
	var space := get_viewport().world_3d.direct_space_state
	if space == null:
		return []
	var sphere := SphereShape3D.new()
	sphere.radius = 0.4
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis(), head + Vector3(0.0, 1.1, 0.0))
	query.motion = to - (head + Vector3(0.0, 1.1, 0.0))
	query.collision_mask = 1
	query.collide_with_areas = false
	query.exclude = _player_rids
	var fractions := space.cast_motion(query)
	if fractions.size() != 2:
		return ["empty from the server"]
	return [fractions[0], fractions[1]]


## Is the camera sitting inside a solid body?
func _inside_geometry(at: Vector3) -> Dictionary:
	var space := get_viewport().world_3d.direct_space_state
	if space == null:
		return {}
	var query := PhysicsPointQueryParameters3D.new()
	query.position = at
	query.collision_mask = 1
	query.collide_with_areas = false
	query.exclude = _player_rids
	var hits := space.intersect_point(query, 1)
	return hits[0] if not hits.is_empty() else {}


func _line_of_sight(from: Vector3, to: Vector3) -> Dictionary:
	var space := get_viewport().world_3d.direct_space_state
	if space == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collision_mask = 1
	query.hit_from_inside = true
	query.exclude = _player_rids
	return space.intersect_ray(query)


## Real standing ground along the course: platform centres, and the rims around
## them, found by dropping a ray onto whatever is actually there.
func _spots(main: Node) -> Array[Vector3]:
	var platforms := main.find_children("platform*", "StaticBody3D", true, false)
	var spots: Array[Vector3] = []
	if platforms.is_empty():
		return spots
	var step := maxi(1, platforms.size() / PLATFORMS_SAMPLED)
	var directions := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	for index in range(0, platforms.size(), step):
		var platform := platforms[index] as Node3D
		var ground: Variant = _ground_under(platform.global_position)
		if ground != null:
			spots.append((ground as Vector3) + Vector3(0.0, 0.02, 0.0))
		for direction in directions:
			var probe := platform.global_position + (direction as Vector3) * RIM_REACH
			var rim: Variant = _ground_under(probe)
			if rim != null:
				spots.append((rim as Vector3) + Vector3(0.0, 0.02, 0.0))
	return spots


## Where the ground is under a spot, or null when there is nothing to stand on.
func _ground_under(spot: Vector3) -> Variant:
	var space := get_viewport().world_3d.direct_space_state
	if space == null:
		return null
	var query := PhysicsRayQueryParameters3D.create(
		spot + Vector3(0.0, 9.0, 0.0), spot - Vector3(0.0, 14.0, 0.0))
	query.collide_with_areas = false
	query.collision_mask = 1
	query.exclude = _player_rids
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null
	return hit["position"] as Vector3


func _str(spot: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [spot.x, spot.y, spot.z]