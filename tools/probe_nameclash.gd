extends Node

## Replays a duplicate local-co-op name both ways round, printing who is warned
## each time. The rule: the player who typed the duplicate *last* is told.

func _ready() -> void:
	await _clash(false)   # player 2 types it second
	await _clash(true)    # player 1 types it second
	get_tree().quit()


func _clash(second_typist_is_p1: bool) -> void:
	var home: Node = load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await get_tree().process_frame
	home.set("p1_name", "Player 1")
	home.set("p2_name", "Player 2")
	home.call("_show_local_options")
	await get_tree().process_frame

	var p1: LineEdit = _field(home, 0)
	var p2: LineEdit = _field(home, 1)
	var first: LineEdit = p1 if second_typist_is_p1 else p2
	var second: LineEdit = p2 if second_typist_is_p1 else p1
	first.text = "Tom"
	first.text_changed.emit("Tom")
	await get_tree().process_frame
	second.text = "Tom"
	second.text_changed.emit("Tom")
	await get_tree().process_frame
	var typed_last := 2 if second_typist_is_p1 else 1
	print("player %d typed 'Tom' last (last=%s)" % [typed_last, home.get("_last_named_player")])
	home.call("_local_start_pressed")
	await get_tree().process_frame
	var warning: Label = home.get("_name_warning")
	print("   START blocked: %s   warned player: %d   message: %s" % [
		home.get("popup_title").text == "LOCAL CO-OP — CONTROLS",
		int(home.get("_name_warning_for")), warning.text.replace("\n", " ")])
	home.queue_free()
	await get_tree().process_frame


func _field(home: Node, index: int) -> LineEdit:
	var found: Array[LineEdit] = []
	for child in (home.get("popup_body") as VBoxContainer).get_children():
		if child is LineEdit:
			found.append(child)
	return found[index]
