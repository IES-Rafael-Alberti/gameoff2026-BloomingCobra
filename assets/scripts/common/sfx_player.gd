class_name SfxPlayer
extends Node2D

## Base audio helper. Typed subclasses expose named stream fields for designers.
## (G) = room-global AudioStreamPlayer · (P) = proximity AudioStreamPlayer2D

@export_group("Proximity")
## World-pixel radius. Keep larger than a room viewport (~480 with zoom 4).
@export var proximity_max_distance: float = 720.0
@export_range(0.0, 4.0, 0.05) var proximity_attenuation: float = 1.0

@export_group("Playback")
@export_range(1, 8) var polyphony: int = 4
@export var bus: StringName = &"Master"

var _global_voices: Array[AudioStreamPlayer] = []
var _proximity_voices: Array[AudioStreamPlayer2D] = []
var _next_global: int = 0
var _next_proximity: int = 0
var _standard: AudioStreamPlayer2D
var _standard_source: AudioStream
var _last_played_sec: Dictionary = {} # StringName -> float


func _ready() -> void:
	_ensure_voices()
	_standard = AudioStreamPlayer2D.new()
	_standard.name = "StandardLoop"
	_standard.bus = String(bus)
	_standard.max_polyphony = 1
	_apply_proximity(_standard)
	_standard.finished.connect(_on_standard_finished)
	add_child(_standard)


func play_global(stream: AudioStream, key: StringName = &"", min_interval: float = 0.0) -> bool:
	if stream == null or not _interval_ok(key, min_interval):
		return false
	_ensure_voices()
	var voice := _global_voices[_next_global]
	_next_global = (_next_global + 1) % _global_voices.size()
	_configure_and_play(voice, stream)
	return true


func play_proximity(stream: AudioStream, key: StringName = &"", min_interval: float = 0.0) -> bool:
	if stream == null or not _interval_ok(key, min_interval):
		return false
	_ensure_voices()
	var voice := _proximity_voices[_next_proximity]
	_next_proximity = (_next_proximity + 1) % _proximity_voices.size()
	_apply_proximity(voice)
	_configure_and_play(voice, stream)
	return true


func play_global_random(streams: Array[AudioStream], key: StringName = &"", min_interval: float = 0.0) -> bool:
	var pick := _pick_stream(streams)
	if pick == null:
		return false
	return play_global(pick, key, min_interval)


func play_proximity_random(streams: Array[AudioStream], key: StringName = &"", min_interval: float = 0.0) -> bool:
	var pick := _pick_stream(streams)
	if pick == null:
		return false
	return play_proximity(pick, key, min_interval)


func _pick_stream(streams: Array[AudioStream]) -> AudioStream:
	var options: Array[AudioStream] = []
	for stream in streams:
		if stream != null:
			options.append(stream)
	if options.is_empty():
		return null
	return options[randi() % options.size()]


## One-shot that survives this node being freed (death / caught / split).
func play_global_detached(stream: AudioStream) -> bool:
	if stream == null:
		return false
	var tree := get_tree()
	if tree == null:
		return false
	var host := tree.current_scene
	if host == null:
		host = tree.root
	var voice := AudioStreamPlayer.new()
	voice.bus = String(bus)
	voice.stream = stream
	host.add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()
	return true


func start_standard(stream: AudioStream) -> void:
	if _standard == null:
		return
	if stream == null:
		_standard_source = null
		stop_standard()
		return
	_apply_proximity(_standard)
	if _standard_source == stream and _standard.playing:
		return
	_standard_source = stream
	_standard.stream = _as_looping(stream)
	# Defer so AudioListener2D / camera are current when enemies activate in _ready.
	_standard.call_deferred("play")


func _as_looping(stream: AudioStream) -> AudioStream:
	# Duplicate so we don't mutate the imported resource on disk.
	var copy := stream.duplicate()
	if copy is AudioStreamOggVorbis:
		(copy as AudioStreamOggVorbis).loop = true
	elif copy is AudioStreamMP3:
		(copy as AudioStreamMP3).loop = true
	elif copy is AudioStreamWAV:
		var wav := copy as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		# Import often leaves loop_end at -1 / 0, which disables LOOP_FORWARD.
		var end_frame := wav.loop_end
		if end_frame <= wav.loop_begin:
			var rate := maxi(wav.mix_rate, 1)
			end_frame = maxi(int(ceil(wav.get_length() * float(rate))) - 1, 1)
		wav.loop_end = end_frame
	return copy


func _on_standard_finished() -> void:
	# Fallback for formats that refuse native looping (e.g. some compressed WAV).
	if _standard == null or _standard_source == null:
		return
	if _standard.stream == null:
		return
	_standard.play()


func stop_standard() -> void:
	_standard_source = null
	if _standard != null and _standard.playing:
		_standard.stop()


func stop_all() -> void:
	stop_standard()
	for voice in _global_voices:
		if voice.playing:
			voice.stop()
	for voice in _proximity_voices:
		if voice.playing:
			voice.stop()


func _interval_ok(key: StringName, min_interval: float) -> bool:
	if key == &"" or min_interval <= 0.0:
		return true
	var now := Time.get_ticks_msec() * 0.001
	var last: float = float(_last_played_sec.get(key, -9999.0))
	if now - last < min_interval:
		return false
	_last_played_sec[key] = now
	return true


func _configure_and_play(voice: Node, stream: AudioStream) -> void:
	voice.bus = String(bus)
	voice.stream = stream
	voice.pitch_scale = 1.0
	voice.play()


func _apply_proximity(voice: AudioStreamPlayer2D) -> void:
	voice.max_distance = maxf(proximity_max_distance, 1.0)
	voice.attenuation = proximity_attenuation


func _ensure_voices() -> void:
	var wanted := maxi(polyphony, 1)
	while _global_voices.size() < wanted:
		var voice := AudioStreamPlayer.new()
		voice.name = "Global_%d" % _global_voices.size()
		voice.bus = String(bus)
		add_child(voice)
		_global_voices.append(voice)
	while _proximity_voices.size() < wanted:
		var voice := AudioStreamPlayer2D.new()
		voice.name = "Proximity_%d" % _proximity_voices.size()
		voice.bus = String(bus)
		_apply_proximity(voice)
		add_child(voice)
		_proximity_voices.append(voice)
	if _next_global >= _global_voices.size():
		_next_global = 0
	if _next_proximity >= _proximity_voices.size():
		_next_proximity = 0
