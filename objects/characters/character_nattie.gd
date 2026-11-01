extends "res://objects/character_style.gd"

## Nattie brings her own skeleton, so she is animated through her bones rather than
## by bending vertices. Her walk clip already animates her legs, spine and earrings
## - but it has no arm tracks at all, which is why her arms used to hang dead still
## while her legs moved. The walk cycle here drives her upper-arm bones, and the
## attack drives them the same way it drives the raccoon's arms, so all three
## characters move in the same style.
##
## Bone names come from the model's own rig (nattie.glb): arm.L_08 / arm.R_018 are
## the upper arms; rotating them carries the forearms and hands with them.

func _init() -> void:
	limb_rig = false          # nothing to bend: her limbs are real bones
	rig_bone_arms = PackedStringArray(["arm.L_08", "arm.R_018"])
	# Her side hair is skinned to these, so they are held against the swing.
	rig_bone_hold = PackedStringArray(["forearm.L_09", "forearm.R_019", "hand.L_010", "hand.R_020"])
	# She is sculpted with her hands on her hips. These turn her arms out of that
	# pose so her hands hang down at her sides at rest; the walk cycle is applied
	# on top of them.
	rig_bone_offsets = {
		"arm.L_08": [0.0, -0.25],
		"arm.R_018": [0.0, -0.25],
		"forearm.L_09": [0.0, 1.30],
		"forearm.R_019": [0.0, 1.30],
	}
	# Her shoulder line sits on the model's centre, so the side axis only has to
	# separate her left arm from her right.
	side_axis = Vector3(1.0, 0.0, 0.0)
	side_origin = Vector3(0.0, 0.0, 0.0)
	arm_amp_scale = 1.0
