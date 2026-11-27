extends Node

## Loads one room scene at a time into RoomContainer and handles door transitions.

signal room_changed(previous: Room, next: Room)

@export var fade_duration: float = 0.18

var current_room: Room = null

var _player: Node2D = null
var _transitioning: bool = false
var _enter_grace_until_msec: int = 0
var _container: Node2D = null
var _fade_layer: CanvasLayer = null
var _fade_rect: ColorRect = null

const ENTER_GRACE_MSEC := 350


func _ready() -> void:
	add_to_group("room_manager")
	if not WorldMode.mode_changed.is_connected(_on_world_mode_changed):
		WorldMode.mode_changed.connect(_on_world_mode_changed)
	_ensure_fade_ui()
	call_deferred("_bootstrap")


func is_enter_grace_active() -> bool:
	return Time.get_ticks_msec() < _enter_grace_until_msec


func is_transitioning() -> bool:
	return _transitioning


func go_to(scene_path: String, entry_door_id: StringName = &"") -> void:
	if _transitioning:
		return
	if scene_path.is_empty():
		push_warning("RoomManager.go_to: empty scene path")
		return
	_transitioning = true
	await _fade_out()

	_player = _get_player()
	if current_room != null:
		# Deactivate first so on_player_exited() commits button/door progress,
		# then persist that committed state (plus any still-pressed buttons).
		current_room.set_active(false, _player)
		current_room.save_state(RunState)
		current_room.queue_free()
		current_room = null
		await get_tree().process_frame

	var packed := await _load_scene(scene_path)
	if packed == null:
		push_error("RoomManager.go_to: failed to load %s" % scene_path)
		_transitioning = false
		await _fade_in()
		return

	var room := packed.instantiate() as Room
	if room == null:
		push_error("RoomManager.go_to: root is not a Room: %s" % scene_path)
		_transitioning = false
		await _fade_in()
		return

	_get_container().add_child(room)
	room.position = Vector2.ZERO
	room.load_state(RunState)

	_place_player(room, entry_door_id)
	current_room = room
	if not room.is_active():
		room.set_active(true, _player)
	# Previous room was queue_free'd — never pass a freed Object into typed Room args.
	room_changed.emit(null, room)
	_preload_neighbors(room)

	await _fade_in()
	_enter_grace_until_msec = Time.get_ticks_msec() + ENTER_GRACE_MSEC
	_transitioning = false


## Keep parkour void-respawn working without a scene change.
func enter_room(room: Room, player: Node2D = null) -> void:
	if room == null:
		return
	if player == null:
		player = _get_player()
	if room == current_room:
		if not room.is_active():
			room.set_active(true, player)
		return
	# Cross-room enter is only valid while the target is already the loaded room.
	current_room = room
	if not room.is_active():
		room.set_active(true, player)
	room_changed.emit(null, room)


func _bootstrap() -> void:
	_player = _get_player()
	var start := RunState.consume_debug_start()
	var scene_path: String = String(start.get("scene", ""))
	var door_id: StringName = start.get("door", &"") as StringName
	if scene_path.is_empty():
		scene_path = RunState.start_room
		door_id = &""
	await go_to(scene_path, door_id)


func _on_world_mode_changed(_index: int) -> void:
	if current_room != null:
		current_room.sync_mode()


func _place_player(room: Room, entry_door_id: StringName) -> void:
	_player = _get_player()
	if _player == null or room == null:
		return
	var target := room.get_default_spawn()
	var door := room.get_door_by_id(entry_door_id)
	if door != null:
		target = door.get_spawn_position()
	if _player is CharacterBody2D:
		(_player as CharacterBody2D).velocity = Vector2.ZERO
	_player.global_position = target


func _get_container() -> Node2D:
	if _container != null and is_instance_valid(_container):
		return _container
	var parent := get_parent()
	if parent != null:
		_container = parent.get_node_or_null("RoomContainer") as Node2D
	if _container == null and parent != null:
		_container = Node2D.new()
		_container.name = "RoomContainer"
		parent.add_child(_container)
		parent.move_child(_container, 0)
	return _container


func _load_scene(path: String) -> PackedScene:
	var resolved := path
	if ResourceLoader.has_cached(resolved):
		return load(resolved) as PackedScene

	var status := ResourceLoader.load_threaded_get_status(resolved)
	if status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		var err := ResourceLoader.load_threaded_request(resolved)
		if err != OK:
			return load(resolved) as PackedScene

	while true:
		var progress: Array = []
		status = ResourceLoader.load_threaded_get_status(resolved, progress)
		match status:
			ResourceLoader.THREAD_LOAD_LOADED:
				return ResourceLoader.load_threaded_get(resolved) as PackedScene
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				return load(resolved) as PackedScene
			_:
				await get_tree().process_frame
	return load(resolved) as PackedScene


func _preload_neighbors(room: Room) -> void:
	if room == null:
		return
	for door in room.get_doors():
		if door == null or not door.is_linked():
			continue
		var path := door.target_room
		if path.is_empty() or ResourceLoader.has_cached(path):
			continue
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_request(path)


func _ensure_fade_ui() -> void:
	if _fade_layer != null:
		return
	_fade_layer = CanvasLayer.new()
	_fade_layer.name = "RoomFade"
	_fade_layer.layer = 120
	add_child(_fade_layer)

	_fade_rect = ColorRect.new()
	_fade_rect.name = "FadeRect"
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade_rect)


func _fade_out() -> void:
	_ensure_fade_ui()
	if fade_duration <= 0.0:
		_fade_rect.color.a = 1.0
		return
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", 1.0, fade_duration)
	await tween.finished


func _fade_in() -> void:
	_ensure_fade_ui()
	if fade_duration <= 0.0:
		_fade_rect.color.a = 0.0
		return
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", 0.0, fade_duration)
	await tween.finished


func _get_player() -> Node2D:
	if _player != null and is_instance_valid(_player):
		return _player
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("player") as Node2D
