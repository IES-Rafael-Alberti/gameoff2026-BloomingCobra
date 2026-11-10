extends Node

## Slow approach → windup → accelerating dash with fixed travel time → done.

@export var approach_speed: float = 28.0
## Only charge in this band so close range can use the spin attack.
@export var min_distance: float = 44.0
@export var trigger_distance: float = 110.0
@export var windup_time: float = 0.45
@export var travel_time: float = 0.85
@export var start_speed: float = 40.0
@export var end_speed: float = 190.0
@export var contact_damage: int = 1

enum Phase { IDLE, WINDUP, DASH, DONE }

var _brain: Node
var _hurtbox: Area2D
var _phase: Phase = Phase.IDLE
var _timer: float = 0.0
var _dash_dir: Vector2 = Vector2.DOWN
var _hit_player: bool = false


func setup(brain: Node, hurtbox: Area2D) -> void:
	_brain = brain
	_hurtbox = hurtbox
	if _hurtbox != null:
		_hurtbox.collision_layer = 0
		_hurtbox.collision_mask = 1 << 1
		_hurtbox.monitoring = false
		_hurtbox.monitorable = false
		_ensure_shape()
		if not _hurtbox.body_entered.is_connected(_on_hurtbox_body_entered):
			_hurtbox.body_entered.connect(_on_hurtbox_body_entered)


func reset() -> void:
	_phase = Phase.IDLE
	_timer = 0.0
	_hit_player = false
	_set_hurtbox(false)


func is_busy() -> bool:
	return _phase == Phase.WINDUP or _phase == Phase.DASH


func can_trigger(distance: float) -> bool:
	return (
		_phase == Phase.IDLE
		and distance <= trigger_distance
		and distance >= min_distance
	)


func begin(to_player: Vector2) -> void:
	_phase = Phase.WINDUP
	_timer = windup_time
	_hit_player = false
	_dash_dir = _cardinal(to_player)
	_brain.set_facing(_dash_dir)
	_brain.get_enemy().velocity = Vector2.ZERO
	_brain.play_charge_anim(_dash_dir)
	_set_hurtbox(false)


func physics_update(delta: float, player: Node2D) -> bool:
	## Returns true while this attack owns the elite.
	match _phase:
		Phase.IDLE:
			return false
		Phase.WINDUP:
			_brain.get_enemy().velocity = Vector2.ZERO
			_timer -= delta
			_brain.play_charge_anim(_dash_dir)
			if _timer <= 0.0:
				_phase = Phase.DASH
				_timer = travel_time
				_set_hurtbox(true)
			return true
		Phase.DASH:
			_timer -= delta
			var t := 1.0 - clampf(_timer / maxf(travel_time, 0.01), 0.0, 1.0)
			# Ease-in: starts slow, then accelerates.
			var speed := lerpf(start_speed, end_speed, t * t)
			_brain.get_enemy().velocity = _dash_dir * speed
			_brain.set_facing(_dash_dir)
			_brain.play_charge_anim(_dash_dir)
			if _timer <= 0.0:
				_finish()
			return true
		Phase.DONE:
			return false
	return false


func _finish() -> void:
	_phase = Phase.DONE
	_set_hurtbox(false)
	_brain.get_enemy().velocity = Vector2.ZERO
	_phase = Phase.IDLE
	if _brain != null and _brain.has_method("on_charge_finished"):
		_brain.on_charge_finished()


func _set_hurtbox(enabled: bool) -> void:
	if _hurtbox == null:
		return
	_hurtbox.monitoring = enabled
	for child in _hurtbox.get_children():
		if child is CollisionShape2D:
			child.disabled = not enabled


func _on_hurtbox_body_entered(body: Node2D) -> void:
	if _hit_player or body == null or not body.is_in_group("player"):
		return
	_hit_player = true
	_deal_contact(body)


func _deal_contact(player: Node2D) -> void:
	var dmg := player.get_node_or_null("Damageable")
	if dmg != null and dmg.has_method("take_damage"):
		dmg.take_damage(contact_damage)
	if player.has_method("apply_knockback"):
		player.apply_knockback(_dash_dir, 160.0)


func _ensure_shape() -> void:
	var shape_node := _hurtbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null:
		return
	if shape_node.shape == null:
		var rect := RectangleShape2D.new()
		rect.size = Vector2(16, 20)
		shape_node.shape = rect
		shape_node.position = Vector2(0, -10)


func _cardinal(dir: Vector2) -> Vector2:
	if dir == Vector2.ZERO:
		return Vector2.DOWN
	if absf(dir.x) >= absf(dir.y):
		return Vector2.RIGHT if dir.x > 0.0 else Vector2.LEFT
	return Vector2.DOWN if dir.y > 0.0 else Vector2.UP
