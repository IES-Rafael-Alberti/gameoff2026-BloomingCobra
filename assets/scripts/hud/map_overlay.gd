extends CanvasLayer

## Fullscreen Isaac-style map toggled with Tab. Does not pause the game.

@export var icon_scale: float = 4.0
## StartingRoom icon multiplier relative to normal room icons.
@export var start_room_scale: float = 1.5
## Extra pixels between normal room icons (after scale).
@export var cell_gap: float = 8.0
@export var dim_alpha: float = 0.55
## Extra pixels around the room grid for the adaptive panel.
@export var panel_padding: float = 20.0
@export var marker_scale: float = 3.0
## Thin axis for tall/wide/L arms (fraction of normal cell width).
@export var elongated_thin_factor: float = 0.5
## 9-slice border thickness for rectangular room icons.
@export var room_icon_slice: int = 1
## Stroke width for polygon L-room outlines (screen px).
@export var room_poly_border_width: float = 2.0
@export var rooms_modulate: Color = Color(1, 1, 1, 1)
@export var current_modulate: Color = Color(1.0, 1.0, 0.55, 1.0)
@export var room_fill_color: Color = Color(1, 1, 1, 1)
@export var room_border_color: Color = Color(0, 0, 0, 1)

@export var discovered_texture: Texture2D
@export var undiscovered_texture: Texture2D
@export var panel_texture: Texture2D
@export var player_marker_texture: Texture2D
@export var connector_texture: Texture2D

const ROOMS_DIR := "res://assets/scenes/rooms/"
const PANEL_SLICE := 6

var _root: Control
var _dim: ColorRect
var _panel: NinePatchRect
var _connectors_layer: Control
var _rooms_layer: Control
var _marker_layer: Control
var _player_marker: TextureRect
var _open: bool = false
var _wired: bool = false
var _grid: Dictionary = {} # room_id(String) -> Vector2i
var _shapes_by_id: Dictionary = {} # room_id -> Room.MapShape as int
var _scene_by_id: Dictionary = {} # room_id -> scene path
var _links_by_id: Dictionary = {} # room_id -> Array of link dicts
var _icons: Dictionary = {} # room_id -> Array[Control]


func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("map_overlay")
	_ensure_textures()
	_build_ui()
	visible = false
	_open = false
	call_deferred("_setup_rooms")


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("toggle_map") or event.is_echo():
		return
	# Don't open the map while the game is paused.
	if get_tree().paused and not _open:
		return
	_set_open(not _open)
	get_viewport().set_input_as_handled()


func refresh() -> void:
	if not _wired:
		_setup_rooms()
	_rebuild_icons()


func close_overlay() -> void:
	_set_open(false)


func is_open() -> bool:
	return _open


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
	if panel_texture == null:
		panel_texture = load("res://assets/sprittesheets/HUD/placeholders/mapPanel.png") as Texture2D
	if player_marker_texture == null:
		player_marker_texture = load("res://assets/sprittesheets/HUD/placeholders/mapPlayer.png") as Texture2D
	if connector_texture == null:
		connector_texture = load("res://assets/sprittesheets/HUD/placeholders/mapConnector.png") as Texture2D


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

	_panel = NinePatchRect.new()
	_panel.name = "Panel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_panel.texture = panel_texture
	_panel.patch_margin_left = PANEL_SLICE
	_panel.patch_margin_top = PANEL_SLICE
	_panel.patch_margin_right = PANEL_SLICE
	_panel.patch_margin_bottom = PANEL_SLICE
	_panel.visible = false
	_root.add_child(_panel)

	_connectors_layer = Control.new()
	_connectors_layer.name = "ConnectorsLayer"
	_connectors_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_connectors_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_connectors_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_root.add_child(_connectors_layer)

	_rooms_layer = Control.new()
	_rooms_layer.name = "RoomsLayer"
	_rooms_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rooms_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rooms_layer.modulate = rooms_modulate
	_rooms_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_root.add_child(_rooms_layer)

	_marker_layer = Control.new()
	_marker_layer.name = "MarkerLayer"
	_marker_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_marker_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_root.add_child(_marker_layer)

	_player_marker = TextureRect.new()
	_player_marker.name = "PlayerMarker"
	_player_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_marker.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_player_marker.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_player_marker.stretch_mode = TextureRect.STRETCH_SCALE
	_player_marker.texture = player_marker_texture
	_player_marker.visible = false
	_marker_layer.add_child(_player_marker)


func _layout_panel_to_grid(origin: Vector2, grid_size: Vector2) -> void:
	if _panel == null:
		return
	if panel_texture == null or grid_size.x <= 0.0 or grid_size.y <= 0.0:
		_panel.visible = false
		return
	var pad := maxf(panel_padding, 0.0)
	var panel_size := Vector2(
		roundf(grid_size.x + pad * 2.0),
		roundf(grid_size.y + pad * 2.0)
	)
	_panel.size = panel_size
	_panel.position = Vector2(
		roundf(origin.x - pad),
		roundf(origin.y - pad)
	)
	_panel.visible = true


func _setup_rooms() -> void:
	_scan_room_catalog()
	_merge_run_state()
	_wire_room_signals()
	_wired = true
	if _open:
		_rebuild_icons()


func _scan_room_catalog() -> void:
	_grid.clear()
	_shapes_by_id.clear()
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
	var map_shape := 0
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
		elif prop_name == "map_shape":
			map_shape = int(value)

	var key := String(room_id)
	_scene_by_id[key] = scene_path
	_shapes_by_id[key] = map_shape
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
	RunState.register_room_meta(room_id, scene_path, _grid[key], map_shape)
	RunState.register_room_links(room_id, links)


func _merge_run_state() -> void:
	for key in RunState.room_cells.keys():
		_grid[String(key)] = RunState.room_cells[key]
	for key in RunState.room_shapes.keys():
		_shapes_by_id[String(key)] = int(RunState.room_shapes[key])
	for key in RunState.room_scenes.keys():
		_scene_by_id[String(key)] = RunState.room_scenes[key]
	for key in RunState.room_links.keys():
		_links_by_id[String(key)] = RunState.room_links[key]


func _footprint_for(room_key: String) -> Array[Vector2i]:
	var origin: Vector2i = _grid.get(room_key, Vector2i.ZERO)
	var shape := int(_shapes_by_id.get(room_key, 0)) as Room.MapShape
	return Room.map_footprint_for(origin, shape)


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
	if _rooms_layer == null or _connectors_layer == null:
		return
	_merge_run_state()
	if _grid.is_empty():
		_scan_room_catalog()

	for child in _rooms_layer.get_children():
		child.queue_free()
	for child in _connectors_layer.get_children():
		child.queue_free()
	_icons.clear()

	var visible_ids: Array[String] = _collect_visible_room_ids()
	if visible_ids.is_empty():
		if _player_marker != null:
			_player_marker.visible = false
		if _panel != null:
			_panel.visible = false
		return

	var min_g := Vector2i(999999, 999999)
	var max_g := Vector2i(-999999, -999999)
	for id in visible_ids:
		for cell in _footprint_for(id):
			min_g.x = mini(min_g.x, cell.x)
			min_g.y = mini(min_g.y, cell.y)
			max_g.x = maxi(max_g.x, cell.x)
			max_g.y = maxi(max_g.y, cell.y)

	var base_tex_size := Vector2(16, 8)
	if discovered_texture != null:
		base_tex_size = Vector2(discovered_texture.get_width(), discovered_texture.get_height())
	var icon_size := base_tex_size * icon_scale
	var start_size := icon_size * start_room_scale
	var step := icon_size + Vector2(cell_gap, cell_gap)

	# Local visuals per room, then center content.
	var local_visuals: Dictionary = {} # room_id -> { bounds, rects?, polygon?, marker }
	var content := Rect2()
	var has_content := false
	for id in visible_ids:
		var visual := _local_room_visual(id, min_g, icon_size, step)
		if id == "habitacion_start":
			visual = _scale_visual_around_center(visual, start_room_scale)
		local_visuals[id] = visual
		var bounds: Rect2 = visual["bounds"]
		if has_content:
			content = content.merge(bounds)
		else:
			content = bounds
			has_content = true

	var vp := get_viewport().get_visible_rect().size
	var offset := (vp - content.size) * 0.5 - content.position
	offset = Vector2(roundf(offset.x), roundf(offset.y))

	_layout_panel_to_grid(content.position + offset, content.size)

	var current_id := _find_current_room_id()
	var marker_points: Dictionary = {} # room_id -> Vector2 screen center for marker

	_draw_connectors(visible_ids, offset, min_g, icon_size, step)

	for id in visible_ids:
		var visual: Dictionary = local_visuals[id]
		var is_current := id == current_id
		var tex := discovered_texture
		if not RunState.is_discovered(StringName(id)) and not is_current:
			tex = undiscovered_texture
		var icons: Array[Control] = []
		if visual.has("polygon"):
			var poly: PackedVector2Array = visual["polygon"]
			var shifted := PackedVector2Array()
			for p in poly:
				shifted.append(p + offset)
			var icon := _make_polygon_room_icon(shifted, is_current)
			_rooms_layer.add_child(icon)
			icons.append(icon)
		else:
			var parts: Array = visual.get("rects", [])
			for part in parts:
				var rect: Rect2 = part
				var icon := _make_room_icon(rect.position + offset, rect.size, tex, is_current)
				_rooms_layer.add_child(icon)
				icons.append(icon)
		_icons[id] = icons
		var marker_local: Vector2 = visual.get("marker", (visual["bounds"] as Rect2).get_center())
		marker_points[id] = marker_local + offset

	_place_player_marker(current_id, marker_points)


func _cell_local_pos(cell: Vector2i, min_g: Vector2i, step: Vector2) -> Vector2:
	return Vector2(
		float(cell.x - min_g.x) * step.x,
		float(cell.y - min_g.y) * step.y
	)


func _local_room_visual(
	room_key: String,
	min_g: Vector2i,
	icon_size: Vector2,
	step: Vector2
) -> Dictionary:
	## Returns { bounds: Rect2, marker: Vector2, rects?: Array[Rect2], polygon?: PackedVector2Array }
	var origin: Vector2i = _grid.get(room_key, Vector2i.ZERO)
	var shape := int(_shapes_by_id.get(room_key, 0)) as Room.MapShape
	# Square cell basis on the SHORT side of the 16x8 tile so elongated arms stay compact.
	var cell := minf(icon_size.x, icon_size.y)
	var thin := cell * elongated_thin_factor
	var long := cell * 2.0 + cell_gap
	var bbox := _cell_local_pos(origin, min_g, step)
	# Center elongated shapes inside the (possibly non-square) grid cell span.
	var span := Vector2(
		icon_size.x * 2.0 + cell_gap,
		icon_size.y * 2.0 + cell_gap
	)

	match shape:
		Room.MapShape.TALL:
			var x := bbox.x + (icon_size.x - thin) * 0.5
			var y := bbox.y + (span.y - long) * 0.5
			var rect := Rect2(Vector2(x, y), Vector2(thin, long))
			var tall_rects: Array[Rect2] = [rect]
			return {"bounds": rect, "rects": tall_rects, "marker": rect.get_center()}
		Room.MapShape.WIDE:
			var x := bbox.x + (span.x - long) * 0.5
			var y := bbox.y + (icon_size.y - thin) * 0.5
			var rect := Rect2(Vector2(x, y), Vector2(long, thin))
			var wide_rects: Array[Rect2] = [rect]
			return {"bounds": rect, "rects": wide_rects, "marker": rect.get_center()}
		Room.MapShape.L_NO_TL:
			# 2x2 square missing top-left quadrant (full cell thickness, short side).
			var s := cell
			var side := s * 2.0
			var origin_px := Vector2(
				bbox.x + (span.x - side) * 0.5,
				bbox.y + (span.y - side) * 0.5
			)
			var poly := PackedVector2Array([
				Vector2(origin_px.x + s, origin_px.y),
				Vector2(origin_px.x + side, origin_px.y),
				Vector2(origin_px.x + side, origin_px.y + side),
				Vector2(origin_px.x, origin_px.y + side),
				Vector2(origin_px.x, origin_px.y + s),
				Vector2(origin_px.x + s, origin_px.y + s),
			])
			var bounds := Rect2(origin_px, Vector2(side, side))
			var elbow := Vector2(origin_px.x + s * 1.5, origin_px.y + s * 1.5)
			return {"bounds": bounds, "polygon": poly, "marker": elbow}
		Room.MapShape.L_NO_BR:
			# 2x2 square missing bottom-right quadrant.
			var s := cell
			var side := s * 2.0
			var origin_px := Vector2(
				bbox.x + (span.x - side) * 0.5,
				bbox.y + (span.y - side) * 0.5
			)
			var poly := PackedVector2Array([
				Vector2(origin_px.x, origin_px.y),
				Vector2(origin_px.x + side, origin_px.y),
				Vector2(origin_px.x + side, origin_px.y + s),
				Vector2(origin_px.x + s, origin_px.y + s),
				Vector2(origin_px.x + s, origin_px.y + side),
				Vector2(origin_px.x, origin_px.y + side),
			])
			var bounds := Rect2(origin_px, Vector2(side, side))
			var elbow := Vector2(origin_px.x + s * 0.5, origin_px.y + s * 0.5)
			return {"bounds": bounds, "polygon": poly, "marker": elbow}
		_:
			var rect := Rect2(bbox, icon_size)
			var cell_rects: Array[Rect2] = [rect]
			return {"bounds": rect, "rects": cell_rects, "marker": rect.get_center()}


func _scale_visual_around_center(visual: Dictionary, scale_factor: float) -> Dictionary:
	if is_equal_approx(scale_factor, 1.0):
		return visual
	var bounds: Rect2 = visual["bounds"]
	var center := bounds.get_center()
	var out := visual.duplicate(true)
	out["bounds"] = Rect2(
		center + (bounds.position - center) * scale_factor,
		bounds.size * scale_factor
	)
	if visual.has("rects"):
		var scaled_rects: Array[Rect2] = []
		for item in visual["rects"]:
			var rect: Rect2 = item
			var new_size := rect.size * scale_factor
			var new_center := center + (rect.get_center() - center) * scale_factor
			scaled_rects.append(Rect2(new_center - new_size * 0.5, new_size))
		out["rects"] = scaled_rects
	if visual.has("polygon"):
		var scaled_poly := PackedVector2Array()
		for p in visual["polygon"]:
			scaled_poly.append(center + (p - center) * scale_factor)
		out["polygon"] = scaled_poly
	if visual.has("marker"):
		var marker: Vector2 = visual["marker"]
		out["marker"] = center + (marker - center) * scale_factor
	return out


func _make_room_icon(pos: Vector2, size: Vector2, tex: Texture2D, is_current: bool) -> Control:
	# NinePatch keeps the 1px art border from scaling into thick slabs on tall/wide icons.
	var icon := NinePatchRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.texture = tex
	var slice := maxi(room_icon_slice, 1)
	icon.patch_margin_left = slice
	icon.patch_margin_top = slice
	icon.patch_margin_right = slice
	icon.patch_margin_bottom = slice
	icon.custom_minimum_size = size
	icon.size = size
	icon.position = Vector2(roundf(pos.x), roundf(pos.y))
	if is_current:
		icon.modulate = current_modulate
	return icon


func _make_polygon_room_icon(points: PackedVector2Array, is_current: bool) -> Control:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for p in points:
		bounds = bounds.expand(p)
	# Pad for stroke so the border isn't clipped.
	var pad := room_poly_border_width
	bounds = bounds.grow(pad)

	var icon := _MapPolyIcon.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2(roundf(bounds.position.x), roundf(bounds.position.y))
	icon.size = bounds.size
	icon.fill = room_fill_color
	icon.border = room_border_color
	icon.border_width = room_poly_border_width
	for p in points:
		icon.points.append(p - bounds.position)
	if is_current:
		icon.modulate = current_modulate
	return icon


class _MapPolyIcon extends Control:
	var points: PackedVector2Array = PackedVector2Array()
	var fill: Color = Color.WHITE
	var border: Color = Color.BLACK
	var border_width: float = 2.0

	func _draw() -> void:
		if points.size() < 3:
			return
		draw_colored_polygon(points, fill)
		var closed := points.duplicate()
		closed.append(points[0])
		draw_polyline(closed, border, border_width, true)


func _draw_connectors(
	visible_ids: Array[String],
	origin: Vector2,
	min_g: Vector2i,
	icon_size: Vector2,
	step: Vector2
) -> void:
	if connector_texture == null:
		return

	var visible_set: Dictionary = {}
	for id in visible_ids:
		visible_set[id] = true

	var drawn: Dictionary = {} # "x1,y1|x2,y2" -> true

	for id in visible_ids:
		var links: Array = _links_by_id.get(id, [])
		for link in links:
			if typeof(link) != TYPE_DICTIONARY:
				continue
			var target_id := _resolve_link_target_id(link)
			if target_id.is_empty() or not visible_set.has(target_id):
				continue
			for from_cell in _footprint_for(id):
				for to_cell in _footprint_for(target_id):
					var delta := to_cell - from_cell
					if absi(delta.x) + absi(delta.y) != 1:
						continue
					var a := from_cell
					var b := to_cell
					if a.x > b.x or (a.x == b.x and a.y > b.y):
						var tmp := a
						a = b
						b = tmp
					var key := "%d,%d|%d,%d" % [a.x, a.y, b.x, b.y]
					if drawn.has(key):
						continue
					drawn[key] = true

					var from_center := origin + Vector2(
						float(from_cell.x - min_g.x) * step.x + icon_size.x * 0.5,
						float(from_cell.y - min_g.y) * step.y + icon_size.y * 0.5
					)
					var to_center := origin + Vector2(
						float(to_cell.x - min_g.x) * step.x + icon_size.x * 0.5,
						float(to_cell.y - min_g.y) * step.y + icon_size.y * 0.5
					)
					_add_connector(from_center, to_center, delta)


func _add_connector(from_center: Vector2, to_center: Vector2, delta: Vector2i) -> void:
	var mid := (from_center + to_center) * 0.5
	var horizontal := delta.x != 0
	var conn := TextureRect.new()
	conn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	conn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	conn.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	conn.stretch_mode = TextureRect.STRETCH_SCALE
	conn.texture = connector_texture

	var tex_w := float(connector_texture.get_width())
	var tex_h := float(connector_texture.get_height())
	if horizontal:
		var width := maxf(cell_gap + 4.0, tex_w * icon_scale * 0.5)
		var height := maxf(tex_h * icon_scale * 0.5, 4.0)
		conn.size = Vector2(width, height)
		conn.custom_minimum_size = conn.size
		conn.position = Vector2(roundf(mid.x - width * 0.5), roundf(mid.y - height * 0.5))
	else:
		# Vertical: rotate the horizontal bar 90 degrees around its center.
		var width := maxf(cell_gap + 4.0, tex_w * icon_scale * 0.5)
		var height := maxf(tex_h * icon_scale * 0.5, 4.0)
		conn.size = Vector2(width, height)
		conn.custom_minimum_size = conn.size
		conn.pivot_offset = Vector2(width * 0.5, height * 0.5)
		conn.rotation_degrees = 90.0
		conn.position = Vector2(roundf(mid.x - width * 0.5), roundf(mid.y - height * 0.5))

	_connectors_layer.add_child(conn)


func _place_player_marker(current_id: String, marker_points: Dictionary) -> void:
	if _player_marker == null:
		return
	if current_id.is_empty() or not marker_points.has(current_id) or player_marker_texture == null:
		_player_marker.visible = false
		return

	var center: Vector2 = marker_points[current_id]
	var marker_size := Vector2(
		player_marker_texture.get_width(),
		player_marker_texture.get_height()
	) * marker_scale
	_player_marker.custom_minimum_size = marker_size
	_player_marker.size = marker_size
	_player_marker.position = Vector2(
		roundf(center.x - marker_size.x * 0.5),
		roundf(center.y - marker_size.y * 0.5)
	)
	_player_marker.visible = true
	_player_marker.move_to_front()


func _resolve_link_target_id(link: Dictionary) -> String:
	var target: String = String(link.get("target_room", ""))
	if target.is_empty():
		return ""
	var target_id := target.get_file().get_basename()
	if _scene_by_id.has(target_id):
		return target_id
	for id in _scene_by_id.keys():
		if String(_scene_by_id[id]) == target:
			return String(id)
	return target_id


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
