class_name BattleArena
extends Node3D

## 1V1 BATTLE ARENA — a competitive duel mode, separate from the five story
## levels and reached from the main menu's multiplayer screen.
##
## Two duelists join an ENet room (the same `Network` autoload the story co-op
## uses). The HOST (peer 1) is the server and owns the official match state:
## the cage countdown, health, round wins and the match result. Clients mirror
## that state through RPCs, and every attack is only a *claim* that the host
## validates before any damage happens. Rounds are best-of-three: first to two
## round wins takes the match, and a double knock-out replays the round with no
## point for either side.
##
## Everything visible is built in code from the project's own primitives, in the
## same magical-fantasy style as the story levels: a floating stone island, a
## glowing energy barrier, purple and blue crystals, two sealed starting cages,
## spectator rocks and clouds.

const PLAYER_SCENE := preload("res://objects/player.tscn")
const CLOUD_SCENE := preload("res://objects/cloud.tscn")
const ROSTER := preload("res://scripts/roster.gd")
const BATTLE_HUD_SCRIPT := preload("res://scripts/battle_hud.gd")
const VIEW_SCRIPT := preload("res://scripts/view.gd")

const ARENA_RADIUS := 15.0
const WALL_RADIUS := 15.3
const WALL_SEGMENTS := 12
## The two starting cages. They sit two units clear of the barrier so the duel
## camera has room behind a duelist at the bell instead of being squeezed flat
## against the wall.
const CAGE_SPAWNS := {1: Vector3(0.0, 0.60, -11.0), 2: Vector3(0.0, 0.60, 11.0)}
const WINS_TO_TAKE_THE_MATCH := 2
const MAX_DUEL_HEALTH := 100.0
const DUEL_DAMAGE := 12.0
const SHIELD_FACTOR := 0.35       # matches player.gd's magical_shield_reduction
const DRAW_WINDOW := 0.6          # both falling inside this window = a draw
const DIMENSION_COOLDOWN := 6.0
const DISCONNECT_RETURN := 5.0

enum Phase { WAITING, COUNTDOWN, FIGHT, ROUND_END, MATCH_OVER, OVER }

@export var round_countdown := 8.0    ## the synchronized cage countdown, in seconds
@export var round_freeze := 4.0       ## the between-round transition
@export var spawn_protection := 2.0   ## no damage for this long after the cages open

# --- Network identity ---------------------------------------------------------
var network: Node
var local_id := 1
var p2_id := 0                 # host only: the connected challenger's peer id
var local_slot := 1
var _leaving := false
var _returning := false
## Client-side: the host's arena has talked to us, so RPCs can now be aimed at
## its node path without being dropped.
var _host_arena_seen := false

# --- Local split-screen duel ---------------------------------------------------
## Set from the menu: two duelists on this machine and no network at all, so the
## match logic below simply runs here instead of over RPCs.
var local_duel := false
var player_two: CharacterBody3D
var _view_two: Node3D
var _split_layer: CanvasLayer

# --- Match state (the host owns it; clients mirror what they are told) --------
var phase: int = Phase.WAITING
var round_number := 1
var rounds_played := 0
var countdown := 0.0
var wins := {1: 0, 2: 0}                 # slot -> round wins
var hp := {1: MAX_DUEL_HEALTH, 2: MAX_DUEL_HEALTH}
var shields_on := {1: false, 2: false}   # slot -> magical shield up
var mirror_dimension := false
var dimension_cooldown := 0.0

var _grace_left := 0.0
var _reported := {}                      # slot -> death already reported this round
var _death_marks := {}                   # slot -> fell this round
var _pending_death := 0                  # slot awaiting the double-KO window
var _death_window := 0.0
var _transition_left := 0.0
var _advance_round := true
var _last_tick := -1
var _rematch_votes := {}                 # slot -> wants another match
var _disconnect_left := 0.0
var _last_pos := {}                      # slot -> last synced position
var _last_rot := {}                      # slot -> last synced yaw

# --- Nodes --------------------------------------------------------------------
var player: CharacterBody3D
var opponent: CharacterBody3D
var view: Node3D
var hud: BattleHUD
var sun: DirectionalLight3D
var barrier_material: StandardMaterial3D
var cage_doors := {}                     # slot -> {body, shape, material, closed_y}
var mirror_steps: Array[Node3D] = []
var _opponent_slash: MeshInstance3D
var _opponent_swing_tween: Tween


func _ready() -> void:
	add_to_group("battle_arena")
	network = get_node_or_null("/root/Network")
	local_id = multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 1
	local_slot = 1 if local_id == 1 else 2
	local_duel = bool(get_tree().get_meta("arena_local_duel", false))
	get_tree().set_meta("level_number", 1)
	Audio.play_music("res://sounds/pixelland.mp3")
	sun = get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.rotation_degrees = Vector3(-46.0, -34.0, 0.0)
		sun.light_color = Color("#fff2d6")
		sun.light_energy = 1.35
	_build_world()
	_build_hud()
	_ensure_shift_action()
	if local_duel:
		_setup_local_duel()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_spawn_local_player()
	_build_opponent_slash()
	_connect_signals()
	_refresh_peers()
	if local_duel:
		# Both duelists are right here in their cages: the duel starts at once,
		# with no handshake and no waiting for anyone to connect.
		_begin_round()
	elif multiplayer.is_server():
		if _both_duelists_present():
			_begin_round()
		else:
			_show_waiting()
	else:
		_show_waiting()
		# Tell the host this arena is loaded. It travels through Network, whose
		# path exists from boot on every peer, so it cannot be lost to a scene
		# that was still loading - and the host answers with a snapshot.
		if network != null:
			network.call("announce_arena_ready")
		_claim_state_later()
	_apply_dimension(mirror_dimension)


# ==============================================================================
#  MENU / SESSION
# ==============================================================================


func _connect_signals() -> void:
	if network != null and not network.peer_list_changed.is_connected(_on_peers_changed):
		network.peer_list_changed.connect(_on_peers_changed)
	if network != null and network.has_signal("arena_ready") \
			and not network.arena_ready.is_connected(_on_arena_ready):
		network.arena_ready.connect(_on_arena_ready)
	if network != null and not network.connection_failed.is_connected(_on_connection_lost):
		network.connection_failed.connect(_on_connection_lost)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_left):
		multiplayer.peer_disconnected.connect(_on_peer_left)
	hud.rematch_pressed.connect(_vote_rematch)
	hud.menu_pressed.connect(_return_to_menu)


func _on_peers_changed() -> void:
	_refresh_peers()
	if multiplayer.is_server() and phase == Phase.WAITING and _both_duelists_present():
		_begin_round()
	elif not multiplayer.is_server():
		_refresh_waiting()


func _other_id() -> int:
	if multiplayer.is_server():
		return p2_id
	return 1


func _other_present() -> bool:
	if network == null:
		return false
	var other := _other_id()
	return other != 0 and network.players.has(other)


func _both_duelists_present() -> bool:
	if local_duel:
		return true
	return multiplayer.multiplayer_peer != null and network != null \
			and _other_present() and network.players.has(1) and _opponent_ready()


## True when the challenger's arena has announced that it is loaded. Until then
## an RPC aimed at this scene has no node to land on over there, so the duel
## must not start: the challenger would miss the cage lock and the countdown.
func _opponent_ready() -> bool:
	if network == null or p2_id == 0 or not multiplayer.is_server():
		return false
	var ready_peers := network.get("arena_ready_peers") as Dictionary
	return ready_peers != null and ready_peers.has(p2_id)


## The host: the challenger's arena is in its cage. Start the duel, or - if a
## round is already running - bring the newcomer up to date.
func _on_arena_ready(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_refresh_peers()
	if p2_id == 0 or int(peer_id) != p2_id:
		return
	if phase == Phase.WAITING and _both_duelists_present():
		_begin_round()
	else:
		rpc_id(peer_id, "_apply_snapshot", _snapshot())


func _snapshot() -> Dictionary:
	return {
		"phase": phase,
		"round": round_number,
		"countdown": countdown,
		"wins1": wins[1],
		"wins2": wins[2],
		"hp1": hp[1],
		"hp2": hp[2],
		"rounds": rounds_played,
		"mirror": mirror_dimension,
	}


func _other_slot() -> int:
	return 3 - local_slot


## Find the challenger (host) or confirm the host (client), then make sure the
## opponent proxy, names and characters all match what the Network autoload knows.
func _refresh_peers() -> void:
	if network == null:
		return
	if multiplayer.is_server():
		p2_id = 0
		for id in network.players.keys():
			if int(id) != 1:
				p2_id = int(id)
				break
	var other := _other_id()
	if other != 0:
		if opponent == null or not is_instance_valid(opponent):
			_spawn_opponent()
		elif str(opponent.get("character_id")) != _character_for(other):
			opponent.queue_free()
			opponent = null
			_spawn_opponent()
		if opponent != null and is_instance_valid(opponent):
			opponent.call("set_player_name", _name_for(other))
	_refresh_names()
	if phase == Phase.WAITING:
		_refresh_waiting()


func _name_for(id: int) -> String:
	if local_duel:
		return _local_name(1 if int(id) == 1 else 2)
	if network == null:
		return "Player %d" % (1 if id == 1 else 2)
	if id == local_id:
		var mine := str(network.local_name).strip_edges()
		return mine if not mine.is_empty() else "Player"
	var who := str(network.get_player_name(id)).strip_edges()
	return who if not who.is_empty() else "Player"


func _character_for(id: int) -> String:
	var picked := ""
	if network != null:
		picked = str(network.local_character) if id == local_id else str(network.get_player_character(id))
	if picked.is_empty() or not ROSTER.has(picked):
		picked = ROSTER.default_id()
	return picked


func _refresh_names() -> void:
	if local_duel:
		hud.set_names(_local_name(1), _local_name(2))
		return
	if network == null:
		hud.set_names("Player 1", "Player 2")
		return
	# Slot 1 is always the host (peer 1). Slot 2 is the challenger: for the host
	# that is the joining peer's id, for the client it is itself. Peer ids are
	# not the same as slots — a host's second peer can be any id — so the names
	# have to be looked up through the ids, never through 1 and 2 directly.
	var slot2_id := _other_id() if local_slot == 1 else local_id
	var one := _name_for(1) if network.players.has(1) else "Player 1"
	var two := _name_for(slot2_id) if (_other_present() or local_slot == 2) else "Player 2"
	hud.set_names(one, two)


func _refresh_waiting() -> void:
	if phase != Phase.WAITING:
		return
	var lines: Array[String] = []
	var one := "PLAYER 1  •  %s" % _name_for(1)
	lines.append(one + ("   (in their cage)" if network != null and network.players.has(1) else "   (not connected)"))
	if _other_present():
		var state := "in their cage"
		if multiplayer.is_server() and not _opponent_ready():
			state = "loading their cage…"
		lines.append("PLAYER 2  •  %s   (%s)" % [_name_for(_other_id()), state])
	else:
		lines.append("PLAYER 2  •  waiting for a challenger…")
	var address := ""
	if multiplayer.is_server():
		address = "Share this address:  %s\nThey pick ENTER BATTLE ARENA → JOIN ARENA and type it in." % network.get_local_address()
	else:
		address = "Connected. The duel begins when the host sees both cages full."
	hud.show_waiting("\n".join(lines), address)


func _show_waiting() -> void:
	_refresh_names()
	_refresh_waiting()


# ==============================================================================
#  THE WORLD
# ==============================================================================


func _build_world() -> void:
	# The arena is its own little world, so it takes its own copy of the shared
	# environment and gives it a cool ambient fill: the story levels are lit by
	# their pastel sky, and a stone arena with no fill reads as a black void.
	var env_node := get_node_or_null("Environment") as WorldEnvironment
	if env_node != null and env_node.environment != null:
		var env := env_node.environment.duplicate() as Environment
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("#a8bdf0")
		env.ambient_light_energy = 0.65
		env_node.environment = env

	# Kept in the project's own palette range (mid-tones, not near-black), so the
	# stone reads as stone under the floating island's sky.
	var stone := _material(Color("#6d6485"), 0.0, 0.8)
	var stone_dark := _material(Color("#4a4260"), 0.0, 0.85)
	var rune := _material(Color("#6fe7ef"), 1.6, 0.3)
	var violet := _material(Color("#b06bff"), 1.5, 0.3)
	var blue := _material(Color("#4fd8ff"), 1.5, 0.3)

	# The fighting floor: a big round stone platform with a decorated rim.
	var floor_body := StaticBody3D.new()
	floor_body.name = "ArenaFloor"
	floor_body.position = Vector3(0.0, -0.8, 0.0)
	var floor_shape := CollisionShape3D.new()
	var floor_cyl := CylinderShape3D.new()
	floor_cyl.radius = ARENA_RADIUS
	floor_cyl.height = 1.6
	floor_shape.shape = floor_cyl
	floor_body.add_child(floor_shape)
	var floor_mesh := MeshInstance3D.new()
	var floor_cyl_mesh := CylinderMesh.new()
	floor_cyl_mesh.top_radius = ARENA_RADIUS
	floor_cyl_mesh.bottom_radius = ARENA_RADIUS
	floor_cyl_mesh.height = 1.6
	floor_cyl_mesh.radial_segments = 48
	floor_mesh.mesh = floor_cyl_mesh
	floor_mesh.material_override = stone
	floor_body.add_child(floor_mesh)
	var floor_rim := MeshInstance3D.new()
	var rim_torus := TorusMesh.new()
	rim_torus.inner_radius = ARENA_RADIUS - 0.25
	rim_torus.outer_radius = ARENA_RADIUS + 0.05
	floor_rim.mesh = rim_torus
	floor_rim.position = Vector3(0.0, 0.02, 0.0)
	floor_rim.material_override = rune
	floor_body.add_child(floor_rim)
	add_child(floor_body)

	# The floating island underside: a rocky cone tapering into the clouds,
	# with a few hanging rock spurs so the base reads as torn-from-the-sky.
	var underside := MeshInstance3D.new()
	underside.name = "IslandUnderside"
	var under_mesh := CylinderMesh.new()
	under_mesh.top_radius = ARENA_RADIUS - 0.4
	under_mesh.bottom_radius = 3.4
	under_mesh.height = 9.0
	under_mesh.radial_segments = 40
	underside.mesh = under_mesh
	underside.position = Vector3(0.0, -6.1, 0.0)
	underside.material_override = stone_dark
	add_child(underside)
	for i in 7:
		var angle := TAU * float(i) / 7.0 + 0.3
		var spur := MeshInstance3D.new()
		var spur_mesh := CylinderMesh.new()
		spur_mesh.top_radius = 1.5
		spur_mesh.bottom_radius = 0.1
		spur_mesh.height = 6.0 + float(i % 3)
		spur.mesh = spur_mesh
		spur.position = Vector3(cos(angle) * 8.0, -11.5, sin(angle) * 8.0)
		spur.material_override = stone_dark
		add_child(spur)

	# The energy barrier: a translucent magical curtain with solid wall
	# segments behind it, so nobody can leave the duel by walking off the edge.
	var curtain := MeshInstance3D.new()
	curtain.name = "EnergyBarrier"
	barrier_material = StandardMaterial3D.new()
	barrier_material.albedo_color = Color(0.69, 0.42, 1.0, 0.13)
	barrier_material.emission_enabled = true
	barrier_material.emission = Color("#b06bff")
	barrier_material.emission_energy_multiplier = 0.9
	barrier_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	barrier_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	barrier_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var curtain_mesh := CylinderMesh.new()
	curtain_mesh.top_radius = WALL_RADIUS + 0.2
	curtain_mesh.bottom_radius = WALL_RADIUS + 0.2
	curtain_mesh.height = 5.6
	curtain_mesh.radial_segments = 48
	curtain.mesh = curtain_mesh
	curtain.position = Vector3(0.0, 2.8, 0.0)
	curtain.material_override = barrier_material
	add_child(curtain)
	for i in WALL_SEGMENTS:
		var angle := TAU * float(i) / float(WALL_SEGMENTS)
		var wall := StaticBody3D.new()
		wall.name = "BarrierWall_%02d" % i
		wall.position = Vector3(cos(angle) * WALL_RADIUS, 2.8, sin(angle) * WALL_RADIUS)
		wall.rotation.y = -(angle + PI * 0.5)
		var wall_shape := CollisionShape3D.new()
		var wall_box := BoxShape3D.new()
		wall_box.size = Vector3(TAU * WALL_RADIUS / float(WALL_SEGMENTS) + 1.6, 5.6, 0.8)
		wall_shape.shape = wall_box
		wall.add_child(wall_shape)
		add_child(wall)

	# Crystal posts along the barrier, alternating purple and blue, plus
	# bigger crystal clusters standing outside it like spectators.
	for i in 12:
		var angle := TAU * float(i) / 12.0 + 0.15
		_crystal(Vector3(cos(angle) * (WALL_RADIUS - 0.45), 0.0, sin(angle) * (WALL_RADIUS - 0.45)),
				2.3 + float(i % 3) * 0.4, violet if i % 2 == 0 else blue, 0.35)
	for i in 16:
		var angle := TAU * float(i) / 16.0 + 0.4
		var reach := 18.0 + float(i % 4) * 2.6
		_crystal(Vector3(cos(angle) * reach, -1.4 + float(i % 3) * 0.5, sin(angle) * reach),
				1.6 + float(i % 3) * 0.7, violet if i % 2 == 0 else blue, 0.5)

	# The central sigil: the duel's fighting circle.
	var sigil := MeshInstance3D.new()
	var sigil_torus := TorusMesh.new()
	sigil_torus.inner_radius = 5.6
	sigil_torus.outer_radius = 5.95
	sigil.mesh = sigil_torus
	sigil.position = Vector3(0.0, 0.03, 0.0)
	sigil.material_override = _material(Color("#ffd451"), 1.5, 0.3)
	add_child(sigil)

	# Spectator surroundings: floating rocks carrying little magical towers,
	# arch gates and clouds, well outside the barrier.
	for i in 10:
		var angle := TAU * float(i) / 10.0 + 0.25
		var reach := 23.0 + float(i % 5) * 3.4
		var height := -3.0 + float(i % 4) * 2.6
		var rock := MeshInstance3D.new()
		var rock_mesh := CylinderMesh.new()
		rock_mesh.top_radius = 2.6 + float(i % 3) * 0.6
		rock_mesh.bottom_radius = 0.9
		rock_mesh.height = 1.4
		rock.mesh = rock_mesh
		rock.position = Vector3(cos(angle) * reach, height, sin(angle) * reach)
		rock.material_override = stone_dark
		add_child(rock)
		_crystal(rock.position + Vector3(0.8, 0.9, 0.4), 1.8, violet if i % 2 == 0 else blue, 0.3)
		if i % 3 == 0:
			var tower := MeshInstance3D.new()
			var tower_mesh := CylinderMesh.new()
			tower_mesh.top_radius = 0.5
			tower_mesh.bottom_radius = 0.9
			tower_mesh.height = 5.0
			tower.mesh = tower_mesh
			tower.position = rock.position + Vector3(-1.2, 3.0, -0.6)
			tower.material_override = stone
			add_child(tower)
			var roof := MeshInstance3D.new()
			var roof_mesh := CylinderMesh.new()
			roof_mesh.top_radius = 0.0
			roof_mesh.bottom_radius = 1.1
			roof_mesh.height = 1.6
			roof.mesh = roof_mesh
			roof.position = rock.position + Vector3(-1.2, 6.1, -0.6)
			roof.material_override = violet
			add_child(roof)
	for i in 6:
		var angle := TAU * float(i) / 6.0 + 0.8
		var gate := Node3D.new()
		gate.position = Vector3(cos(angle) * 27.0, -1.0 + float(i % 2) * 1.5, sin(angle) * 27.0)
		gate.rotation.y = -angle + PI * 0.5
		for side in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			var post_mesh := CylinderMesh.new()
			post_mesh.top_radius = 0.35
			post_mesh.bottom_radius = 0.5
			post_mesh.height = 6.0
			post.mesh = post_mesh
			post.position = Vector3(side * 2.4, 3.0, 0.0)
			post.material_override = stone
			gate.add_child(post)
		var lintel := MeshInstance3D.new()
		var lintel_mesh := BoxMesh.new()
		lintel_mesh.size = Vector3(6.4, 0.8, 1.0)
		lintel.mesh = lintel_mesh
		lintel.position = Vector3(0.0, 6.4, 0.0)
		lintel.material_override = violet
		gate.add_child(lintel)
		add_child(gate)
	for i in 7:
		var angle := TAU * float(i) / 7.0 + 1.2
		var cloud: Node3D = CLOUD_SCENE.instantiate()
		cloud.position = Vector3(cos(angle) * (34.0 + float(i % 3) * 6.0), -6.0 - float(i % 3) * 2.0, sin(angle) * (34.0 + float(i % 3) * 6.0))
		cloud.scale = Vector3.ONE * (2.2 + float(i % 3) * 0.5)
		add_child(cloud)

	# The mirror-dimension steps: glowing crystal discs that only exist while
	# the world is shifted, giving the duel a second, shared layer to fight on.
	_build_mirror_steps(violet, blue)

	# The two starting cages, on opposite sides of the sigil.
	_build_cage(1, Color("#4fd8ff"))
	_build_cage(2, Color("#ff8ec9"))


func _build_mirror_steps(violet: StandardMaterial3D, blue: StandardMaterial3D) -> void:
	var spots := [
		Vector3(-6.5, 3.4, -4.0), Vector3(6.5, 3.4, 4.0),
		Vector3(-10.0, 5.6, 2.0), Vector3(10.0, 5.6, -2.0),
		Vector3(-3.4, 7.4, 7.4), Vector3(3.4, 7.4, -7.4),
	]
	for i in spots.size():
		var step := StaticBody3D.new()
		step.name = "MirrorStep_%02d" % i
		step.position = spots[i]
		step.add_to_group("mirror_dimension")
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 1.7
		cyl.height = 0.4
		shape.shape = cyl
		step.add_child(shape)
		var mesh := MeshInstance3D.new()
		var cyl_mesh := CylinderMesh.new()
		cyl_mesh.top_radius = 1.7
		cyl_mesh.bottom_radius = 1.7
		cyl_mesh.height = 0.4
		cyl_mesh.radial_segments = 24
		mesh.mesh = cyl_mesh
		mesh.material_override = blue if i % 2 == 0 else violet
		step.add_child(mesh)
		# A slowly turning rune ring under each step, purely decorative.
		var ring := MeshInstance3D.new()
		var ring_torus := TorusMesh.new()
		ring_torus.inner_radius = 1.85
		ring_torus.outer_radius = 2.05
		ring.mesh = ring_torus
		ring.position = Vector3(0.0, -0.16, 0.0)
		ring.material_override = violet
		step.add_child(ring)
		mirror_steps.append(step)
		add_child(step)


## A sealed starting cage: a raised pad, four posts, a roof and a solid door
## facing the sigil. The door's collision is a direct child of its own body and
## the body is added to the tree after both exist, so Jolt always registers it.
func _build_cage(slot: int, accent: Color) -> void:
	var spawn: Vector3 = CAGE_SPAWNS[slot]
	var inward := 1.0 if slot == 1 else -1.0
	var cage := Node3D.new()
	cage.name = "Cage_%d" % slot
	cage.position = spawn
	add_child(cage)

	var stone := _material(Color("#6d6485"), 0.0, 0.8)
	var pad := StaticBody3D.new()
	pad.name = "Pad"
	pad.position = Vector3(0.0, -0.25, 0.0)
	var pad_shape := CollisionShape3D.new()
	var pad_box := BoxShape3D.new()
	pad_box.size = Vector3(4.2, 0.5, 4.2)
	pad_shape.shape = pad_box
	pad.add_child(pad_shape)
	var pad_mesh := MeshInstance3D.new()
	var pad_mesh_box := BoxMesh.new()
	pad_mesh_box.size = Vector3(4.2, 0.5, 4.2)
	pad_mesh.mesh = pad_mesh_box
	pad_mesh.material_override = stone
	pad.add_child(pad_mesh)
	cage.add_child(pad)

	var gate_material := _material(Color("#ff5b72"), 1.8, 0.35)
	for corner in [Vector2(-1.9, -1.9), Vector2(1.9, -1.9), Vector2(-1.9, 1.9), Vector2(1.9, 1.9)]:
		var post := MeshInstance3D.new()
		var post_mesh := CylinderMesh.new()
		post_mesh.top_radius = 0.16
		post_mesh.bottom_radius = 0.22
		post_mesh.height = 3.4
		post.mesh = post_mesh
		post.position = Vector3(corner.x, 1.7, corner.y)
		post.material_override = stone
		cage.add_child(post)
	var roof := MeshInstance3D.new()
	var roof_mesh := BoxMesh.new()
	roof_mesh.size = Vector3(4.2, 0.35, 4.2)
	roof.mesh = roof_mesh
	roof.position = Vector3(0.0, 3.55, 0.0)
	roof.material_override = stone
	cage.add_child(roof)
	var roof_glow := MeshInstance3D.new()
	var roof_glow_mesh := BoxMesh.new()
	roof_glow_mesh.size = Vector3(3.4, 0.12, 3.4)
	roof_glow.mesh = roof_glow_mesh
	roof_glow.position = Vector3(0.0, 3.32, 0.0)
	roof_glow.material_override = _material(accent, 1.4, 0.3)
	cage.add_child(roof_glow)

	# The door: a solid slab on the side that faces the arena centre.
	var door := StaticBody3D.new()
	door.name = "Door"
	var closed_y := 1.75
	door.position = Vector3(0.0, closed_y, inward * 2.0)
	var door_shape := CollisionShape3D.new()
	var door_box := BoxShape3D.new()
	door_box.size = Vector3(4.0, 3.4, 0.3)
	door_shape.shape = door_box
	door.add_child(door_shape)
	var door_mesh := MeshInstance3D.new()
	var door_mesh_box := BoxMesh.new()
	door_mesh_box.size = Vector3(4.0, 3.4, 0.3)
	door_mesh.mesh = door_mesh_box
	door_mesh.material_override = gate_material
	door.add_child(door_mesh)
	cage.add_child(door)
	cage_doors[slot] = {"body": door, "shape": door_shape, "material": gate_material, "closed_y": closed_y, "accent": accent}


func _crystal(at: Vector3, height: float, material: StandardMaterial3D, tilt: float) -> void:
	var crystal := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 0.34 * (0.6 + height * 0.25)
	mesh.height = height
	mesh.radial_segments = 6
	crystal.mesh = mesh
	crystal.position = at + Vector3(0.0, height * 0.5, 0.0)
	crystal.rotation = Vector3(tilt, at.x * 0.3, tilt * 0.6)
	crystal.material_override = material
	add_child(crystal)


func _material(color: Color, emission: float, rough: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.emission_enabled = emission > 0.0
	mat.emission = color
	mat.emission_energy_multiplier = emission
	return mat


# ==============================================================================
#  PLAYERS
# ==============================================================================


func _build_hud() -> void:
	hud = BATTLE_HUD_SCRIPT.new()
	hud.local_slot = local_slot
	add_child(hud)
	hud.set_round(round_number, wins[1], wins[2])
	hud.set_health(1, MAX_DUEL_HEALTH, MAX_DUEL_HEALTH)
	hud.set_health(2, MAX_DUEL_HEALTH, MAX_DUEL_HEALTH)


func _spawn_local_player() -> void:
	player = PLAYER_SCENE.instantiate()
	player.name = "Duelist"
	player.set("character_id", _character_for(local_id))
	player.set("player_index", 0 if local_slot == 1 else 1)
	player.position = CAGE_SPAWNS[local_slot]
	add_child(player)
	player.set("arena_mode", true)
	player.set("controls_locked", true)
	player.call("set_player_name", _name_for(local_id))
	player.velocity = Vector3.ZERO

	view = Node3D.new()
	view.name = "View"
	view.set_script(VIEW_SCRIPT)
	# The duel camera: the boom cast has to start clear of the duelist's own
	# collider (its capsule tops out 1.6 above the floor), or the sweep begins in
	# contact and pins the boom to nothing. And in a duel the duelist is never
	# hidden: a cage is a tight spot, and a player who cannot see themselves
	# cannot judge a swing.
	view.set("avoid_head_height", 1.7)
	view.set("hide_target_when_close", 0.0)
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.fov = 40.0
	camera.position = Vector3(0.0, 0.0, 10.0)
	camera.current = true
	view.add_child(camera)
	# view.gd resolves $Camera and reads its target in _ready, so both must be
	# in place before the view enters the tree.
	view.set("target", player)
	add_child(view)
	# Aim the boom along the cage's facing so the duel opens looking at the
	# opponent across the sigil, the same way a level opens looking along its route.
	var ahead: Vector3 = (Vector3.ZERO - CAGE_SPAWNS[local_slot])
	ahead.y = 0.0
	var yaw := rad_to_deg(atan2(-ahead.x, -ahead.z)) if ahead.length() > 0.01 else 0.0
	view.rotation.y = deg_to_rad(yaw)
	view.set("camera_rotation", Vector3(-16.0, yaw, 0.0))
	player.set("view", view)

	player.died.connect(_on_local_died)
	player.magical_shield_changed.connect(_on_local_shield_changed)
	player.attacked.connect(_on_local_attacked)
	_last_pos[local_slot] = player.global_position
	_last_rot[local_slot] = player.rotation.y


func _spawn_opponent() -> void:
	var other := _other_id()
	if other == 0:
		return
	opponent = PLAYER_SCENE.instantiate()
	opponent.name = "Opponent"
	opponent.set("character_id", _character_for(other))
	opponent.set("player_index", 1 if local_slot == 1 else 0)
	opponent.set("view", null)
	opponent.position = CAGE_SPAWNS[_other_slot()]
	add_child(opponent)
	opponent.set("arena_mode", true)
	opponent.set("controls_locked", true)
	opponent.set_physics_process(false)
	# This is the only node the arena puts in the "enemies" group: the local
	# duelist's slash reaches it, and its take_hit() forwards the claim to the
	# host. Story-mode proxies are never in this group.
	opponent.add_to_group("enemies")
	opponent.call("set_player_name", _name_for(other))
	opponent.set_meta("net_target", opponent.position)
	opponent.set_meta("net_rot", opponent.rotation.y)
	_last_pos[_other_slot()] = opponent.position
	_last_rot[_other_slot()] = opponent.rotation.y


func _build_opponent_slash() -> void:
	_opponent_slash = MeshInstance3D.new()
	_opponent_slash.name = "OpponentSlash"
	var mesh := SphereMesh.new()
	mesh.radius = 0.55
	mesh.height = 1.1
	mesh.radial_segments = 14
	mesh.rings = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.95, 0.8, 0.85)
	mat.emission_enabled = true
	mat.emission = Color("#ffe078")
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = mat
	_opponent_slash.mesh = mesh
	_opponent_slash.visible = false
	add_child(_opponent_slash)


# ==============================================================================
#  LOCAL SPLIT-SCREEN DUEL
# ==============================================================================


## Keyboard keys per duelist slot: player 1 on the WASD side, player 2 on the
## arrow/numpad side, exactly like the story co-op's local split screen.
const _DUEL_KEYS := {
	1: {
		"left": KEY_A, "right": KEY_D, "forward": KEY_W, "back": KEY_S,
		"jump": KEY_SPACE, "dash": KEY_SHIFT, "time_freeze": KEY_F,
		"attack": KEY_J, "inventory": KEY_I,
		"magical_shield": KEY_H, "shift_dimension": KEY_Q,
	},
	2: {
		"left": KEY_LEFT, "right": KEY_RIGHT, "forward": KEY_UP, "back": KEY_DOWN,
		"jump": KEY_ENTER, "dash": KEY_KP_0, "time_freeze": KEY_KP_2,
		"attack": KEY_KP_3, "inventory": KEY_KP_5,
		"magical_shield": KEY_KP_4, "shift_dimension": KEY_KP_1,
	},
}


## Two duelists on one machine: player 1 in cage one, player 2 in cage two, each
## with half the screen and their own device. No network is involved at all.
func _setup_local_duel() -> void:
	var p1_device := str(get_tree().get_meta("local_p1_device", "keyboard"))
	var p2_device := str(get_tree().get_meta("local_p2_device", "keyboard"))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if p1_device.begins_with("pad") else Input.MOUSE_MODE_CAPTURED

	_spawn_local_player()

	player_two = PLAYER_SCENE.instantiate()
	player_two.name = "Duelist2"
	var picked := str(get_tree().get_meta("p2_character", ""))
	player_two.set("character_id", picked if ROSTER.has(picked) else ROSTER.default_id())
	player_two.set("player_index", 1)
	player_two.position = CAGE_SPAWNS[2]
	add_child(player_two)
	player_two.set("arena_mode", true)
	player_two.set("controls_locked", true)
	player_two.call("set_player_name", _local_name(2))
	# The arena's shared helpers work on "the other duelist": that is player two.
	opponent = player_two
	# Both duelists can be hit by the other: a swing finds them by group.
	player.add_to_group("enemies")
	player_two.add_to_group("enemies")

	_split_screen(p1_device, p2_device)
	player_two.died.connect(_on_second_died)
	_last_pos[1] = player.global_position
	_last_pos[2] = player_two.global_position
	_last_rot[1] = player.rotation.y
	_last_rot[2] = player_two.rotation.y
	hud.hint_label.text = "P1  %s   •   P2  %s   •   first to two rounds wins" % [
			_local_device_label(p1_device, 1), _local_device_label(p2_device, 2)]


## Two halves of the screen, built the way the story co-op does it: the 3D world
## stays in the root viewport and each SubViewport renders it through its own
## camera.
func _split_screen(p1_device: String, p2_device: String) -> void:
	_split_layer = CanvasLayer.new()
	_split_layer.name = "SplitScreen"
	_split_layer.layer = -1        # below the battle HUD
	add_child(_split_layer)
	var columns := HBoxContainer.new()
	columns.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	columns.add_theme_constant_override("separation", 3)
	_split_layer.add_child(columns)

	var viewport_a := _viewport_container(columns)
	var viewport_b := _viewport_container(columns)

	# Player 1's camera moves into the left half; player 2's is built fresh.
	remove_child(view)
	viewport_a.add_child(view)

	_view_two = Node3D.new()
	_view_two.name = "View2"
	_view_two.set_script(VIEW_SCRIPT)
	# The same duel-camera rules as player 1: never hide the duelist, and start
	# the boom cast clear of their own collider.
	_view_two.set("avoid_head_height", 1.7)
	_view_two.set("hide_target_when_close", 0.0)
	var camera_b := Camera3D.new()
	camera_b.name = "Camera"
	camera_b.fov = 40.0
	camera_b.position = Vector3(0.0, 0.0, 10.0)
	camera_b.current = true
	_view_two.add_child(camera_b)
	viewport_b.add_child(_view_two)
	_view_two.set("target", player_two)
	# Aim player 2's boom along their cage's facing, like player 1's.
	var ahead: Vector3 = Vector3.ZERO - CAGE_SPAWNS[2]
	ahead.y = 0.0
	var yaw := rad_to_deg(atan2(-ahead.x, -ahead.z))
	_view_two.rotation.y = deg_to_rad(yaw)
	_view_two.set("camera_rotation", Vector3(-16.0, yaw, 0.0))
	player_two.set("view", _view_two)

	# Each duelist gets their own action set, so a shared keyboard never fights.
	_configure_duelist(player, view, p1_device, 1)
	_configure_duelist(player_two, _view_two, p2_device, 2)


func _viewport_container(parent: Node) -> SubViewport:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.handle_input_locally = false
	container.add_child(viewport)
	return viewport


func _local_name(slot: int) -> String:
	return str(get_tree().get_meta("local_p1_name" if slot == 1 else "local_p2_name", "Player %d" % slot))


func _local_device_label(device: String, slot: int) -> String:
	if device.begins_with("pad"):
		return "controller"
	return "WASD + mouse" if slot == 1 else "arrows + numpad"


## Wire one duelist to the device the menu picked. Each slot gets its own action
## names ("p1_"/"p2_"), so two players never share an action.
func _configure_duelist(p: CharacterBody3D, v: Node3D, device: String, slot: int) -> void:
	var prefix := "p%d_" % slot
	for suffix in ["left", "right", "forward", "back", "jump", "dash", "time_freeze",
			"attack", "inventory", "cam_left", "cam_right", "cam_up", "cam_down",
			"magical_shield", "shift_dimension"]:
		_define_local_action(prefix + suffix)

	var is_pad := device.begins_with("pad")
	if is_pad:
		_bind_pad_actions(prefix, int(device.split(":")[1]))
	else:
		_bind_keyboard_actions(prefix, slot)

	p.set("action_left", prefix + "left")
	p.set("action_right", prefix + "right")
	p.set("action_forward", prefix + "forward")
	p.set("action_back", prefix + "back")
	p.set("action_jump", prefix + "jump")
	p.set("action_dash", prefix + "dash")
	p.set("action_time_freeze", prefix + "time_freeze")
	p.set("action_attack", prefix + "attack")
	p.set("action_magical_shield", prefix + "magical_shield")

	if v != null:
		v.set("action_cam_left", prefix + "cam_left")
		v.set("action_cam_right", prefix + "cam_right")
		v.set("action_cam_up", prefix + "cam_up")
		v.set("action_cam_down", prefix + "cam_down")
		v.set("input_enabled", true)
		# Only player 1 on the keyboard looks with the mouse.
		v.set("mouse_look", slot == 1 and not is_pad)


func _define_local_action(action_name: String) -> void:
	if InputMap.has_action(action_name):
		for existing in InputMap.action_get_events(action_name):
			InputMap.action_erase_event(action_name, existing)
	else:
		InputMap.add_action(action_name)
	InputMap.action_set_deadzone(action_name, 0.25)


func _bind_keyboard_actions(prefix: String, slot: int) -> void:
	var keys: Dictionary = _DUEL_KEYS[slot]
	var settings := get_node_or_null("/root/Settings")
	var binds: Dictionary = settings.get("key_binds") if settings != null else {}
	for action in keys.keys():
		# Player 1 on the keyboard uses whatever they rebound in the options;
		# player 2 keeps the arrow-key side so the two never collide.
		if slot == 1 and binds.has(str(action)):
			_add_stored_bind(prefix + str(action), int(binds[str(action)]))
			continue
		var key := InputEventKey.new()
		key.physical_keycode = keys[action] as Key
		key.device = -1
		InputMap.action_add_event(prefix + str(action), key)
	if slot == 1 and not binds.has("jump"):
		# Player 1 can also jump with the left mouse button, until they rebind it.
		var mouse_jump := InputEventMouseButton.new()
		mouse_jump.button_index = MOUSE_BUTTON_LEFT
		mouse_jump.device = -1
		InputMap.action_add_event(prefix + "jump", mouse_jump)


func _add_stored_bind(action_name: String, key_code: int) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = key_code as Key
	key.device = -1
	InputMap.action_add_event(action_name, key)


func _bind_pad_actions(prefix: String, pad_id: int) -> void:
	_add_joy_motion(prefix + "left", JOY_AXIS_LEFT_X, -1.0, pad_id)
	_add_joy_motion(prefix + "right", JOY_AXIS_LEFT_X, 1.0, pad_id)
	_add_joy_motion(prefix + "forward", JOY_AXIS_LEFT_Y, -1.0, pad_id)
	_add_joy_motion(prefix + "back", JOY_AXIS_LEFT_Y, 1.0, pad_id)
	_add_joy_motion(prefix + "cam_left", JOY_AXIS_RIGHT_X, -1.0, pad_id)
	_add_joy_motion(prefix + "cam_right", JOY_AXIS_RIGHT_X, 1.0, pad_id)
	_add_joy_motion(prefix + "cam_up", JOY_AXIS_RIGHT_Y, -1.0, pad_id)
	_add_joy_motion(prefix + "cam_down", JOY_AXIS_RIGHT_Y, 1.0, pad_id)
	_add_joy_button(prefix + "left", JOY_BUTTON_DPAD_LEFT, pad_id)
	_add_joy_button(prefix + "right", JOY_BUTTON_DPAD_RIGHT, pad_id)
	_add_joy_button(prefix + "forward", JOY_BUTTON_DPAD_UP, pad_id)
	_add_joy_button(prefix + "back", JOY_BUTTON_DPAD_DOWN, pad_id)
	_add_joy_button(prefix + "jump", JOY_BUTTON_A, pad_id)
	_add_joy_button(prefix + "dash", JOY_BUTTON_X, pad_id)
	_add_joy_button(prefix + "dash", JOY_BUTTON_RIGHT_SHOULDER, pad_id)
	_add_joy_button(prefix + "time_freeze", JOY_BUTTON_Y, pad_id)
	_add_joy_button(prefix + "attack", JOY_BUTTON_B, pad_id)
	_add_joy_button(prefix + "inventory", JOY_BUTTON_BACK, pad_id)
	_add_joy_button(prefix + "magical_shield", JOY_BUTTON_LEFT_SHOULDER, pad_id)
	_add_joy_button(prefix + "shift_dimension", JOY_BUTTON_LEFT_STICK, pad_id)


func _add_joy_motion(action_name: String, axis: JoyAxis, value: float, device: int) -> void:
	var motion := InputEventJoypadMotion.new()
	motion.axis = axis
	motion.axis_value = value
	motion.device = device
	InputMap.action_add_event(action_name, motion)


func _add_joy_button(action_name: String, button: JoyButton, device: int) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.device = device
	InputMap.action_add_event(action_name, event)


func _on_second_died() -> void:
	if local_duel:
		_host_on_death(2)


func _place_duelist(duelist: CharacterBody3D, slot: int) -> void:
	if duelist == null or not is_instance_valid(duelist):
		return
	var spawn: Vector3 = CAGE_SPAWNS[slot]
	duelist.global_position = spawn
	duelist.velocity = Vector3.ZERO
	duelist.set("is_dead", false)
	duelist.set("gravity", 0.0)
	duelist.set("knockback", Vector3.ZERO)
	duelist.set("movement_velocity", Vector3.ZERO)
	duelist.set("attack_timer", 0.0)
	duelist.set("attack_cooldown_left", 0.0)
	duelist.set("controls_locked", true)
	var ahead: Vector3 = -spawn
	if ahead.length() > 0.01:
		# player.gd steers rotation.y toward `rotation_direction` every frame, so the
		# target has to be set too or the duelist slowly turns back to +Z (0.0) while
		# waiting in the cage and opens the round facing away from the sigil.
		var facing := atan2(ahead.x, ahead.z)
		duelist.rotation.y = facing
		duelist.set("rotation_direction", facing)
	var model := duelist.get("model") as Node3D
	if model != null:
		model.scale = Vector3.ONE
	if duelist == player:
		player.call("reset_vitals")
		player.call("set_fly_mode", false)
	elif local_duel and player_two != null and duelist == player_two:
		player_two.call("reset_vitals")
	_last_pos[slot] = spawn
	_last_rot[slot] = duelist.rotation.y
	if duelist == opponent:
		opponent.set_meta("net_target", spawn)
		opponent.set_meta("net_rot", duelist.rotation.y)


func _lock_duelist() -> void:
	_set_controls_locked(true)


## Freeze or release every duelist on this machine (a local duel has two).
func _set_controls_locked(locked: bool) -> void:
	for duelist in [player, player_two]:
		if duelist == null or not is_instance_valid(duelist):
			continue
		duelist.set("controls_locked", locked)
		duelist.set("movement_velocity", Vector3.ZERO)
		if locked:
			duelist.velocity = Vector3.ZERO


# ==============================================================================
#  MATCH FLOW (host-authoritative; every transition travels by RPC)
# ==============================================================================


func _host_tick(delta: float) -> void:
	dimension_cooldown = maxf(0.0, dimension_cooldown - delta)
	if phase == Phase.COUNTDOWN:
		countdown = maxf(0.0, countdown - delta)
		var seconds := ceili(countdown)
		if seconds != _last_tick:
			_last_tick = seconds
			_broadcast("_apply_countdown", {"seconds": seconds})
		if countdown <= 0.0:
			_open_arena()
	elif phase == Phase.FIGHT:
		_grace_left = maxf(0.0, _grace_left - delta)
		if _pending_death != 0:
			_death_window -= delta
			if _death_window <= 0.0:
				_host_finish_round()
	elif phase == Phase.ROUND_END:
		_transition_left -= delta
		if _transition_left <= 0.0:
			if int(wins[1]) >= WINS_TO_TAKE_THE_MATCH or int(wins[2]) >= WINS_TO_TAKE_THE_MATCH:
				_host_match_over(1 if int(wins[1]) >= WINS_TO_TAKE_THE_MATCH else 2)
			else:
				if _advance_round:
					round_number += 1
				_begin_round()


func _begin_round() -> void:
	if not multiplayer.is_server():
		return
	phase = Phase.COUNTDOWN
	_reported.clear()
	_death_marks.clear()
	_pending_death = 0
	_death_window = 0.0
	_grace_left = 0.0
	countdown = maxf(1.0, round_countdown)
	_last_tick = -1
	hp[1] = MAX_DUEL_HEALTH
	hp[2] = MAX_DUEL_HEALTH
	_rematch_votes.clear()
	_broadcast("_apply_duelists_reset", {"hp1": hp[1], "hp2": hp[2], "round": round_number, "wins1": wins[1], "wins2": wins[2]})
	_broadcast("_apply_phase", {"phase": Phase.COUNTDOWN, "round": round_number, "countdown": countdown})
	_broadcast("_apply_countdown", {"seconds": int(ceil(countdown))})


func _open_arena() -> void:
	if not multiplayer.is_server():
		return
	phase = Phase.FIGHT
	_grace_left = spawn_protection
	_broadcast("_apply_cages_open", {})
	_broadcast("_apply_phase", {"phase": Phase.FIGHT, "round": round_number, "countdown": 0.0})


## Host-only: one duelist has fallen. A second death inside the draw window
## means a double knock-out: the round is replayed and neither side scores.
func _host_on_death(slot: int) -> void:
	if phase != Phase.FIGHT or slot == 0:
		return
	if _reported.has(slot):
		return
	_reported[slot] = true
	_death_marks[slot] = true
	if _pending_death == 0:
		_pending_death = slot
		_death_window = DRAW_WINDOW
	else:
		_host_finish_round()


func _host_finish_round() -> void:
	if phase != Phase.FIGHT or _pending_death == 0:
		return
	var fallen: int = _pending_death
	var other := 3 - fallen
	var draw := _death_marks.has(other)
	var winner := 0 if draw else other
	if not draw:
		wins[winner] = int(wins[winner]) + 1
	rounds_played += 1
	_advance_round = not draw
	_pending_death = 0
	_death_window = 0.0
	phase = Phase.ROUND_END
	_transition_left = round_freeze
	_broadcast("_apply_round_end", {
		"draw": draw,
		"winner": winner,
		"wins1": wins[1],
		"wins2": wins[2],
		"round": round_number,
		"rounds": rounds_played,
	})


func _host_match_over(winner_slot: int) -> void:
	phase = Phase.MATCH_OVER
	_rematch_votes.clear()
	_broadcast("_apply_match_over", {
		"winner": winner_slot,
		"wins1": wins[1],
		"wins2": wins[2],
		"rounds": rounds_played,
	})


func _host_vote(slot: int) -> void:
	if phase != Phase.MATCH_OVER or slot == 0:
		return
	_rematch_votes[slot] = true
	_broadcast("_apply_rematch", {"v1": _rematch_votes.has(1), "v2": _rematch_votes.has(2)})
	if _rematch_votes.has(1) and _rematch_votes.has(2):
		# Both duelists asked for another match: back to round one, fresh score.
		wins[1] = 0
		wins[2] = 0
		round_number = 1
		rounds_played = 0
		mirror_dimension = false
		_begin_round()


func _host_try_hit(attacker_slot: int, from: Vector3) -> void:
	if phase != Phase.FIGHT or _grace_left > 0.0:
		return
	var victim := 3 - attacker_slot
	if _reported.has(attacker_slot) or _reported.has(victim):
		return
	if float(hp.get(victim, 0.0)) <= 0.0:
		return
	# Server-side validation triangle: the attacker must really be near the
	# point they claimed, and the victim within the swing's reach of it.
	var attacker_pos: Vector3 = _last_pos.get(attacker_slot, from)
	if attacker_pos.distance_to(from) > 3.0:
		return
	var victim_pos: Vector3 = _last_pos.get(victim, Vector3.ZERO)
	if victim_pos.distance_to(from) > 3.1:
		return
	var amount := DUEL_DAMAGE
	if bool(shields_on.get(victim, false)):
		amount *= SHIELD_FACTOR
	hp[victim] = maxf(0.0, float(hp[victim]) - amount)
	_broadcast("_apply_hit", {"victim": victim, "amount": amount, "hp1": hp[1], "hp2": hp[2], "from": from})
	if float(hp[victim]) <= 0.0:
		_host_on_death(victim)


# ==============================================================================
#  INPUT & LOCAL REQUESTS
# ==============================================================================


func _unhandled_input(event: InputEvent) -> void:
	# Either duelist can shift the shared world in a local duel.
	var shift := _pressed(event, "shift_dimension") \
			or (local_duel and _pressed(event, "p2_shift_dimension"))
	if shift and phase == Phase.FIGHT \
			and player != null and not bool(player.get("controls_locked")):
		_request_dimension()
	elif event.is_action_pressed("ui_cancel") and phase in [Phase.WAITING, Phase.MATCH_OVER]:
		_return_to_menu()


## Guarded input check: the campaign creates its actions on demand, so a duel can
## be the first thing played and an action may simply not exist yet.
func _pressed(event: InputEvent, action: String) -> bool:
	if not InputMap.has_action(action):
		return false
	return event.is_action_pressed(action)


## The dimension key has to exist for a duel to notice it.
func _ensure_shift_action() -> void:
	if InputMap.has_action("shift_dimension"):
		return
	InputMap.add_action("shift_dimension")
	InputMap.action_set_deadzone("shift_dimension", 0.25)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_Q
	key.device = -1
	InputMap.action_add_event("shift_dimension", key)


## A slash reached the other duelist: only a claim until the host validates it.
## Called from player.take_hit() on the opponent proxy.
func request_hit(from: Vector3) -> bool:
	if local_duel:
		# Both duelists are on this machine, so the swing itself says who made
		# it: the attacker is the one standing at the claimed point.
		_host_try_hit(_nearest_duelist_slot(from), from)
	elif multiplayer.is_server():
		_host_try_hit(local_slot, from)
	elif multiplayer.multiplayer_peer != null:
		rpc_id(1, "_claim_hit", {"from": from})
	return true


## Which of the two local duelists swung at [param from]: the one nearest the
## claimed hit point (the victim is the node the swing reached, so the attacker
## is the one beside it).
func _nearest_duelist_slot(from: Vector3) -> int:
	if player_two == null or not is_instance_valid(player_two):
		return 1
	var one := player.global_position.distance_to(from)
	var two := player_two.global_position.distance_to(from)
	return 1 if one <= two else 2


func _on_local_attacked(direction: int) -> void:
	if multiplayer.multiplayer_peer == null or phase != Phase.FIGHT:
		return
	_broadcast_visual("_opponent_swing", {"dir": direction})


func _on_local_died() -> void:
	if phase != Phase.FIGHT:
		return
	if multiplayer.is_server():
		_host_on_death(local_slot)
	elif multiplayer.multiplayer_peer != null:
		rpc_id(1, "_claim_death", {})


func _on_local_shield_changed(active: bool, _cooldown_left: float, _cooldown_max: float) -> void:
	shields_on[local_slot] = active
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		rpc_id(1, "_report_shield", {"active": active})


func _request_dimension() -> void:
	if multiplayer.is_server():
		_host_shift_dimension()
	elif multiplayer.multiplayer_peer != null:
		rpc_id(1, "_claim_dimension", {})


func _host_shift_dimension() -> void:
	if phase != Phase.FIGHT or dimension_cooldown > 0.0:
		return
	dimension_cooldown = DIMENSION_COOLDOWN
	mirror_dimension = not mirror_dimension
	_broadcast("_apply_dimension_state", {"mirror": mirror_dimension})


func _vote_rematch() -> void:
	if phase != Phase.MATCH_OVER:
		return
	if local_duel:
		# Both duelists share this screen, so one press is enough to restart.
		_host_vote(1)
		_host_vote(2)
		return
	if multiplayer.is_server():
		_host_vote(local_slot)
	elif multiplayer.multiplayer_peer != null:
		rpc_id(1, "_claim_rematch", {})


func _claim_state() -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		rpc_id(1, "_ask_state", {})


## A slow start: if nothing from the host has arrived shortly after the arena
## loaded, ask for the snapshot directly as well.
func _claim_state_later() -> void:
	await get_tree().create_timer(2.5).timeout
	if phase == Phase.WAITING and not _host_arena_seen:
		_claim_state()


# ==============================================================================
#  NETWORK PLUMBING
# ==============================================================================


func _broadcast(method_name: StringName, data: Dictionary) -> void:
	if multiplayer.multiplayer_peer != null and _can_reach_opponent():
		rpc(method_name, data)
	else:
		# No opponent whose arena exists yet: run it here only, or the packet is
		# dropped on the other side with "Node not found".
		callv(method_name, [data])


## True when an RPC from this arena can actually reach the other duelist: their
## arena scene has to exist over there, or the packet is lost.
func _can_reach_opponent() -> bool:
	if local_duel:
		return false
	if not multiplayer.is_server():
		return multiplayer.multiplayer_peer != null
	return _opponent_ready()


## Visual-only events do not run on the sender (it plays them itself).
func _broadcast_visual(method_name: StringName, data: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	rpc(method_name, data)


func _slot_of(id: int) -> int:
	return 1 if int(id) == 1 else 2


@rpc("any_peer", "call_remote", "reliable")
func _claim_hit(data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_host_try_hit(_slot_of(multiplayer.get_remote_sender_id()), data.get("from", Vector3.ZERO))


@rpc("any_peer", "call_remote", "reliable")
func _claim_death(_data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_host_on_death(_slot_of(multiplayer.get_remote_sender_id()))


@rpc("any_peer", "call_remote", "reliable")
func _claim_rematch(_data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_host_vote(_slot_of(multiplayer.get_remote_sender_id()))


@rpc("any_peer", "call_remote", "reliable")
func _claim_dimension(_data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_host_shift_dimension()


@rpc("any_peer", "call_remote", "reliable")
func _report_shield(data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	shields_on[_slot_of(multiplayer.get_remote_sender_id())] = bool(data.get("active", false))


@rpc("any_peer", "call_remote", "reliable")
func _ask_state(_data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		return
	rpc_id(peer, "_apply_snapshot", _snapshot())


@rpc("any_peer", "call_remote", "unreliable")
func _recv_state(data: Dictionary) -> void:
	_host_arena_seen = true
	var sender := multiplayer.get_remote_sender_id()
	var id := int(data.get("id", 0))
	if multiplayer.is_server():
		if sender != id:
			return
	else:
		if sender != 1:
			return
	var slot := _slot_of(id)
	_last_pos[slot] = data.get("pos", Vector3.ZERO)
	_last_rot[slot] = data.get("rot", 0.0)
	if slot == _other_slot() and opponent != null and is_instance_valid(opponent):
		opponent.set_meta("net_target", _last_pos[slot])
		opponent.set_meta("net_rot", _last_rot[slot])
	if multiplayer.is_server():
		for peer_id in multiplayer.get_peers():
			if peer_id != id:
				rpc_id(peer_id, "_recv_state", data)


# ==============================================================================
#  STATE APPLIED (runs on every peer; call_local RPCs)
# ==============================================================================


@rpc("any_peer", "call_local", "unreliable")
func _apply_snapshot(data: Dictionary) -> void:
	_host_arena_seen = true
	phase = int(data.get("phase", Phase.WAITING))
	round_number = int(data.get("round", 1))
	rounds_played = int(data.get("rounds", 0))
	countdown = float(data.get("countdown", 0.0))
	wins[1] = int(data.get("wins1", 0))
	wins[2] = int(data.get("wins2", 0))
	hp[1] = float(data.get("hp1", MAX_DUEL_HEALTH))
	hp[2] = float(data.get("hp2", MAX_DUEL_HEALTH))
	hud.set_round(round_number, wins[1], wins[2])
	hud.set_health(1, hp[1], MAX_DUEL_HEALTH)
	hud.set_health(2, hp[2], MAX_DUEL_HEALTH)
	_set_cages_locked(phase != Phase.FIGHT)
	hud.hide_waiting()
	hud.hide_victory()
	if phase == Phase.COUNTDOWN:
		hud.show_banner("GET READY FOR BATTLE!", Color("#ffe078"))
		hud.show_countdown(int(ceil(countdown)))
	elif phase == Phase.FIGHT:
		hud.hide_banner()
		hud.hide_countdown()
		_set_controls_locked(false)
	_apply_dimension(bool(data.get("mirror", false)))


@rpc("authority", "call_local", "reliable")
func _apply_duelists_reset(data: Dictionary) -> void:
	hp[1] = float(data.get("hp1", MAX_DUEL_HEALTH))
	hp[2] = float(data.get("hp2", MAX_DUEL_HEALTH))
	wins[1] = int(data.get("wins1", wins[1]))
	wins[2] = int(data.get("wins2", wins[2]))
	round_number = int(data.get("round", round_number))
	_reported.clear()
	_death_marks.clear()
	_pending_death = 0
	hud.hide_waiting()
	hud.hide_victory()
	hud.hide_disconnect()
	hud.set_round(round_number, wins[1], wins[2])
	hud.set_health(1, hp[1], MAX_DUEL_HEALTH)
	hud.set_health(2, hp[2], MAX_DUEL_HEALTH)
	hud.set_rematch_status(_rematch_hint())
	_place_duelist(player, local_slot)
	_place_duelist(opponent, _other_slot())
	_set_cages_locked(true)
	_apply_dimension(mirror_dimension)


@rpc("authority", "call_local", "reliable")
func _apply_phase(data: Dictionary) -> void:
	phase = int(data.get("phase", phase))
	round_number = int(data.get("round", round_number))
	countdown = float(data.get("countdown", countdown))
	hud.hide_waiting()
	match phase:
		Phase.COUNTDOWN:
			_lock_duelist()
			hud.set_round(round_number, wins[1], wins[2])
			hud.show_banner("GET READY FOR BATTLE!", Color("#ffe078"))
			hud.announce("BOTH CAGES SEALED — ROUND %d" % round_number, 26, Color("#cfe9ff"))
		Phase.FIGHT:
			hud.hide_banner()
			hud.hide_countdown()
			_set_controls_locked(false)
			hud.announce("FIGHT!", 64, Color("#ffd451"))
		Phase.ROUND_END:
			_lock_duelist()
		Phase.MATCH_OVER:
			_lock_duelist()


@rpc("authority", "call_local", "reliable")
func _apply_countdown(data: Dictionary) -> void:
	if phase != Phase.COUNTDOWN:
		return
	var seconds := int(data.get("seconds", 0))
	hud.show_countdown(seconds)
	hud.show_banner("GET READY FOR BATTLE!", Color("#ffe078"))


@rpc("authority", "call_local", "reliable")
func _apply_cages_open(_data: Dictionary) -> void:
	_set_cages_locked(false)
	# The dramatic beat: the barrier flares, both doors rise together.
	if barrier_material != null:
		barrier_material.emission_energy_multiplier = 3.2
		var barrier_tween := create_tween()
		barrier_tween.tween_property(barrier_material, "emission_energy_multiplier", 0.9, 1.1)
	Audio.play("res://sounds/land.ogg")
	hud.hide_countdown()
	hud.announce("FIGHT!", 64, Color("#ffd451"))


@rpc("authority", "call_local", "reliable")
func _apply_hit(data: Dictionary) -> void:
	var victim := int(data.get("victim", 0))
	hp[1] = float(data.get("hp1", hp[1]))
	hp[2] = float(data.get("hp2", hp[2]))
	var from: Vector3 = data.get("from", Vector3.ZERO)
	hud.set_health(1, hp[1], MAX_DUEL_HEALTH)
	hud.set_health(2, hp[2], MAX_DUEL_HEALTH)
	if victim == local_slot:
		_apply_local_damage(float(data.get("amount", 0.0)), from)
		hud.flash_hurt()
	elif local_duel and victim == _other_slot():
		_apply_duelist_damage(player_two, float(data.get("amount", 0.0)), from)
		hud.flash_hurt()
	else:
		_flash_opponent_hit(from)


@rpc("authority", "call_local", "reliable")
func _apply_round_end(data: Dictionary) -> void:
	phase = Phase.ROUND_END
	rounds_played = int(data.get("rounds", rounds_played))
	wins[1] = int(data.get("wins1", wins[1]))
	wins[2] = int(data.get("wins2", wins[2]))
	hud.hide_countdown()
	hud.set_round(int(data.get("round", round_number)), wins[1], wins[2])
	_lock_duelist()
	if bool(data.get("draw", false)):
		hud.show_banner("DOUBLE KNOCK-OUT — ROUND REPLAYED", Color("#ff8a9c"))
		hud.announce("No point for either duelist. The round is replayed!", 26, Color("#ff8a9c"))
	else:
		var winner := int(data.get("winner", 0))
		hud.show_banner("%s TAKES ROUND %d" % [_name_for(_id_for_slot(winner)).to_upper(), int(data.get("round", round_number))],
				Color("#8fe0ff") if winner == local_slot else Color("#ffd451"))
		hud.announce("%d  —  %d" % [wins[1], wins[2]], 54, Color("#ffe078"))


@rpc("authority", "call_local", "reliable")
func _apply_match_over(data: Dictionary) -> void:
	phase = Phase.MATCH_OVER
	wins[1] = int(data.get("wins1", wins[1]))
	wins[2] = int(data.get("wins2", wins[2]))
	rounds_played = int(data.get("rounds", rounds_played))
	var winner := int(data.get("winner", 0))
	var winner_name := _name_for(_id_for_slot(winner))
	var local_won := winner == local_slot
	hud.hide_banner()
	hud.hide_countdown()
	_lock_duelist()
	hud.show_victory(winner_name, "%d  —  %d   •   %d ROUNDS PLAYED" % [wins[1], wins[2], rounds_played],
		("%s fought bravely and fell to your magic. Well duelled!" if local_won
			else "%s takes the crown this time — challenge them again!" % winner_name),
		local_won)
	hud.set_rematch_status(_rematch_hint())


## A local duel shares one screen, so one press restarts it; an online match
## needs both duelists to agree.
func _rematch_hint() -> String:
	return "PLAY AGAIN restarts the duel." if local_duel else "PLAY AGAIN needs both duelists to agree."


@rpc("authority", "call_local", "reliable")
func _apply_rematch(data: Dictionary) -> void:
	var votes := 0
	if bool(data.get("v1", false)):
		votes += 1
	if bool(data.get("v2", false)):
		votes += 1
	var mine := false
	if multiplayer.is_server():
		mine = bool(data.get("v1", false))
	else:
		mine = bool(data.get("v2", false))
	if mine:
		hud.set_rematch_status("%d/2 duelists ready — waiting for your opponent…" % votes)
	else:
		hud.set_rematch_status("%d/2 duelists ready — your opponent wants a rematch!" % votes)


@rpc("authority", "call_local", "reliable")
func _apply_dimension_state(data: Dictionary) -> void:
	_apply_dimension(bool(data.get("mirror", false)))


func _apply_dimension(mirror: bool) -> void:
	mirror_dimension = mirror
	for node in get_tree().get_nodes_in_group("mirror_dimension"):
		var n := node as Node3D
		if n == null:
			continue
		n.visible = mirror
		for shape in n.find_children("*", "CollisionShape3D", true, false):
			(shape as CollisionShape3D).set_deferred("disabled", not mirror)
	for step in mirror_steps:
		if is_instance_valid(step):
			step.visible = mirror
	if sun != null:
		sun.light_color = Color("#a7eaff") if mirror else Color("#fff2d6")
	if barrier_material != null:
		barrier_material.emission = Color("#8fe0ff") if mirror else Color("#b06bff")
		barrier_material.albedo_color = Color(0.45, 0.8, 1.0, 0.13) if mirror else Color(0.69, 0.42, 1.0, 0.13)
	if phase == Phase.FIGHT:
		hud.announce("MIRROR DIMENSION" if mirror else "MATERIAL DIMENSION", 30, Color("#a6f4ff"))


@rpc("any_peer", "call_remote", "reliable")
func _opponent_swing(data: Dictionary) -> void:
	if opponent == null or not is_instance_valid(opponent):
		return
	var direction := int(data.get("dir", 0))
	_play_opponent_swing(direction)


func _play_opponent_swing(direction: int) -> void:
	if opponent == null or not is_instance_valid(opponent):
		return
	var model := opponent.get("model") as Node3D
	if model != null and model.has_method("set_swing"):
		if _opponent_swing_tween != null and _opponent_swing_tween.is_valid():
			_opponent_swing_tween.kill()
		_opponent_swing_tween = create_tween()
		_opponent_swing_tween.tween_method(
			func(amount: float) -> void:
				if is_instance_valid(model):
					model.call("set_swing", amount, direction),
			0.0, 1.0, 0.09)
		_opponent_swing_tween.tween_method(
			func(amount: float) -> void:
				if is_instance_valid(model):
					model.call("set_swing", amount, direction),
			1.0, 0.0, 0.09)
	if _opponent_slash != null:
		_opponent_slash.visible = true
		_opponent_slash.global_position = opponent.global_position + Vector3(0.0, 0.75, 0.0) \
				+ Vector3(sin(opponent.rotation.y), 0.0, cos(opponent.rotation.y)) * 1.1
		_opponent_slash.scale = Vector3(0.4, 0.4, 0.4)
		var flash := create_tween()
		flash.tween_property(_opponent_slash, "scale", Vector3.ONE, 0.08)
		flash.tween_property(_opponent_slash, "scale", Vector3(1.4, 1.4, 1.4), 0.12)
		flash.tween_callback(func() -> void: _opponent_slash.visible = false)
	Audio.play("res://sounds/break.ogg")


func _apply_local_damage(amount: float, from: Vector3) -> void:
	_apply_duelist_damage(player, amount, from)


## A duelist on this machine was hit: health, knockback, squash, sound, and the
## death that ends the round.
func _apply_duelist_damage(duelist: CharacterBody3D, amount: float, from: Vector3) -> void:
	if duelist == null or not is_instance_valid(duelist) or bool(duelist.get("is_dead")):
		return
	duelist.set("health", maxf(0.0, float(duelist.get("health")) - amount))
	duelist.emit_signal("health_changed", duelist.get("health"), duelist.get("max_health"))
	var away := duelist.global_position - from
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = -Vector3(sin(duelist.rotation.y), 0.0, cos(duelist.rotation.y))
	duelist.set("knockback", away.normalized() * float(duelist.get("hurt_knockback")))
	var model := duelist.get("model") as Node3D
	if model != null:
		model.scale = Vector3(1.35, 0.7, 1.35)
	Audio.play("res://sounds/land.ogg")
	if float(duelist.get("health")) <= 0.0:
		duelist.set("knockback", Vector3.ZERO)
		duelist.call("die", "pvp")


func _flash_opponent_hit(_from: Vector3) -> void:
	if opponent == null or not is_instance_valid(opponent):
		return
	var model := opponent.get("model") as Node3D
	if model != null:
		model.scale = Vector3(1.35, 0.7, 1.35)
	if _opponent_slash != null:
		_opponent_slash.visible = true
		_opponent_slash.global_position = opponent.global_position + Vector3(0.0, 0.8, 0.0)
		_opponent_slash.scale = Vector3(1.3, 1.3, 1.3)
		var flash := create_tween()
		flash.tween_property(_opponent_slash, "scale", Vector3(0.2, 0.2, 0.2), 0.18)
		flash.tween_callback(func() -> void: _opponent_slash.visible = false)
	Audio.play("res://sounds/break.ogg")


func _set_cages_locked(locked: bool) -> void:
	for slot in cage_doors.keys():
		var door: Dictionary = cage_doors[slot]
		var body := door["body"] as StaticBody3D
		var shape := door["shape"] as CollisionShape3D
		var material := door["material"] as StandardMaterial3D
		if body == null or not is_instance_valid(body):
			continue
		if locked:
			body.position.y = float(door["closed_y"])
			shape.set_deferred("disabled", false)
			material.albedo_color = Color("#ff5b72")
			material.emission = Color("#ff5b72")
		else:
			shape.set_deferred("disabled", true)
			var target_y := float(door["closed_y"]) + 3.9
			var tween := body.create_tween()
			tween.tween_property(body, "position:y", target_y, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			material.albedo_color = Color("#4fd8ff")
			material.emission = Color("#4fd8ff")


func _id_for_slot(slot: int) -> int:
	if local_duel:
		return slot
	if slot == 1:
		return 1
	if multiplayer.is_server():
		return p2_id if p2_id != 0 else local_id
	return local_id


# ==============================================================================
#  FRAME LOOP
# ==============================================================================


func _physics_process(delta: float) -> void:
	if phase == Phase.OVER:
		return
	if multiplayer.is_server():
		_host_tick(delta)
	_sync_my_state()


func _process(delta: float) -> void:
	# A local duel has no proxy to lerp: player two runs its own movement.
	if not local_duel and opponent != null and is_instance_valid(opponent):
		var target: Vector3 = opponent.get_meta("net_target", opponent.position)
		opponent.position = opponent.position.lerp(target, delta * 12.0)
		var target_rot: float = opponent.get_meta("net_rot", opponent.rotation.y)
		opponent.rotation.y = lerp_angle(opponent.rotation.y, target_rot, delta * 12.0)
	if _disconnect_left > 0.0:
		_disconnect_left = maxf(0.0, _disconnect_left - delta)
		hud.set_disconnect_count(ceili(_disconnect_left))
		if _disconnect_left <= 0.0:
			_return_to_menu()


func _sync_my_state() -> void:
	if player == null or not is_instance_valid(player):
		return
	_last_pos[local_slot] = player.global_position
	_last_rot[local_slot] = player.rotation.y
	if local_duel and player_two != null and is_instance_valid(player_two):
		_last_pos[2] = player_two.global_position
		_last_rot[2] = player_two.rotation.y
	if multiplayer.multiplayer_peer == null:
		return
	var data := {"id": local_id, "pos": player.global_position, "rot": player.rotation.y}
	if multiplayer.is_server():
		if _opponent_ready():
			rpc("_recv_state", data)
	else:
		if _host_arena_seen \
				and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			rpc_id(1, "_recv_state", data)


# ==============================================================================
#  LEAVING & DISCONNECTS
# ==============================================================================


func _on_peer_left(id: int) -> void:
	if _leaving or _returning:
		return
	if int(id) == local_id:
		return
	_show_opponent_left("Your opponent left the arena. The match is over.")


func _on_connection_lost() -> void:
	if _returning:
		return
	_show_opponent_left("The arena connection was closed.")


func _show_opponent_left(body: String) -> void:
	if _returning:
		return
	_leaving = true
	phase = Phase.OVER
	_lock_duelist()
	hud.hide_waiting()
	hud.hide_victory()
	hud.hide_banner()
	hud.hide_countdown()
	_disconnect_left = DISCONNECT_RETURN
	hud.show_disconnect(body + "\nYou are returned to the multiplayer menu safely.", ceili(_disconnect_left))


func _return_to_menu() -> void:
	if _returning:
		return
	_returning = true
	if network != null:
		network.close()
	get_tree().set_meta("online", false)
	get_tree().set_meta("local_coop", false)
	get_tree().set_meta("open_multiplayer_menu", true)
	get_tree().paused = false
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/home.tscn")
