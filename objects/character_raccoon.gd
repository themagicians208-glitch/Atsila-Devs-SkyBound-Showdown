extends "res://objects/character_style.gd"

## Jamal (the raccoon) is the only character whose body is one fused mesh with the
## arms and legs inside it, and the only one with a separate tail mesh. He is
## therefore the only character that opts into the limb rig (the tail pivot plus
## the vertex-deforming body shader) with the default joint measurements.


func _init() -> void:
	limb_rig = true
	rig_tail = true
