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


func _physics_process(_delta: float) -> void:
	# Resume / silence spatial audio as the player enters or leaves this room.
	# Pre-placed enemies (e.g. Elite under Game/Enemy) often call start_standard
	# before the player shares the room — keep the desired loop and start later.
	if _player_in_same_room():
		_resume_standard_if_needed()
		return
	_pause_spatial_for_room_leave()
	if _standard_source == null and not _any_spatial_playing():
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
		stop_standard()
		return
	var same_already_playing := _standard_source == stream and _standard.playing
	_standard_source = stream
	set_physics_process(true)
	if not _player_in_same_room():
		if _standard.playing:
			_standard.stop()
		return
	if same_already_playing:
		return
	_apply_proximity(_standard)
	_standard.stream = _as_looping(stream)
	_standard.call_deferred("play")


func _resume_standard_if_needed() -> void:
	if _standard == null or _standard_source == null:
		return
	if _standard.playing:
		return
	_apply_proximity(_standard)
	_standard.stream = _as_looping(_standard_source)
	_standard.play()


func _pause_spatial_for_room_leave() -> void:
	# Keep `_standard_source` so ambient can resume when the player returns.
	if _standard != null and _standard.playing:
		_standard.stop()
	_stop_spatial_voices()


func _as_looping(stream: AudioStream) -> AudioStream:
	var copy := stream.duplicate()
	if copy is AudioStreamOggVorbis:
		(copy as AudioStreamOggVorbis).loop = true
	elif copy is AudioStreamMP3:
		(copy as AudioStreamMP3).loop = true
	elif copy is AudioStreamWAV:
		var wav := copy as AudioStreamWAV
		# IMA-ADPCM + a bad loop_end can mute immediately. Prefer finished→replay.
		if wav.format == AudioStreamWAV.FORMAT_IMA_ADPCM:
			wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
			return copy
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
		# Keep desired source; physics watcher will resume on re-enter.
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

	var self_room := _get_own_room()
	var player_room := _get_current_room()
	if player_room == null:
		player_room = _find_room_at(player.global_position)
	if self_room != null and player_room != null:
		return self_room == player_room

	# Spawned enemies live under an inactive Room until the player enters.
	if self_room != null and self_room.has_method("is_active") and bool(self_room.call("is_active")):
		return true

	# Last resort for pre-placed foes sitting just outside tile bounds.
	if self_room != null and self_room.has_method("contains_world_point"):
		return bool(self_room.call("contains_world_point", player.global_position, 48.0))
	return false


## Room that owns this emitter: parent Room if spawned, else room under our feet.
func _get_own_room() -> Node:
	var node: Node = self
	while node != null:
		if node is Room or node.is_in_group("rooms"):
			return node
		node = node.get_parent()
	return _find_room_at(global_position)


func _get_current_room() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var manager := tree.get_first_node_in_group("room_manager")
	if manager != null and "current_room" in manager:
		return manager.current_room
	return null


func _find_room_at(point: Vector2) -> Node:
	var manager := get_tree().get_first_node_in_group("room_manager") if get_tree() != null else null
	if manager != null and manager.has_method("get_room_at"):
		return manager.call("get_room_at", point, 48.0)

	var tree := get_tree()
	if tree == null:
		return null
	var best: Node = null
	var best_area := INF
	for room in tree.get_nodes_in_group("rooms"):
		if room == null or not room.has_method("contains_world_point"):
			continue
		# Wider margin than gameplay (8px) so doorway / offset placements still match.
		if not bool(room.call("contains_world_point", point, 48.0)):
			continue
		var area := INF
		if room.has_method("get_camera_bounds"):
			var bounds: Rect2 = room.call("get_camera_bounds")
			if bounds.size != Vector2.ZERO:
				area = absf(bounds.get_area())
		if area < best_area:
			best_area = area
			best = room
	return best
