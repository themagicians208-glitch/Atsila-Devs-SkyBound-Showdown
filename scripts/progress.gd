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
var third_fragment_recovered := false
var ice_shield_unlocked := false
var frost_dash_unlocked := false
var crystal_activation_unlocked := false
var frozen_seals_activated := 0


func _ready() -> void:
	load_progress()


func load_progress() -> void:
	var config := ConfigFile.new()
	if config.load(config_path) != OK:
		return
	fragment_recovered = bool(config.get_value("island", "fragment_recovered", false))
	third_fragment_recovered = bool(config.get_value("frozen_skies", "third_fragment_recovered", false))
	ice_shield_unlocked = bool(config.get_value("frozen_skies", "ice_shield_unlocked", false))
	frost_dash_unlocked = bool(config.get_value("frozen_skies", "frost_dash_unlocked", false))
	crystal_activation_unlocked = bool(config.get_value("frozen_skies", "crystal_activation_unlocked", false))
	frozen_seals_activated = int(config.get_value("frozen_skies", "frozen_seals_activated", 0))


func save_progress() -> void:
	var config := ConfigFile.new()
	config.set_value("island", "fragment_recovered", fragment_recovered)
	config.set_value("frozen_skies", "third_fragment_recovered", third_fragment_recovered)
	config.set_value("frozen_skies", "ice_shield_unlocked", ice_shield_unlocked)
	config.set_value("frozen_skies", "frost_dash_unlocked", frost_dash_unlocked)
	config.set_value("frozen_skies", "crystal_activation_unlocked", crystal_activation_unlocked)
	config.set_value("frozen_skies", "frozen_seals_activated", frozen_seals_activated)
	config.save(config_path)


## The First Fragment is out of the chest. Called once, by the chest itself.
func recover_fragment() -> void:
	if fragment_recovered:
		return
	fragment_recovered = true
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


## Forget everything. Only the dev checks call this.
func clear() -> void:
	fragment_recovered = false
	third_fragment_recovered = false
	ice_shield_unlocked = false
	frost_dash_unlocked = false
	crystal_activation_unlocked = false
	frozen_seals_activated = 0
	save_progress()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(config_path))
