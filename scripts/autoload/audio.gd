extends Node
## Audio by id (DESIGN.md §16.2). SFX: res://assets/audio/sfx/<id>.ogg|.wav, music:
## res://assets/audio/music/<id>.ogg. Missing files are silent no-ops so placeholder builds run.

const SFX_ROOT := "res://assets/audio/sfx"
const MUSIC_ROOT := "res://assets/audio/music"
const SFX_VOICES := 16

var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _music: AudioStreamPlayer
var _cache: Dictionary = {}


func _ready() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")
	for i in SFX_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_voices.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	Events.settings_changed.connect(apply_volumes)
	apply_volumes()


func play_sfx(id: String, pitch_jitter: float = 0.05) -> void:
	var stream := _find_stream(SFX_ROOT, id)
	if stream == null:
		return
	var p := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % SFX_VOICES
	p.stream = stream
	# Pitch jitter is cosmetic, so it uses the fx stream (allowed to desync).
	p.pitch_scale = 1.0 + RNG.stream("fx").randf_range(-pitch_jitter, pitch_jitter)
	p.play()


func play_music(id: String) -> void:
	var stream := _find_stream(MUSIC_ROOT, id)
	if stream == null or _music.stream == stream:
		return
	_music.stream = stream
	_music.play()


func stop_music() -> void:
	_music.stop()


func apply_volumes() -> void:
	var a: Dictionary = MetaSave.settings.get("audio", {})
	_set_bus_volume("Master", float(a.get("master", 1.0)))
	_set_bus_volume("Music", float(a.get("music", 0.7)))
	_set_bus_volume("SFX", float(a.get("sfx", 0.9)))


func _find_stream(root: String, id: String) -> AudioStream:
	var key := root + "/" + id
	if _cache.has(key):
		return _cache[key]
	var found: AudioStream = null
	for ext in [".ogg", ".wav"]:
		var path: String = key + ext
		if ResourceLoader.exists(path):
			found = load(path)
			break
	_cache[key] = found
	return found


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0, 1.0)))
