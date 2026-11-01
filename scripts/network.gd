extends Node

## ENet-based online co-op. One player hosts (creates a room), others join by
## the host's IP address. No external service is required.

signal connection_succeeded
signal connection_failed
signal peer_list_changed
# Raised on the peer whose name was already in use: the host has given it a free
# variation of it and this is what it is now.
signal name_taken(new_name: String)

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
# Chosen characters (ids from res://scripts/roster.gd), local and per peer.
var local_character := ""
var player_characters: Dictionary = {}  # peer_id -> character id


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
	player_characters.clear()
	player_characters[1] = local_character
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
	player_characters.clear()


## Send our name and chosen character to the host (which relays them to everyone).
## Safe to call again when the local player changes their pick after connecting.
func announce_profile() -> void:
	if not is_online or multiplayer.multiplayer_peer == null:
		return
	var my_id := multiplayer.get_unique_id()
	if multiplayer.is_server():
		player_names[my_id] = local_name
		player_characters[my_id] = local_character
		peer_list_changed.emit()
	else:
		# Not connected yet: the connect handler will announce the current pick.
		if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			return
		rpc("_register_profile", my_id, local_name, local_character)


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
		rpc_id(id, "_register_profile", multiplayer.get_unique_id(), local_name, local_character)
		# A client that joins after the host started goes straight into the level.
		if game_started:
			rpc_id(id, "_set_level", current_level)


func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	peer_list_changed.emit()


func _on_connected_to_server() -> void:
	players[1] = true
	peer_list_changed.emit()
	# Announce my name and character to the host, which relays them to everyone else.
	rpc("_register_profile", multiplayer.get_unique_id(), local_name, local_character)
	connection_succeeded.emit()


func _on_connection_failed() -> void:
	close()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	close()
	connection_failed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _register_profile(id: int, player_name: String, character_id: String) -> void:
	var sender_id := multiplayer.get_remote_sender_id()

	if multiplayer.is_server():
		if sender_id != id:
			return
		# The host arbitrates names: whoever arrives with one that is already in
		# use is told, and gets the first free variation of it. This happens
		# before the profile is stored and relayed, so everyone sees one name.
		var unique := _unique_name(player_name, id)
		if unique != player_name:
			player_name = unique
			rpc_id(id, "_name_taken", unique)
	else:
		if sender_id != 1:
			return

	player_names[id] = player_name
	player_characters[id] = character_id
	peer_list_changed.emit()
	# The host relays profiles so every client learns every player's name and pick.
	if multiplayer.is_server():
		for peer_id in multiplayer.get_peers():
			if peer_id != id:
				rpc_id(peer_id, "_register_profile", id, player_name, character_id)


## Host-only: a variation of `wanted` that no other player is using.
func _unique_name(wanted: String, except_id: int) -> String:
	var taken: Array[String] = []
	for peer_id in player_names:
		if peer_id != except_id:
			taken.append(str(player_names[peer_id]).to_lower())
	if not taken.has(wanted.to_lower()):
		return wanted
	var suffix := 2
	while taken.has(("%s %d" % [wanted, suffix]).to_lower()):
		suffix += 1
	return "%s %d" % [wanted, suffix]


@rpc("authority", "call_remote", "reliable")
func _name_taken(new_name: String) -> void:
	local_name = new_name
	name_taken.emit(new_name)


func get_player_name(id: int) -> String:
	return str(player_names.get(id, "Player"))


func get_player_character(id: int) -> String:
	return str(player_characters.get(id, ""))


@rpc("authority", "call_remote", "reliable")
func _set_level(level: int) -> void:
	get_tree().set_meta("level_number", level)
	get_tree().set_meta("online", true)
	get_tree().set_meta("local_coop", false)
	get_tree().change_scene_to_file("res://scenes/main.tscn")
