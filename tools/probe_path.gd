extends Node

## Is a collision shape under an intermediate Node3D registered, and is one that is
## a direct child of the body? The gate nests its shape under a "Slab" node so the
## mesh can sink when the puzzle is solved.

func _ready() -> void:
	# Nesting: body -> Slab -> shape, all before the body joins the tree.
	var nested := StaticBody3D.new()
	nested.name = "NestedWall"
	var slab := Node3D.new()
	slab.name = "Slab"
	nested.add_child(slab)
	var nested_shape := CollisionShape3D.new()
	var nested_box := BoxShape3D.new()
	nested_box.size = Vector3(4.0, 2.0, 0.5)
	nested_shape.shape = nested_box
	nested_shape.position.y = 1.0
	slab.add_child(nested_shape)
	nested.position = Vector3(0.0, 0.0, 40.0)
	add_child(nested)

	# Direct: body -> shape, before the tree.
	var direct := StaticBody3D.new()
	direct.name = "DirectWall"
	var direct_shape := CollisionShape3D.new()
	var direct_box := BoxShape3D.new()
	direct_box.size = Vector3(4.0, 2.0, 0.5)
	direct_shape.shape = direct_box
	direct_shape.position.y = 1.0
	direct.add_child(direct_shape)
	direct.position = Vector3(0.0, 0.0, 60.0)
	add_child(direct)

	# Direct, but resized in _ready() time the way the gate resizes its own.
	var resized := StaticBody3D.new()
	resized.name = "ResizedWall"
	var resized_shape := CollisionShape3D.new()
	var resized_box := BoxShape3D.new()
	resized_box.size = Vector3(4.0, 2.0, 0.5)
	resized_shape.shape = resized_box
	resized_shape.position.y = 1.0
	resized.add_child(resized_shape)
	resized.position = Vector3(0.0, 0.0, 80.0)
	add_child(resized)
	(resized_shape.shape as BoxShape3D).size = Vector3(6.5, 3.2, 0.7)

	await get_tree().physics_frame
	await get_tree().physics_frame
	for body: CollisionObject3D in [nested, direct, resized]:
		print("%s: server shape count %d" % [
			body.name, PhysicsServer3D.body_get_shape_count(body.get_rid())])
	get_tree().quit()
