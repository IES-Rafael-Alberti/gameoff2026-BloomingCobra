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
## Isaac-style map grid cell for this room (top-left of the shape bounding box).
@export var map_cell: Vector2i = Vector2i.ZERO
## Minimap footprint. CELL=1x1, TALL=1x2, WIDE=2x1,
## L_NO_TL=2x2 missing top-left, L_NO_BR=2x2 missing bottom-right.
## CELL=square, TALL/WIDE=elongated, L_*=L rooms (icon rotations differ).
enum MapShape { CELL, TALL, WIDE, L_NO_TL, L_NO_BR, L_NO_BL }
@export var map_shape: MapShape = MapShape.CELL

## Optional: drag Door StaticBodies here. If empty, auto-detects Door nodes
## (including under Switchable/Pesadilla or Switchable/Sueño, like props).
@export var doors: Array[Door] = []
## Grace time after enter before sealing doors.
@export var door_close_delay: float = 0.15

@export_group("Enemy Spawns")
## One entry per EnemySpawnPoint (tree order). Editable on room instances in the Inspector.
## Leave an element empty to keep that marker's default enemy.
@export var spawn_enemy_scenes: Array[PackedScene] = []

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
var _buttons_persist_wired: bool = false
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
	call_deferred("_install_spike_tile_damage")
	call_deferred("_setup_button_unlock")
	call_deferred("_setup_button_persistence")
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
	RunState.register_room_meta(room_id, scene_file_path, map_cell, int(map_shape))


## Absolute map cells occupied by this room's minimap footprint.
func get_map_footprint() -> Array[Vector2i]:
	return map_footprint_for(map_cell, map_shape)


static func map_footprint_for(origin: Vector2i, shape: MapShape) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	match shape:
		MapShape.TALL:
			cells.append(origin)
			cells.append(origin + Vector2i(0, 1))
		MapShape.WIDE:
			cells.append(origin)
			cells.append(origin + Vector2i(1, 0))
		MapShape.L_NO_TL:
			# 2x2 bbox; missing top-left.
			cells.append(origin + Vector2i(1, 0))
			cells.append(origin + Vector2i(0, 1))
			cells.append(origin + Vector2i(1, 1))
		MapShape.L_NO_BR:
			# 2x2 bbox; missing bottom-right.
			cells.append(origin)
			cells.append(origin + Vector2i(1, 0))
			cells.append(origin + Vector2i(0, 1))
		MapShape.L_NO_BL:
			# 2x2 bbox; missing bottom-left (type-3 icon rotated 90° CCW).
			cells.append(origin)
			cells.append(origin + Vector2i(1, 0))
			cells.append(origin + Vector2i(1, 1))
		_:
			cells.append(origin)
	return cells


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
	# Per-door committed unlocks (button-controlled doors only).
	var committed: Array = state.get("committed_doors", [])
	for door in get_button_unlock_doors():
		if door.is_button_unlock_committed() and not committed.has(String(door.door_id)):
			committed.append(String(door.door_id))
	state["committed_doors"] = committed
	state["buttons_committed"] = _button_unlock_committed or bool(state.get("buttons_committed", false))
	# Per-button pressed state (partial puzzle progress), keyed by path relative to the room.
	var buttons_state := {}
	for button in get_buttons():
		if button.permanent_press and button.is_pressed():
			buttons_state[String(get_path_to(button))] = true
	state["buttons"] = buttons_state
	_register_links_with_run_state()
	RunState.register_room_meta(room_id, scene_file_path, map_cell, int(map_shape))


func load_state(_run_state: Node = null) -> void:
	var state := RunState.ensure_room(room_id)
	_discovered = bool(state.get("discovered", false))
	_state_cleared = bool(state.get("cleared", false))
	var committed: Array = state.get("committed_doors", [])
	for door in get_button_unlock_doors():
		if committed.has(String(door.door_id)):
			door.commit_buttons()
	# Restore individually pressed buttons (partial puzzle progress).
	var buttons_state: Dictionary = state.get("buttons", {})
	for button in get_buttons():
		if not button.permanent_press:
			continue
		var key := String(get_path_to(button))
		if buttons_state.has(key) and bool(buttons_state[key]):
			button.force_pressed(false)
	_button_unlock_committed = _are_all_button_doors_committed(get_button_unlock_doors())
	_button_unlock_done = _are_all_button_doors_unlocked(get_button_unlock_doors())


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
## Button-controlled doors are left to their own buttons.
func _seal_unlinked_doors() -> void:
	for door in get_doors():
		if door == null or door.is_linked() or door.has_button_unlock():
			continue
		door.starts_open = false
		door.set_open(false)


func _door_world_center(door: Door) -> Vector2:
	var rect := _collision_global_rect(door)
	if rect.size != Vector2.ZERO:
		return rect.get_center()
	return door.global_position


const _SPIKE_DAMAGE_SCRIPT: GDScript = preload("res://assets/scripts/props/static/spike_tile_damage.gd")

## Attach SpikeTileDamage to any TileMapLayer painted with a spikes tileset,
## even if the designer forgot to set spikes_tile_layer.gd on the node.
func _install_spike_tile_damage() -> void:
	for node in find_children("*", "TileMapLayer", true, false):
		var layer := node as TileMapLayer
		if layer == null or layer.tile_set == null:
			continue
		if not _tile_set_has_spike_data(layer.tile_set):
			continue
		if layer.get_node_or_null("SpikeTileDamage") != null:
			continue
		var helper: Node = _SPIKE_DAMAGE_SCRIPT.new()
		helper.name = "SpikeTileDamage"
		layer.add_child(helper)
		layer.z_index = maxi(layer.z_index, 1)
		if not layer.is_in_group("prop_spikes"):
			layer.add_to_group("prop_spikes")


func _tile_set_has_spike_data(ts: TileSet) -> bool:
	if ts == null:
		return false
	var path := ts.resource_path
	if path.ends_with("tileset_spikes_pesadilla.tres") or path.ends_with("tileset_spikes_vigilia.tres"):
		return true
	for i in ts.get_custom_data_layers_count():
		if ts.get_custom_data_layer_name(i) == &"spikes":
			return true
	return false


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

	var walls_rect := _bounds_from_walls()
	if walls_rect.size != Vector2.ZERO:
		if has_any:
			combined = combined.merge(walls_rect)
		else:
			combined = walls_rect
			has_any = true

	if not has_any:
		return Rect2()
	_cached_bounds = combined
	_bounds_cached = true
	return _cached_bounds


## Outer AABB of Walls/*/CollisionShape2D, if present.
func _bounds_from_walls() -> Rect2:
	var walls := get_node_or_null("Walls") as Node2D
	if walls == null:
		return Rect2()
	var has_any := false
	var min_v := Vector2.ZERO
	var max_v := Vector2.ZERO
	for child in walls.get_children():
		if child is not CollisionShape2D:
			continue
		var shape_node := child as CollisionShape2D
		if shape_node.shape == null:
			continue
		var rect := _collision_shape_global_rect(shape_node)
		if rect.size == Vector2.ZERO:
			continue
		if not has_any:
			min_v = rect.position
			max_v = rect.end
			has_any = true
		else:
			min_v.x = minf(min_v.x, rect.position.x)
			min_v.y = minf(min_v.y, rect.position.y)
			max_v.x = maxf(max_v.x, rect.end.x)
			max_v.y = maxf(max_v.y, rect.end.y)
	if not has_any:
		return Rect2()
	return Rect2(min_v, max_v - min_v)


func _collision_shape_global_rect(shape_node: CollisionShape2D) -> Rect2:
	var shape := shape_node.shape
	if shape is RectangleShape2D:
		var size: Vector2 = (shape as RectangleShape2D).size * shape_node.global_scale.abs()
		return Rect2(shape_node.global_position - size * 0.5, size)
	if shape is CircleShape2D:
		var radius: float = (shape as CircleShape2D).radius * maxf(
			absf(shape_node.global_scale.x), absf(shape_node.global_scale.y)
		)
		var extent := Vector2(radius, radius)
		return Rect2(shape_node.global_position - extent, extent * 2.0)
	return Rect2()


func invalidate_camera_bounds() -> void:
	_bounds_cached = false
	_cached_bounds = Rect2()


## Tile geometry under Switchable modes or a root SafeRoom (non-switchable safe zones).
func _find_bounds_tile_layers() -> Array[Node2D]:
	var result: Array[Node2D] = []
	var sw := get_node_or_null("Switchable")
	if sw != null:
		for mode_name in ["Pesadilla", "Sueño", "Sueno", "SafeRoom"]:
			var mode_root := sw.get_node_or_null(mode_name)
			if mode_root == null:
				continue
			var before := result.size()
			_collect_tile_nodes(mode_root, result)
			if result.size() == before:
				# Mode root itself may be a tile node (legacy layout).
				_collect_tile_nodes_self(mode_root, result)

	# Safe rooms without Switchable keep tiles under a root SafeRoom node.
	var safe_root := get_node_or_null("SafeRoom")
	if safe_root != null:
		_collect_tile_nodes(safe_root, result)
	return result


func _collect_tile_nodes(node: Node, out: Array[Node2D]) -> void:
	_collect_tile_nodes_self(node, out)
	for child in node.get_children():
		_collect_tile_nodes(child, out)


func _collect_tile_nodes_self(node: Node, out: Array[Node2D]) -> void:
	if node is TileMapLayer or node is TileMap:
		if not out.has(node):
			out.append(node as Node2D)


func _tile_node_global_bounds(layer: Node2D) -> Rect2:
	if layer == null or not layer.has_method("get_used_rect"):
		return Rect2()
	var tileset: TileSet = layer.get("tile_set") as TileSet
	if tileset == null:
		return Rect2()

	# Debug TileMap: Switchable disables layers on the inactive mode, and
	# get_used_rect() then returns empty — re-enable briefly to measure.
	var restored_layers: Array[bool] = []
	var tm := layer as TileMap
	if tm != null:
		for i in tm.get_layers_count():
			restored_layers.append(tm.is_layer_enabled(i))
			tm.set_layer_enabled(i, true)

	var used: Rect2i = layer.call("get_used_rect") as Rect2i
	if tm != null:
		for i in restored_layers.size():
			tm.set_layer_enabled(i, restored_layers[i])

	if used.size.x <= 0 or used.size.y <= 0:
		return Rect2()
	var tile_size := Vector2(tileset.tile_size)
	var top_left_local: Vector2 = (layer.call("map_to_local", used.position) as Vector2) - tile_size * 0.5
	var bottom_right_local: Vector2 = (
		(layer.call("map_to_local", used.position + used.size - Vector2i.ONE) as Vector2) + tile_size * 0.5
	)
	var top_left := layer.to_global(top_left_local)
	var bottom_right := layer.to_global(bottom_right_local)
	return Rect2(top_left, bottom_right - top_left).abs()


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
	_collect_doors(self, found)
	return found


func _collect_doors(node: Node, out: Array[Door]) -> void:
	for child in node.get_children():
		if child is Door:
			out.append(child as Door)
		else:
			_collect_doors(child, out)


func get_buttons() -> Array[PropButton]:
	var found: Array[PropButton] = []
	_collect_buttons(self, found)
	return found


func _collect_buttons(node: Node, out: Array[PropButton]) -> void:
	for child in node.get_children():
		if child is PropButton:
			out.append(child as PropButton)
		else:
			_collect_buttons(child, out)


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
		# Button-controlled doors follow their own buttons; bulk open/close skips them.
		if door.has_button_unlock():
			continue
		door.set_open(open)


## Doors that have their own buttons assigned. Each door opens from its own
## buttons; the room only aggregates for locks / persistence / cleared hooks.
func get_button_unlock_doors() -> Array[Door]:
	var out: Array[Door] = []
	for door in get_doors():
		if door != null and door.has_button_unlock():
			out.append(door)
	return out


func _are_all_button_doors_unlocked(doors: Array[Door]) -> bool:
	var counted := 0
	for door in doors:
		# Mode-scoped duplicates (Pesadilla/Sueño) only count while that mode is active.
		if not door.is_mode_present():
			continue
		counted += 1
		if not door.is_button_unlock_done():
			return false
	return counted > 0


func _are_all_button_doors_committed(doors: Array[Door]) -> bool:
	var counted := 0
	for door in doors:
		if not door.is_mode_present():
			continue
		counted += 1
		if not door.is_button_unlock_committed():
			return false
	return counted > 0


func _setup_button_unlock() -> void:
	if _buttons_wired:
		return
	_buttons_wired = true
	for door in get_button_unlock_doors():
		if door.has_signal("button_unlocked") and not door.button_unlocked.is_connected(_on_door_button_unlocked):
			door.button_unlocked.connect(_on_door_button_unlocked)
	# A door may already have unlocked before this deferred setup ran.
	call_deferred("_reconcile_button_unlock")


func _reconcile_button_unlock() -> void:
	if _button_unlock_done:
		return
	if _are_all_button_doors_unlocked(get_button_unlock_doors()):
		_button_unlock_done = true
		on_button_unlock()


func _on_door_button_unlocked() -> void:
	if _button_unlock_done:
		return
	if not _are_all_button_doors_unlocked(get_button_unlock_doors()):
		return
	_button_unlock_done = true
	# Button press arrives during physics flush — react next frame.
	call_deferred("on_button_unlock")


## Persist permanent buttons the moment they are pressed, so the press survives
## death (the room is not re-saved on exit until then).
func _setup_button_persistence() -> void:
	if _buttons_persist_wired:
		return
	_buttons_persist_wired = true
	for button in get_buttons():
		if not button.permanent_press:
			continue
		if button.has_signal("pressed") and not button.pressed.is_connected(_on_button_pressed_persist):
			button.pressed.connect(_on_button_pressed_persist)


func _on_button_pressed_persist() -> void:
	# Deferred: pressed arrives during a physics callback.
	call_deferred("save_state", RunState)


## Call when leaving the room successfully so pressed buttons stay down forever.
## Commits every door whose buttons are currently pressed.
func commit_unlock_buttons() -> void:
	var doors := get_button_unlock_doors()
	if doors.is_empty():
		return
	for door in doors:
		if door.is_button_unlock_done() or door.are_buttons_satisfied():
			door.commit_buttons()
	_button_unlock_committed = _are_all_button_doors_committed(doors)
	_button_unlock_done = _are_all_button_doors_unlocked(doors)


## Call on void respawn / failed attempt — undoes uncommitted button progress.
func reset_unlock_buttons() -> void:
	var doors := get_button_unlock_doors()
	if doors.is_empty():
		return
	for door in doors:
		door.reset_buttons()
	_button_unlock_done = _are_all_button_doors_unlocked(doors)
	_button_unlock_committed = _are_all_button_doors_committed(doors)


## Called once all button-controlled doors are unlocked. Override in room types
## to clear locks / mark the room cleared.
func on_button_unlock() -> void:
	cancel_pending_door_close()


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
