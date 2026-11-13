extends Node

## Owns current_room, door transitions, and WorldMode sync for the active room only.

signal room_changed(previous: Room, next: Room)

@export var detect_margin: float = 8.0

var current_room: Room = null

var _player: Node2D = null
var _transitioning: bool = false


func _ready() -> void:
	add_to_group("room_manager")
	if not WorldMode.mode_changed.is_connected(_on_world_mode_changed):
		WorldMode.mode_changed.connect(_on_world_mode_changed)
	call_deferred("_bootstrap")


func _physics_process(_delta: float) -> void:
	if _transitioning:
		return
	_player = _get_player()
	if _player == null:
		return
	# Don't room-hop while the player is mid void-fall animation.
	if _player.has_method("is_void_falling") and bool(_player.call("is_void_falling")):
		return
	if current_room == null:
		_bootstrap_current_room()
		return
	if current_room.contains_world_point(_player.global_position, detect_margin):
		return
	_try_transition_from_exit()


func enter_room(room: Room, player: Node2D = null) -> void:
	if room == null:
		return
	if player == null:
		player = _get_player()
	if room == current_room:
		if not room.is_active():
			room.set_active(true, player)
		return

	_transitioning = true
	var previous := current_room
	if previous != null and previous != room:
		previous.set_active(false, player)
	current_room = room
	if not room.is_active():
		room.set_active(true, player)
	room_changed.emit(previous, room)
	_transitioning = false


func get_room_at(point: Vector2, margin: float = -1.0) -> Room:
	var use_margin := detect_margin if margin < 0.0 else margin
	var best: Room = null
	var best_area := INF
	for node in get_tree().get_nodes_in_group("rooms"):
		var room := node as Room
		if room == null:
			continue
		if not room.contains_world_point(point, use_margin):
			continue
		var bounds := room.get_camera_bounds()
		var area := bounds.get_area() if bounds.size != Vector2.ZERO else INF
		if area < best_area:
			best_area = area
			best = room
	return best


func _bootstrap() -> void:
	_assign_resident_enemies()
	_bootstrap_current_room()


func _bootstrap_current_room() -> void:
	_player = _get_player()
	if _player == null:
		return
	var room := get_room_at(_player.global_position)
	if room == null:
		return
	enter_room(room, _player)


func _on_world_mode_changed(_index: int) -> void:
	if current_room != null:
		current_room.sync_mode()


func _try_transition_from_exit() -> void:
	if current_room == null or _player == null:
		return

	# Must actually be inside another room (void / gaps do not force a transition).
	var geometric := get_room_at(_player.global_position)
	if geometric == null or geometric == current_room:
		return

	var next := geometric
	var door := current_room.nearest_door_to(_player.global_position)
	if door != null:
		var explicit := current_room.get_door_target(door)
		# Prefer authored link when it matches where the player landed.
		if explicit != null and (
			explicit == geometric
			or explicit.contains_world_point(_player.global_position, detect_margin)
		):
			next = explicit

	if next == null or next == current_room:
		return
	enter_room(next, _player)


func _assign_resident_enemies() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group("enemy"):
		_try_register_orphan_enemy(node)
	for node in tree.get_nodes_in_group("cat"):
		if not node.is_in_group("enemy"):
			node.add_to_group("enemy")
		_try_register_orphan_enemy(node)


func _try_register_orphan_enemy(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if _owns_room_ancestor(enemy):
		return
	if enemy is not Node2D:
		return
	var room := get_room_at((enemy as Node2D).global_position, 48.0)
	if room == null:
		return
	room.register_resident(enemy)


func _owns_room_ancestor(node: Node) -> bool:
	var cursor := node.get_parent()
	while cursor != null:
		if cursor is Room or cursor.is_in_group("rooms"):
			return true
		cursor = cursor.get_parent()
	return false


func _get_player() -> Node2D:
	if _player != null and is_instance_valid(_player):
		return _player
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("player") as Node2D
