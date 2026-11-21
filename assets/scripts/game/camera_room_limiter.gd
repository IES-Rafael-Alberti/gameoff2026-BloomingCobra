@tool
extends Camera2D

## Room-limited player camera with switchable follow styles.
enum Mode {
	## Glued to the player (no lag). Previous default behaviour.
	FIXED,
	## Camera is dragged along with the player, with optional smoothing lag.
	FOLLOW,
	## Square dead zone around the view center; leaving it pushes the camera.
	DEAD_ZONE,
}

const MODE_COUNT := 3

@export var mode: Mode = Mode.FIXED:
	set(value):
		if mode == value:
			return
		mode = value
		queue_redraw()
		if Engine.is_editor_hint():
			return
		if is_inside_tree():
			_apply_mode(true)

@export_group("Follow")
## Soft lag when dragging the camera (FOLLOW mode). Higher = heavier drag.
@export_range(0.5, 20.0, 0.1) var follow_smoothing: float = 8.0

@export_group("Dead Zone")
## World-space half-extents of the centered dead zone (full size = 2 * this).
@export var dead_zone_half_extents: Vector2 = Vector2(40.0, 28.0):
	set(value):
		dead_zone_half_extents = value.abs().max(Vector2(1.0, 1.0))
		queue_redraw()

## Draw the dead-zone square while playing (always drawn in the editor).
@export var show_dead_zone_gizmo: bool = false:
	set(value):
		show_dead_zone_gizmo = value
		queue_redraw()

@export var dead_zone_gizmo_color: Color = Color(0.2, 0.85, 1.0, 0.85):
	set(value):
		dead_zone_gizmo_color = value
		queue_redraw()

var _current_room: Room = null
## Playable room rect (before viewport padding). Used to keep look-at inside the room.
var _playable_bounds: Rect2 = Rect2()
## Desired world-space view center for DEAD_ZONE (and while easing into FOLLOW).
var _look_at: Vector2 = Vector2.ZERO
var _has_look_at: bool = false


func _ready() -> void:
	queue_redraw()
	if Engine.is_editor_hint():
		return
	enabled = true
	make_current()
	limit_enabled = true
	set_process(true)
	if GameSettings != null:
		mode = GameSettings.camera_mode as Mode
	call_deferred("_bind_room_manager")
	_apply_mode(true)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or show_dead_zone_gizmo:
		queue_redraw()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var player := get_parent() as Node2D
	if player == null:
		return

	match mode:
		Mode.FIXED:
			_update_fixed()
		Mode.FOLLOW:
			_update_follow(player, delta)
		Mode.DEAD_ZONE:
			_update_dead_zone(player)


func _draw() -> void:
	if not Engine.is_editor_hint() and not show_dead_zone_gizmo:
		return
	var half := dead_zone_half_extents
	var rect := Rect2(-half, half * 2.0)
	var fill := dead_zone_gizmo_color
	fill.a *= 0.12
	draw_rect(rect, fill, true)
	draw_rect(rect, dead_zone_gizmo_color, false, 1.0)
	var arm := mini(half.x, half.y) * 0.25
	draw_line(Vector2(-arm, 0.0), Vector2(arm, 0.0), dead_zone_gizmo_color, 1.0)
	draw_line(Vector2(0.0, -arm), Vector2(0.0, arm), dead_zone_gizmo_color, 1.0)


func _bind_room_manager() -> void:
	var manager := get_tree().get_first_node_in_group("room_manager")
	if manager == null:
		return
	if manager.has_signal("room_changed") and not manager.room_changed.is_connected(_on_room_changed):
		manager.room_changed.connect(_on_room_changed)
	if "current_room" in manager and manager.current_room != null:
		_on_room_changed(null, manager.current_room)


func _on_room_changed(_previous: Room, next: Room) -> void:
	_current_room = next
	if next == null:
		return
	# Defer one frame so room transforms / tile used_rects are fully settled.
	_apply_bounds(next)
	_reset_look_at_for_room(next)
	_snap_now()
	call_deferred("_refresh_current_room_bounds")


func _refresh_current_room_bounds() -> void:
	if _current_room == null or not is_instance_valid(_current_room):
		return
	if _current_room.has_method("invalidate_camera_bounds"):
		_current_room.invalidate_camera_bounds()
	_apply_bounds(_current_room)
	_reset_look_at_for_room(_current_room)
	_snap_now()


func _apply_bounds(room: Room) -> void:
	var bounds: Rect2 = (
		room.get_camera_limit_bounds()
		if room.has_method("get_camera_limit_bounds")
		else room.get_camera_bounds()
	)
	if bounds.size == Vector2.ZERO:
		# Never keep the previous room's limits — that traps the camera in a smaller box.
		_playable_bounds = Rect2()
		limit_enabled = false
		return
	_playable_bounds = bounds
	# Camera2D keeps the *visible* rect inside limit_*. Grow by half the view so the
	# camera can stay centered on the player anywhere inside the playable room
	# (otherwise it "hits the map edge" and stops while the player keeps walking).
	var half_view := _half_view_extents()
	var cam_limits := bounds.grow_individual(half_view.x, half_view.y, half_view.x, half_view.y)
	limit_enabled = true
	limit_left = int(floor(cam_limits.position.x))
	limit_top = int(floor(cam_limits.position.y))
	limit_right = int(ceil(cam_limits.end.x))
	limit_bottom = int(ceil(cam_limits.end.y))


func _half_view_extents() -> Vector2:
	return get_viewport_rect().size * 0.5 / zoom.abs()


## Call after a forced player teleport so limits + scroll match the new room now.
func snap_to_room(room: Room) -> void:
	if room == null:
		return
	_current_room = room
	_apply_bounds(room)
	_reset_look_at_for_room(room)
	_snap_now()
	call_deferred("_refresh_current_room_bounds")


func set_mode(new_mode: Mode) -> void:
	mode = new_mode


func cycle_mode() -> Mode:
	mode = ((int(mode) + 1) % MODE_COUNT) as Mode
	return mode


func _apply_mode(snap: bool) -> void:
	# Manual offset control for all modes; FOLLOW lerps look-at in script.
	position_smoothing_enabled = false
	var player := get_parent() as Node2D
	if player != null:
		match mode:
			Mode.FIXED:
				position = Vector2.ZERO
				_look_at = player.global_position
				_has_look_at = true
			Mode.FOLLOW, Mode.DEAD_ZONE:
				if not _has_look_at:
					_look_at = player.global_position
					_has_look_at = true
				_set_look_at(_look_at, player)
	if snap:
		_snap_now()
	queue_redraw()


func _update_fixed() -> void:
	position = Vector2.ZERO


func _update_follow(player: Node2D, delta: float) -> void:
	if not _has_look_at:
		_look_at = player.global_position
		_has_look_at = true
	# Exp smoothing: camera is dragged toward the player each frame.
	var weight := 1.0 - exp(-follow_smoothing * delta)
	_look_at = _look_at.lerp(player.global_position, weight)
	_set_look_at(_clamp_look_at(_look_at), player)


func _update_dead_zone(player: Node2D) -> void:
	if not _has_look_at:
		_look_at = player.global_position
		_has_look_at = true

	var half := dead_zone_half_extents
	var delta_pos := player.global_position - _look_at
	var push := Vector2.ZERO
	if delta_pos.x > half.x:
		push.x = delta_pos.x - half.x
	elif delta_pos.x < -half.x:
		push.x = delta_pos.x + half.x
	if delta_pos.y > half.y:
		push.y = delta_pos.y - half.y
	elif delta_pos.y < -half.y:
		push.y = delta_pos.y + half.y

	if push != Vector2.ZERO:
		_look_at += push

	_set_look_at(_clamp_look_at(_look_at), player)


func _set_look_at(world_center: Vector2, player: Node2D) -> void:
	_look_at = world_center
	_has_look_at = true
	# Camera is a child of the player: local offset places the view at world_center.
	position = world_center - player.global_position


func _clamp_look_at(center: Vector2) -> Vector2:
	if _playable_bounds.size == Vector2.ZERO:
		return center
	# Keep the focus inside the playable room; limit_* already include view padding.
	var min_c := _playable_bounds.position
	var max_c := _playable_bounds.end
	if min_c.x > max_c.x:
		center.x = _playable_bounds.get_center().x
	else:
		center.x = clampf(center.x, min_c.x, max_c.x)
	if min_c.y > max_c.y:
		center.y = _playable_bounds.get_center().y
	else:
		center.y = clampf(center.y, min_c.y, max_c.y)
	return center


func _reset_look_at_for_room(_room: Room) -> void:
	var player := get_parent() as Node2D
	if player == null:
		_has_look_at = false
		return
	_look_at = player.global_position
	_has_look_at = true
	match mode:
		Mode.FIXED:
			position = Vector2.ZERO
		Mode.FOLLOW, Mode.DEAD_ZONE:
			_set_look_at(_clamp_look_at(_look_at), player)


func _snap_now() -> void:
	var was_limit_smoothed := limit_smoothed
	var was_pos_smoothed := position_smoothing_enabled
	limit_smoothed = false
	position_smoothing_enabled = false
	make_current()
	reset_smoothing()
	force_update_scroll()
	limit_smoothed = was_limit_smoothed
	position_smoothing_enabled = was_pos_smoothed
