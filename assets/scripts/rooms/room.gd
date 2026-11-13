class_name Room
extends Node2D

## Base room: camera bounds, activation, doors, and enemy spawns.

signal player_entered(player: Node2D)
signal player_exited(player: Node2D)
signal discovered()

## Optional: drag Door StaticBodies here. If empty, auto-detects Door children.
@export var doors: Array[Door] = []
## Snap the player past the doorway when this room becomes active.
@export var teleport_on_enter: bool = true
## How far inside (from the entry door toward the room center) to place the player.
@export var enter_teleport_inset: float = 40.0
## Grace time after enter before sealing doors (player is already teleported inside).
@export var door_close_delay: float = 0.15

@export_group("Enemy Spawns")
## One entry per EnemySpawnPoint (tree order). Editable on room instances in the Inspector.
## Leave an element empty to keep that marker's default enemy.
@export var spawn_enemy_scenes: Array[PackedScene] = []

@export_group("Navigation")
## Destination room per door, same order as get_doors(). Empty = geometric fallback.
@export var door_targets: Array[Room] = []

@export_group("Button Unlock")
## When enabled, assigned buttons can open this room's doors / clear its lock.
@export var unlock_doors_with_buttons: bool = false
## Drag PropButton nodes here (scene: res://assets/scenes/props/interactive/button.tscn).
@export var unlock_buttons: Array[Area2D] = []
## If true, every assigned button must be pressed. If false, any one is enough.
@export var require_all_buttons: bool = true

var _active: bool = false
var _discovered: bool = false
var _spawned_enemies: Array[Node] = []
var _resident_enemies: Array[Node] = []
var _door_close_token: int = 0
var _button_unlock_done: bool = false
var _button_unlock_committed: bool = false
var _buttons_wired: bool = false
var _bounds_cached: bool = false
var _cached_bounds: Rect2 = Rect2()


func _ready() -> void:
	add_to_group("rooms")
	_active = false
	# Inactive rooms pause scripts/enemies, but walls/doors must keep colliding
	# (default DISABLE_MODE_REMOVE would let the player walk out of the map).
	_keep_world_collision_when_disabled()
	process_mode = Node.PROCESS_MODE_DISABLED
	# PROCESS_MODE_DISABLED does not skip rendering — hide for HTML5 perf.
	visible = false
	call_deferred("_setup_button_unlock")
	call_deferred("_seal_unlinked_doors")


func is_active() -> bool:
	return _active


func is_discovered() -> bool:
	return _discovered


func mark_discovered() -> void:
	if _discovered:
		return
	_discovered = true
	discovered.emit()


func set_active(active: bool, player: Node2D = null) -> void:
	if _active == active:
		return
	_active = active
	if _active:
		visible = true
		process_mode = Node.PROCESS_MODE_INHERIT
		sync_mode()
		if player != null:
			teleport_player_inside_from_entry(player)
		_enable_spawned_enemies()
		_enable_resident_enemies()
		mark_discovered()
		on_player_entered(player)
		player_entered.emit(player)
	else:
		on_player_exited(player)
		player_exited.emit(player)
		_disable_spawned_enemies()
		_disable_resident_enemies()
		process_mode = Node.PROCESS_MODE_DISABLED
		visible = false


## Apply WorldMode to this room's tilemaps and enemies (lazy sync on enter / active switch).
func sync_mode() -> void:
	var room_sw := get_node_or_null("Switchable")
	if room_sw != null and room_sw.has_method("set_mode"):
		room_sw.call("set_mode", WorldMode.mode)
	# Split enemy hitbox work onto the next frame so the shift hitch is smaller on web.
	call_deferred("_sync_all_enemies_mode")


func _sync_all_enemies_mode() -> void:
	_sync_spawned_enemies_mode()
	_sync_resident_enemies_mode()


## Pre-placed enemies that live in this room (assigned by RoomManager).
func register_resident(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if _resident_enemies.has(enemy):
		return
	_resident_enemies.append(enemy)
	if enemy.has_signal("tree_exiting"):
		enemy.tree_exiting.connect(_on_resident_enemy_exiting.bind(enemy), CONNECT_ONE_SHOT)
	_sync_enemy_mode(enemy)
	if _active:
		enemy.process_mode = Node.PROCESS_MODE_INHERIT
	else:
		enemy.process_mode = Node.PROCESS_MODE_DISABLED


## Places the player just inside the nearest doorway so they never stand in the seal zone.
func teleport_player_inside_from_entry(player: Node2D) -> void:
	if not teleport_on_enter or player == null:
		return
	var bounds := get_camera_bounds()
	if bounds.size == Vector2.ZERO:
		return
	# Already deep inside (e.g. run start) — don't yank.
	var deep := bounds.grow(-enter_teleport_inset)
	if deep.size.x > 0.0 and deep.size.y > 0.0 and deep.has_point(player.global_position):
		return

	var target := get_entry_teleport_position(player.global_position)
	if player is CharacterBody2D:
		var body := player as CharacterBody2D
		body.velocity = Vector2.ZERO
		body.global_position = target
	else:
		player.global_position = target


func get_entry_teleport_position(from_world: Vector2) -> Vector2:
	var bounds := get_camera_bounds()
	var center := bounds.get_center()
	var origin := from_world
	var door := _nearest_door_to(from_world)
	if door != null:
		origin = _door_world_center(door)

	var inward := center - origin
	if inward.length_squared() < 0.01:
		inward = center - from_world
	if inward.length_squared() < 0.01:
		return center
	inward = inward.normalized()

	var target := origin + inward * enter_teleport_inset
	var safe := bounds.grow(-maxf(enter_teleport_inset * 0.5, 16.0))
	if safe.size.x > 0.0 and safe.size.y > 0.0:
		target.x = clampf(target.x, safe.position.x, safe.end.x)
		target.y = clampf(target.y, safe.position.y, safe.end.y)
	return target


func nearest_door_to(point: Vector2) -> Door:
	var best: Door = null
	var best_dist := INF
	for door in get_doors():
		var dist := _door_world_center(door).distance_squared_to(point)
		if dist < best_dist:
			best_dist = dist
			best = door
	return best


func _nearest_door_to(point: Vector2) -> Door:
	return nearest_door_to(point)


## Room linked to `door` via door_targets (same order as get_doors()). Null if unset.
func get_door_target(door: Door) -> Room:
	if door == null:
		return null
	var index := _door_index(door)
	if index < 0:
		return null
	return _door_target_at(index)


## True when this door has an authored destination room.
func is_door_linked(door: Door) -> bool:
	return get_door_target(door) != null


## Doors with no door_targets entry stay closed as a permanent barrier.
func _seal_unlinked_doors() -> void:
	var doors := get_doors()
	for i in doors.size():
		if _door_target_at(i) != null:
			continue
		var door := doors[i]
		door.starts_open = false
		door.set_open(false)


func _door_index(door: Door) -> int:
	var doors := get_doors()
	for i in doors.size():
		if doors[i] == door:
			return i
	return -1


func _door_target_at(index: int) -> Room:
	if index < 0 or index >= door_targets.size():
		return null
	return door_targets[index]


func _door_world_center(door: Door) -> Vector2:
	var rect := _collision_global_rect(door)
	if rect.size != Vector2.ZERO:
		return rect.get_center()
	return door.global_position


func _keep_world_collision_when_disabled() -> void:
	_keep_world_collision_recursive(self)


func _keep_world_collision_recursive(node: Node) -> void:
	if node.name == "Enemies":
		return
	# Keep walls, doors, and props solid while the room script is paused.
	if node is CollisionObject2D:
		(node as CollisionObject2D).disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	for child in node.get_children():
		_keep_world_collision_recursive(child)


func on_player_entered(_player: Node2D) -> void:
	# Base rooms with EnemySpawnPoint children spawn on enter.
	# Typed rooms (Safe, Parkour, …) override and skip this if needed.
	if not get_spawn_points().is_empty():
		spawn_enemies()


func on_player_exited(_player: Node2D) -> void:
	pass


func get_camera_bounds() -> Rect2:
	if _bounds_cached:
		return _cached_bounds

	var tilemap := get_node_or_null("Switchable/Pesadilla") as TileMap
	if tilemap == null or tilemap.tile_set == null:
		return Rect2()

	var used: Rect2i = tilemap.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return Rect2()

	var tile_size := Vector2(tilemap.tile_set.tile_size)
	var top_left_local: Vector2 = tilemap.map_to_local(used.position) - tile_size * 0.5
	var bottom_right_local: Vector2 = (
		tilemap.map_to_local(used.position + used.size - Vector2i.ONE) + tile_size * 0.5
	)
	var top_left: Vector2 = tilemap.to_global(top_left_local)
	var bottom_right: Vector2 = tilemap.to_global(bottom_right_local)
	_cached_bounds = Rect2(top_left, bottom_right - top_left)
	_bounds_cached = true
	return _cached_bounds


func contains_world_point(point: Vector2, margin: float = 8.0) -> bool:
	var bounds := get_camera_bounds()
	if bounds.size == Vector2.ZERO:
		return false
	return bounds.grow(margin).has_point(point)


func get_doors() -> Array[Door]:
	if not doors.is_empty():
		var assigned: Array[Door] = []
		for door in doors:
			if door != null:
				assigned.append(door)
		return assigned

	var found: Array[Door] = []
	for child in get_children():
		if child is Door:
			found.append(child as Door)
	return found


func get_spawn_points() -> Array[EnemySpawnPoint]:
	var points: Array[EnemySpawnPoint] = []
	_collect_spawn_points(self, points)
	return points


func spawn_enemies() -> Array[Node]:
	var container := _get_or_create_enemies_container()
	_prune_spawned_enemies()
	_apply_spawn_type_overrides()
	for point in get_spawn_points():
		var enemy := point.spawn(container)
		if enemy != null and not _spawned_enemies.has(enemy):
			_spawned_enemies.append(enemy)
			if enemy.has_signal("tree_exiting"):
				enemy.tree_exiting.connect(_on_spawned_enemy_exiting.bind(enemy), CONNECT_ONE_SHOT)
		if enemy != null:
			_sync_enemy_mode(enemy)
	_enable_spawned_enemies()
	_sync_spawned_enemies_mode()
	return _spawned_enemies.duplicate()


func _apply_spawn_type_overrides() -> void:
	if spawn_enemy_scenes.is_empty():
		return
	var points := get_spawn_points()
	for i in mini(points.size(), spawn_enemy_scenes.size()):
		var packed: PackedScene = spawn_enemy_scenes[i]
		if packed == null:
			continue
		points[i].set_enemy_scene_override(packed)


func get_alive_enemies() -> Array[Node]:
	_prune_spawned_enemies()
	return _spawned_enemies.duplicate()


func has_alive_enemies() -> bool:
	return not get_alive_enemies().is_empty()


## Used by splitters (e.g. Divider) so child segments stay tracked for room clear.
func register_enemy(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if _spawned_enemies.has(enemy):
		return
	_spawned_enemies.append(enemy)
	if enemy.has_signal("tree_exiting"):
		enemy.tree_exiting.connect(_on_spawned_enemy_exiting.bind(enemy), CONNECT_ONE_SHOT)
	_sync_enemy_mode(enemy)
	if _active:
		enemy.process_mode = Node.PROCESS_MODE_INHERIT
	else:
		enemy.process_mode = Node.PROCESS_MODE_DISABLED


func set_all_doors_open(open: bool) -> void:
	var doors := get_doors()
	for i in doors.size():
		# Unlinked doors are permanent barriers — never open them via bulk unlock.
		if open and _door_target_at(i) == null:
			continue
		doors[i].set_open(open)


func _setup_button_unlock() -> void:
	if _buttons_wired or not unlock_doors_with_buttons:
		return
	_buttons_wired = true
	for button in unlock_buttons:
		if button == null:
			continue
		if button.has_signal("pressed") and not button.pressed.is_connected(_on_unlock_button_changed):
			button.pressed.connect(_on_unlock_button_changed)
		if button.has_signal("released") and not button.released.is_connected(_on_unlock_button_changed):
			button.released.connect(_on_unlock_button_changed)


func _on_unlock_button_changed() -> void:
	if _button_unlock_done or _button_unlock_committed or not unlock_doors_with_buttons:
		return
	if not _are_unlock_buttons_satisfied():
		return
	_button_unlock_done = true
	# Button press arrives during physics flush — open doors next frame.
	call_deferred("on_button_unlock")


func _are_unlock_buttons_satisfied() -> bool:
	if unlock_buttons.is_empty():
		return false
	if require_all_buttons:
		for button in unlock_buttons:
			if button == null:
				return false
			if button.has_method("is_pressed"):
				if not bool(button.call("is_pressed")):
					return false
			else:
				return false
		return true
	for button in unlock_buttons:
		if button != null and button.has_method("is_pressed") and bool(button.call("is_pressed")):
			return true
	return false


## Call when leaving the room successfully so pressed buttons stay down forever.
func commit_unlock_buttons() -> void:
	if not unlock_doors_with_buttons:
		return
	if not _button_unlock_done and not _are_unlock_buttons_satisfied():
		return
	_button_unlock_done = true
	_button_unlock_committed = true
	for button in unlock_buttons:
		if button != null and button.has_method("commit"):
			button.call("commit")


## Call on void respawn / failed attempt — undoes uncommitted button progress.
func reset_unlock_buttons() -> void:
	if not unlock_doors_with_buttons or _button_unlock_committed:
		return
	_button_unlock_done = false
	for button in unlock_buttons:
		if button != null and button.has_method("reset"):
			button.call("reset")


## Override in room types that clear locks / open a specific exit door.
func on_button_unlock() -> void:
	cancel_pending_door_close()
	set_all_doors_open(true)


## Closes doors after `door_close_delay`. Cancelled if the player leaves first.
## Safe to call after enter teleport — the player is already clear of the doorway.
func close_doors_after_delay() -> void:
	_door_close_token += 1
	var token := _door_close_token
	if door_close_delay > 0.0:
		await get_tree().create_timer(door_close_delay).timeout
	if token != _door_close_token or not is_active():
		return
	set_all_doors_open(false)


func cancel_pending_door_close() -> void:
	_door_close_token += 1


func _collision_global_rect(node: Node) -> Rect2:
	var shape_node := node.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or shape_node.shape == null:
		return Rect2()
	var shape := shape_node.shape
	if shape is RectangleShape2D:
		var size: Vector2 = (shape as RectangleShape2D).size * shape_node.global_scale.abs()
		return Rect2(shape_node.global_position - size * 0.5, size)
	if shape is CircleShape2D:
		var radius: float = (shape as CircleShape2D).radius * maxf(absf(shape_node.global_scale.x), absf(shape_node.global_scale.y))
		var extent := Vector2(radius, radius)
		return Rect2(shape_node.global_position - extent, extent * 2.0)
	return Rect2(shape_node.global_position - Vector2(8, 8), Vector2(16, 16))


func _get_or_create_enemies_container() -> Node:
	var existing := get_node_or_null("Enemies")
	if existing != null:
		return existing
	var container := Node2D.new()
	container.name = "Enemies"
	add_child(container)
	return container


func _collect_spawn_points(node: Node, out: Array[EnemySpawnPoint]) -> void:
	if node is EnemySpawnPoint:
		out.append(node)
	for child in node.get_children():
		# Skip live enemy instances under Enemies.
		if child.name == "Enemies":
			continue
		_collect_spawn_points(child, out)


func _enable_spawned_enemies() -> void:
	_prune_spawned_enemies()
	for enemy in _spawned_enemies:
		enemy.process_mode = Node.PROCESS_MODE_INHERIT
	_sync_spawned_enemies_mode()


func _disable_spawned_enemies() -> void:
	_prune_spawned_enemies()
	for enemy in _spawned_enemies:
		enemy.process_mode = Node.PROCESS_MODE_DISABLED


func _enable_resident_enemies() -> void:
	_prune_resident_enemies()
	for enemy in _resident_enemies:
		enemy.process_mode = Node.PROCESS_MODE_INHERIT
	_sync_resident_enemies_mode()


func _disable_resident_enemies() -> void:
	_prune_resident_enemies()
	for enemy in _resident_enemies:
		enemy.process_mode = Node.PROCESS_MODE_DISABLED


func _prune_spawned_enemies() -> void:
	_spawned_enemies = _spawned_enemies.filter(func(e: Node) -> bool: return is_instance_valid(e))


func _prune_resident_enemies() -> void:
	_resident_enemies = _resident_enemies.filter(func(e: Node) -> bool: return is_instance_valid(e))


func _on_spawned_enemy_exiting(enemy: Node) -> void:
	_spawned_enemies.erase(enemy)


func _on_resident_enemy_exiting(enemy: Node) -> void:
	_resident_enemies.erase(enemy)


## Keep spawned enemies in phase with the room dream/nightmare switch.
## Spawning mid-Sueño otherwise leaves them at start_index 0 and inverts later toggles.
func _sync_spawned_enemies_mode() -> void:
	_prune_spawned_enemies()
	for enemy in _spawned_enemies:
		_sync_enemy_mode(enemy)


func _sync_resident_enemies_mode() -> void:
	_prune_resident_enemies()
	for enemy in _resident_enemies:
		_sync_enemy_mode(enemy)


func _sync_enemy_mode(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var mode := _get_world_mode()
	var enemy_sw := enemy.get_node_or_null("Switchable")
	if enemy_sw != null and enemy_sw.has_method("set_mode"):
		enemy_sw.call("set_mode", mode)


func _get_world_mode() -> int:
	return WorldMode.mode
