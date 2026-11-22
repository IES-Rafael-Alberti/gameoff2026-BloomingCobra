extends Node

## Persistent run data across single-room scene loads.

const DEFAULT_START_ROOM := "res://assets/scenes/rooms/habitacion_start.tscn"

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


func reset() -> void:
	rooms.clear()
	debug_start.clear()
	room_scenes.clear()
	room_cells.clear()
	room_shapes.clear()
	room_links.clear()
	start_room = DEFAULT_START_ROOM


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
