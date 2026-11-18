extends CanvasLayer

## Fullscreen Isaac-style map toggled with Tab. Does not pause the game.

@export var icon_scale: float = 4.0
## StartingRoom icon multiplier relative to normal room icons.
@export var start_room_scale: float = 1.5
## Extra pixels between normal room icons (after scale).
@export var cell_gap: float = 8.0
@export var dim_alpha: float = 0.28
@export var rooms_modulate: Color = Color(1, 1, 1, 1)
@export var current_modulate: Color = Color(1.0, 1.0, 0.55, 1.0)

@export var discovered_texture: Texture2D
@export var undiscovered_texture: Texture2D
@export var current_texture: Texture2D

const ROOMS_DIR := "res://assets/scenes/rooms/"

var _root: Control
var _dim: ColorRect
var _rooms_layer: Control
var _open: bool = false
var _wired: bool = false
var _grid: Dictionary = {} # room_id(String) -> Vector2i
var _scene_by_id: Dictionary = {} # room_id -> scene path
var _links_by_id: Dictionary = {} # room_id -> Array of link dicts
var _icons: Dictionary = {} # room_id -> TextureRect


func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_textures()
	_build_ui()
	visible = false
	_open = false
	call_deferred("_setup_rooms")


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("toggle_map") or event.is_echo():
		return
	_set_open(not _open)
	get_viewport().set_input_as_handled()


func refresh() -> void:
	if not _wired:
		_setup_rooms()
	_rebuild_icons()


func _set_open(open: bool) -> void:
	_open = open
	visible = open
	if open:
		refresh()


func _ensure_textures() -> void:
	if discovered_texture == null:
		discovered_texture = load("res://assets/sprittesheets/HUD/placeholders/roomDiscovered.png") as Texture2D
	if undiscovered_texture == null:
		undiscovered_texture = load("res://assets/sprittesheets/HUD/placeholders/roomUndiscovered.png") as Texture2D
	if current_texture == null:
		current_texture = load("res://assets/sprittesheets/HUD/placeholders/map.png") as Texture2D


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_root)

	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0, 0, 0, dim_alpha)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dim)

	_rooms_layer = Control.new()
	_rooms_layer.name = "RoomsLayer"
	_rooms_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rooms_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rooms_layer.modulate = rooms_modulate
	_rooms_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_root.add_child(_rooms_layer)


func _setup_rooms() -> void:
	_scan_room_catalog()
	_merge_run_state()
	_wire_room_signals()
	_wired = true
	if _open:
		_rebuild_icons()


func _scan_room_catalog() -> void:
	_grid.clear()
	_scene_by_id.clear()
	_links_by_id.clear()
	_scan_dir(ROOMS_DIR)


func _scan_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			if file_name != "." and file_name != ".." and not file_name.begins_with("."):
				_scan_dir(path.path_join(file_name))
		elif file_name.ends_with(".tscn") and not file_name.ends_with(".tscn.tscn"):
			# Skip the shared enemy-test base; use its inherited instances instead.
			if file_name == "habitacion_enemy_test.tscn":
				file_name = dir.get_next()
				continue
			_ingest_room_scene(path.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()


func _ingest_room_scene(scene_path: String) -> void:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	var state := packed.get_state()
	if state == null or state.get_node_count() <= 0:
		return
	# Root props live on node 0.
	var room_id := StringName(scene_path.get_file().get_basename())
	var map_cell := Vector2i.ZERO
	var has_cell := false
	for i in state.get_node_property_count(0):
		var prop_name := String(state.get_node_property_name(0, i))
		var value: Variant = state.get_node_property_value(0, i)
		if prop_name == "room_id" and value is StringName and value != &"":
			room_id = value
		elif prop_name == "room_id" and value is String and not String(value).is_empty():
			room_id = StringName(value)
		elif prop_name == "map_cell" and value is Vector2i:
			map_cell = value
			has_cell = true

	var key := String(room_id)
	_scene_by_id[key] = scene_path
	if has_cell:
		_grid[key] = map_cell
	else:
		_grid[key] = Vector2i.ZERO

	var links: Array = []
	for node_idx in state.get_node_count():
		var node_name := String(state.get_node_name(node_idx))
		var type_name := String(state.get_node_type(node_idx))
		var is_door := type_name == "StaticBody2D" or node_name.begins_with("Door")
		if not is_door:
			continue
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
				var script_path := String((pval as Script).resource_path)
				if script_path.ends_with("door.gd"):
					looks_like_door = true
		if not looks_like_door:
			continue
		if target_room.is_empty():
			continue
		links.append({
			"door_id": door_id,
			"target_room": target_room,
			"target_door_id": target_door_id,
		})
	_links_by_id[key] = links
	RunState.register_room_meta(room_id, scene_path, _grid[key])
	RunState.register_room_links(room_id, links)


func _merge_run_state() -> void:
	for key in RunState.room_cells.keys():
		_grid[String(key)] = RunState.room_cells[key]
	for key in RunState.room_scenes.keys():
		_scene_by_id[String(key)] = RunState.room_scenes[key]
	for key in RunState.room_links.keys():
		_links_by_id[String(key)] = RunState.room_links[key]


func _wire_room_signals() -> void:
	var manager := get_tree().get_first_node_in_group("room_manager")
	if manager != null and manager.has_signal("room_changed"):
		if not manager.room_changed.is_connected(_on_room_changed):
			manager.room_changed.connect(_on_room_changed)
	for node in get_tree().get_nodes_in_group("rooms"):
		if node is Room:
			_wire_one_room(node as Room)


func _wire_one_room(room: Room) -> void:
	if not room.discovered.is_connected(_on_room_discovered):
		room.discovered.connect(_on_room_discovered)
	var entered_cb := _on_room_entered.bind(room)
	if not room.player_entered.is_connected(entered_cb):
		room.player_entered.connect(entered_cb)


func _on_room_changed(_previous: Room, next: Room) -> void:
	if next != null:
		_wire_one_room(next)
		_merge_run_state()
	if _open:
		_rebuild_icons()


func _on_room_discovered() -> void:
	if _open:
		_rebuild_icons()


func _on_room_entered(_player: Node2D, _room: Room) -> void:
	if _open:
		_rebuild_icons()


func _rebuild_icons() -> void:
	if _rooms_layer == null:
		return
	_merge_run_state()
	if _grid.is_empty():
		_scan_room_catalog()

	for child in _rooms_layer.get_children():
		child.queue_free()
	_icons.clear()

	var visible_ids: Array[String] = _collect_visible_room_ids()
	if visible_ids.is_empty():
		return

	var min_g := Vector2i(999999, 999999)
	var max_g := Vector2i(-999999, -999999)
	for id in visible_ids:
		var g: Vector2i = _grid.get(id, Vector2i.ZERO)
		min_g.x = mini(min_g.x, g.x)
		min_g.y = mini(min_g.y, g.y)
		max_g.x = maxi(max_g.x, g.x)
		max_g.y = maxi(max_g.y, g.y)

	var base_tex_size := Vector2(16, 8)
	if discovered_texture != null:
		base_tex_size = Vector2(discovered_texture.get_width(), discovered_texture.get_height())
	var icon_size := base_tex_size * icon_scale
	var start_size := icon_size * start_room_scale
	var step := icon_size + Vector2(cell_gap, cell_gap)

	var grid_w := float(max_g.x - min_g.x) * step.x + icon_size.x
	var grid_h := float(max_g.y - min_g.y) * step.y + icon_size.y
	var vp := get_viewport().get_visible_rect().size
	var origin := (vp - Vector2(grid_w, grid_h)) * 0.5
	origin = Vector2(roundf(origin.x), roundf(origin.y))

	var current_id := _find_current_room_id()

	for id in visible_ids:
		var g: Vector2i = _grid.get(id, Vector2i.ZERO)
		var cell_origin := origin + Vector2(
			float(g.x - min_g.x) * step.x,
			float(g.y - min_g.y) * step.y
		)
		var is_start := id == "habitacion_start"
		var draw_size := start_size if is_start else icon_size
		var icon_pos := cell_origin + (icon_size - draw_size) * 0.5
		icon_pos = Vector2(roundf(icon_pos.x), roundf(icon_pos.y))

		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.custom_minimum_size = draw_size
		icon.size = draw_size
		icon.position = icon_pos

		var is_current := id == current_id
		if is_start and current_texture != null:
			icon.texture = current_texture
			if is_current:
				icon.modulate = current_modulate
		elif is_current and current_texture != null:
			icon.texture = current_texture
			icon.modulate = current_modulate
		elif RunState.is_discovered(StringName(id)):
			icon.texture = discovered_texture
		else:
			icon.texture = undiscovered_texture

		_rooms_layer.add_child(icon)
		_icons[id] = icon


func _collect_visible_room_ids() -> Array[String]:
	var result: Array[String] = []
	var discovered: Array[String] = []

	for id in _grid.keys():
		var key := String(id)
		if RunState.is_discovered(StringName(key)):
			discovered.append(key)
			result.append(key)

	# Reveal undiscovered rooms linked from a discovered room.
	for id in _grid.keys():
		var key := String(id)
		if RunState.is_discovered(StringName(key)):
			continue
		for d in discovered:
			if _rooms_linked(d, key):
				result.append(key)
				break
	return result


func _rooms_linked(a_id: String, b_id: String) -> bool:
	var b_scene: String = String(_scene_by_id.get(b_id, ""))
	var links: Array = _links_by_id.get(a_id, [])
	for link in links:
		if typeof(link) != TYPE_DICTIONARY:
			continue
		var target: String = String(link.get("target_room", ""))
		if target.is_empty():
			continue
		if not b_scene.is_empty() and target == b_scene:
			return true
		var target_id := target.get_file().get_basename()
		if target_id == b_id:
			return true
		for id in _scene_by_id.keys():
			if String(_scene_by_id[id]) == target and String(id) == b_id:
				return true
	return false


func _find_current_room_id() -> String:
	var manager := get_tree().get_first_node_in_group("room_manager")
	if manager != null and "current_room" in manager and manager.current_room is Room:
		var room := manager.current_room as Room
		return String(room.room_id)
	return ""
