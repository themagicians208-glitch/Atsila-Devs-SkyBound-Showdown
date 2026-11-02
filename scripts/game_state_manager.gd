extends Node
## GameStateManager: The Single Source of Truth for the game state.
## Handles synchronization between host and clients.

signal state_changed(new_state: Dictionary)

# The master state object
var state := {
	"current_level": 1,
	"game_status": "LOBBY", # LOBBY, PLAYING, GAME_OVER
	"coins_collected": 0,
	"coin_goal": 0,
	"puzzle_solved": false,
	"active_modifiers": {},
	"player_data": {} # peer_id -> { "score": 0, "checkpoint": 0 }
}

func update_state(key: String, value: Variant) -> void:
	if state.has(key):
		state[key] = value
		if multiplayer.is_server():
			rpc("_sync_state", state)
		state_changed.emit(state)

func set_player_data(peer_id: int, key: String, value: Variant) -> void:
	if not state.player_data.has(peer_id):
		state.player_data[peer_id] = {}

	state.player_data[peer_id][key] = value
	if multiplayer.is_server():
		rpc("_sync_state", state)
	state_changed.emit(state)

@rpc("authority", "call_remote", "reliable")
func _sync_state(new_state: Dictionary) -> void:
	state = new_state
	state_changed.emit(state)
