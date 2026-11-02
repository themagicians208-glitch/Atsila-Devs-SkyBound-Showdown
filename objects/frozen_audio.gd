extends Node
class_name FrozenAudio

@export_enum("ambient", "boss") var mode := "ambient"
@export var volume_db := -30.0

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
	if mode == "ambient":
		start()

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
	var gust := 0.5 + 0.5 * sin(time * 0.35)
	var wind := sin(TAU * 145.0 * time + sin(time * 0.7) * 5.0) * 0.012
	return wind + randf_range(-0.004, 0.004) * (0.5 + gust)
