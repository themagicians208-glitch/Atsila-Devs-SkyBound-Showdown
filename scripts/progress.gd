extends Node

## Saved progression, in user://progress.cfg. Small on purpose: this game keeps
## what a player has achieved, not where they were standing.
##
##   * the First Fragment - once it is out of the Forgotten Island's chest, it
##     stays recovered, and the island's chest is already open when it is
##     revisited.
##
## [member config_path] can be pointed elsewhere, which the dev checks do so they
## never touch a real player's save file.

const CONFIG_PATH := "user://progress.cfg"

var config_path := CONFIG_PATH
var fragment_recovered := false
var second_fragment_recovered := false
var third_fragment_recovered := false
var ice_shield_unlocked := false
var frost_dash_unlocked := false
var crystal_activation_unlocked := false
var frozen_seals_activated := 0
var frozen_coin_ids: Array[String] = []
var frost_titan_defeated := false
var crystal_light_solved := false
var frozen_generators_activated := 0
var frozen_crystal_blocks_aligned := false
var frozen_checkpoint_index := 0
## Rule-changing puzzle state, one entry per puzzle id: {done, shifted, steps, fails}.
## Frozen Skies' puzzles change their rules mid-solve, so what has to survive a
## reload is not just "solved" but which set of rules the puzzle is running.
var frozen_rule_states: Dictionary = {}
var rescued_creatures: Dictionary = {}
var woods_coins_best := 0

# Level 4: Ember Heights progression
var fourth_fragment_recovered := false
var malakar_fortress_discovered := false
var magical_shield_unlocked := false
var ember_switch_solved := false
var ember_crystals_activated := 0
var ember_machines_activated := 0
var ember_rising_lava_solved := false
var ember_fortress_solved := false
var ember_seals_activated := 0
var ember_dragon_defeated := false
var ember_coin_ids: Array[String] = []
var ember_checkpoint_index := 0


func _ready() -> void:
	load_progress()


func load_progress() -> void:
	var config := ConfigFile.new()
	if config.load(config_path) != OK:
		return
	fragment_recovered = bool(config.get_value("island", "fragment_recovered", false))
	second_fragment_recovered = bool(config.get_value("woods", "second_fragment_recovered", config.get_value("progression", "second_fragment_recovered", false)))
	var saved_creatures: Variant = config.get_value("woods", "rescued_creatures", {})
	if saved_creatures is Dictionary:
		rescued_creatures = (saved_creatures as Dictionary).duplicate()
	else:
		rescued_creatures = {}
	woods_coins_best = int(config.get_value("woods", "coins_best", 0))
	third_fragment_recovered = bool(config.get_value("frozen_skies", "third_fragment_recovered", false))
	ice_shield_unlocked = bool(config.get_value("frozen_skies", "ice_shield_unlocked", false))
	frost_dash_unlocked = bool(config.get_value("frozen_skies", "frost_dash_unlocked", false))
	crystal_activation_unlocked = bool(config.get_value("frozen_skies", "crystal_activation_unlocked", false))
	frozen_seals_activated = int(config.get_value("frozen_skies", "frozen_seals_activated", 0))
	frozen_coin_ids.clear()
	for coin_id in config.get_value("frozen_skies", "frozen_coin_ids", PackedStringArray()):
		frozen_coin_ids.append(str(coin_id))
	frost_titan_defeated = bool(config.get_value("frozen_skies", "frost_titan_defeated", false))
	crystal_light_solved = bool(config.get_value("frozen_skies", "crystal_light_solved", false))
	frozen_generators_activated = int(config.get_value("frozen_skies", "frozen_generators_activated", 0))
	frozen_crystal_blocks_aligned = bool(config.get_value("frozen_skies", "frozen_crystal_blocks_aligned", false))
	frozen_checkpoint_index = int(config.get_value("frozen_skies", "frozen_checkpoint_index", 0))
	frozen_rule_states.clear()
	if config.has_section("frozen_rules"):
		for key in config.get_section_keys("frozen_rules"):
			var value: Variant = config.get_value("frozen_rules", key, {})
			if value is Dictionary:
				frozen_rule_states[str(key)] = (value as Dictionary).duplicate()
	fourth_fragment_recovered = bool(config.get_value("ember_heights", "fourth_fragment_recovered", false))
	malakar_fortress_discovered = bool(config.get_value("ember_heights", "malakar_fortress_discovered", false))
	magical_shield_unlocked = bool(config.get_value("ember_heights", "magical_shield_unlocked", false))
	ember_switch_solved = bool(config.get_value("ember_heights", "ember_switch_solved", false))
	ember_crystals_activated = int(config.get_value("ember_heights", "ember_crystals_activated", 0))
	ember_machines_activated = int(config.get_value("ember_heights", "ember_machines_activated", 0))
	ember_rising_lava_solved = bool(config.get_value("ember_heights", "ember_rising_lava_solved", false))
	ember_fortress_solved = bool(config.get_value("ember_heights", "ember_fortress_solved", false))
	ember_seals_activated = int(config.get_value("ember_heights", "ember_seals_activated", 0))
	ember_dragon_defeated = bool(config.get_value("ember_heights", "ember_dragon_defeated", false))
	ember_coin_ids.clear()
	for coin_id in config.get_value("ember_heights", "ember_coin_ids", PackedStringArray()):
		ember_coin_ids.append(str(coin_id))
	ember_checkpoint_index = int(config.get_value("ember_heights", "ember_checkpoint_index", 0))


func save_progress() -> void:
	var config := ConfigFile.new()
	config.set_value("island", "fragment_recovered", fragment_recovered)
	config.set_value("progression", "second_fragment_recovered", second_fragment_recovered)
	config.set_value("woods", "second_fragment_recovered", second_fragment_recovered)
	config.set_value("woods", "rescued_creatures", rescued_creatures)
	config.set_value("woods", "coins_best", woods_coins_best)
	config.set_value("frozen_skies", "third_fragment_recovered", third_fragment_recovered)
	config.set_value("frozen_skies", "ice_shield_unlocked", ice_shield_unlocked)
	config.set_value("frozen_skies", "frost_dash_unlocked", frost_dash_unlocked)
	config.set_value("frozen_skies", "crystal_activation_unlocked", crystal_activation_unlocked)
	config.set_value("frozen_skies", "frozen_seals_activated", frozen_seals_activated)
	config.set_value("frozen_skies", "frozen_coin_ids", PackedStringArray(frozen_coin_ids))
	config.set_value("frozen_skies", "frost_titan_defeated", frost_titan_defeated)
	config.set_value("frozen_skies", "crystal_light_solved", crystal_light_solved)
	config.set_value("frozen_skies", "frozen_generators_activated", frozen_generators_activated)
	config.set_value("frozen_skies", "frozen_crystal_blocks_aligned", frozen_crystal_blocks_aligned)
	config.set_value("frozen_skies", "frozen_checkpoint_index", frozen_checkpoint_index)
	for rule_id in frozen_rule_states.keys():
		config.set_value("frozen_rules", str(rule_id), frozen_rule_states[rule_id])
	config.set_value("ember_heights", "fourth_fragment_recovered", fourth_fragment_recovered)
	config.set_value("ember_heights", "malakar_fortress_discovered", malakar_fortress_discovered)
	config.set_value("ember_heights", "magical_shield_unlocked", magical_shield_unlocked)
	config.set_value("ember_heights", "ember_switch_solved", ember_switch_solved)
	config.set_value("ember_heights", "ember_crystals_activated", ember_crystals_activated)
	config.set_value("ember_heights", "ember_machines_activated", ember_machines_activated)
	config.set_value("ember_heights", "ember_rising_lava_solved", ember_rising_lava_solved)
	config.set_value("ember_heights", "ember_fortress_solved", ember_fortress_solved)
	config.set_value("ember_heights", "ember_seals_activated", ember_seals_activated)
	config.set_value("ember_heights", "ember_dragon_defeated", ember_dragon_defeated)
	config.set_value("ember_heights", "ember_coin_ids", PackedStringArray(ember_coin_ids))
	config.set_value("ember_heights", "ember_checkpoint_index", ember_checkpoint_index)
	config.save(config_path)


## The First Fragment is out of the chest. Called once, by the chest itself.
func recover_fragment() -> void:
	if fragment_recovered:
		return
	fragment_recovered = true
	save_progress()

func recover_second_fragment() -> void:
	if second_fragment_recovered:
		return
	second_fragment_recovered = true
	save_progress()

func record_creature_rescued(creature_id: String) -> void:
	if creature_id.is_empty():
		return
	rescued_creatures[creature_id] = true
	save_progress()

func is_creature_rescued(creature_id: String) -> bool:
	return bool(rescued_creatures.get(creature_id, false))

func rescued_count() -> int:
	return rescued_creatures.size()

func record_woods_coins(amount: int) -> void:
	if amount > woods_coins_best:
		woods_coins_best = amount
		save_progress()

func recover_third_fragment() -> void:
	if third_fragment_recovered:
		return
	third_fragment_recovered = true
	save_progress()

func unlock_ice_shield() -> void:
	ice_shield_unlocked = true
	save_progress()

func unlock_frost_dash() -> void:
	frost_dash_unlocked = true
	save_progress()

func unlock_crystal_activation() -> void:
	crystal_activation_unlocked = true
	save_progress()

func set_frozen_seals_activated(value: int) -> void:
	frozen_seals_activated = clampi(value, 0, 3)
	save_progress()


func set_frozen_rule_state(rule_id: String, state: Dictionary) -> void:
	if rule_id.is_empty():
		return
	frozen_rule_states[rule_id] = state.duplicate()
	save_progress()


func frozen_rule_state(rule_id: String) -> Dictionary:
	var value: Variant = frozen_rule_states.get(rule_id, {})
	if value is Dictionary:
		return value as Dictionary
	return {}


func frozen_rule_done(rule_id: String) -> bool:
	return bool(frozen_rule_state(rule_id).get("done", false))


func frozen_rule_shifted(rule_id: String) -> bool:
	return bool(frozen_rule_state(rule_id).get("shifted", false))


## How many rule-changing puzzles are finished, for the HUD's puzzle counter.
func frozen_rules_completed() -> int:
	var count := 0
	for rule_id in frozen_rule_states.keys():
		if bool((frozen_rule_states[rule_id] as Dictionary).get("done", false)):
			count += 1
	return count

func has_frozen_coin(coin_id: String) -> bool:
	return coin_id in frozen_coin_ids

func collect_frozen_coin(coin_id: String) -> void:
	if coin_id.is_empty() or has_frozen_coin(coin_id):
		return
	frozen_coin_ids.append(coin_id)
	save_progress()

func frozen_coins_collected() -> int:
	return frozen_coin_ids.size()

func mark_frost_titan_defeated() -> void:
	frost_titan_defeated = true
	save_progress()

func mark_crystal_light_solved() -> void:
	crystal_light_solved = true
	save_progress()

func set_frozen_generators_activated(value: int) -> void:
	frozen_generators_activated = clampi(value, 0, 3)
	save_progress()

func set_frozen_crystal_blocks_aligned(value: bool) -> void:
	frozen_crystal_blocks_aligned = value
	save_progress()

func set_frozen_checkpoint(index: int) -> void:
	frozen_checkpoint_index = maxi(0, index)
	save_progress()


# --- Level 4: Ember Heights helper methods -----------------------------------

func recover_fourth_fragment() -> void:
	if fourth_fragment_recovered:
		return
	fourth_fragment_recovered = true
	save_progress()

func discover_malakar_fortress() -> void:
	if malakar_fortress_discovered:
		return
	malakar_fortress_discovered = true
	save_progress()

func unlock_magical_shield() -> void:
	if magical_shield_unlocked:
		return
	magical_shield_unlocked = true
	save_progress()

func mark_ember_switch_solved() -> void:
	ember_switch_solved = true
	save_progress()

func set_ember_crystals_activated(value: int) -> void:
	ember_crystals_activated = clampi(value, 0, 3)
	save_progress()

func set_ember_machines_activated(value: int) -> void:
	ember_machines_activated = clampi(value, 0, 3)
	save_progress()

func mark_ember_rising_lava_solved() -> void:
	ember_rising_lava_solved = true
	save_progress()

func mark_ember_fortress_solved() -> void:
	ember_fortress_solved = true
	save_progress()

func set_ember_seals_activated(value: int) -> void:
	ember_seals_activated = clampi(value, 0, 4)
	save_progress()

func mark_ember_dragon_defeated() -> void:
	ember_dragon_defeated = true
	save_progress()

func has_ember_coin(coin_id: String) -> bool:
	return coin_id in ember_coin_ids

func collect_ember_coin(coin_id: String) -> void:
	if coin_id.is_empty() or has_ember_coin(coin_id):
		return
	ember_coin_ids.append(coin_id)
	save_progress()

func ember_coins_collected() -> int:
	return ember_coin_ids.size()

func set_ember_checkpoint(index: int) -> void:
	ember_checkpoint_index = maxi(0, index)
	save_progress()


## Forget everything. Only the dev checks call this.
func clear() -> void:
	fragment_recovered = false
	second_fragment_recovered = false
	third_fragment_recovered = false
	ice_shield_unlocked = false
	frost_dash_unlocked = false
	crystal_activation_unlocked = false
	frozen_seals_activated = 0
	frozen_coin_ids.clear()
	frost_titan_defeated = false
	crystal_light_solved = false
	frozen_generators_activated = 0
	frozen_crystal_blocks_aligned = false
	frozen_checkpoint_index = 0
	frozen_rule_states.clear()
	rescued_creatures.clear()
	woods_coins_best = 0
	fourth_fragment_recovered = false
	malakar_fortress_discovered = false
	magical_shield_unlocked = false
	ember_switch_solved = false
	ember_crystals_activated = 0
	ember_machines_activated = 0
	ember_rising_lava_solved = false
	ember_fortress_solved = false
	ember_seals_activated = 0
	ember_dragon_defeated = false
	ember_coin_ids.clear()
	ember_checkpoint_index = 0
	save_progress()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(config_path))
