extends Node3D
class_name RuleShift

## One reusable engine for every "the puzzle changes its rules while you solve it"
## puzzle in Frozen Skies. A puzzle site owns one RuleShift, feeds it progress
## (`note_progress`), and supplies one callable that re-configures the world for
## the current rules (`shifted` false = the rules the player first met, true = the
## corrupted rules). Everything else - the warning, the notices, the save state,
## the reset/retry flow - is shared.
##
## State flow:
##
##   INITIAL_STATE -> (progress reaches trigger_after) -> RULE_CHANGE_WARNING
##                 -> (warning_seconds of visible/audible warning) -> RULE_CHANGED
##                 -> NEW_OBJECTIVE -> COMPLETED
##                                       or FAILED -> RESETTING -> back to
##                                       RULE_CHANGED (rules stay corrupted)
##
## Nothing in here teleports or damages the player, so a rule change can never
## trap them: the level only ever re-configures platforms, crystals and switches.

enum State {
	INITIAL_STATE,
	RULE_CHANGE_WARNING,
	RULE_CHANGED,
	NEW_OBJECTIVE,
	COMPLETED,
	FAILED,
	RESETTING,
}

const STATE_NAMES := [
	"INITIAL_STATE", "RULE_CHANGE_WARNING", "RULE_CHANGED",
	"NEW_OBJECTIVE", "COMPLETED", "FAILED", "RESETTING",
]

## What the player is told, and when. Tone is "warning", "changed", "objective",
## "complete" or "fail" - the HUD colours each one differently.
signal notice(text: String, tone: String)
signal state_changed(state: int, puzzle_name: String)
signal progress_changed(done: int, total: int, puzzle_name: String)
## Fired the moment the world switches rules, so tests and the level can react.
signal rules_changed(shifted: bool, puzzle_name: String)
signal warning_started(puzzle_name: String)
signal completed(puzzle_name: String)
signal failed(reason: String, puzzle_name: String)

@export var puzzle_id := ""
@export var puzzle_name := ""
## Shown when the player first reaches the site: "the rules as you find them".
@export var initial_objective := ""
## Shown when the corrupted rules take over.
@export var new_objective := ""
@export var steps_total := 3
## Progress count that triggers the rule change (2 = "after the second switch").
@export var trigger_after := 2
## An advanced puzzle changes its rules more than once: one trigger per change.
@export var shift_triggers: Array[int] = []
@export var warning_seconds := 2.4
## Text shown when the rules change; per-puzzle so each one reads its own way.
@export var change_headline := "NEW PUZZLE RULES!"
@export var change_detail := ""
@export var persist := true

var state: int = State.INITIAL_STATE
var steps_done := 0
## 0 = the rules the player first met; 1, 2, ... after each rule change.
var stage := 0
var shifted := false
var finished := false
var fail_count := 0
var introduced := false

var _warning_left := 0.0
var _apply_rules: Callable = Callable()
var _time := 0.0
var _beacon: MeshInstance3D
var _beacon_material: StandardMaterial3D
var _beacon_left := 0.0
var _headlines: Array[String] = []
var _details: Array[String] = []
var _objectives: Array[String] = []


func configure(
		id: String,
		display_name: String,
		total_steps: int,
		triggers: Variant,
		apply_rules: Callable,
		headline := "NEW PUZZLE RULES!",
		detail := "ADAPT TO THE NEW PATH!",
		warning_secs := 2.4,
		save_it := true) -> void:
	puzzle_id = id
	puzzle_name = display_name
	steps_total = maxi(1, total_steps)
	shift_triggers.clear()
	if triggers is Array:
		for value in (triggers as Array):
			shift_triggers.append(int(value))
	else:
		shift_triggers.append(int(triggers))
	for index in shift_triggers.size():
		shift_triggers[index] = clampi(shift_triggers[index], 1, steps_total)
	trigger_after = shift_triggers[0]
	_apply_rules = apply_rules
	change_headline = headline
	change_detail = detail
	_headlines = [headline]
	_details = [detail]
	_objectives = [""]
	warning_seconds = warning_secs
	persist = save_it
	_build_beacon()


## Register the words for a later rule change (stage index 1 = the second change).
func add_stage_text(index: int, headline: String, detail: String, objective: String) -> void:
	while _headlines.size() <= index:
		_headlines.append("NEW PUZZLE RULES!")
		_details.append("ADAPT TO THE NEW PATH!")
		_objectives.append("")
	_headlines[index] = headline
	_details[index] = detail
	_objectives[index] = objective


## How many rule changes this puzzle has in total.
func total_stages() -> int:
	return _headlines.size()


## The progress count that fires the next rule change, or -1 when there is none.
func next_trigger() -> int:
	if stage >= shift_triggers.size():
		return -1
	return shift_triggers[stage]


## The rules the player meets, stated once, when they first reach the site.
func introduce() -> void:
	if introduced or initial_objective.is_empty():
		return
	introduced = true
	notice.emit("%s: %s" % [puzzle_name, initial_objective], "objective")


func _build_beacon() -> void:
	# A ring of light over the puzzle site: the visible half of the warning.
	_beacon = MeshInstance3D.new()
	_beacon.name = "RuleShiftBeacon"
	var ring := TorusMesh.new()
	ring.inner_radius = 1.5
	ring.outer_radius = 1.68
	_beacon.mesh = ring
	_beacon.position.y = 2.6
	_beacon_material = StandardMaterial3D.new()
	_beacon_material.albedo_color = Color("#ffd166")
	_beacon_material.emission_enabled = true
	_beacon_material.emission = Color("#ffb347")
	_beacon_material.emission_energy_multiplier = 1.6
	_beacon.material_override = _beacon_material
	_beacon.visible = false
	add_child(_beacon)


func _process(delta: float) -> void:
	_time += delta
	if _beacon_left > 0.0:
		_beacon_left = maxf(0.0, _beacon_left - delta)
		if _beacon != null:
			_beacon.rotate_y(delta * 2.6)
			var pulse := 1.0 + sin(_time * 9.0) * 0.12
			_beacon.scale = Vector3.ONE * pulse
			if _beacon_left <= 0.0:
				_beacon.visible = false
	if state != State.RULE_CHANGE_WARNING:
		return
	_warning_left = maxf(0.0, _warning_left - delta)
	if _warning_left <= 0.0:
		_apply_shift()


## One more step of the puzzle solved. The rule change fires exactly once.
func note_progress(_step_label := "") -> void:
	if finished:
		return
	steps_done += 1
	progress_changed.emit(steps_done, steps_total, puzzle_name)
	if steps_done >= steps_total:
		complete()
	elif stage < shift_triggers.size() and steps_done >= shift_triggers[stage]:
		request_rule_change()


## Begin the visible/audible warning window. Nothing changes until it ends.
func request_rule_change() -> void:
	if finished or state == State.RULE_CHANGE_WARNING:
		return
	if stage >= shift_triggers.size():
		return
	state = State.RULE_CHANGE_WARNING
	_warning_left = warning_seconds
	_show_beacon(warning_seconds + 1.4)
	notice.emit("WARNING: THE ICE IS SHIFTING!", "warning")
	notice.emit("Puzzle rules are changing...", "warning")
	state_changed.emit(state, puzzle_name)
	warning_started.emit(puzzle_name)
	Audio.play("res://sounds/break.ogg")
	FrozenAudio.cue(self, "warning", warning_seconds + 0.4, -14.0)


## Apply the next set of rules now, skipping the warning (restore, tools, tests).
func force_rule_change() -> void:
	if finished or stage >= shift_triggers.size():
		return
	_warning_left = 0.0
	_show_beacon(1.6)
	_apply_shift()


func _apply_shift() -> void:
	stage += 1
	shifted = stage > 0
	state = State.RULE_CHANGED
	_call_apply_rules()
	if _beacon != null:
		_beacon_material.albedo_color = Color("#7ce7ff")
		_beacon_material.emission = Color("#38cfff")
	Audio.play("res://sounds/coin.ogg")
	FrozenAudio.cue(self, "shift", 1.4, -12.0)
	var index := stage - 1
	if index < _headlines.size() and not _headlines[index].is_empty():
		notice.emit(_headlines[index], "changed")
	if index < _details.size() and not _details[index].is_empty():
		notice.emit(_details[index], "changed")
	state_changed.emit(state, puzzle_name)
	rules_changed.emit(true, puzzle_name)
	save_state()
	state = State.NEW_OBJECTIVE
	state_changed.emit(state, puzzle_name)
	var objective := new_objective
	if index < _objectives.size() and not _objectives[index].is_empty():
		objective = _objectives[index]
	if not objective.is_empty():
		notice.emit(objective, "objective")


func complete() -> void:
	if finished:
		return
	finished = true
	steps_done = steps_total
	state = State.COMPLETED
	_show_beacon(1.2)
	Audio.play("res://sounds/coin.ogg")
	notice.emit("%s COMPLETE" % puzzle_name, "complete")
	state_changed.emit(state, puzzle_name)
	completed.emit(puzzle_name)
	save_state()


## The player broke a rule: buzz, then hand them the puzzle back.
func fail(reason := "") -> void:
	if finished:
		return
	fail_count += 1
	state = State.FAILED
	if not reason.is_empty():
		notice.emit(reason, "fail")
	failed.emit(reason, puzzle_name)
	state_changed.emit(state, puzzle_name)
	Audio.play("res://sounds/fall.ogg")
	reset()


## Back to the start of the puzzle. Whatever rules are in force stay in force, and
## the progress the player had made when those rules began is kept, so a retry
## never undoes a rule change they already adapted to.
func reset(keep_shift := true) -> void:
	if finished:
		return
	state = State.RESETTING
	state_changed.emit(state, puzzle_name)
	var kept := 0
	if stage > 0 and keep_shift:
		kept = shift_triggers[clampi(stage - 1, 0, shift_triggers.size() - 1)]
	steps_done = clampi(kept, 0, steps_total)
	if not keep_shift:
		shifted = false
		stage = 0
	_call_apply_rules()
	state = State.RULE_CHANGED if shifted else State.INITIAL_STATE
	progress_changed.emit(steps_done, steps_total, puzzle_name)
	notice.emit("%s RESET - try again" % puzzle_name, "fail")
	state_changed.emit(state, puzzle_name)
	save_state()


func is_complete() -> bool:
	return finished


func state_name() -> String:
	return STATE_NAMES[clampi(state, 0, STATE_NAMES.size() - 1)]


func summary() -> Dictionary:
	return {
		"done": finished,
		"shifted": shifted,
		"stage": stage,
		"steps": steps_done,
		"fails": fail_count,
		"state": state,
	}


## Re-apply the rules for the saved state, without replaying the announcement.
func restore() -> void:
	if not persist or puzzle_id.is_empty():
		return
	var saved: Dictionary = Progress.frozen_rule_state(puzzle_id)
	if saved.is_empty():
		return
	finished = bool(saved.get("done", false))
	stage = int(saved.get("stage", 1 if bool(saved.get("shifted", false)) else 0))
	shifted = stage > 0
	steps_done = int(saved.get("steps", 0))
	fail_count = int(saved.get("fails", 0))
	_call_apply_rules()
	if finished:
		state = State.COMPLETED
		steps_done = steps_total
	elif shifted:
		state = State.NEW_OBJECTIVE
	else:
		state = State.INITIAL_STATE


func save_state() -> void:
	if not persist or puzzle_id.is_empty():
		return
	Progress.set_frozen_rule_state(puzzle_id, summary())


## The puzzle's own callable is told which set of rules to install.
func _call_apply_rules() -> void:
	if _apply_rules.is_valid():
		_apply_rules.call(stage)


func _show_beacon(duration: float) -> void:
	if _beacon == null:
		return
	_beacon_left = duration
	_beacon.visible = true