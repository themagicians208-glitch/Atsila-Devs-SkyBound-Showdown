extends Node

## Checks the multiplayer menus exactly as a player meets them. The device
## question comes first - LOCAL split screen or an ONLINE room - and the mode
## (story co-op or the 1v1 duel) comes after, with the launch flags each door
## sets.
##
## Run headless:
##   godot --headless res://tools/check_mp_menu.tscn
##   godot --headless res://tools/check_mp_menu.tscn -- duel

const HOME_SCENE := preload("res://scenes/home.tscn")

var _problems: Array[String] = []
# Cached: the story-mode launch swaps the scene under this test's feet, which
# detaches it from the tree, so get_tree() cannot be used after that point.
var _tree: SceneTree
# "story" checks the local story launch, "duel" the local duel one: only one
# scene change can be judged per run.
var _launch := "story"


func _check(condition: bool, message: String) -> void:
	if not condition:
		_problems.append(message)


func _ready() -> void:
	print("--- Multiplayer menu check ---")
	_tree = get_tree()
	if OS.get_cmdline_user_args().has("duel"):
		_launch = "duel"
	_tree.set_meta("open_multiplayer_menu", false)
	var home: Node = HOME_SCENE.instantiate()
	add_child(home)
	await get_tree().process_frame
	await get_tree().process_frame

	# 1. The main menu offers MULTIPLAYER, and it opens with the device question
	#    first: local split screen, or an online room.
	var menu_button := _find_button(home, "MULTIPLAYER", true)
	_check(menu_button != null, "the main menu has no MULTIPLAYER button")
	if menu_button == null:
		_report()
		return
	menu_button.pressed.emit()
	await get_tree().process_frame
	_check(_title(home) == "MULTIPLAYER",
			"MULTIPLAYER did not open the multiplayer screen (title '%s')" % _title(home))
	var options := _body_buttons(home)
	_check(options.size() == 2, "the multiplayer screen must offer exactly two options, found %d" % options.size())
	_check(_find_button(home, "PLAY LOCAL", false) != null, "no PLAY LOCAL button")
	_check(_find_button(home, "PLAY ONLINE", false) != null, "no PLAY ONLINE button")
	var texts := _body_texts(home)
	_check(texts.has("LOCAL"), "the local option title is missing")
	_check(texts.has("ONLINE"), "the online option title is missing")
	_check(texts.has("Two players on this machine: split screen, sharing the keyboard or using two controllers."),
			"the local option does not describe split screen")
	_check(texts.has("Create a room and share your address, or join a friend on the same network."),
			"the online option does not describe creating a room")
	var back := home.get("back_button") as Button
	_check(back != null and back.visible, "the screen has no visible BACK button")
	_check(back != null and back.text == "BACK", "the back button is not labelled BACK")

	# 2. LOCAL first, then the mode: the story co-op or the 1v1 arena.
	_press(home, "PLAY LOCAL")
	await get_tree().process_frame
	_check(_title(home) == "LOCAL  •  SPLIT SCREEN",
			"PLAY LOCAL did not open the local screen (title '%s')" % _title(home))
	_check(_find_button(home, "PLAY STORY CO-OP", false) != null, "the local screen has no story option")
	_check(_find_button(home, "START A LOCAL DUEL", false) != null, "the local screen has no duel option")
	texts = _body_texts(home)
	_check(texts.has("Explore Aetheria together, complete missions, solve puzzles and fight enemies."),
			"the local story option does not describe the campaign")
	_check(texts.has("Two duelists on one screen: best of three rounds in the floating arena."),
			"the local duel option does not describe the duel")

	# Local story -> the shared device/name screen, back a step at a time.
	_press(home, "PLAY STORY CO-OP")
	await get_tree().process_frame
	_check(_title(home).begins_with("LOCAL"),
			"the local co-op set-up did not open (title '%s')" % _title(home))
	back.pressed.emit()
	await get_tree().process_frame
	_check(_title(home) == "LOCAL  •  SPLIT SCREEN",
			"BACK from the co-op set-up did not return to the local screen")

	# Local duel -> the same screen, titled for a duel.
	_press(home, "START A LOCAL DUEL")
	await get_tree().process_frame
	_check(_title(home).begins_with("LOCAL DUEL"),
			"the local duel set-up did not open (title '%s')" % _title(home))
	_check(_find_button(home, "START", false) != null, "the duel set-up has no START button")
	back.pressed.emit()
	await get_tree().process_frame
	_check(_title(home) == "LOCAL  •  SPLIT SCREEN",
			"BACK from the duel set-up did not return to the local screen")
	back.pressed.emit()
	await get_tree().process_frame
	_check(_title(home) == "MULTIPLAYER", "BACK from the local screen did not return to MULTIPLAYER")

	# 3. ONLINE next, then the mode: a story room, or an arena match.
	_press(home, "PLAY ONLINE")
	await get_tree().process_frame
	_check(_title(home) == "ONLINE  •  CREATE OR JOIN A ROOM",
			"PLAY ONLINE did not open the online screen (title '%s')" % _title(home))
	_check(_find_button(home, "PLAY STORY CO-OP", false) != null, "the online screen has no story option")
	_check(_find_button(home, "PLAY 1V1 ONLINE", false) != null, "the online screen has no duel option")
	texts = _body_texts(home)
	_check(texts.has("Enter a battle arena, challenge another player and compete to win two rounds."),
			"the online duel option does not describe the arena")

	# Online story -> create or join a room.
	_press(home, "PLAY STORY CO-OP")
	await get_tree().process_frame
	_check(_title(home) == "ONLINE", "the story room screen did not open (title '%s')" % _title(home))
	_check(_find_button(home, "CREATE ROOM", true) != null, "the room screen has no CREATE ROOM button")
	_check(_find_button(home, "JOIN ROOM", true) != null, "the room screen has no JOIN ROOM button")
	back.pressed.emit()
	await get_tree().process_frame
	_check(_title(home) == "ONLINE  •  CREATE OR JOIN A ROOM",
			"BACK from the room screen did not return to the online screen")

	# 4. The online duel opens the arena lobby, with its own back step.
	_press(home, "PLAY 1V1 ONLINE")
	await get_tree().process_frame
	_check(_title(home) == "1V1 BATTLE ARENA",
			"PLAY 1V1 ONLINE did not open the arena lobby (title '%s')" % _title(home))
	_check(_find_button(home, "CREATE ARENA", true) != null, "the arena lobby has no CREATE ARENA button")
	_check(_find_button(home, "JOIN ARENA", true) != null, "the arena lobby has no JOIN ARENA button")
	back.pressed.emit()
	await get_tree().process_frame
	_check(_title(home) == "ONLINE  •  CREATE OR JOIN A ROOM",
			"BACK from the arena lobby did not return to the online screen")
	back.pressed.emit()
	await get_tree().process_frame
	_check(_title(home) == "MULTIPLAYER", "BACK from the online screen did not return to MULTIPLAYER")

	# 5. BACK closes the whole popup from the multiplayer screen itself.
	back.pressed.emit()
	await get_tree().create_timer(0.45).timeout
	var popup := home.get("popup") as Control
	_check(popup != null and not popup.visible, "BACK from the multiplayer screen did not close the menu")

	# 5. Returning from the arena reopens the multiplayer screen.
	_tree.set_meta("open_multiplayer_menu", true)
	var again: Node = HOME_SCENE.instantiate()
	add_child(again)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_title(again) == "MULTIPLAYER",
			"returning from the arena did not reopen the multiplayer screen (title '%s')" % _title(again))
	again.queue_free()

	# 6. The launch behind the last door: only one scene change can be judged per
	#    run (the first one detaches this test from the tree), so the second
	#    launch is checked by running this suite again with "duel".
	if _launch == "duel":
		_press(home, "PLAY LOCAL")
		await get_tree().process_frame
		_press(home, "START A LOCAL DUEL")
		await get_tree().process_frame
		home.call("_start_local_duel")
		_check(bool(_tree.get_meta("arena_local_duel", false)),
				"starting a local duel did not flag the arena's local mode")
		_check(not bool(_tree.get_meta("local_coop", false)),
				"the local duel left the story co-op flag on")
		_check(not bool(_tree.get_meta("online", true)),
				"the local duel left the online flag on")
		_check(str(_tree.get_meta("local_p1_device", "")) != "" and str(_tree.get_meta("local_p2_device", "")) != "",
				"the local duel did not pass both devices")
		_check(str(_tree.get_meta("local_p1_name", "")) != "" and str(_tree.get_meta("local_p2_name", "")) != "",
				"the local duel did not pass both names")
		_check(_tree.has_meta("p1_character") and _tree.has_meta("p2_character"),
				"the local duel did not pass the characters")
	else:
		home.call("_start_local", 1)
		_check(not bool(_tree.get_meta("arena_local_duel", true)),
				"starting the story co-op left the local duel flag on")
		_check(bool(_tree.get_meta("local_coop", false)),
				"story multiplayer did not set the campaign's local co-op flag")
		_check(int(_tree.get_meta("level_number", 0)) == 1, "story multiplayer did not select level 1")
	_check(ResourceLoader.exists("res://scenes/main.tscn"), "the campaign's main scene is missing")

	_report()


func _report() -> void:
	if _problems.is_empty():
		print("MULTIPLAYER MENU OK")
		_tree.quit(0)
	else:
		for problem in _problems:
			print("PROBLEM: ", problem)
		print("MULTIPLAYER MENU FAILED (%d problems)" % _problems.size())
		_tree.quit(1)


# --- Small tree helpers --------------------------------------------------------


func _title(home: Node) -> String:
	var label := home.get("popup_title") as Label
	return "" if label == null else label.text


func _body_buttons(home: Node) -> Array:
	var body := home.get("popup_body") as Node
	if body == null:
		return []
	return body.find_children("*", "Button", true, false)


func _body_texts(home: Node) -> Array[String]:
	var texts: Array[String] = []
	var body := home.get("popup_body") as Node
	if body == null:
		return texts
	for child in body.find_children("*", "Label", true, false):
		texts.append((child as Label).text)
	return texts


func _find_button(home: Node, text: String, anywhere: bool) -> Button:
	var root: Node = home if anywhere else (home.get("popup_body") as Node)
	if root == null:
		return null
	for child in root.find_children("*", "Button", true, false):
		if (child as Button).text == text:
			return child as Button
	return null


func _find_button_starting(home: Node, prefix: String, anywhere: bool) -> Button:
	var root: Node = home if anywhere else (home.get("popup_body") as Node)
	if root == null:
		return null
	for child in root.find_children("*", "Button", true, false):
		if (child as Button).text.begins_with(prefix):
			return child as Button
	return null


func _press(home: Node, text: String) -> void:
	var button := _find_button(home, text, true)
	_check(button != null, "no button labelled '%s'" % text)
	if button != null:
		button.pressed.emit()


func _press_starting(home: Node, prefix: String) -> void:
	var button := _find_button_starting(home, prefix, true)
	_check(button != null, "no button starting with '%s'" % prefix)
	if button != null:
		button.pressed.emit()