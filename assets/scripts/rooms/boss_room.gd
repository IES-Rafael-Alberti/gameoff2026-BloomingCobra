class_name BossRoom
extends Room

## Boss arena: seals doors on enter, starts the multi-part boss, opens on defeat.

@export var boss_path: NodePath = NodePath("Boss")
@export var button_slots_path: NodePath = NodePath("ButtonSlots")
@export var auto_start_fight: bool = true
## Extra margin around wall collision when computing camera bounds.
@export var camera_bounds_padding: float = 8.0
## Extra padding when fitting the framed view (above 1.0 keeps a small margin).
@export var camera_fit_padding: float = 1.02
## Space above the boss's top-most sprite so the head never touches the edge.
@export var camera_head_padding: float = 16.0
## Space below the arena floor so the player is never cut at the bottom edge.
@export var camera_floor_margin: float = 12.0
## Fine nudge for the locked view (negative Y = raise the camera).
@export var camera_center_offset: Vector2 = Vector2.ZERO
@export_group("Intro")
## Camera pullback from player view to the full arena before the fight starts.
@export var intro_camera_duration: float = 1.7
## Beat after the pullback before attacks begin.
@export var intro_hold_duration: float = 0.55
@export_group("Vigilia Layouts")
## Parent holding the Layout* nodes (each with spike tiles + Button/Teleport markers).
@export var layouts_path: NodePath = NodePath("Switchable/Sueño")
## Button spawned on the chosen layout's Button marker.
@export var layout_button_scene: PackedScene = preload("res://assets/scenes/props/vigilia/interactive/buttonVigilia.tscn")
## Teleport marker used when a layout has none of its own.
@export var fallback_teleport_path: NodePath = NodePath("Teleport")
## Pressing the layout button switches back to nightmare automatically.
@export var button_switches_to_nightmare: bool = true

var _boss: Boss = null
var _fight_started: bool = false
var _boss_defeated: bool = false
var _camera_locked: bool = false
var _intro_running: bool = false
var _intro_token: int = 0
## Layouts not yet used in the current shuffle bag (avoids repeats until exhausted).
var _layout_bag: Array[Node2D] = []
var _active_layout: Node2D = null
var _layout_button: Area2D = null
## True only while this room is the one holding the world-mode lock.
var _layout_lock_owned: bool = false


func _ready() -> void:
	super._ready()
	_boss = get_node_or_null(boss_path) as Boss
	if _boss != null and not _boss.defeated.is_connected(_on_boss_defeated):
		_boss.defeated.connect(_on_boss_defeated)
	# The vigilia layouts own the weak-point button, so the boss must not spawn one.
	if _boss != null and not _layouts().is_empty():
		_boss.manage_button = false
	if not WorldMode.mode_changed.is_connected(_on_world_mode_changed):
		WorldMode.mode_changed.connect(_on_world_mode_changed)
	_clear_layout()


## Prefer wall collision over TileMapLayer used_rect (tileset tile_size may not match atlas 128).
func get_camera_bounds() -> Rect2:
	var from_walls := _bounds_from_walls()
	if from_walls.size != Vector2.ZERO:
		_cached_bounds = from_walls
		_bounds_cached = true
		return _cached_bounds
	return super.get_camera_bounds()


func on_player_entered(player: Node2D) -> void:
	_refresh_layout_visibility()
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
	_end_vigilia_layout()


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
	# Entered the arena already in vigilia: drop them straight onto a layout.
	if WorldMode.get_mode() == WorldMode.MODE_SUENO:
		_begin_vigilia_layout()


func _on_boss_defeated() -> void:
	_boss_defeated = true
	_fight_started = false
	_intro_running = false
	_intro_token += 1
	_end_vigilia_layout()
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
	if arena.size == Vector2.ZERO:
		return arena
	# Frame from the boss's real top sprite down to just above the floor instead of
	# a fixed strip of sky. That strip forced the zoom far out, so the fight looked
	# tiny and the empty void below the arena stayed on screen.
	var top := arena.position.y - camera_head_padding
	var boss_rect := _boss_visual_bounds()
	if boss_rect.size != Vector2.ZERO:
		top = minf(top, boss_rect.position.y - camera_head_padding)
	var bottom := arena.end.y + camera_floor_margin
	return Rect2(arena.position.x, top, arena.size.x, bottom - top)


## Merged world-space rect of every visible sprite under the boss.
func _boss_visual_bounds() -> Rect2:
	var boss := get_node_or_null(boss_path) as Node2D
	if boss == null:
		return Rect2()
	var rects: Array[Rect2] = []
	_collect_sprite_rects(boss, rects)
	if rects.is_empty():
		return Rect2()
	var merged := rects[0]
	for i in range(1, rects.size()):
		merged = merged.merge(rects[i])
	return merged


func _collect_sprite_rects(node: Node, out: Array[Rect2]) -> void:
	for child in node.get_children():
		if child is AnimatedSprite2D:
			var anim := child as AnimatedSprite2D
			if anim.is_visible_in_tree() and anim.sprite_frames != null:
				var frame_tex := anim.sprite_frames.get_frame_texture(anim.animation, anim.frame)
				if frame_tex != null:
					out.append(_sprite_global_rect(anim, frame_tex.get_size(), anim.centered, anim.offset))
		elif child is Sprite2D:
			var sprite := child as Sprite2D
			if sprite.is_visible_in_tree() and sprite.texture != null:
				out.append(_sprite_global_rect(sprite, sprite.texture.get_size(), sprite.centered, sprite.offset))
		_collect_sprite_rects(child, out)


func _sprite_global_rect(sprite: Node2D, tex_size: Vector2, centered: bool, offset: Vector2) -> Rect2:
	var local := Rect2(offset, tex_size)
	if centered:
		local.position -= tex_size * 0.5
	var xform := sprite.global_transform
	var rect := Rect2(xform * local.position, Vector2.ZERO)
	rect = rect.expand(xform * Vector2(local.end.x, local.position.y))
	rect = rect.expand(xform * local.end)
	rect = rect.expand(xform * Vector2(local.position.x, local.end.y))
	return rect


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


## Layout* nodes under the vigilia root (each: spike tiles + Button/Teleport markers).
func _layouts() -> Array[Node2D]:
	var result: Array[Node2D] = []
	var root := get_node_or_null(layouts_path)
	if root == null:
		return result
	for child in root.get_children():
		if child is Node2D and String(child.name).begins_with("Layout"):
			result.append(child as Node2D)
	return result


func _hide_all_layouts() -> void:
	for layout in _layouts():
		layout.visible = false
		for node in layout.find_children("*", "TileMapLayer", true, false):
			(node as TileMapLayer).collision_enabled = false


## Called on enter: layouts start hidden until the player shifts into vigilia.
func _refresh_layout_visibility() -> void:
	if _active_layout == null or WorldMode.get_mode() != WorldMode.MODE_SUENO:
		_hide_all_layouts()


func _on_world_mode_changed(index: int) -> void:
	# Only during the fight: the intro is a scripted camera moment.
	if not _fight_started or _boss_defeated:
		return
	if index == WorldMode.MODE_SUENO:
		_begin_vigilia_layout()
	elif index == WorldMode.MODE_PESADILLA:
		_end_vigilia_layout()


## Shifting into vigilia: lock the mode, pick a non-repeating layout, teleport the
## player onto it and drop the button that sends them back to nightmare.
func _begin_vigilia_layout() -> void:
	if _boss_defeated or is_room_cleared() or not is_active():
		return
	var layouts := _layouts()
	if layouts.is_empty():
		return
	_end_vigilia_layout()
	WorldMode.set_locked(true)
	_layout_lock_owned = true
	_active_layout = _pick_layout()
	_hide_all_layouts()
	_show_layout(_active_layout)
	_spawn_layout_button(_active_layout)
	_teleport_player_to_layout(_active_layout)


func _end_vigilia_layout() -> void:
	if _layout_lock_owned:
		WorldMode.set_locked(false)
		_layout_lock_owned = false
	if _layout_button != null and is_instance_valid(_layout_button):
		_layout_button.queue_free()
	_layout_button = null
	_active_layout = null
	_hide_all_layouts()


## Shuffle bag: every layout is used once before any can repeat.
func _pick_layout() -> Node2D:
	var layouts := _layouts()
	var remaining: Array[Node2D] = []
	for entry in _layout_bag:
		if is_instance_valid(entry) and layouts.has(entry):
			remaining.append(entry)
	_layout_bag = remaining
	if _layout_bag.is_empty():
		_layout_bag = layouts.duplicate()
		_layout_bag.shuffle()
	return _layout_bag.pop_back()


func _show_layout(layout: Node2D) -> void:
	if layout == null:
		return
	layout.visible = true
	for node in layout.find_children("*", "TileMapLayer", true, false):
		(node as TileMapLayer).collision_enabled = true


func _layout_marker(layout: Node2D, prefix: String) -> Node2D:
	if layout == null:
		return null
	for child in layout.get_children():
		if child is Node2D and String(child.name).begins_with(prefix):
			return child as Node2D
	return null


func _spawn_layout_button(layout: Node2D) -> void:
	if layout_button_scene == null:
		return
	var marker := _layout_marker(layout, "Button")
	if marker == null:
		return
	_layout_button = layout_button_scene.instantiate() as Area2D
	if _layout_button == null:
		return
	_layout_button.name = "LayoutButton"
	layout.add_child(_layout_button)
	_layout_button.global_position = marker.global_position
	if _layout_button.has_signal("pressed"):
		_layout_button.pressed.connect(_on_layout_button_pressed)
	if "permanent_press" in _layout_button:
		_layout_button.permanent_press = false


func _on_layout_button_pressed() -> void:
	if _boss != null and is_instance_valid(_boss):
		_boss.trigger_weakpoint()
	if button_switches_to_nightmare:
		WorldMode.set_mode(WorldMode.MODE_PESADILLA)


func _teleport_player_to_layout(layout: Node2D) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or layout == null:
		return
	var target := _layout_marker(layout, "Teleport")
	if target == null:
		target = get_node_or_null(fallback_teleport_path) as Node2D
	if target == null:
		return
	player.global_position = target.global_position
	if player is CharacterBody2D:
		var body := player as CharacterBody2D
		body.velocity = Vector2.ZERO
		if "_knockback" in body:
			body.set("_knockback", Vector2.ZERO)
	var cam := _player_camera()
	if cam != null and cam.has_method("snap_to_room"):
		cam.call("snap_to_room", self)


func _clear_layout() -> void:
	_layout_bag.clear()
	_active_layout = null
	_layout_button = null
	_hide_all_layouts()


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
