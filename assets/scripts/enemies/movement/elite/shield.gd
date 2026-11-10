extends Node

## Frontal shield: blocks hits from the front and knocks the player back.

@export var block_dot_threshold: float = 0.25
@export var knockback_force: float = 140.0
@export var shield_forward: float = 10.0
## Negative Y = higher on screen (sprite torso/head).
@export var shield_height: float = -20.0

var _brain: Node
var _shield_area: Area2D
var _active: bool = true


func setup(brain: Node, shield_area: Area2D) -> void:
	_brain = brain
	_shield_area = shield_area
	if _shield_area == null:
		return
	_shield_area.collision_layer = 0
	_shield_area.collision_mask = 0
	_shield_area.monitoring = false
	_shield_area.monitorable = false
	_ensure_shape()
	update_facing(brain.get_facing() if brain.has_method("get_facing") else Vector2.DOWN)


func set_shield_active(active: bool) -> void:
	_active = active
	if _active and _brain != null:
		_brain.play_defense_anim()
	if _shield_area != null:
		_shield_area.visible = _active


func is_active() -> bool:
	return _active


func blocks_hit_from(hit_origin: Vector2) -> bool:
	if not _active or _brain == null:
		return false
	var facing: Vector2 = _brain.get_facing()
	var to_origin: Vector2 = hit_origin - _brain.get_enemy().global_position
	if to_origin.length_squared() < 0.001:
		return true
	return facing.dot(to_origin.normalized()) >= block_dot_threshold


func apply_block_to_player(player: Node2D) -> void:
	if player == null or _brain == null:
		return
	var away: Vector2 = player.global_position - _brain.get_enemy().global_position
	if away == Vector2.ZERO:
		away = -_brain.get_facing()
	away = away.normalized()
	if player.has_method("apply_knockback"):
		player.apply_knockback(away, knockback_force)


func update_facing(facing: Vector2) -> void:
	if _shield_area == null:
		return
	var dir := facing.normalized() if facing != Vector2.ZERO else Vector2.DOWN
	# Keep the slab in front and raised toward the torso/head.
	_shield_area.rotation = dir.angle()
	_shield_area.position = dir * shield_forward + Vector2(0.0, shield_height)


func _ensure_shape() -> void:
	var shape_node := _shield_area.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null:
		return
	if shape_node.shape == null:
		var rect := RectangleShape2D.new()
		rect.size = Vector2(14, 22)
		shape_node.shape = rect
	# Local offset forward + slightly up relative to the Area2D.
	shape_node.position = Vector2(8, -4)
