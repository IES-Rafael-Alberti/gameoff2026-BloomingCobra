class_name BossRoom
extends Room

## Boss arena: seals doors on enter, starts the multi-part boss, opens on defeat.

@export var boss_path: NodePath = NodePath("Boss")
@export var button_slots_path: NodePath = NodePath("ButtonSlots")
@export var auto_start_fight: bool = true
## Extra margin around wall collision when computing camera bounds.
@export var camera_bounds_padding: float = 8.0

var _boss: Boss = null
var _fight_started: bool = false
var _boss_defeated: bool = false


func _ready() -> void:
	super._ready()
	_boss = get_node_or_null(boss_path) as Boss
	if _boss != null and not _boss.defeated.is_connected(_on_boss_defeated):
		_boss.defeated.connect(_on_boss_defeated)


## Prefer wall collision over TileMap used_rect (tileset tile_size may not match atlas 128).
func get_camera_bounds() -> Rect2:
	var from_walls := _bounds_from_walls()
	if from_walls.size != Vector2.ZERO:
		_cached_bounds = from_walls
		_bounds_cached = true
		return _cached_bounds
	return super.get_camera_bounds()


func on_player_entered(player: Node2D) -> void:
	if _boss_defeated:
		set_all_doors_open(true)
		return
	close_doors_after_delay()
	if auto_start_fight and not _fight_started:
		call_deferred("_start_boss_fight", player)


func _start_boss_fight(_player: Node2D) -> void:
	if _fight_started or _boss_defeated:
		return
	_boss = get_node_or_null(boss_path) as Boss
	if _boss == null:
		return
	_fight_started = true
	var slots: Array = []
	var slots_node := get_node_or_null(button_slots_path)
	if slots_node != null:
		for child in slots_node.get_children():
			if child is Marker2D:
				slots.append(child)
	_boss.start_fight(get_camera_bounds(), slots)


func _on_boss_defeated() -> void:
	_boss_defeated = true
	_fight_started = false
	cancel_pending_door_close()
	set_all_doors_open(true)


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
