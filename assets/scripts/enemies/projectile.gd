extends Area2D

@export var speed: float = 120.0
@export var lifetime: float = 2.0
@export var damage: int = 1
@export var knockback_force: float = 90.0
## Sprite art points down by default; rotation = direction.angle() + this offset.
@export var facing_angle_offset: float = -PI / 2.0
@export var float_amplitude: float = 1.6
@export var float_speed: float = 7.0
@export var impact_anim: StringName = &"impact"
@export var fly_anim: StringName = &"fly"
## When false, the bolt only hits the player (used by the external boss perch).
@export var collide_with_world: bool = true

const MASK_WORLD := 1 << 0
const MASK_PLAYER := 1 << 1
const MASK_DOOR_ENEMY := 1 << 3

var direction: Vector2 = Vector2.RIGHT
var _alive: bool = false
var _impacting: bool = false
var _float_t: float = 0.0
var _sprite: Node2D
var _base_sprite_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	_cache_sprite()
	_apply_collision()
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	monitoring = false
	monitorable = false
	visible = false
	set_physics_process(false)


func launch(dir: Vector2, launch_speed: float = -1.0, _owner_enemy: Node = null) -> void:
	direction = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	if launch_speed > 0.0:
		speed = launch_speed
	_cache_sprite()
	_apply_collision()
	_alive = true
	_impacting = false
	_float_t = randf() * TAU
	visible = true
	monitoring = true
	monitorable = false
	set_physics_process(true)
	_orient_to_direction()
	_play_fly()


func _cache_sprite() -> void:
	_sprite = get_node_or_null("AnimatedSprite2D") as Node2D
	if _sprite == null:
		_sprite = get_node_or_null("Sprite2D") as Node2D
	if _sprite != null:
		_base_sprite_pos = _sprite.position


func _apply_collision() -> void:
	collision_layer = 0
	if collide_with_world:
		collision_mask = MASK_WORLD | MASK_PLAYER | MASK_DOOR_ENEMY
	else:
		collision_mask = MASK_PLAYER


func _orient_to_direction() -> void:
	rotation = direction.angle() + facing_angle_offset


func _play_fly() -> void:
	var anim := _sprite as AnimatedSprite2D
	if anim == null or anim.sprite_frames == null:
		return
	if anim.sprite_frames.has_animation(fly_anim):
		anim.sprite_frames.set_animation_loop(fly_anim, true)
		anim.play(fly_anim)


func _physics_process(delta: float) -> void:
	if _impacting:
		_update_float(delta)
		return
	if not _alive:
		return

	_update_float(delta)

	var motion: Vector2 = direction * speed * delta
	var from: Vector2 = global_position
	var to: Vector2 = from + motion

	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit.position
		_handle_hit(hit.collider)
		return

	global_position = to
	lifetime -= delta
	if lifetime <= 0.0:
		_begin_impact()


func _update_float(delta: float) -> void:
	if _sprite == null:
		return
	_float_t += delta * float_speed
	# Bob perpendicular to travel so it reads as a soft hover, not sliding along the shot.
	var side := Vector2(-direction.y, direction.x)
	if side == Vector2.ZERO:
		side = Vector2.RIGHT
	_sprite.position = _base_sprite_pos + side * sin(_float_t) * float_amplitude


func _on_body_entered(body: Node2D) -> void:
	_handle_hit(body)


func _handle_hit(body: Object) -> void:
	if _impacting or not _alive:
		return
	_alive = false
	set_deferred("monitoring", false)

	if body is Node and (body as Node).is_in_group("player"):
		var player := body as Node2D
		var dmg := player.get_node_or_null("Damageable")
		if dmg != null and dmg.has_method("take_damage"):
			dmg.take_damage(damage)
		if player.has_method("apply_knockback") and knockback_force > 0.0:
			var away := direction
			if away == Vector2.ZERO:
				away = Vector2.DOWN
			player.apply_knockback(away.normalized(), knockback_force)

	_begin_impact()


func _begin_impact() -> void:
	if _impacting:
		return
	_impacting = true
	_alive = false
	set_deferred("monitoring", false)
	# Impact FX is drawn upright; undo flight rotation.
	rotation = 0.0
	if _sprite != null:
		_sprite.position = _base_sprite_pos

	var anim := _sprite as AnimatedSprite2D
	if anim != null and anim.sprite_frames != null and anim.sprite_frames.has_animation(impact_anim):
		anim.sprite_frames.set_animation_loop(impact_anim, false)
		if not anim.animation_finished.is_connected(_on_impact_finished):
			anim.animation_finished.connect(_on_impact_finished, CONNECT_ONE_SHOT)
		anim.play(impact_anim)
		return

	queue_free()


func _on_impact_finished() -> void:
	queue_free()
