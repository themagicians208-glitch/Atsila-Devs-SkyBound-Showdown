extends Node3D
class_name CharacterStyle

## Character styling + motion.
##
## The supplied model has no skeleton and its body, arms and legs are a single
## fused mesh, so this script
## 1. tints the character per player so 2-4 players look distinct, and
## 2. animates the limbs via `racoon_body.gdshader`, which bends the arm and leg
##    regions of that mesh around their joints.
##
## If a rigged model with animation clips is used later, set `animate_motion`
## to false and the clips take over.

const BODY_SHADER := preload("res://shaders/racoon_body.gdshader")

# --- limb rig configuration -------------------------------------------------
# Every character's limbs sit in a different place, so each one configures the
# rig in its own units. Subclasses (character_raccoon.gd, character_sam.gd, ...)
# fill these in; the defaults here are the raccoon's.
#
# Values are in the model's own space, which is the space the shader measures in:
#   * Y is up and starts at the feet.
#   * the "side" axis runs left/right, measured from the body's centre.
#
# Which meshes get rigged is decided by the `rig_arm_parents` / `rig_leg_parents`
# lists (the parent node names of the limb meshes). With no names given, the mesh
# reaching lowest is used, which is the right answer for a character whose body
# is one fused mesh.
@export var limb_rig := false
var rig_arm_parents: PackedStringArray = PackedStringArray()
var rig_leg_parents: PackedStringArray = PackedStringArray()
var rig_arm_all := false   # every mesh carries arm masks (limbs split by material)
var rig_leg_all := false
var side_axis := Vector3(0.0, 0.0, 1.0)
# A model-space point lying on the body's centre line. Models that are not built
# around their own origin (isabelle is 2.13 units to the side of hers) need this,
# or the limb masks and pivots land next to the character instead of on it.
var side_origin := Vector3(0.0, 0.0, 0.0)
var arm_y0 := 0.96     # arm band: fades in from y0 to y1 ...
var arm_y1 := 1.22
var arm_y2 := 1.56     # ... and back out from y2 to y3
var arm_y3 := 1.72
var arm_x_in := 0.44   # |side| where the arm weight starts rising
var arm_x_out := 0.86  # |side| where it is full
# Optional outer edge. 0 means the arm mask has no far edge, which suits models
# whose arms are the only thing out there. isabelle's hair hangs into the arm band
# further out than her hands, so she sets one.
var arm_x_far := 0.0
# Some models need both arms moved the same way rather than mirrored; see the
# shader s u_arm_flap_mirror.
var arm_flap_mirror := 1.0
var leg_y0 := 0.36     # complete leg weight below y0
var leg_y1 := 0.70     # none above y1
var leg_split := 0.16  # half-width of the gap between the legs
var leg_side := 0.33   # side offset of each hip
var hip_y := 0.46
var shoulder_y := 1.38
var shoulder_side := 0.58
# The raccoon is sculpted with its arms out to the sides; this drops them so they
# hang down at the character's sides. -PI/2 would be straight down.
var arm_drop := -1.30
# Only the raccoon has a separate tail mesh to sway; every other model would
# pick up some unrelated mesh as a "tail" and wobble it.
var rig_tail := false
# How much of the standard limb swing this character uses. A long dress, for
# instance, should only sway gently rather than stride.
var arm_amp_scale := 1.0
var leg_amp_scale := 1.0
# Some models have their arms running along the side axis (isabelle's are short
# stubs out to the sides). Reaching about that axis would only twist them, so a
# slash is played on the flap channel instead, lifting the arms in view. Such a
# character sets its own SWING_FLAP_POSE below.
var swing_via_flap := false
# Flap angles for a slash, keyed by direction: negative lifts the arms, positive
# drops them.
const SWING_FLAP_POSE := {0: -0.75, 1: 1.00, -1: -1.05}

# How far the limbs move, in radians. Swinging forward/back happens along the
# camera's view axis, so the walk only stays readable from behind thanks to the
# sideways motion: arms lifting/dropping and legs stepping wider.
const WALK_LEG_SWING := 0.85
const WALK_LEG_SPLAY := 0.24
const WALK_ARM_FLAP := 0.22
const WALK_ARM_SWING := 0.50
const AIR_LEG_TUCK := 0.12
const IDLE_ARM_FLAP := 0.07
const WALK_TAIL_SWAY := 0.45
const IDLE_TAIL_SWAY := 0.10

# Limb cycles per second at a normal walking pace (movement_speed 250 units/s at
# 60 fps comes to roughly 4.2 world units a second). The rate follows the real
# ground speed, so sprinting or dashing throws the arms and legs faster instead
# of the character sliding along at the same gait.
const WALK_RATE := 10.0
const WALK_SPEED := 4.2
const IDLE_RATE := 2.2
const SPRINT_RATE_MAX := 2.6

# Slash poses. Reach drives both arms the same way about the shoulder (negative =
# thrust forward, past horizontal and up), flap lifts them out to the sides, and
# SWING_LEAN is how far the body tips into the strike: forward and down lean in,
# an up swing leans back. One entry per direction, keyed 0 forward, 1 up, -1 down.
const SWING_REACH := {0: -1.55, 1: -2.75, -1: -0.55}
const SWING_FLAP := {0: 0.18, 1: 0.90, -1: -0.45}
const SWING_LEAN := {0: 0.30, 1: -0.34, -1: 0.30}

const PALETTES := [
	Color(1.00, 0.86, 0.38),  # player 1 - sunny gold
	Color(0.46, 0.80, 1.00),  # player 2 - sky blue
	Color(0.62, 1.00, 0.58),  # player 3 - mint green
	Color(1.00, 0.62, 0.86),  # player 4 - blossom pink
]

@export var player_index := 0
@export var animate_motion := true

# A model that brings its own skeleton can be driven by real bones instead of by
# bending vertices (Nattie). These are the bone names whose rotation carries the
# walk cycle; rotating an upper arm swings everything below it with it.
var rig_bone_arms: PackedStringArray = PackedStringArray()
# Bones to hold steady against that rotation. Nattie's side hair is skinned to her
# hand and forearm bones, so without this her hair sweeps around with her arms.
var rig_bone_hold: PackedStringArray = PackedStringArray()
# Rest-pose corrections, "bone name": [swing, lift] in radians, applied constantly
# and then walked over by the walk cycle. Nattie's hands rest on her hips, so hers
# turn the forearms until they hang at her sides. Lift is mirrored per side
# (a positive value raises both arms), swing is not (it moves both the same way).
var rig_bone_offsets: Dictionary = {}
var _bone_arms: Array[Dictionary] = []
var _skeleton: Skeleton3D

var _materials: Array[BaseMaterial3D] = []
var _base_colors: Array[Color] = []
var _anim_node: Node3D
var _body: CharacterBody3D
var _phase := 0.0
var _collected := false

# Limb animation state. One material per rigged mesh, because each mesh has its
# own local space and the joints have to be expressed in that space.
var _limb_materials: Array[ShaderMaterial] = []
var _limb_bases: Array[Color] = []

# Slash pose, driven by the player while an attack plays: how far through the
# swing it is (0 to 1) and which way it is aimed (0 forward, 1 up, -1 down).
var swing := 0.0
var swing_dir := 0
var _leg_swing := 0.0
var _arm_swing := 0.0
var _crouch := 0.0
var _arm_flap := 0.0
var _leg_splay := 0.0

# The tail is a separate mesh, so it can simply be rotated - and it is the most
# visible part of the character from the game camera.
var _tail_pivot: Node3D
var _tail_sway := 0.0

# Brighten mid-greys so a tint reads as a bold colour instead of muddy brown.
const TINT_GAIN := 1.6


func _ready() -> void:
	_anim_node = get_node_or_null("anim") as Node3D
	_body = get_parent() as CharacterBody3D
	_loop_cycle_clips()
	_collect_materials()
	apply_player_color(player_index)


## A model's walk cycle is usually exported as a one-shot clip, so it plays once
## and then the character's legs freeze mid-stride. Anything named like a loop is
## made to loop here.
func _loop_cycle_clips() -> void:
	for node in find_children("*", "AnimationPlayer", true, false):
		var player := node as AnimationPlayer
		for clip_name in player.get_animation_list():
			var lower := String(clip_name).to_lower()
			if not (lower.contains("walk") or lower.contains("run") or lower.contains("idle")):
				continue
			var clip := player.get_animation(clip_name)
			if clip != null and clip.loop_mode == Animation.LOOP_NONE:
				clip.loop_mode = Animation.LOOP_LINEAR


func _collect_materials() -> void:
	_materials.clear()
	_base_colors.clear()
	_limb_materials.clear()
	_limb_bases.clear()
	_collected = true

	if rig_tail:
		_build_tail_pivot()
	_build_bone_rig()

	# Limb meshes get the bending shader instead of a plain tint.
	var rigged: Dictionary = {}
	for entry in _rig_meshes():
		var mesh_instance: MeshInstance3D = entry["mesh"]
		_build_limb_shader(mesh_instance, entry["arms"], entry["legs"])
		rigged[mesh_instance] = true

	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if rigged.has(mesh_instance):
			continue
		var mesh: Mesh = mesh_instance.mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var material: Material = mesh_instance.get_active_material(surface)
			if material is BaseMaterial3D:
				# Duplicate so tinting one player never affects the others.
				var copy := (material as BaseMaterial3D).duplicate() as BaseMaterial3D
				mesh_instance.set_surface_override_material(surface, copy)
				_materials.append(copy)
				_base_colors.append(copy.albedo_color)

	# A bone rig with no vertex materials to update (Nattie) would otherwise sit in
	# the model's own rest pose until something posed it.
	_apply_pose()


## Which meshes carry limbs, and which of the two masks each one needs.
func _rig_meshes() -> Array[Dictionary]:
	var picked: Array[Dictionary] = []
	if not limb_rig:
		return picked
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var parent_name := ""
		if mesh_instance.get_parent() != null:
			parent_name = String(mesh_instance.get_parent().name)
		var arms := rig_arm_all or rig_arm_parents.has(parent_name)
		var legs := rig_leg_all or rig_leg_parents.has(parent_name)
		if arms or legs:
			picked.append({"mesh": mesh_instance, "arms": arms, "legs": legs})
	if picked.is_empty():
		# Limbs fused into one mesh: it is the mesh reaching lowest.
		var body := _find_body_mesh()
		if body != null:
			picked.append({"mesh": body, "arms": true, "legs": true})
	return picked


## Transform from a node's own space up to the model root (the GLB instance node).
## This is the space the joint constants above were measured in.
func _transform_to_model_root(node: Node3D) -> Transform3D:
	var chain: Array[Node3D] = []
	var walk: Node = node
	while walk != null and walk.name != "model":
		if walk is Node3D:
			chain.append(walk as Node3D)
		walk = walk.get_parent()
	var result := Transform3D()
	for i in range(chain.size() - 1, -1, -1):
		result = result * chain[i].transform
	return result


func _find_body_mesh() -> MeshInstance3D:
	var lowest := INF
	var found: MeshInstance3D = null
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var mesh: Mesh = mesh_instance.mesh
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var bottom := _mesh_bottom(mesh_instance)
		if bottom < lowest:
			lowest = bottom
			found = mesh_instance
	return found


func _mesh_bottom(mesh_instance: MeshInstance3D) -> float:
	var xform := _transform_to_model_root(mesh_instance)
	var box := mesh_instance.get_aabb()
	var lowest := INF
	for corner_index in 8:
		var corner := box.position + Vector3(
			box.size.x * float(corner_index & 1),
			box.size.y * float((corner_index >> 1) & 1),
			box.size.z * float((corner_index >> 2) & 1))
		lowest = minf(lowest, (xform * corner).y)
	return lowest


## Work out how to drive a character's own skeleton. Each bone is stored with the
## axes it needs, converted from model space into that bone's own space, and the
## sign that makes the left arm lead with the left leg.
func _build_bone_rig() -> void:
	_bone_arms.clear()
	_skeleton = null
	if rig_bone_arms.is_empty():
		return
	_skeleton = _find_skeleton()
	if _skeleton == null:
		return
	var to_model := _transform_to_model_root(_skeleton)
	for index in _skeleton.get_bone_count():
		var bone_name := String(_skeleton.get_bone_name(index))
		var driven := rig_bone_arms.has(bone_name)
		var held := rig_bone_hold.has(bone_name)
		if not (driven or held):
			continue
		var bone_to_model := to_model * _skeleton.get_bone_global_rest(index)
		var side := (bone_to_model.origin - side_origin).dot(side_axis)
		var offset: Array = rig_bone_offsets.get(bone_name, [0.0, 0.0])
		_bone_arms.append({
			"index": index,
			"parent": _skeleton.get_bone_parent(index),
			"bone_to_model": bone_to_model.basis,
			# A held bone keeps the orientation it has at rest, whatever its parents do.
			"driven": driven,
			"swing_off": float(offset[0]),
			"lift_off": float(offset[1]),
			"lead": -signf(side) if absf(side) > 0.0001 else 1.0,
		})
	if not _bone_arms.is_empty():
		pass


func _find_skeleton() -> Skeleton3D:
	for node in find_children("*", "Skeleton3D", true, false):
		return node as Skeleton3D
	return null


## The same walk cycle the vertex rig uses, applied to real bones instead.
##
## Each bone gets a target rotation in model space, and its own pose is whatever is
## left after its parents have been accounted for - that is what keeps a held bone
## (her hair rides on the hand bones) still when the arm above it swings.
func _apply_bone_pose(arm_swing: float, arm_reach: float, arm_flap: float) -> void:
	if _bone_arms.is_empty() or _skeleton == null:
		return
	var axis_side := side_axis.normalized()
	var axis_front := Vector3.UP.cross(side_axis).normalized()
	var totals: Dictionary = {}
	for entry in _bone_arms:
		var index := int(entry["index"])
		var parent := int(entry["parent"])
		var parent_total: Quaternion = totals.get(parent, Quaternion.IDENTITY)
		var desired := Quaternion.IDENTITY
		var lead := float(entry["lead"])
		var off_swing := float(entry["swing_off"])
		var off_lift := float(entry["lift_off"]) * lead
		if bool(entry["driven"]):
			var swing_amount := (arm_swing * lead - arm_reach) * arm_amp_scale + off_swing
			var lift := arm_flap * lead * arm_amp_scale + off_lift
			desired = Quaternion(axis_side, swing_amount) * Quaternion(axis_front, lift)
		elif not (is_zero_approx(off_swing) and is_zero_approx(off_lift)):
			# A held bone still holds, but at its corrected rest angle: the arm above
			# it swings without dragging the geometry skinned to this bone.
			desired = Quaternion(axis_side, off_swing) * Quaternion(axis_front, off_lift)
		totals[index] = desired
		var own_model := parent_total.inverse() * desired
		var rest := entry["bone_to_model"] as Basis
		var pose := rest.inverse() * Basis(own_model) * rest
		_skeleton.set_bone_pose_rotation(index, pose.get_rotation_quaternion())


## The tail is its own mesh group, so wrap it in a pivot at its base and sway that.
func _build_tail_pivot() -> void:
	var furthest := INF
	var tail_mesh: MeshInstance3D = null
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var centre := _model_box(mesh_instance).get_center()
		if centre.x < furthest:
			furthest = centre.x
			tail_mesh = mesh_instance
	if tail_mesh == null:
		return
	var group := tail_mesh.get_parent() as Node3D
	if group == null:
		return
	var host := group.get_parent() as Node3D
	if host == null:
		return

	var union := AABB()
	var first := true
	for node in group.find_children("*", "MeshInstance3D", true, false):
		var box := _model_box(node as MeshInstance3D)
		if first:
			union = box
			first = false
		else:
			union = union.merge(box)
	# Hinge at the inner end of the tail, where it meets the body.
	var base := Vector3(union.end.x, union.get_center().y, union.get_center().z)

	var host_to_model := _transform_to_model_root(host)
	var pivot := Node3D.new()
	pivot.name = "TailPivot"
	host.add_child(pivot)
	pivot.transform = host_to_model.affine_inverse() * Transform3D(Basis(), base)
	group.reparent(pivot, true)
	_tail_pivot = pivot


## A mesh instance's bounds expressed in model space.
func _model_box(mesh_instance: MeshInstance3D) -> AABB:
	var xform := _transform_to_model_root(mesh_instance)
	var box := mesh_instance.get_aabb()
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for corner_index in 8:
		var corner := box.position + Vector3(
			box.size.x * float(corner_index & 1),
			box.size.y * float((corner_index >> 1) & 1),
			box.size.z * float((corner_index >> 2) & 1))
		var point := xform * corner
		low = low.min(point)
		high = high.max(point)
	return AABB(low, high - low)


## Give one mesh the limb-bending shader, with every joint converted from model
## space into that mesh's own space.
func _build_limb_shader(body: MeshInstance3D, arms: bool, legs: bool) -> void:
	var to_model := _transform_to_model_root(body)
	var to_model_basis := to_model.basis
	var origin := to_model.origin
	var model_to_local := to_model_basis.inverse()

	var material := ShaderMaterial.new()
	material.shader = BODY_SHADER

	# A model-space coordinate along `axis` is dot(model_point, axis), and the
	# model point is basis * vertex + origin, so it reads as a dot product with
	# the axis expressed in the mesh's own space.
	var up := Vector3.UP
	var centre := side_origin.dot(side_axis)
	material.set_shader_parameter("u_y_vec", Vector3(
		to_model_basis.x.dot(up), to_model_basis.y.dot(up), to_model_basis.z.dot(up)))
	material.set_shader_parameter("u_y_off", origin.dot(up))
	material.set_shader_parameter("u_side_vec", Vector3(
		to_model_basis.x.dot(side_axis), to_model_basis.y.dot(side_axis), to_model_basis.z.dot(side_axis)))
	material.set_shader_parameter("u_side_off", origin.dot(side_axis) - centre)

	# The limb masks, already weighted towards this model's proportions.
	material.set_shader_parameter("u_arm_y0", arm_y0)
	material.set_shader_parameter("u_arm_y1", arm_y1)
	material.set_shader_parameter("u_arm_y2", arm_y2)
	material.set_shader_parameter("u_arm_y3", arm_y3)
	material.set_shader_parameter("u_arm_x_in", arm_x_in)
	material.set_shader_parameter("u_arm_x_out", arm_x_out)
	material.set_shader_parameter("u_arm_x_far", arm_x_far)
	material.set_shader_parameter("u_arm_flap_mirror", arm_flap_mirror)
	material.set_shader_parameter("u_leg_y0", leg_y0)
	material.set_shader_parameter("u_leg_y1", leg_y1)
	material.set_shader_parameter("u_leg_split", leg_split)
	material.set_shader_parameter("u_leg_side", leg_side)
	material.set_shader_parameter("u_do_arms", 1.0 if arms else 0.0)
	material.set_shader_parameter("u_do_legs", 1.0 if legs else 0.0)
	material.set_shader_parameter("u_arm_drop", arm_drop)

	material.set_shader_parameter("u_axis_up", (model_to_local * up).normalized())
	material.set_shader_parameter("u_axis_left_right", (model_to_local * side_axis).normalized())
	material.set_shader_parameter("u_axis_front_back", (model_to_local * up.cross(side_axis)).normalized())
	material.set_shader_parameter("u_up_local", model_to_local * up)
	var centre_line := Vector3(side_origin.x, hip_y, side_origin.z)
	material.set_shader_parameter("u_leg_pivot_l", model_to_local * (centre_line - side_axis * leg_side - origin))
	material.set_shader_parameter("u_leg_pivot_r", model_to_local * (centre_line + side_axis * leg_side - origin))
	var shoulder_line := Vector3(side_origin.x, shoulder_y, side_origin.z)
	material.set_shader_parameter("u_arm_pivot_l", model_to_local * (shoulder_line - side_axis * shoulder_side - origin))
	material.set_shader_parameter("u_arm_pivot_r", model_to_local * (shoulder_line + side_axis * shoulder_side - origin))

	var base := Color.WHITE
	var existing := body.get_active_material(0)
	if existing is BaseMaterial3D:
		base = (existing as BaseMaterial3D).albedo_color
		material.set_shader_parameter("roughness", (existing as BaseMaterial3D).roughness)
	material.set_shader_parameter("albedo_color", base)

	body.material_override = material
	_limb_materials.append(material)
	_limb_bases.append(base)
	_apply_pose()


func set_player_index(index: int) -> void:
	apply_player_color(index)


func apply_player_color(index: int) -> void:
	player_index = index
	if not _collected:
		_collect_materials()
	# Player 2 keeps the colours the model was made with. Everyone else is
	# recoloured, so a co-op pair is still easy to tell apart.
	var plain := index == 1
	var tint: Color = PALETTES[index % PALETTES.size()]
	for i in _materials.size():
		_materials[i].albedo_color = _base_colors[i] if plain else _tinted(_base_colors[i], tint)
	for i in _limb_materials.size():
		_limb_materials[i].set_shader_parameter("albedo_color",
			_limb_bases[i] if plain else _tinted(_limb_bases[i], tint))


## Recolour from the original shade every time, so the raccoon's black mask and
## pale chest keep their contrast while the fur takes the player colour.
func _tinted(base: Color, tint: Color) -> Color:
	return Color(
		minf(base.r * tint.r * TINT_GAIN, 1.0),
		minf(base.g * tint.g * TINT_GAIN, 1.0),
		minf(base.b * tint.b * TINT_GAIN, 1.0),
		base.a)


## Force a limb pose (used by the preview tools).
func set_pose(leg_swing: float, arm_swing: float, crouch: float, arm_flap: float = 0.0,
		leg_splay: float = 0.0, tail_sway: float = 0.0) -> void:
	_leg_swing = leg_swing
	_arm_swing = arm_swing
	_crouch = crouch
	_arm_flap = arm_flap
	_leg_splay = leg_splay
	_tail_sway = tail_sway
	_apply_pose()


## Drive the attack pose: `amount` is 0 at rest and peaks at 1 mid-swing.
func set_swing(amount: float, direction: int) -> void:
	swing = clampf(amount, 0.0, 1.0)
	swing_dir = direction
	_apply_pose()


func _apply_pose() -> void:
	var arm_swing := _arm_swing
	var arm_reach := 0.0
	var arm_flap := _arm_flap
	if swing > 0.001:
		# A slash takes the arms off the walk cycle entirely.
		arm_swing = 0.0
		if swing_via_flap:
			arm_flap = lerpf(_arm_flap, float(SWING_FLAP_POSE[swing_dir]), swing)
		else:
			arm_reach = lerpf(0.0, float(SWING_REACH[swing_dir]), swing)
			arm_flap = lerpf(_arm_flap, float(SWING_FLAP[swing_dir]), swing)
	for material in _limb_materials:
		material.set_shader_parameter("u_leg_swing", _leg_swing * leg_amp_scale)
		material.set_shader_parameter("u_arm_swing", arm_swing * arm_amp_scale)
		material.set_shader_parameter("u_arm_reach", arm_reach * arm_amp_scale)
		material.set_shader_parameter("u_crouch", _crouch)
		material.set_shader_parameter("u_arm_flap", arm_flap * arm_amp_scale)
		material.set_shader_parameter("u_leg_splay", _leg_splay * leg_amp_scale)
	_apply_bone_pose(arm_swing, arm_reach, arm_flap)
	if _tail_pivot != null:
		_tail_pivot.rotation.y = _tail_sway


func _process(delta: float) -> void:
	if not animate_motion or _anim_node == null or _body == null:
		return
	var speed := Vector2(_body.velocity.x, _body.velocity.z).length()
	var grounded := _body.is_on_floor()
	var moving := speed > 0.6 and grounded
	var gait := clampf(speed / WALK_SPEED, 0.55, SPRINT_RATE_MAX)
	_phase += delta * (WALK_RATE * gait if moving else IDLE_RATE)

	# Legs and arms swing in opposite phase while walking; the legs tuck up in
	# the air; otherwise the arms just breathe gently.
	var leg_target := 0.0
	var splay_target := 0.0
	var swing_target := 0.0
	var flap_target := 0.0
	var crouch_target := 0.0
	var tail_target := 0.0
	if moving:
		leg_target = sin(_phase) * WALK_LEG_SWING
		splay_target = -sin(_phase) * WALK_LEG_SPLAY
		swing_target = -sin(_phase) * WALK_ARM_SWING
		flap_target = -sin(_phase) * WALK_ARM_FLAP
		# The tail swings across the body, in time with the steps.
		tail_target = sin(_phase * 0.5) * WALK_TAIL_SWAY
	elif not grounded:
		crouch_target = AIR_LEG_TUCK
		swing_target = -WALK_ARM_SWING
		flap_target = -WALK_ARM_FLAP * 0.6
		tail_target = 0.0
	else:
		flap_target = sin(_phase) * IDLE_ARM_FLAP
		tail_target = sin(_phase * 0.5) * IDLE_TAIL_SWAY

	_leg_swing = lerpf(_leg_swing, leg_target, delta * 14.0)
	_leg_splay = lerpf(_leg_splay, splay_target, delta * 14.0)
	_arm_swing = lerpf(_arm_swing, swing_target, delta * 14.0)
	_arm_flap = lerpf(_arm_flap, flap_target, delta * 14.0)
	_crouch = lerpf(_crouch, crouch_target, delta * 9.0)
	_tail_sway = lerpf(_tail_sway, tail_target, delta * 10.0)
	_apply_pose()

	# A little whole-body bob and waddle on top of the limb motion.
	var amplitude := (0.09 * minf(gait, 1.6)) if moving else 0.016
	_anim_node.position.y = lerpf(_anim_node.position.y, absf(sin(_phase)) * amplitude, delta * 12.0)
	var roll := sin(_phase * 0.5) * (0.11 if moving else 0.02)
	_anim_node.rotation.z = lerpf(_anim_node.rotation.z, roll, delta * 8.0)
	# Lean into a slash, which reads even on a rig whose clips we are not using.
	var swing_lean := 0.0
	if swing > 0.001:
		swing_lean = float(SWING_LEAN[swing_dir]) * swing
	var pitch := (0.07 if moving else 0.0) + swing_lean
	_anim_node.rotation.x = lerpf(_anim_node.rotation.x, pitch, delta * 14.0)