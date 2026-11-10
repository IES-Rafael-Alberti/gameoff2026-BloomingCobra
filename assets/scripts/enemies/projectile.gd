extends Area2D

@export var speed: float = 120.0
@export var lifetime: float = 2.0
@export var damage: int = 1
@export var knockback_force: float = 90.0

const MASK_WORLD := 1 << 0
const MASK_PLAYER := 1 << 1
const MASK_DOOR_ENEMY := 1 << 3

var direction: Vector2 = Vector2.RIGHT
var _alive: bool = false


func _ready() -> void:
	_apply_collision()
	body_entered.connect(_on_body_entered)
	monitoring = false
	monitorable = false
	visible = false
	set_physics_process(false)


func launch(dir: Vector2, launch_speed: float = -1.0, _owner_enemy: Node = null) -> void:
	direction = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	if launch_speed > 0.0:
		speed = launch_speed
	_apply_collision()
	visible = true
	monitoring = true
	_alive = true
	set_physics_process(true)


func _apply_collision() -> void:
	collision_layer = 0
	# world + player + door barriers
	collision_mask = MASK_WORLD | MASK_PLAYER | MASK_DOOR_ENEMY


func _physics_process(delta: float) -> void:
	if not _alive:
		return

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
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	_handle_hit(body)


func _handle_hit(body: Object) -> void:
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
		queue_free()
		return
	# Walls, doors, and any other solid body.
	queue_free()
