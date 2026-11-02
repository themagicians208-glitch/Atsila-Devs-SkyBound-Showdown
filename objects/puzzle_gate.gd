extends StaticBody3D
class_name PuzzleGate

## A barrier that blocks the path to the flag until every lever is pressed.
## When opened it sinks out of the way and turns off its collision.

var opened := false
@export var open_drop := 2.6


func open() -> void:
	if opened:
		return
	opened = true
	for child in find_children("*", "CollisionShape3D", true, false):
		(child as CollisionShape3D).set_deferred("disabled", true)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "position:y", position.y - open_drop, 0.7)
