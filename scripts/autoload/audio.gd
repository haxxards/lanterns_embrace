extends Node
## Minimal drop-in audio. Sounds are named in data/audio/audio.json; game code
## only ever asks for a name ("coins", "door_open"), so replacing a sound
## means replacing a file. Missing files are skipped with one warning.
##
## Three buses (created here if the project has none): Music, SFX and
## Ambience, with volumes from game_config.json. One music track and one
## ambience loop play at a time and crossfade when the map changes.

const CONFIG_PATH := "res://data/audio/audio.json"
const SFX_VOICES := 8
const FADE_TIME := 1.5

var current_music: String = ""
var current_ambience: String = ""

var _sfx: Dictionary = {}       # id -> Array of paths (one is picked at random)
var _music: Dictionary = {}     # id -> path
var _ambience: Dictionary = {}  # id -> path
var _streams: Dictionary = {}   # path -> AudioStream
var _warned: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _music_player: AudioStreamPlayer
var _ambience_player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # menus click while paused
	for bus in ["Music", "SFX", "Ambience"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	for bus in GameConfig.audio_volume_db:
		var i := AudioServer.get_bus_index(str(bus))
		if i >= 0:
			AudioServer.set_bus_volume_db(i, float(GameConfig.audio_volume_db[bus]))
	for i in SFX_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_voices.append(p)
	_music_player = _make_loop_player("Music")
	_ambience_player = _make_loop_player("Ambience")
	reload()


func reload() -> void:
	var d: Variant = JsonUtil.load_json(CONFIG_PATH)
	if not d is Dictionary:
		return
	_sfx.clear()
	var sfx: Dictionary = d.get("sfx", {})
	for id in sfx:
		_sfx[id] = sfx[id] if sfx[id] is Array else [sfx[id]]
	_music = d.get("music", {})
	_ambience = d.get("ambience", {})


func has_sound(id: String) -> bool:
	return _sfx.has(id)


## Plays a one-shot sound effect by name (with a little pitch variation).
func play_sfx(id: String) -> void:
	var paths: Array = _sfx.get(id, [])
	if paths.is_empty():
		_warn_once(id, "Audio: no sound named '%s' in %s" % [id, CONFIG_PATH])
		return
	var stream := _stream(str(paths.pick_random()))
	if stream == null:
		return
	var p := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	p.stream = stream
	p.pitch_scale = randf_range(0.96, 1.04)
	p.play()


## Crossfades to a music track ("" stops the music).
func play_music(id: String) -> void:
	if id == current_music:
		return
	current_music = id
	_crossfade(_music_player, _music.get(id, ""), id)


## Crossfades to an ambience loop ("" stops it).
func play_ambience(id: String) -> void:
	if id == current_ambience:
		return
	current_ambience = id
	_crossfade(_ambience_player, _ambience.get(id, ""), id)


func _crossfade(player: AudioStreamPlayer, path: String, id: String) -> void:
	var stream: AudioStream = null
	if not id.is_empty():
		if path.is_empty():
			_warn_once(id, "Audio: no music or ambience named '%s'" % id)
		else:
			stream = _stream(path)
	var tw := create_tween()
	if player.playing:
		tw.tween_property(player, "volume_db", -40.0, FADE_TIME * 0.5)
	tw.tween_callback(_swap_stream.bind(player, stream))
	if stream != null:
		tw.tween_property(player, "volume_db", 0.0, FADE_TIME)


func _swap_stream(player: AudioStreamPlayer, stream: AudioStream) -> void:
	player.stop()
	player.stream = stream
	if stream != null:
		_set_loop(stream)
		player.volume_db = -40.0
		player.play()


func _make_loop_player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func _set_loop(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(stream as AudioStreamWAV).loop_end = int((stream as AudioStreamWAV).get_length() * (stream as AudioStreamWAV).mix_rate)


## Loads an imported stream (res://) or an .ogg file from anywhere.
func _stream(path: String) -> AudioStream:
	if _streams.has(path):
		return _streams[path]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path) as AudioStream
	elif FileAccess.file_exists(path) and path.get_extension().to_lower() == "ogg":
		s = AudioStreamOggVorbis.load_from_file(path)
	if s == null:
		_warn_once(path, "Audio: file not found: %s" % path)
	_streams[path] = s
	return s


func _warn_once(key: String, text: String) -> void:
	if not _warned.has(key):
		_warned[key] = true
		push_warning(text)
