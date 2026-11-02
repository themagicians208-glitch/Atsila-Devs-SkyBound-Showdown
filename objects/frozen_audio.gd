extends Node
class_name FrozenAudio

@export_enum("ambient", "boss", "warning", "shift", "reset", "crack") var mode := "ambient"
@export var volume_db := -30.0
## A one-shot cue frees itself after [member duration] and is never looped.
@export var one_shot := false
@export var duration := 1.4

var _player: AudioStreamPlayer
var _sample_time := 0.0
const MIX_RATE := 44100.0

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = MIX_RATE
	stream.buffer_length = 0.5
	_player.stream = stream
	_player.volume_db = volume_db
	var audio := get_node_or_null("/root/Audio")
	if audio != null and audio.get("bus") != null:
		_player.bus = str(audio.get("bus"))
	add_child(_player)
	if mode == "ambient" or one_shot:
		start()


## Play a short procedural cue (a rule-change stinger, an ice crack) and return
## the node that owns it, so callers can keep or ignore it.
static func cue(parent: Node, cue_mode: String, cue_duration := 1.4, cue_volume_db := -12.0) -> FrozenAudio:
	var audio := FrozenAudio.new()
	audio.name = "FrozenCue_%s" % cue_mode
	audio.mode = cue_mode
	audio.one_shot = true
	audio.duration = cue_duration
	audio.volume_db = cue_volume_db
	if parent != null and parent.is_inside_tree():
		parent.add_child(audio)
	elif parent != null:
		parent.add_child(audio)
	audio.start()
	return audio

func start() -> void:
	if _player != null and not _player.playing:
		_player.play()

func stop() -> void:
	if _player != null:
		_player.stop()

func is_playing() -> bool:
	return _player != null and _player.playing

func _process(_delta: float) -> void:
	if not is_playing():
		return
	if one_shot and _sample_time >= duration:
		stop()
		queue_free()
		return
	var playback := _player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var frames := mini(playback.get_frames_available(), 2048)
	for _index in frames:
		var sample := _sample(_sample_time)
		playback.push_frame(Vector2(sample, sample))
		_sample_time += 1.0 / MIX_RATE

func _sample(time: float) -> float:
	if mode == "boss":
		var beat := floorf(time * 2.0)
		var notes := [55.0, 65.4, 73.4, 49.0]
		var frequency: float = notes[int(beat) % notes.size()]
		var envelope := exp(-fmod(time, 0.5) * 4.0)
		return (sin(TAU * frequency * time) * 0.028 + sin(TAU * frequency * 2.0 * time) * 0.009) * envelope
	if mode == "warning":
		# Two-tone alarm: the audible half of "the rules are about to change".
		var pulse := fmod(time, 0.36)
		if pulse > 0.22:
			return 0.0
		var tone := 720.0 if pulse < 0.11 else 540.0
		return sin(TAU * tone * time) * 0.09 * exp(-pulse * 5.0)
	if mode == "shift":
		# A rising sweep with a bell on top: reality re-knitting itself.
		var progress := clampf(time / maxf(0.2, duration), 0.0, 1.0)
		var sweep := 240.0 + progress * 720.0
		var fade := 1.0 - progress
		return (sin(TAU * sweep * time) * 0.075 + sin(TAU * sweep * 2.02 * time) * 0.03) * maxf(0.0, fade)
	if mode == "reset":
		var fall := clampf(time / maxf(0.2, duration), 0.0, 1.0)
		var drop := 520.0 - fall * 400.0
		return sin(TAU * drop * time) * 0.07 * (1.0 - fall)
	if mode == "crack":
		# Ice cracking: a noise burst that dies away fast.
		var decay := exp(-time * 9.0)
		return randf_range(-1.0, 1.0) * 0.05 * decay + sin(TAU * 1400.0 * time) * 0.02 * decay
	var gust := 0.5 + 0.5 * sin(time * 0.35)
	var wind := sin(TAU * 145.0 * time + sin(time * 0.7) * 5.0) * 0.012
	return wind + randf_range(-0.004, 0.004) * (0.5 + gust)
