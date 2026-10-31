extends Node

## ENet-based online co-op. One player hosts (creates a room), others join by
## the host's IP address. No external service is required.

signal connection_succeeded
signal connection_failed
signal peer_list_changed

const DEFAULT_PORT := 27015
const MAX_PLAYERS := 4

var is_host := false
var is_online := false
var game_started := false
var current_level := 1
var players: Dictionary = {}
# Character names: the local player's name, and the name of every peer.
var local_name := "Player"
var player_names: Dictionary = {}  # peer_id -> name


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host(port: int = DEFAULT_PORT) -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(port, MAX_PLAYERS - 1) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	is_online = true
	is_host = true
	players.clear()
	players[1] = true
	player_names.clear()
	player_names[1] = local_name
	peer_list_changed.emit()
	return true


func join(address: String, port: int = DEFAULT_PORT) -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address, port) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	is_online = true
	is_host = false
	players.clear()
	player_names.clear()
	return true


func close() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	is_online = false
	is_host = false
	game_started = false
	players.clear()
	player_names.clear()


## Host-only: tell every connected client (and any future joiner) to load `level`.
func start_game(level: int) -> void:
	current_level = level
	game_started = true
	if multiplayer.is_server():
		rpc("_set_level", level)


func get_local_address() -> String:
	for address in IP.get_local_addresses():
		if address.count(".") == 3 and not address.begins_with("127.") and not address.begins_with("169.254."):
			return address
	return "127.0.0.1"


func player_ids() -> Array:
	return players.keys()


func _on_peer_connected(id: int) -> void:
	players[id] = true
	peer_list_changed.emit()
	if multiplayer.is_server():
		# Tell the newcomer who I am.
		rpc_id(id, "_register_name", multiplayer.get_unique_id(), local_name)
		# A client that joins after the host started goes straight into the level.
		if game_started:
			rpc_id(id, "_set_level", current_level)


func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	peer_list_changed.emit()


func _on_connected_to_server() -> void:
	players[1] = true
	peer_list_changed.emit()
	# Announce my name to the host, which relays it to everyone else.
	rpc("_register_name", multiplayer.get_unique_id(), local_name)
	connection_succeeded.emit()


func _on_connection_failed() -> void:
	close()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	close()
	connection_failed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _register_name(id: int, player_name: String) -> void:
	var sender_id := multiplayer.get_remote_sender_id()

	if multiplayer.is_server():
		if sender_id != id:
			return
	else:
		if sender_id != 1:
			return

	player_names[id] = player_name
	peer_list_changed.emit()
	# The host relays names so every client learns every player's name.
	if multiplayer.is_server():
		for peer_id in multiplayer.get_peers():
			if peer_id != id:
				rpc_id(peer_id, "_register_name", id, player_name)


func get_player_name(id: int) -> String:
	return str(player_names.get(id, "Player"))


@rpc("authority", "call_remote", "reliable")
func _set_level(level: int) -> void:
	get_tree().set_meta("level_number", level)
	get_tree().set_meta("online", true)
	get_tree().set_meta("local_coop", false)
	get_tree().change_scene_to_file("res://scenes/main.tscn")
