extends Node

## Persistent run data across single-room scene loads.
## Checkpoints are written when entering a SafeRoom.

const DEFAULT_START_ROOM := "res://assets/scenes/rooms/14.tscn"
const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 1

## room_id -> { discovered, cleared, buttons_committed, collected_pickups, dead_residents }
var rooms: Dictionary = {}
## Optional F6 / debug boot: { "scene": String, "door": StringName }
var debug_start: Dictionary = {}
## First room loaded when starting a normal run.
var start_room: String = DEFAULT_START_ROOM
## room_id -> scene path (filled as rooms register / are visited)
var room_scenes: Dictionary = {}
## room_id -> Vector2i map cell
var room_cells: Dictionary = {}
## room_id -> Room.MapShape as int
var room_shapes: Dictionary = {}
## room_id -> Array of { door_id, target_room, target_door_id } for map neighbors
var room_links: Dictionary = {}

## SafeRoom checkpoint: where the player respawns on Continue.
var checkpoint_room_id: String = ""
var checkpoint_scene: String = ""
## Memory ids collected during this run (flushed to disk on SafeRoom enter).
var collected_memories: Array = []


func reset() -> void:
	rooms.clear()
	debug_start.clear()
	room_scenes.clear()
	room_cells.clear()
	room_shapes.clear()
	room_links.clear()
	start_room = DEFAULT_START_ROOM
	checkpoint_room_id = ""
	checkpoint_scene = ""
	collected_memories.clear()


func ensure_room(room_id: StringName) -> Dictionary:
	var key := String(room_id)
	if not rooms.has(key):
		rooms[key] = {
			"discovered": false,
			"cleared": false,
			"buttons_committed": false,
			"collected_pickups": [],
			"dead_residents": [],
		}
	return rooms[key]


func is_discovered(room_id: StringName) -> bool:
	return bool(ensure_room(room_id).get("discovered", false))


func is_cleared(room_id: StringName) -> bool:
	return bool(ensure_room(room_id).get("cleared", false))


func mark_discovered(room_id: StringName) -> void:
	ensure_room(room_id)["discovered"] = true


func mark_cleared(room_id: StringName, cleared: bool = true) -> void:
	ensure_room(room_id)["cleared"] = cleared


func register_room_meta(
	room_id: StringName,
	scene_path: String,
	map_cell: Vector2i,
	map_shape: int = 0
) -> void:
	var key := String(room_id)
	if not scene_path.is_empty():
		room_scenes[key] = scene_path
	room_cells[key] = map_cell
	room_shapes[key] = map_shape


func register_room_links(room_id: StringName, links: Array) -> void:
	room_links[String(room_id)] = links


func consume_debug_start() -> Dictionary:
	var start := debug_start.duplicate(true)
	debug_start.clear()
	return start


# --- Memories ---------------------------------------------------------------

func collect_memory(memory_id: StringName) -> void:
	var key := String(memory_id)
	if key.is_empty() or collected_memories.has(key):
		return
	collected_memories.append(key)


func has_collected_memory(memory_id: StringName) -> bool:
	return collected_memories.has(String(memory_id))


# --- Checkpoint save / load -------------------------------------------------

## Snapshot progress at a SafeRoom and write it to disk.
## Spawn = this safe room's default spawn (empty entry door on Continue).
func save_checkpoint(room: Node = null) -> bool:
	if room != null:
		var room_id_value := String(room.get("room_id"))
		var scene_path_value := String(room.get("scene_file_path"))
		if not room_id_value.is_empty():
			checkpoint_room_id = room_id_value
		if not scene_path_value.is_empty():
			checkpoint_scene = scene_path_value
		elif not checkpoint_room_id.is_empty() and room_scenes.has(checkpoint_room_id):
			checkpoint_scene = String(room_scenes[checkpoint_room_id])
		if room.has_method("save_state"):
			room.call("save_state", self)
		if not checkpoint_room_id.is_empty():
			mark_discovered(StringName(checkpoint_room_id))

	if checkpoint_scene.is_empty():
		push_warning("RunState.save_checkpoint: no checkpoint scene")
		return false

	var payload := {
		"version": SAVE_VERSION,
		"checkpoint_room_id": checkpoint_room_id,
		"checkpoint_scene": checkpoint_scene,
		"rooms": rooms.duplicate(true),
		"collected_memories": collected_memories.duplicate(),
		"room_scenes": room_scenes.duplicate(true),
		"room_cells": _serialize_cells(room_cells),
		"room_shapes": room_shapes.duplicate(true),
		"room_links": room_links.duplicate(true),
	}
	var json := JSON.stringify(payload, "\t")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("RunState.save_checkpoint: cannot write %s" % SAVE_PATH)
		return false
	file.store_string(json)
	print(
		"[Save] Checkpoint @ %s | discovered=%d cleared=%d memories=%d"
		% [
			checkpoint_room_id,
			_count_flag("discovered"),
			_count_flag("cleared"),
			collected_memories.size(),
		]
	)
	return true


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func clear_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


## Load disk checkpoint into this autoload and point start_room at the SafeRoom.
func load_save() -> bool:
	if not has_save():
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("RunState.load_save: cannot read %s" % SAVE_PATH)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_error("RunState.load_save: invalid save data")
		return false
	var data := parsed as Dictionary
	reset()
	checkpoint_room_id = String(data.get("checkpoint_room_id", ""))
	checkpoint_scene = String(data.get("checkpoint_scene", ""))
	_merge_rooms_dict(data.get("rooms", {}))
	_merge_string_array(data.get("collected_memories", []), collected_memories)
	_merge_string_dict(data.get("room_scenes", {}), room_scenes)
	_merge_cells(data.get("room_cells", {}), room_cells)
	_merge_int_dict(data.get("room_shapes", {}), room_shapes)
	_merge_links_dict(data.get("room_links", {}), room_links)

	if checkpoint_scene.is_empty() and not checkpoint_room_id.is_empty():
		checkpoint_scene = String(room_scenes.get(checkpoint_room_id, ""))
	if checkpoint_scene.is_empty():
		push_warning("RunState.load_save: missing checkpoint scene")
		return false
	start_room = checkpoint_scene
	return true


func begin_new_run() -> void:
	reset()
	clear_save()


# --- Serialization helpers --------------------------------------------------

func _serialize_cells(source: Dictionary) -> Dictionary:
	var out := {}
	for key in source.keys():
		var cell: Variant = source[key]
		if cell is Vector2i:
			var v := cell as Vector2i
			out[String(key)] = [v.x, v.y]
		elif cell is Array and (cell as Array).size() >= 2:
			out[String(key)] = [int(cell[0]), int(cell[1])]
	return out


func _merge_rooms_dict(source: Variant) -> void:
	if typeof(source) != TYPE_DICTIONARY:
		return
	for key in (source as Dictionary).keys():
		var entry: Variant = source[key]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var dst := ensure_room(StringName(String(key)))
		var src := entry as Dictionary
		dst["discovered"] = bool(src.get("discovered", false))
		dst["cleared"] = bool(src.get("cleared", false))
		dst["buttons_committed"] = bool(src.get("buttons_committed", false))
		dst["collected_pickups"] = _to_string_array(src.get("collected_pickups", []))
		dst["dead_residents"] = _to_string_array(src.get("dead_residents", []))


func _merge_string_array(source: Variant, dest: Array) -> void:
	dest.clear()
	if typeof(source) != TYPE_ARRAY:
		return
	for item in source as Array:
		var text := String(item)
		if not text.is_empty() and not dest.has(text):
			dest.append(text)


func _merge_string_dict(source: Variant, dest: Dictionary) -> void:
	dest.clear()
	if typeof(source) != TYPE_DICTIONARY:
		return
	for key in (source as Dictionary).keys():
		dest[String(key)] = String(source[key])


func _merge_int_dict(source: Variant, dest: Dictionary) -> void:
	dest.clear()
	if typeof(source) != TYPE_DICTIONARY:
		return
	for key in (source as Dictionary).keys():
		dest[String(key)] = int(source[key])


func _merge_cells(source: Variant, dest: Dictionary) -> void:
	dest.clear()
	if typeof(source) != TYPE_DICTIONARY:
		return
	for key in (source as Dictionary).keys():
		var cell: Variant = source[key]
		if cell is Array and (cell as Array).size() >= 2:
			dest[String(key)] = Vector2i(int(cell[0]), int(cell[1]))
		elif cell is Dictionary:
			dest[String(key)] = Vector2i(int(cell.get("x", 0)), int(cell.get("y", 0)))


func _merge_links_dict(source: Variant, dest: Dictionary) -> void:
	dest.clear()
	if typeof(source) != TYPE_DICTIONARY:
		return
	for key in (source as Dictionary).keys():
		var links: Variant = source[key]
		dest[String(key)] = links if typeof(links) == TYPE_ARRAY else []


func _to_string_array(source: Variant) -> Array:
	var out: Array = []
	if typeof(source) != TYPE_ARRAY:
		return out
	for item in source as Array:
		out.append(String(item))
	return out


func _count_flag(flag: String) -> int:
	var total := 0
	for key in rooms.keys():
		var entry: Variant = rooms[key]
		if typeof(entry) == TYPE_DICTIONARY and bool((entry as Dictionary).get(flag, false)):
			total += 1
	return total
