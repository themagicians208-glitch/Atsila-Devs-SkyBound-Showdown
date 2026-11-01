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


func _ready() -> void:
	load_progress()


func load_progress() -> void:
	var config := ConfigFile.new()
	if config.load(config_path) != OK:
		return
	fragment_recovered = bool(config.get_value("island", "fragment_recovered", false))


func save_progress() -> void:
	var config := ConfigFile.new()
	config.set_value("island", "fragment_recovered", fragment_recovered)
	config.save(config_path)


## The First Fragment is out of the chest. Called once, by the chest itself.
func recover_fragment() -> void:
	if fragment_recovered:
		return
	fragment_recovered = true
	save_progress()


## Forget everything. Only the dev checks call this.
func clear() -> void:
	fragment_recovered = false
	save_progress()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(config_path))