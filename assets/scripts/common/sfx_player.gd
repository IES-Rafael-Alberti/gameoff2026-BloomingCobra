class_name SfxPlayer
extends Node2D

## Audio helper for entities.
## (UI) Always hear — player feedback (slash, steps, pickups).
## (R) Room — flat volume, only while the player shares this room.
## (P) Proximity — distance falloff, and only in the same room.

@export_group("Proximity")
## How close the listener must be to hear (P) sounds.
@export var proximity_max_distance: float = 160.0
@export_range(0.0, 4.0, 0.05) var proximity_attenuation: float = 1.0

@export_group("Playback")
@export_range(1, 8) var polyphony: int = 4
@export var bus: StringName = &"Master"

var _ui_voices: Array[AudioStreamPlayer] = []
var _room_voices: Array[AudioStreamPlayer] = []
var _proximity_voices: Array[AudioStreamPlayer2D] = []
var _next_ui: int = 0
var _next_room: int = 0
var _next_proximity: int = 0
var _standard: AudioStreamPlayer2D
var _standard_source: AudioStream
var _last_played_sec: Dictionary = {} # StringName -> float
var _cached_room: Node = null


func _ready() -> void:
	set_physics_process(false)
	_ensure_voices()
	_standard = AudioStreamPlayer2D.new()
	_standard.name = "StandardLoop"
	_standard.bus = String(bus)
	_standard.max_polyphony = 1
	_apply_proximity(_standard)
	_standard.finished.connect(_on_standard_finished)
	add_child(_standard)
	_cached_room = _resolve_room()


func _physics_process(_delta: float) -> void:
	# Silence spatial/room voices if the player left this room.
	if _player_in_same_room():
		return
	stop_standard()
	_stop_spatial_voices()
	if not _any_spatial_playing():
		set_physics_process(false)


## Always-on player/UI feedback (no room gate).
func play_global(stream: AudioStream, key: StringName = &"", min_interval: float = 0.0) -> bool:
	if stream == null or not _interval_ok(key, min_interval):
		return false
	_ensure_voices()
	var voice := _ui_voices[_next_ui]
	_next_ui = (_next_ui + 1) % _ui_voices.size()
	_configure_and_play(voice, stream)
	return true


## Flat volume, current room only.
func play_room(stream: AudioStream, key: StringName = &"", min_interval: float = 0.0) -> bool:
	if stream == null or not _interval_ok(key, min_interval):
		return false
	if not _player_in_same_room():
		return false
	_ensure_voices()
	var voice := _room_voices[_next_room]
	_next_room = (_next_room + 1) % _room_voices.size()
	_configure_and_play(voice, stream)
	set_physics_process(true)
	return true


## Distance-attenuated, and only if the player is in this room.
func play_proximity(stream: AudioStream, key: StringName = &"", min_interval: float = 0.0) -> bool:
	if stream == null or not _interval_ok(key, min_interval):
		return false
	if not _player_in_same_room():
		return false
	_ensure_voices()
	var voice := _proximity_voices[_next_proximity]
	_next_proximity = (_next_proximity + 1) % _proximity_voices.size()
	_apply_proximity(voice)
	_configure_and_play(voice, stream)
	set_physics_process(true)
	return true


func play_global_random(streams: Array[AudioStream], key: StringName = &"", min_interval: float = 0.0) -> bool:
	var pick := _pick_stream(streams)
	if pick == null:
		return false
	return play_global(pick, key, min_interval)


func play_room_random(streams: Array[AudioStream], key: StringName = &"", min_interval: float = 0.0) -> bool:
	var pick := _pick_stream(streams)
	if pick == null:
		return false
	return play_room(pick, key, min_interval)


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
## Room-scoped: only starts if the player is in this room.
func play_global_detached(stream: AudioStream) -> bool:
	return play_room_detached(stream)


func play_room_detached(stream: AudioStream) -> bool:
	if stream == null:
		return false
	if not _player_in_same_room():
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
	if not _player_in_same_room():
		stop_standard()
		return
	_apply_proximity(_standard)
	if _standard_source == stream and _standard.playing:
		return
	_standard_source = stream
	_standard.stream = _as_looping(stream)
	set_physics_process(true)
	_standard.call_deferred("play")


func _as_looping(stream: AudioStream) -> AudioStream:
	var copy := stream.duplicate()
	if copy is AudioStreamOggVorbis:
		(copy as AudioStreamOggVorbis).loop = true
	elif copy is AudioStreamMP3:
		(copy as AudioStreamMP3).loop = true
	elif copy is AudioStreamWAV:
		var wav := copy as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		var end_frame := wav.loop_end
		if end_frame <= wav.loop_begin:
			var rate := maxi(wav.mix_rate, 1)
			end_frame = maxi(int(ceil(wav.get_length() * float(rate))) - 1, 1)
		wav.loop_end = end_frame
	return copy


func _on_standard_finished() -> void:
	if _standard == null or _standard_source == null or _standard.stream == null:
		return
	if not _player_in_same_room():
		stop_standard()
		return
	_standard.play()


func stop_standard() -> void:
	_standard_source = null
	set_physics_process(false)
	if _standard != null and _standard.playing:
		_standard.stop()


func stop_all() -> void:
	stop_standard()
	for voice in _ui_voices:
		if voice.playing:
			voice.stop()
	_stop_spatial_voices()


func _stop_spatial_voices() -> void:
	for voice in _room_voices:
		if voice.playing:
			voice.stop()
	for voice in _proximity_voices:
		if voice.playing:
			voice.stop()


func _any_spatial_playing() -> bool:
	if _standard != null and _standard.playing:
		return true
	for voice in _room_voices:
		if voice.playing:
			return true
	for voice in _proximity_voices:
		if voice.playing:
			return true
	return false


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
	while _ui_voices.size() < wanted:
		var voice := AudioStreamPlayer.new()
		voice.name = "UI_%d" % _ui_voices.size()
		voice.bus = String(bus)
		add_child(voice)
		_ui_voices.append(voice)
	while _room_voices.size() < wanted:
		var voice := AudioStreamPlayer.new()
		voice.name = "Room_%d" % _room_voices.size()
		voice.bus = String(bus)
		add_child(voice)
		_room_voices.append(voice)
	while _proximity_voices.size() < wanted:
		var voice := AudioStreamPlayer2D.new()
		voice.name = "Proximity_%d" % _proximity_voices.size()
		voice.bus = String(bus)
		_apply_proximity(voice)
		add_child(voice)
		_proximity_voices.append(voice)
	if _next_ui >= _ui_voices.size():
		_next_ui = 0
	if _next_room >= _room_voices.size():
		_next_room = 0
	if _next_proximity >= _proximity_voices.size():
		_next_proximity = 0


func _player_in_same_room() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var player := tree.get_first_node_in_group("player") as Node2D
	if player == null:
		return false
	var room := _resolve_room()
	if room != null:
		if room.has_method("is_active") and bool(room.call("is_active")):
			return true
		if room.has_method("contains_world_point"):
			return bool(room.call("contains_world_point", player.global_position))
	var player_room := _find_room_at(player.global_position)
	var self_room := _find_room_at(global_position)
	return player_room != null and player_room == self_room


func _resolve_room() -> Node:
	if _cached_room != null and is_instance_valid(_cached_room):
		return _cached_room
	var node: Node = self
	while node != null:
		if node is Room or node.is_in_group("rooms"):
			_cached_room = node
			return _cached_room
		node = node.get_parent()
	_cached_room = _find_room_at(global_position)
	return _cached_room


func _find_room_at(point: Vector2) -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	for room in tree.get_nodes_in_group("rooms"):
		if room != null and room.has_method("contains_world_point") and bool(room.call("contains_world_point", point)):
			return room
	return null
