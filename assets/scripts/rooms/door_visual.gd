@tool
class_name DoorVisual
extends Node

## Oriented door art + collision/spawn layout for a parent [Door].
## Closed uses per-direction textures; open uses the north open texture rotated.
## Body/trigger sizes follow the closed art footprint (thin doorway), not the open sprite AABB.

@export_group("Closed")
@export var north_closed: Texture2D
@export var east_closed: Texture2D
@export var south_closed: Texture2D
@export var west_closed: Texture2D

@export_group("Open")
## Drawn in north orientation; rotated for east/south/west.
@export var open_texture: Texture2D

@export_group("Layout")
@export var sprite_scale: float = 0.3
@export var open_scale: float = 0.5
@export var spawn_margin: float = 12.0
## How deep the transport trigger is (into the room).
@export var trigger_depth: float = 18.0
## Trigger width/height along the wall vs closed sprite span (1 = full door width).
@export_range(0.2, 1.5, 0.05) var trigger_span_mul: float = 0.7
## Body collision uses a thin slab through the doorway instead of full sprite height.
@export var body_depth: float = 14.0
@export_range(0.2, 1.5, 0.05) var body_span_mul: float = 0.85


func apply(orientation: int, is_open: bool) -> void:
	var door := _door()
	if door == null:
		return
	var sprite := door.get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return

	var closed_tex := closed_texture_for(orientation)
	var show_open := is_open and open_texture != null
	var tex: Texture2D = open_texture if show_open else closed_tex
	if tex == null:
		tex = closed_tex
	if tex == null:
		return

	var scale_closed := _float_or(sprite_scale, 0.3)
	var scale_open := _float_or(open_scale, 0.5)
	var scale_val := scale_open if show_open else scale_closed
	sprite.visible = true
	sprite.texture = tex
	sprite.scale = Vector2(scale_val, scale_val)
	sprite.rotation = _open_rotation(orientation) if show_open else 0.0

	# Footprint from closed art so open VFX (tall floor plates) do not inflate hitboxes.
	var closed_size := _closed_visual_size(orientation)
	if closed_size == Vector2.ZERO:
		closed_size = _visual_size(tex, scale_val, show_open, orientation)

	var body_size := _slab_size(
		closed_size,
		orientation,
		_float_or(body_span_mul, 0.85),
		_float_or(body_depth, 14.0)
	)
	var trigger_size := _slab_size(
		closed_size,
		orientation,
		_float_or(trigger_span_mul, 0.7),
		_float_or(trigger_depth, 18.0)
	)
	_apply_body_shape(door, body_size)
	_apply_trigger_shape(door, trigger_size)
	_apply_spawn(door, orientation, body_size)


func closed_texture_for(orientation: int) -> Texture2D:
	match orientation:
		1: # EAST
			return east_closed
		2: # SOUTH
			return south_closed
		3: # WEST
			return west_closed
		_:
			return north_closed


func has_oriented_art() -> bool:
	return (
		north_closed != null
		or east_closed != null
		or south_closed != null
		or west_closed != null
		or open_texture != null
	)


func _door() -> StaticBody2D:
	return get_parent() as StaticBody2D


func _open_rotation(orientation: int) -> float:
	match orientation:
		1: # EAST
			return PI * 0.5
		2: # SOUTH
			return PI
		3: # WEST
			return PI * 1.5
		_:
			return 0.0


func _float_or(value: Variant, fallback: float) -> float:
	if value == null:
		return fallback
	return float(value)


func _closed_visual_size(orientation: int) -> Vector2:
	var tex := closed_texture_for(orientation)
	if tex == null:
		return Vector2.ZERO
	return tex.get_size() * _float_or(sprite_scale, 0.3)


func _visual_size(tex: Texture2D, scale_val: float, rotating_open: bool, orientation: int) -> Vector2:
	var raw := tex.get_size() * scale_val
	if rotating_open and (orientation == 1 or orientation == 3):
		return Vector2(raw.y, raw.x)
	return raw


## Thin doorway slab: span along the wall, fixed depth into the room.
func _slab_size(closed_size: Vector2, orientation: int, span_mul: float, depth: float) -> Vector2:
	var east_west := orientation == 1 or orientation == 3
	if east_west:
		# Side doors: span is vertical, depth is horizontal.
		return Vector2(maxf(depth, 4.0), maxf(closed_size.y * span_mul, 8.0))
	# North/South: span is horizontal, depth is vertical.
	return Vector2(maxf(closed_size.x * span_mul, 8.0), maxf(depth, 4.0))


func _apply_body_shape(door: StaticBody2D, shape_size: Vector2) -> void:
	var shape_node := door.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null:
		return
	var rect := RectangleShape2D.new()
	rect.size = shape_size
	shape_node.shape = rect
	shape_node.position = Vector2.ZERO


func _apply_trigger_shape(door: StaticBody2D, shape_size: Vector2) -> void:
	var trigger := door.get_node_or_null("Trigger") as Area2D
	if trigger == null:
		return
	var shape_node := trigger.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null:
		return
	var rect := RectangleShape2D.new()
	rect.size = shape_size
	shape_node.shape = rect
	shape_node.position = Vector2.ZERO


func _apply_spawn(door: StaticBody2D, orientation: int, body_size: Vector2) -> void:
	var spawn := door.get_node_or_null("Spawn") as Marker2D
	if spawn == null:
		return
	var inward := _inward_dir(orientation)
	var depth := body_size.y if absf(inward.y) > absf(inward.x) else body_size.x
	spawn.position = inward * (depth * 0.5 + _float_or(spawn_margin, 12.0))


func _inward_dir(orientation: int) -> Vector2:
	match orientation:
		1: # EAST
			return Vector2.LEFT
		2: # SOUTH
			return Vector2.UP
		3: # WEST
			return Vector2.RIGHT
		_:
			return Vector2.DOWN
