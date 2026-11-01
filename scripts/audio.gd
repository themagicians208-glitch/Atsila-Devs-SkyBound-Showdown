extends Node

# Code adapted from KidsCanCode

var num_players = 12
var bus = "master"
var music_player: AudioStreamPlayer

var available = []  # The available players.
var queue = []  # The queue of sounds to play.

func _ready():

	music_player = AudioStreamPlayer.new()
	add_child(music_player)
	music_player.volume_db = -14
	music_player.bus = bus

	for i in num_players:
		var p = AudioStreamPlayer.new()
		add_child(p)
		
		available.append(p)
		
		p.volume_db = -10
		p.finished.connect(_on_stream_finished.bind(p))
		p.bus = bus


func _on_stream_finished(stream): available.append(stream)

func play(sound_path): queue.append(sound_path)

func play_music(sound_path: String) -> void:
	if music_player.playing and music_player.stream and music_player.stream.resource_path == sound_path:
		return

	var stream = load(sound_path)
	if stream == null:
		print("Audio Error: Could not load music file at %s" % sound_path)
		return

	music_player.stream = stream
	if music_player.stream is AudioStreamMP3 or music_player.stream is AudioStreamOggVorbis:
		music_player.stream.loop = true
	music_player.play()

func stop_all() -> void:
	queue.clear()
	for child in get_children():
		if child is AudioStreamPlayer:
			child.stop()

func _process(_delta):

	if not queue.is_empty() and not available.is_empty():
		
		available[0].stream = load(queue.pop_front())
		available[0].play()
		available[0].pitch_scale = randf_range(0.9, 1.1)
		
		available.pop_front()
