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

var _root: Control
var _dim: ColorRect
var _rooms_layer: Control
var _open: bool = false
var _wired: bool = false
var _grid: Dictionary = {} # Room -> Vector2i
var _icons: Dictionary = {} # Room -> TextureRect


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
	_wire_room_signals()
	_assign_grid()
	_wired = true
	if _open:
		_rebuild_icons()


func _wire_room_signals() -> void:
	for node in get_tree().get_nodes_in_group("rooms"):
		if not (node is Room):
			continue
		var room := node as Room
		if not room.discovered.is_connected(_on_room_discovered):
			room.discovered.connect(_on_room_discovered)
		var entered_cb := _on_room_entered.bind(room)
		if not room.player_entered.is_connected(entered_cb):
			room.player_entered.connect(entered_cb)


func _on_room_discovered() -> void:
	if _open:
		_rebuild_icons()


func _on_room_entered(_player: Node2D, _room: Room) -> void:
	if _open:
		_rebuild_icons()


func _assign_grid() -> void:
	_grid.clear()
	var rooms: Array[Room] = []
	var centers: Array[Vector2] = []
	var sizes: Array[Vector2] = []

	for node in get_tree().get_nodes_in_group("rooms"):
		if not (node is Room):
			continue
		var room := node as Room
		var bounds: Rect2 = room.get_camera_bounds()
		if bounds.size == Vector2.ZERO:
			continue
		rooms.append(room)
		centers.append(bounds.get_center())
		sizes.append(bounds.size)

	if rooms.is_empty():
		return

	var avg_size := Vector2.ZERO
	for s in sizes:
		avg_size += s
	avg_size /= float(sizes.size())

	# Tight clusters so side rooms of the start (parkour/trap) keep their own
	# columns and do not stack under the rooms above them.
	var merge_x := maxf(avg_size.x * 0.32, 1.0)
	var merge_y := maxf(avg_size.y * 0.32, 1.0)

	var xs: Array[float] = []
	var ys: Array[float] = []
	for c in centers:
		_cluster_insert(xs, c.x, merge_x)
		_cluster_insert(ys, c.y, merge_y)
	xs.sort()
	ys.sort()

	var used_cells: Dictionary = {} # Vector2i -> Room
	for i in rooms.size():
		var cell := Vector2i(_nearest_index(xs, centers[i].x), _nearest_index(ys, centers[i].y))
		if used_cells.has(cell):
			cell = _find_free_cell(cell, used_cells)
		used_cells[cell] = rooms[i]
		_grid[rooms[i]] = cell


func _cluster_insert(values: Array[float], value: float, threshold: float) -> void:
	for i in values.size():
		if absf(values[i] - value) <= threshold:
			# Pull cluster center toward the new sample.
			values[i] = (values[i] + value) * 0.5
			return
	values.append(value)


func _nearest_index(values: Array[float], value: float) -> int:
	var best_i := 0
	var best_d := INF
	for i in values.size():
		var d := absf(values[i] - value)
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


func _find_free_cell(start: Vector2i, used: Dictionary) -> Vector2i:
	if not used.has(start):
		return start
	for radius in range(1, 8):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := start + Vector2i(x, y)
				if not used.has(candidate):
					return candidate
	return start + Vector2i(used.size(), 0)


func _rebuild_icons() -> void:
	if _rooms_layer == null:
		return
	if _grid.is_empty():
		_assign_grid()

	for child in _rooms_layer.get_children():
		child.queue_free()
	_icons.clear()

	var visible_rooms: Array[Room] = _collect_visible_rooms()
	if visible_rooms.is_empty():
		return

	var min_g := Vector2i(999999, 999999)
	var max_g := Vector2i(-999999, -999999)
	for room in visible_rooms:
		var g: Vector2i = _grid[room]
		min_g.x = mini(min_g.x, g.x)
		min_g.y = mini(min_g.y, g.y)
		max_g.x = maxi(max_g.x, g.x)
		max_g.y = maxi(max_g.y, g.y)

	var base_tex_size := Vector2(16, 8)
	if discovered_texture != null:
		base_tex_size = Vector2(discovered_texture.get_width(), discovered_texture.get_height())
	var icon_size := base_tex_size * icon_scale
	var start_size := icon_size * start_room_scale
	# Pack the grid tightly around normal icons; start room can overhang a bit.
	var step := icon_size + Vector2(cell_gap, cell_gap)

	var grid_w := float(max_g.x - min_g.x) * step.x + icon_size.x
	var grid_h := float(max_g.y - min_g.y) * step.y + icon_size.y
	var vp := get_viewport().get_visible_rect().size
	var origin := (vp - Vector2(grid_w, grid_h)) * 0.5
	origin = Vector2(roundf(origin.x), roundf(origin.y))

	var current_room := _find_current_room()

	for room in visible_rooms:
		var g: Vector2i = _grid[room]
		var cell_origin := origin + Vector2(
			float(g.x - min_g.x) * step.x,
			float(g.y - min_g.y) * step.y
		)
		var is_start := room is StartingRoom
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

		var is_current := room == current_room
		if is_start and current_texture != null:
			icon.texture = current_texture
			if is_current:
				icon.modulate = current_modulate
		elif is_current and current_texture != null:
			icon.texture = current_texture
			icon.modulate = current_modulate
		elif room.is_discovered():
			icon.texture = discovered_texture
		else:
			icon.texture = undiscovered_texture

		_rooms_layer.add_child(icon)
		_icons[room] = icon


func _collect_visible_rooms() -> Array[Room]:
	var result: Array[Room] = []
	var discovered: Array[Room] = []

	for room in _grid.keys():
		var r := room as Room
		if r.is_discovered():
			discovered.append(r)
			result.append(r)

	# Reveal undiscovered rooms that actually touch a discovered one in the world
	# (door/corridor), not just grid neighbors — so parkour/trap don't look linked
	# to the rooms stacked above them.
	for room in _grid.keys():
		var r := room as Room
		if r.is_discovered():
			continue
		for d in discovered:
			if _rooms_touch(r, d):
				result.append(r)
				break
	return result


## True when room bounds nearly touch (shared doorway / adjacent placement).
func _rooms_touch(a: Room, b: Room) -> bool:
	var ba := a.get_camera_bounds()
	var bb := b.get_camera_bounds()
	if ba.size == Vector2.ZERO or bb.size == Vector2.ZERO:
		return false
	const MARGIN := 24.0
	return ba.grow(MARGIN).intersects(bb.grow(MARGIN))


func _find_current_room() -> Room:
	for room in _grid.keys():
		var r := room as Room
		if r.is_active():
			return r
	return null
