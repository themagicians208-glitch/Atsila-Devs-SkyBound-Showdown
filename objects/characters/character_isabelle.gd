extends "res://objects/character_style.gd"

## isabelle: her meshes are split by material rather than by body part, so the arm
## masks go on every mesh - they only ever catch geometry out past the shoulders,
## and each mesh has its own falloff expressed in its own space.
##
## Measured in the model's own space (isabelle.glb, before the scene's 0.01266
## scale): y is up from the feet (0 at the soles, 79 at the top of her hair), she
## faces +Z, x runs left to right, and her body is centred on x = -2.5 rather than
## on the model's origin.
##
## Her arms are short stubs held out at about y 28..36, and her hair hangs down
## into that same band but much further out (|side| 18..24 against 9..15 for her
## hands). That is what arm_x_far is for: without an outer edge the hair swings
## around with her arms. Her legs are inside a long dress, so only the boots below
## y 11 are rigged, and gently.

const CENTRE_X := -2.5
const CENTRE_Z := 38.0


func _init() -> void:
	limb_rig = true
	# Chosen so that up x side points along her forward axis (+Z).
	side_axis = Vector3(-1.0, 0.0, 0.0)
	side_origin = Vector3(CENTRE_X, 0.0, CENTRE_Z)
	rig_arm_all = true
	rig_tail = false
	# Her arms are short and her legs barely move, so the swing is pushed up a
	# little to carry the walk.
	arm_amp_scale = 1.3

	# Arms: the band her arms and hands live in, with the outer edge that keeps
	# her hair out of it.
	arm_y0 = 26.0
	arm_y1 = 29.0
	arm_y2 = 34.0
	arm_y3 = 37.0
	arm_x_in = 9.5
	arm_x_out = 11.0
	arm_x_far = 17.0
	# The pivot has to sit at the arm s own height, not above it: her arms are short
	# stubs, and a pivot above them swings the hands into her body instead of down.
	shoulder_y = 31.0
	shoulder_side = 9.5
	# She is sculpted with her arms almost level; a gentle drop relaxes them without
	# collapsing the mask across her dress.
	arm_drop = 1.55
	# Her arms run along the side axis, so the mirrored drop would send one arm up
	# and the other down. Unmirrored, both hang.
	arm_flap_mirror = -1.0

	# Her arms run along the side axis, so a reach about it would just twist them.
	# She plays a slash by lifting and dropping them instead.
	swing_via_flap = true

	# Feet: only the boots stick out below the dress.
	rig_leg_all = true
	leg_y0 = 8.0
	leg_y1 = 11.0
	leg_split = 4.0
	leg_side = 9.0
	hip_y = 12.0
	leg_amp_scale = 0.5
