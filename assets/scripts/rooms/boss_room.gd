class_name BossRoom
extends Room

## Boss arena: seals doors on enter, starts the multi-part boss, opens on defeat.

@export var boss_path: NodePath = NodePath("Boss")
@export var button_slots_path: NodePath = NodePath("ButtonSlots")
@export var auto_start_fight: bool = true
## Extra margin around wall collision when computing camera bounds.
@export var camera_bounds_padding: float = 8.0
## Extra padding when fitting the whole arena into view.
@export var camera_fit_padding: float = 1.08
## Extra space north of the playable floor so the external head stays on screen.
@export var camera_north_margin: float = 280.0
## Nudge the locked view (negative Y = raise camera, more headroom above the boss).
@export var camera_center_offset: Vector2 = Vector2(0, -52)
@export_group("Intro")
## Camera pullback from player view to the full arena before the fight starts.
@export var intro_camera_duration: float = 1.7
## Beat after the pullback before attacks begin.
@export var intro_hold_duration: float = 0.55

var _boss: Boss = null
var _fight_started: bool = false
var _boss_defeated: bool = false
var _camera_locked: bool = false
var _intro_running: bool = false
var _intro_token: int = 0


func _ready() -> void:
	super._ready()
	_boss = get_node_or_null(boss_path) as Boss
	if _boss != null and not _boss.defeated.is_connected(_on_boss_defeated):
		_boss.defeated.connect(_on_boss_defeated)


## Prefer wall collision over TileMapLayer used_rect (tileset tile_size may not match atlas 128).
func get_camera_bounds() -> Rect2:
	var from_walls := _bounds_from_walls()
	if from_walls.size != Vector2.ZERO:
		_cached_bounds = from_walls
		_bounds_cached = true
		return _cached_bounds
	return super.get_camera_bounds()


func on_player_entered(player: Node2D) -> void:
	if is_room_cleared():
		_boss_defeated = true
	if _boss_defeated:
		set_all_doors_open(true)
		return
	close_doors_after_delay()
	if auto_start_fight and not _fight_started and not _intro_running:
		call_deferred("_start_boss_fight", player)


func on_player_exited(player: Node2D) -> void:
	_cancel_intro(player)
	_unlock_boss_camera()


func _start_boss_fight(player: Node2D) -> void:
	if _fight_started or _boss_defeated or _intro_running:
		return
	_boss = get_node_or_null(boss_path) as Boss
	if _boss == null:
		return

	_intro_running = true
	_intro_token += 1
	var token := _intro_token
	_set_player_intro_locked(player, true)

	var arena := get_camera_bounds()
	var slots: Array = []
	var slots_node := get_node_or_null(button_slots_path)
	if slots_node != null:
		for child in slots_node.get_children():
			if child is Marker2D:
				slots.append(child)

	await _play_camera_intro(arena)
	if token != _intro_token or _boss_defeated or not is_inside_tree():
		_set_player_intro_locked(player, false)
		_intro_running = false
		return

	if intro_hold_duration > 0.0:
		await get_tree().create_timer(intro_hold_duration).timeout
	if token != _intro_token or _boss_defeated or not is_inside_tree():
		_set_player_intro_locked(player, false)
		_intro_running = false
		return

	_fight_started = true
	_intro_running = false
	_set_player_intro_locked(player, false)
	_boss.start_fight(arena, slots)


func _on_boss_defeated() -> void:
	_boss_defeated = true
	_fight_started = false
	_intro_running = false
	_intro_token += 1
	_unlock_boss_camera()
	mark_room_cleared()
	cancel_pending_door_close()
	set_all_doors_open(true)


func _play_camera_intro(arena: Rect2) -> void:
	var cam := _player_camera()
	if cam == null:
		return
	var view := _framed_boss_view(arena)
	var center := (
		view.get_center() + camera_center_offset
		if view.size != Vector2.ZERO
		else global_position + camera_center_offset
	)
	var fit := view.size if view.size != Vector2.ZERO else Vector2.ZERO
	if cam.has_method("animate_lock_to_world_point"):
		await cam.animate_lock_to_world_point(center, fit, camera_fit_padding, intro_camera_duration)
	elif cam.has_method("lock_to_world_point"):
		cam.lock_to_world_point(center, fit, camera_fit_padding)
	_camera_locked = true


func _framed_boss_view(arena: Rect2) -> Rect2:
	var view := arena
	if view.size != Vector2.ZERO and camera_north_margin > 0.0:
		# Include the head parked above the north wall in the framed view.
		view = Rect2(
			view.position.x,
			view.position.y - camera_north_margin,
			view.size.x,
			view.size.y + camera_north_margin
		)
	return view


func _cancel_intro(player: Node2D = null) -> void:
	if not _intro_running:
		return
	_intro_token += 1
	_intro_running = false
	_set_player_intro_locked(player, false)


func _set_player_intro_locked(player: Node2D, locked: bool) -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.has_method("set_cutscene_locked"):
		player.call("set_cutscene_locked", locked)


func _unlock_boss_camera() -> void:
	if not _camera_locked:
		return
	var cam := _player_camera()
	if cam != null and cam.has_method("unlock_world_point"):
		cam.unlock_world_point()
	_camera_locked = false


func _player_camera() -> Camera2D:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return null
	return player.get_node_or_null("Camera2D") as Camera2D


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
		var rect := _shape_global_rect(shape_node)
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
	var bounds := Rect2(min_v, max_v - min_v).grow(-camera_bounds_padding)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return Rect2(min_v, max_v - min_v)
	return bounds


func _shape_global_rect(shape_node: CollisionShape2D) -> Rect2:
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
