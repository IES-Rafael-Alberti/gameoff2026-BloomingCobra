extends Node

## Close-range circular AoE with a short windup.

@export var trigger_distance: float = 42.0
@export var windup_time: float = 0.45
@export var active_time: float = 0.7
@export var cooldown: float = 1.2
@export var damage: int = 1

enum Phase { IDLE, WINDUP, ACTIVE, COOLDOWN }

var _brain: Node
var _attack_area: Area2D
var _phase: Phase = Phase.IDLE
var _timer: float = 0.0
var _hit_ids: Dictionary = {}


func setup(brain: Node, attack_area: Area2D) -> void:
	_brain = brain
	_attack_area = attack_area
	if _attack_area != null:
		_attack_area.collision_layer = 0
		_attack_area.collision_mask = 1 << 1
		_attack_area.monitoring = false
		_attack_area.monitorable = false
		if not _attack_area.body_entered.is_connected(_on_body_entered):
			_attack_area.body_entered.connect(_on_body_entered)
	_set_area(false)


func reset() -> void:
	_phase = Phase.IDLE
	_timer = 0.0
	_hit_ids.clear()
	_set_area(false)


func is_busy() -> bool:
	return _phase == Phase.WINDUP or _phase == Phase.ACTIVE


func can_trigger(distance: float) -> bool:
	return _phase == Phase.IDLE and distance <= trigger_distance


func begin() -> void:
	_phase = Phase.WINDUP
	_timer = windup_time
	_hit_ids.clear()
	_brain.get_enemy().velocity = Vector2.ZERO
	_brain.play_rotate_attack()
	_set_area(false)


func physics_update(delta: float) -> bool:
	match _phase:
		Phase.IDLE:
			return false
		Phase.WINDUP:
			_brain.get_enemy().velocity = Vector2.ZERO
			# Animation already started in begin(); don't restart it each tick.
			_timer -= delta
			if _timer <= 0.0:
				_phase = Phase.ACTIVE
				_timer = active_time
				_set_area(true)
			return true
		Phase.ACTIVE:
			_brain.get_enemy().velocity = Vector2.ZERO
			_timer -= delta
			if _timer <= 0.0:
				_set_area(false)
				_phase = Phase.COOLDOWN
				_timer = cooldown
			return true
		Phase.COOLDOWN:
			_timer -= delta
			if _timer <= 0.0:
				_phase = Phase.IDLE
			return false
	return false


func _set_area(enabled: bool) -> void:
	if _attack_area == null:
		return
	_attack_area.monitoring = enabled
	for child in _attack_area.get_children():
		if child is CollisionShape2D:
			child.disabled = not enabled


func _on_body_entered(body: Node2D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	var id := body.get_instance_id()
	if _hit_ids.has(id):
		return
	_hit_ids[id] = true
	var dmg := body.get_node_or_null("Damageable")
	if dmg != null and dmg.has_method("take_damage"):
		dmg.take_damage(damage)
	if body.has_method("apply_knockback") and _brain != null:
		var away: Vector2 = body.global_position - _brain.get_enemy().global_position
		if away == Vector2.ZERO:
			away = Vector2.DOWN
		body.apply_knockback(away.normalized(), 120.0)
