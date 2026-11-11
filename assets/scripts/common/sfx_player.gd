class_name SfxPlayer
extends Node2D

## Add only the cues this entity needs (size/order free).
## Typical ids: walk, attack, hurt, death, charge, sleep.
@export var cues: Array[SfxCue] = []:
	set(value):
		cues = value
		_rebuild_index()

@export_range(1, 8) var polyphony: int = 3
@export var bus: StringName = &"Master"

var _by_id: Dictionary = {} # StringName -> SfxCue
var _last_played_sec: Dictionary = {} # StringName -> float
var _players: Array[AudioStreamPlayer2D] = []
var _next_player: int = 0


func _ready() -> void:
	_ensure_players()
	_rebuild_index()


func has_cue(id: StringName) -> bool:
	return _by_id.has(id) and (_by_id[id] as SfxCue).stream != null


func get_cue(id: StringName) -> SfxCue:
	return _by_id.get(id) as SfxCue


## Plays cue by id. Returns false if missing, on cooldown, or no stream.
func play(id: StringName) -> bool:
	var cue := get_cue(id)
	if cue == null or cue.stream == null:
		return false
	return _play_cue(cue)


func play_cue(cue: SfxCue) -> bool:
	if cue == null or cue.stream == null:
		return false
	return _play_cue(cue)


## Plays at this node position, then frees the voice when done (survives owner free).
func play_detached(id: StringName) -> bool:
	var cue := get_cue(id)
	if cue == null or cue.stream == null:
		return false
	var tree := get_tree()
	if tree == null:
		return false
	var host := tree.current_scene
	if host == null:
		host = tree.root
	var player := AudioStreamPlayer2D.new()
	player.stream = cue.stream
	player.volume_db = cue.volume_db
	player.bus = String(bus)
	if cue.pitch_variance > 0.0:
		player.pitch_scale = 1.0 + randf_range(-cue.pitch_variance, cue.pitch_variance)
	player.global_position = global_position
	host.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	return true


func stop_all() -> void:
	for player in _players:
		if player.playing:
			player.stop()


func _play_cue(cue: SfxCue) -> bool:
	_ensure_players()
	if cue.min_interval > 0.0:
		var now := Time.get_ticks_msec() * 0.001
		var last: float = float(_last_played_sec.get(cue.id, -9999.0))
		if now - last < cue.min_interval:
			return false
		_last_played_sec[cue.id] = now

	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = cue.stream
	player.volume_db = cue.volume_db
	player.bus = String(bus)
	if cue.pitch_variance > 0.0:
		player.pitch_scale = 1.0 + randf_range(-cue.pitch_variance, cue.pitch_variance)
	else:
		player.pitch_scale = 1.0
	player.play()
	return true


func _rebuild_index() -> void:
	_by_id.clear()
	for cue in cues:
		if cue == null or cue.id == &"":
			continue
		_by_id[cue.id] = cue


func _ensure_players() -> void:
	var wanted := maxi(polyphony, 1)
	while _players.size() < wanted:
		var p := AudioStreamPlayer2D.new()
		p.name = "Voice_%d" % _players.size()
		p.bus = String(bus)
		add_child(p)
		_players.append(p)
	# Shrink only unused extras created by this component.
	while _players.size() > wanted:
		var extra := _players.pop_back() as AudioStreamPlayer2D
		if is_instance_valid(extra):
			extra.queue_free()
	if _next_player >= _players.size():
		_next_player = 0
