extends Node

## Every collision shape a level builds has to be known to the physics server, or
## the wall, gate, platform or zone it belongs to is not there at all - it looks
## solid and is not.
##
## That is not hypothetical: with the Jolt backend, a CollisionShape3D added to a
## body that is ALREADY inside the tree is never registered. Every IslandGate in
## the Forgotten Island was built that way, so the sealed gates could be walked
## straight through. This check asks each shape whether the space knows it: a
## zero-length ray from inside a registered shape reports it, and an unregistered
## one reports nothing at all.
##
## Run one level per go: `tools/check_collision.tscn -- 2` (default 1).

## Below this, a shape's dimension is not a wall but a sheet of paper.
const MIN_THICKNESS := 0.02
## Some geometry is assembled a moment after the level loads, so the whole board is
## walked more than once.
const SCANS := 2
const SCAN_GAP_SECONDS := 2.5

var _problems: Array = []


func _ready() -> void:
	var level := 1
	for arg in OS.get_cmdline_user_args():
		if str(arg).is_valid_int():
			level = int(arg)
			break
	get_tree().set_meta("level_number", level)
	get_tree().set_meta("local_coop", false)
	get_tree().set_meta("online", false)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(0.8).timeout
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := get_viewport().world_3d.direct_space_state
	var checked := 0
	var skipped := 0
	for scan in SCANS:
		var shapes := main.find_children("*", "CollisionShape3D", true, false)
		for node in shapes:
			var shape := node as CollisionShape3D
			if shape.shape == null or shape.disabled:
				skipped += 1
				continue
			var body := _owning_body(shape)
			if body == null:
				skipped += 1
				continue
			# Thickness is checked whatever the layer: a shape with no volume is
			# wrong even when it belongs to the dimension nobody is in right now.
			var degenerate := _degenerate_size(shape.shape)
			if degenerate != "":
				_report("shape %s (%s, on %s at %s) is %s - a shape with no thickness has no volume, so it cannot stop anyone" % [
					shape.name, main.get_path_to(shape), body.name,
					(body as Node3D).global_position.round(), degenerate])
			if body.collision_layer == 0:
				# Trigger-only by design: areas that watch for a player
				# (checkpoints, portals, bounce pads) sit on layer 0 so nothing
				# else collides with them, and they detect whoever their mask
				# names. No ray can see them, and that is correct, so they are not
				# this check's business.
				skipped += 1
				continue
			checked += 1
			var spot := shape.global_position
			var query := PhysicsRayQueryParameters3D.create(spot, spot + Vector3(0.0, 0.03, 0.0))
			query.hit_from_inside = true
			query.collide_with_areas = true
			query.collide_with_bodies = true
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				_report("shape %s (%s, on %s at %s, layer %d mask %d) is not registered with physics - it is not solid" % [
					shape.name, main.get_path_to(shape), body.name,
					(body as Node3D).global_position.round(),
					body.collision_layer, body.collision_mask])
		if scan < SCANS - 1:
			# Some geometry is put together a moment after the level loads, and a
			# one-off look would never see it.
			await get_tree().create_timer(SCAN_GAP_SECONDS).timeout
			await get_tree().physics_frame

	print("level %d: %d collision shapes checked, %d skipped, %d problems" % [
		level, checked, skipped, _problems.size()])
	if _problems.is_empty():
		print("COLLISION OK - level %d's shapes are all solid" % level)
	else:
		print("COLLISION PROBLEMS (%d):" % _problems.size())
		for problem in _problems:
			print("  - %s" % problem)
	get_tree().quit(0 if _problems.is_empty() else 1)


## Note a problem once, however many scans see it.
func _report(problem: String) -> void:
	if not _problems.has(problem):
		_problems.append(problem)


## Whether the physics server really has this shape. The ray starts just outside
## one of the shape's own faces and points inward, so nothing else can possibly be
## in the way - and it must come back naming the body that owns the shape.
func _is_registered(space: PhysicsDirectSpaceState3D, shape: CollisionShape3D, body: CollisionObject3D) -> bool:
	var spot := shape.global_position
	for axis: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3.LEFT, Vector3.DOWN, Vector3.FORWARD]:
		var half := _extent(shape.shape, axis)
		if half <= 0.0:
			continue
		var from: Vector3 = spot + axis * (half + 0.05)
		var query := PhysicsRayQueryParameters3D.create(from, spot + axis * (half - 0.05))
		query.hit_back_faces = true
		query.collide_with_areas = true
		query.collide_with_bodies = true
		var hit := space.intersect_ray(query)
		if not hit.is_empty() and hit["collider"] == body:
			return true
	return false


## A shape with no thickness has no volume: the physics server will not stop anyone
## with it, so a wall built that way is one a player walks through while looking
## straight at it. This reports the shape's own dimensions when any of them is
## effectively zero.
func _degenerate_size(shape: Shape3D) -> String:
	if shape is BoxShape3D:
		var size := (shape as BoxShape3D).size
		var thin := PackedStringArray()
		for axis in ["x", "y", "z"]:
			if absf(size[axis]) < MIN_THICKNESS:
				thin.append(axis)
		if not thin.is_empty():
			return "a box of %s with no %s thickness" % [size, ", ".join(thin)]
	elif shape is CapsuleShape3D:
		if (shape as CapsuleShape3D).height < MIN_THICKNESS:
			return "a capsule with height %.3f" % (shape as CapsuleShape3D).height
	elif shape is CylinderShape3D:
		if (shape as CylinderShape3D).height < MIN_THICKNESS:
			return "a cylinder with height %.3f" % (shape as CylinderShape3D).height
	elif shape is SphereShape3D:
		if (shape as SphereShape3D).radius < MIN_THICKNESS:
			return "a sphere of radius %.3f" % (shape as SphereShape3D).radius
	elif shape is ConcavePolygonShape3D:
		var box: AABB = (shape as ConcavePolygonShape3D).get_aabb()
		if box.size.x < MIN_THICKNESS or box.size.y < MIN_THICKNESS or box.size.z < MIN_THICKNESS:
			return "a flat surface %s" % box.size
	return ""


## How far the shape reaches along one world axis.
func _extent(shape: Shape3D, axis: Vector3) -> float:
	if shape is BoxShape3D:
		var size := (shape as BoxShape3D).size
		return absf(size.x * axis.x) + absf(size.y * axis.y) + absf(size.z * axis.z)
	if shape is SphereShape3D:
		return (shape as SphereShape3D).radius
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		return capsule.radius + absf(axis.y) * capsule.height * 0.5
	if shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		return cylinder.radius + absf(axis.y) * cylinder.height * 0.5
	if shape is ConcavePolygonShape3D:
		var aabb: AABB = (shape as ConcavePolygonShape3D).get_aabb()
		return absf(aabb.size.x * axis.x) * 0.5 + absf(aabb.size.y * axis.y) * 0.5 + absf(aabb.size.z * axis.z) * 0.5
	return 1.0


## The CollisionObject3D a shape belongs to, however deep it is nested.
func _owning_body(shape: Node) -> CollisionObject3D:
	var walk: Node = shape.get_parent()
	while walk != null and not (walk is CollisionObject3D):
		walk = walk.get_parent()
	return walk as CollisionObject3D