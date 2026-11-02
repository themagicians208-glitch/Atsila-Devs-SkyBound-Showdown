extends Node3D

## Visual tour of Frozen Skies' rule-changing puzzle sites: builds Level 3, flies a
## free camera to each site in both its starting rules and its changed rules, and
## saves one screenshot per stop to res://preview_shots/.
##
## Run it live (editor Game tab / run_scene) so it renders; it quits itself when the
## tour is done. Screenshots are named 01_..., 02_... in tour order.

const SHOT_DIR := "res://preview_shots"
const ROUTE_AHEAD := 14.0

var _main: Node
var _fs: Node
var _player: Node
var _cam: Camera3D
var _caption: Label
var _tour: Array[Dictionary] = []
var _index := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await _setup()
	_build_tour()
	for stop in _tour:
		await _shoot(stop)
	print("FROZEN PREVIEW: %d screenshots written to %s" % [_index, SHOT_DIR])
	get_tree().quit()


func _setup() -> void:
	var prog := get_node_or_null("/root/Progress")
	if prog != null:
		prog.set("config_path", "user://progress_preview_frozen.cfg")
		prog.call("clear")
		prog.call("recover_fragment")
		prog.call("recover_second_fragment")
		prog.call("unlock_ice_shield")
	get_tree().set_meta("level_number", 3)
	get_tree().set_meta("local_coop", false)
	get_tree().set_meta("online", false)
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	for frame in 4:
		await get_tree().process_frame
	_fs = _main.get("frozen_skies")
	_player = _main.get("player")
	if _player != null:
		_player.set("controls_locked", true)
		_player.visible = false
		_player.process_mode = Node.PROCESS_MODE_DISABLED
	_cam = Camera3D.new()
	_cam.name = "PreviewCamera"
	_cam.fov = 72.0
	add_child(_cam)
	_cam.current = true
	_build_caption_overlay()
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)


func _build_caption_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PreviewCaption"
	layer.layer = 10
	add_child(layer)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.05, 0.09, 0.62)
	backdrop.set_anchors_preset(Control.PRESET_TOP_WIDE)
	backdrop.offset_top = 28.0
	backdrop.offset_bottom = 116.0
	layer.add_child(backdrop)
	_caption = Label.new()
	_caption.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_caption.offset_top = 40.0
	_caption.offset_bottom = 112.0
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 30)
	_caption.add_theme_color_override("font_color", Color("#e9f6ff"))
	_caption.add_theme_color_override("font_outline_color", Color(0.0, 0.05, 0.1, 0.9))
	_caption.add_theme_constant_override("outline_size", 8)
	layer.add_child(_caption)


func _rule_puzzle(id: String) -> Node:
	var rules: Dictionary = _fs.get("rule_puzzles")
	return rules.get(id) as Node


func _build_tour() -> void:
	var switch_puzzle: Node = _rule_puzzle("frozen_switch")
	var valley: Node = _rule_puzzle("ice_wind_valley")
	var crystals: Node = _rule_puzzle("three_crystals")
	var lake: Node = _rule_puzzle("frozen_lake")
	var fortress: Node = _rule_puzzle("fortress_shift")
	var seal_one: Node = _rule_puzzle("seal_one")
	var titan: Node = _fs.get("_titan")
	var stops: Array[Dictionary] = [
		{"site": switch_puzzle, "far": "islands", "label": "I - THE FROZEN SWITCH (starting rules)",
			"file": "switch_initial", "shift": 0, "settle": 1.2},
		{"site": switch_puzzle, "far": "islands", "label": "I - THE FROZEN SWITCH (new rules: switch I is dead, crystal revealed)",
			"file": "switch_changed", "shift": 1, "settle": 2.2},
		{"site": valley, "far": "island", "label": "II - SLIPPERY ICE VALLEY (starting wind)",
			"file": "valley_initial", "shift": 0, "settle": 1.2},
		{"site": valley, "far": "island", "label": "II - SLIPPERY ICE VALLEY (wind turned: patrols reversed, one frozen, one slick)",
			"file": "valley_changed", "shift": 1, "settle": 2.2},
		{"site": crystals, "far": "mirror", "label": "III - THREE CRYSTALS (new rules: one crystal spins, one is shelled, mirror lit)",
			"file": "crystals_changed", "shift": 1, "settle": 2.2},
		{"site": lake, "far": "shore", "label": "IV - THE FROZEN LAKE (starting rules: solid)",
			"file": "lake_initial", "shift": 0, "settle": 1.2},
		{"site": lake, "far": "shore", "label": "IV - THE FROZEN LAKE (melted into a wave, then re-frozen slick)",
			"file": "lake_changed", "shift": 2, "settle": 2.4},
		{"site": fortress, "far": "routes", "label": "V - SHATTERED ICE FORTRESS (starting rules)",
			"file": "fortress_initial", "shift": 0, "settle": 1.2},
		{"site": fortress, "far": "routes", "label": "V - SHATTERED ICE FORTRESS (structure altered: gravity section, walled corridor, mirror route)",
			"file": "fortress_changed", "shift": 1, "settle": 2.4},
		{"site": fortress, "far": "routes", "label": "V - SHATTERED ICE FORTRESS (frost storm: the walk phases in and out)",
			"file": "fortress_storm", "shift": 2, "settle": 2.4},
		{"site": seal_one, "far": "side", "label": "SEAL I - THE MOVING ICE (platforms reversed mid-crossing)",
			"file": "seal_one_changed", "shift": 1, "settle": 2.2},
		{"site": titan, "far": "ahead", "label": "FROST TITAN'S SANCTUARY (four phases, arena slabs move at Absolute Frost)",
			"file": "titan_sanctuary", "shift": 0, "settle": 1.4},
	]
	for stop in stops:
		if stop["site"] != null:
			_tour.append(stop)


func _anchor_of(site: Node) -> Vector3:
	var shift: Node = site.get("rule_shift")
	if shift is Node3D:
		return (shift as Node3D).global_position
	return (site as Node3D).global_position


func _far_point(stop: Dictionary) -> Vector3:
	var site: Node = stop["site"]
	var anchor := _anchor_of(site)
	var kind: String = stop["far"]
	var points: Array = []
	match kind:
		"islands":
			if site.has_method("island_positions"):
				points = site.call("island_positions")
			if points.is_empty():
				return anchor + _lane_ahead(anchor) * ROUTE_AHEAD
			return points[points.size() - 1]
		"island":
			if site.has_method("island_position"):
				return site.call("island_position")
		"shore":
			if site.has_method("far_shore_position"):
				return site.call("far_shore_position")
		"mirror":
			if site.has_method("mirror_position"):
				return site.call("mirror_position")
		"side":
			if site.has_method("far_side_position"):
				return site.call("far_side_position")
		"routes":
			if site.has_method("mirror_route_positions"):
				points = site.call("mirror_route_positions")
			if points.is_empty():
				return anchor + _lane_ahead(anchor) * ROUTE_AHEAD
			var mid := anchor
			for point in points:
				mid += point
			return mid / float(points.size() + 1)
		"ahead":
			return anchor + _lane_ahead(anchor) * ROUTE_AHEAD
	return anchor + _lane_ahead(anchor) * ROUTE_AHEAD


func _lane_ahead(point: Vector3) -> Vector3:
	var route: Array = _fs.get("route")
	if route.is_empty():
		return Vector3(0.0, 0.0, -1.0)
	var best := 0
	var best_distance := INF
	for index in route.size():
		var distance: float = (route[index] as Vector3).distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = index
	var before: Vector3 = route[maxi(best - 1, 0)]
	var after: Vector3 = route[mini(best + 1, route.size() - 1)]
	var direction := after - before
	direction.y = 0.0
	if direction.length() < 0.01:
		return Vector3(0.0, 0.0, -1.0)
	return direction.normalized()


func _shoot(stop: Dictionary) -> void:
	_index += 1
	var site: Node = stop["site"]
	var shift: Node = site.get("rule_shift")
	var stages: int = stop["shift"]
	for step in stages:
		if shift != null and shift.has_method("force_rule_change"):
			shift.call("force_rule_change")
	var anchor := _anchor_of(site)
	var far := _far_point(stop)
	var direction := far - anchor
	direction.y = 0.0
	if direction.length() < 0.5:
		direction = _lane_ahead(anchor)
	direction = direction.normalized()
	var length := anchor.distance_to(far)
	var middle := (anchor + far) * 0.5
	var back := maxf(10.0, length * 0.8)
	var height := maxf(6.5, length * 0.45)
	# Frame the site from the side the player arrives from, looking along it.
	_cam.global_position = middle - direction * back + Vector3(0.0, height, 0.0)
	_cam.look_at(middle + Vector3(0.0, 0.8, 0.0), Vector3.UP)
	print("FROZEN PREVIEW stop %d (%s): anchor=%s far=%s cam=%s" % [
		_index, stop["file"], anchor, far, _cam.global_position])
	_caption.text = "%d/%d   %s" % [_index, _tour.size(), stop["label"]]
	await get_tree().create_timer(float(stop["settle"])).timeout
	for frame in 2:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%02d_%s.png" % [SHOT_DIR, _index, stop["file"]]
	var error := image.save_png(path)
	if error != OK:
		push_error("FROZEN PREVIEW: could not write %s (error %d)" % [path, error])
	else:
		print("FROZEN PREVIEW: wrote ", path)