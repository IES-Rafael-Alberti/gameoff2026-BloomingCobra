@tool
extends EditorScript

## Run from the Script Editor: File → Run (Ctrl+Shift+X).
## Validates door links, room_id uniqueness, and map_cell uniqueness.

const ROOMS_DIR := "res://assets/scenes/rooms/"


func _run() -> void:
	var scenes: PackedStringArray = []
	_collect_scenes(ROOMS_DIR, scenes)
	var room_ids: Dictionary = {} # id -> path
	var map_cells: Dictionary = {} # Vector2i -> path
	var door_index: Dictionary = {} # path -> { door_id -> true }
	var links: Array = [] # { from_path, door_id, target_room, target_door_id }

	print("=== validate_room_links: %d scenes ===" % scenes.size())
	for path in scenes:
		var data := _read_scene(path)
		if data.is_empty():
			continue
		var room_id: String = String(data.get("room_id", path.get_file().get_basename()))
		var map_cell: Vector2i = data.get("map_cell", Vector2i.ZERO)
		if room_ids.has(room_id):
			push_warning("Duplicate room_id '%s': %s and %s" % [room_id, room_ids[room_id], path])
		else:
			room_ids[room_id] = path
		if map_cells.has(map_cell):
			push_warning("Duplicate map_cell %s: %s and %s" % [map_cell, map_cells[map_cell], path])
		else:
			map_cells[map_cell] = path

		var doors: Dictionary = data.get("doors", {})
		door_index[path] = doors
		for door_id in doors.keys():
			var info: Dictionary = doors[door_id]
			var target: String = String(info.get("target_room", ""))
			if target.is_empty():
				continue
			links.append({
				"from_path": path,
				"door_id": door_id,
				"target_room": target,
				"target_door_id": info.get("target_door_id", &""),
			})

	var errors := 0
	for link in links:
		var target_path: String = String(link["target_room"])
		if not ResourceLoader.exists(target_path):
			push_error("Missing target_room %s (from %s door %s)" % [
				target_path, link["from_path"], link["door_id"]
			])
			errors += 1
			continue
		var target_doors: Dictionary = door_index.get(target_path, {})
		# Inherited scenes may not re-list base doors; fall back to loading.
		if target_doors.is_empty():
			target_doors = _read_scene(target_path).get("doors", {})
			door_index[target_path] = target_doors
		var target_door_id: StringName = link["target_door_id"]
		if target_door_id != &"" and not target_doors.has(String(target_door_id)):
			# Also accept lowercase node-name fallbacks present in base scenes.
			var found := false
			for did in target_doors.keys():
				if String(did) == String(target_door_id):
					found = true
					break
			if not found:
				push_error("target_door_id '%s' missing in %s (from %s door %s)" % [
					target_door_id, target_path, link["from_path"], link["door_id"]
				])
				errors += 1
				continue

		# Reciprocal check.
		var reciprocal := false
		for back_id in target_doors.keys():
			var back: Dictionary = target_doors[back_id]
			var back_target: String = String(back.get("target_room", ""))
			if back_target != String(link["from_path"]):
				continue
			var back_door: StringName = back.get("target_door_id", &"")
			if back_door == &"" or String(back_door) == String(link["door_id"]):
				reciprocal = true
				break
		if not reciprocal:
			push_warning("Non-reciprocal link: %s.%s -> %s.%s" % [
				link["from_path"].get_file(), link["door_id"],
				target_path.get_file(), link["target_door_id"]
			])

	print("=== validate_room_links done (%d hard errors) ===" % errors)


func _collect_scenes(path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			if file_name != "." and file_name != ".." and not file_name.begins_with("."):
				_collect_scenes(path.path_join(file_name), out)
		elif file_name.ends_with(".tscn") and not file_name.ends_with(".tscn.tscn"):
			if file_name != "habitacion_enemy_test.tscn":
				out.append(path.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()


func _read_scene(scene_path: String) -> Dictionary:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return {}
	var state := packed.get_state()
	if state == null or state.get_node_count() <= 0:
		return {}

	var room_id := StringName(scene_path.get_file().get_basename())
	var map_cell := Vector2i.ZERO
	for i in state.get_node_property_count(0):
		var prop_name := String(state.get_node_property_name(0, i))
		var value: Variant = state.get_node_property_value(0, i)
		if prop_name == "room_id":
			if value is StringName and value != &"":
				room_id = value
			elif value is String and not String(value).is_empty():
				room_id = StringName(value)
		elif prop_name == "map_cell" and value is Vector2i:
			map_cell = value

	var doors: Dictionary = {}
	# If this is an inherited scene, merge base doors first.
	var base_path := _inherited_base_path(state)
	if not base_path.is_empty() and base_path != scene_path:
		var base_data := _read_scene(base_path)
		doors = base_data.get("doors", {}).duplicate(true)

	for node_idx in state.get_node_count():
		var node_name := String(state.get_node_name(node_idx))
		var door_id := StringName(node_name.to_lower())
		var target_room := ""
		var target_door_id: StringName = &""
		var looks_like_door := false
		for p in state.get_node_property_count(node_idx):
			var pname := String(state.get_node_property_name(node_idx, p))
			var pval: Variant = state.get_node_property_value(node_idx, p)
			if pname == "door_id":
				looks_like_door = true
				if pval is StringName:
					door_id = pval
				elif pval is String and not String(pval).is_empty():
					door_id = StringName(pval)
			elif pname == "target_room" and pval is String:
				looks_like_door = true
				target_room = pval
			elif pname == "target_door_id":
				looks_like_door = true
				if pval is StringName:
					target_door_id = pval
				elif pval is String:
					target_door_id = StringName(pval)
			elif pname == "script" and pval is Script:
				if String((pval as Script).resource_path).ends_with("door.gd"):
					looks_like_door = true
		if not looks_like_door and not node_name.begins_with("Door"):
			continue
		var key := String(door_id)
		var existing: Dictionary = doors.get(key, {})
		if not target_room.is_empty():
			existing["target_room"] = target_room
		if target_door_id != &"":
			existing["target_door_id"] = target_door_id
		doors[key] = existing

	return {
		"room_id": room_id,
		"map_cell": map_cell,
		"doors": doors,
	}


func _inherited_base_path(state: SceneState) -> String:
	# Node 0 instance path when scene is inherited.
	if state.get_node_count() <= 0:
		return ""
	var instance := state.get_node_instance(0)
	if instance == null:
		return ""
	return instance.resource_path
