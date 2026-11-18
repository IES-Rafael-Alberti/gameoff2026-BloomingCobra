class_name Room
extends Node2D

## Base room: camera bounds, activation, doors, and enemy spawns.
## Designed to be loaded one-at-a-time under RoomManager / RoomContainer.

signal player_entered(player: Node2D)
signal player_exited(player: Node2D)
signal discovered()

const GAME_SCENE := "res://assets/scenes/game.tscn"

## Unique id for RunState. Empty = basename of scene_file_path.
@export var room_id: StringName = &""
## Isaac-style map grid cell for this room.
@export var map_cell: Vector2i = Vector2i.ZERO

## Optional: drag Door StaticBodies here. If empty, auto-detects Door children.
@export var doors: Array[Door] = []
## Grace time after enter before sealing doors.
@export var door_close_delay: float = 0.15

@export_group("Enemy Spawns")
## One entry per EnemySpawnPoint (tree order). Editable on room instances in the Inspector.
## Leave an element empty to keep that marker's default enemy.
@export var spawn_enemy_scenes: Array[PackedScene] = []

@export_group("Button Unlock")
## When enabled, assigned buttons can open this room's doors / clear its lock.
@export var unlock_doors_with_buttons: bool = false
## Drag PropButton nodes here (scene: res://assets/scenes/props/interactive/button.tscn).
@export var unlock_buttons: Array[Area2D] = []
## If true, every assigned button must be pressed. If false, any one is enough.
@export var require_all_buttons: bool = true

@export_group("Camera")
## Extra pixels beyond playable tile bounds for Camera2D limits (shows background past walls).
## Does not affect room detection / transitions.
@export var camera_limit_expand: float = 0.0

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
var _state_cleared: bool = false


func _ready() -> void:
	add_to_group("rooms")
	if room_id == &"":
		room_id = _default_room_id()
	_register_meta_with_run_state()

	# F6 / Run Current Scene: room is the scene root → boot game.tscn into this room.
	# Prefer parent==root: current_scene can still be null during _ready.
	if _is_running_as_main_scene():
		_queue_debug_boot()
		return

	_active = false
	process_mode = Node.PROCESS_MODE_DISABLED
	_keep_world_collision_when_disabled()
	_register_preplaced_residents()
	call_deferred("_setup_button_unlock")
	call_deferred("_seal_unlinked_doors")
	call_deferred("_register_links_with_run_state")


func _is_running_as_main_scene() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	if get_parent() == tree.root:
		return true
	return tree.current_scene == self


func _queue_debug_boot() -> void:
	var path := scene_file_path
	if path.is_empty():
		push_error("Room F6 boot: scene_file_path is empty (save the scene first)")
		return
	RunState.debug_start = {
		"scene": path,
		"door": &"",
	}
	call_deferred("_boot_via_game_scene")


func _boot_via_game_scene() -> void:
	# Re-assert in case something cleared it between ready and deferred.
	if RunState.debug_start.is_empty() and not scene_file_path.is_empty():
		RunState.debug_start = {
			"scene": scene_file_path,
			"door": &"",
		}
	var err := get_tree().change_scene_to_file(GAME_SCENE)
	if err != OK:
		push_error("Room F6 boot: failed to change to %s (error %s)" % [GAME_SCENE, err])


func _default_room_id() -> StringName:
	var path := scene_file_path
	if path.is_empty():
		return StringName(name)
	return StringName(path.get_file().get_basename())


func _register_meta_with_run_state() -> void:
	RunState.register_room_meta(room_id, scene_file_path, map_cell)


func _register_links_with_run_state() -> void:
	var links: Array = []
	for door in get_doors():
		if door == null or not door.is_linked():
			continue
		links.append({
			"door_id": door.door_id,
			"target_room": door.target_room,
			"target_door_id": door.target_door_id,
		})
	RunState.register_room_links(room_id, links)


func is_active() -> bool:
	return _active


func is_discovered() -> bool:
	return _discovered


func mark_discovered() -> void:
	if _discovered:
		return
	_discovered = true
	RunState.mark_discovered(room_id)
	discovered.emit()


func set_active(active: bool, player: Node2D = null) -> void:
	if _active == active:
		return
	_active = active
	if _active:
		visible = true
		process_mode = Node.PROCESS_MODE_INHERIT
		sync_mode()
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


## Pre-placed enemies that live in this room.
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


func _register_preplaced_residents() -> void:
	for node in get_children():
		_collect_preplaced_enemies(node)


func _collect_preplaced_enemies(node: Node) -> void:
	if node.is_in_group("enemy") or node.is_in_group("cat"):
		if node.is_in_group("cat") and not node.is_in_group("enemy"):
			node.add_to_group("enemy")
		register_resident(node)
		return
	for child in node.get_children():
		if child.name == "Enemies":
			continue
		_collect_preplaced_enemies(child)


func get_door_by_id(id: StringName) -> Door:
	if id == &"":
		return null
	for door in get_doors():
		if door != null and door.door_id == id:
			return door
	# Fallback: match node name case-insensitively.
	var needle := String(id).to_lower()
	for door in get_doors():
		if door != null and String(door.name).to_lower() == needle:
			return door
	return null


func get_default_spawn() -> Vector2:
	var marker := get_node_or_null("DefaultSpawn") as Marker2D
	if marker != null:
		return marker.global_position
	var bounds := get_camera_bounds()
	if bounds.size != Vector2.ZERO:
		return bounds.get_center()
	return global_position


func save_state(_run_state: Node = null) -> void:
	var state := RunState.ensure_room(room_id)
	state["discovered"] = _discovered or bool(state.get("discovered", false))
	state["cleared"] = _state_cleared or bool(state.get("cleared", false))
	state["buttons_committed"] = _button_unlock_committed or bool(state.get("buttons_committed", false))
	_register_links_with_run_state()
	RunState.register_room_meta(room_id, scene_file_path, map_cell)


func load_state(_run_state: Node = null) -> void:
	var state := RunState.ensure_room(room_id)
	_discovered = bool(state.get("discovered", false))
	_state_cleared = bool(state.get("cleared", false))
	_button_unlock_committed = bool(state.get("buttons_committed", false))
	if _button_unlock_committed:
		_button_unlock_done = true
		for button in unlock_buttons:
			if button != null and button.has_method("commit"):
				button.call("commit")


func mark_room_cleared() -> void:
	_state_cleared = true
	RunState.mark_cleared(room_id, true)


func is_room_cleared() -> bool:
	return _state_cleared


func nearest_door_to(point: Vector2) -> Door:
	var best: Door = null
	var best_dist := INF
	for door in get_doors():
		var dist := _door_world_center(door).distance_squared_to(point)
		if dist < best_dist:
			best_dist = dist
			best = door
	return best


## Doors with no target_room stay closed as a permanent barrier.
func _seal_unlinked_doors() -> void:
	for door in get_doors():
		if door == null or door.is_linked():
			continue
		door.starts_open = false
		door.set_open(false)


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
	if _state_cleared:
		return
	if not get_spawn_points().is_empty():
		spawn_enemies()


func on_player_exited(_player: Node2D) -> void:
	pass


func get_camera_bounds() -> Rect2:
	if _bounds_cached:
		return _cached_bounds

	var layers := _find_bounds_tile_layers()
	if layers.is_empty():
		return Rect2()

	var combined := Rect2()
	var has_any := false
	for layer in layers:
		var rect := _tile_node_global_bounds(layer)
		if rect.size == Vector2.ZERO:
			continue
		if not has_any:
			combined = rect
			has_any = true
		else:
			combined = combined.merge(rect)

	if not has_any:
		return Rect2()
	_cached_bounds = combined
	_bounds_cached = true
	return _cached_bounds


## TileMapLayer nodes under Switchable/Pesadilla (union for bounds). Debug TileMap as fallback.
func _find_bounds_tile_layers() -> Array[Node2D]:
	var result: Array[Node2D] = []
	var sw := get_node_or_null("Switchable")
	if sw == null:
		return result

	var mode_root: Node = null
	for mode_name in ["Pesadilla", "Sueño", "Sueno"]:
		mode_root = sw.get_node_or_null(mode_name)
		if mode_root != null:
			break
	if mode_root == null:
		return result

	_collect_tile_map_layers(mode_root, result)
	if not result.is_empty():
		return result

	# Debug rooms still using a monolithic TileMap.
	if mode_root is TileMap:
		result.append(mode_root as Node2D)
		return result
	for child in mode_root.get_children():
		if child is TileMap:
			result.append(child as Node2D)
			break
	return result


func _collect_tile_map_layers(node: Node, out: Array[Node2D]) -> void:
	if node is TileMapLayer:
		out.append(node as Node2D)
	for child in node.get_children():
		_collect_tile_map_layers(child, out)


func _tile_node_global_bounds(layer: Node2D) -> Rect2:
	if layer == null or not layer.has_method("get_used_rect"):
		return Rect2()
	var tileset: TileSet = layer.get("tile_set") as TileSet
	if tileset == null:
		return Rect2()
	var used: Rect2i = layer.call("get_used_rect") as Rect2i
	if used.size.x <= 0 or used.size.y <= 0:
		return Rect2()
	var tile_size := Vector2(tileset.tile_size)
	var top_left_local: Vector2 = layer.call("map_to_local", used.position) as Vector2 - tile_size * 0.5
	var bottom_right_local: Vector2 = (
		layer.call("map_to_local", used.position + used.size - Vector2i.ONE) as Vector2 + tile_size * 0.5
	)
	var top_left := layer.to_global(top_left_local)
	var bottom_right := layer.to_global(bottom_right_local)
	return Rect2(top_left, bottom_right - top_left)


## Bounds used by Camera2D limits. May be larger than playable `get_camera_bounds()`.
func get_camera_limit_bounds() -> Rect2:
	var bounds := get_camera_bounds()
	if bounds.size == Vector2.ZERO or camera_limit_expand <= 0.0:
		return bounds
	return bounds.grow(camera_limit_expand)


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
	if _state_cleared:
		return []
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
	for door in get_doors():
		# Unlinked doors are permanent barriers — never open them via bulk unlock.
		if open and not door.is_linked():
			continue
		door.set_open(open)


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
