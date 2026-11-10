extends Area2D

## Player nightmare projectile: damages enemies, stops on world/doors.

@export var speed: float = 160.0
@export var lifetime: float = 1.5
@export var damage: int = 2

const MASK_WORLD := 1 << 0
const MASK_ENEMY := 1 << 2
const MASK_DOOR_ENEMY := 1 << 3
const MASK_PROP_BREAKABLE := 1 << 6

var direction: Vector2 = Vector2.RIGHT
var _alive: bool = false
var _hit: Dictionary = {}


func _ready() -> void:
	collision_layer = 0
	collision_mask = MASK_WORLD | MASK_ENEMY | MASK_DOOR_ENEMY | MASK_PROP_BREAKABLE
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	monitoring = false
	monitorable = false
	set_physics_process(false)


func launch(dir: Vector2, launch_speed: float = -1.0) -> void:
	direction = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	if launch_speed > 0.0:
		speed = launch_speed
	rotation = direction.angle()
	monitoring = true
	_alive = true
	visible = true
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not _alive:
		return

	var motion := direction * speed * delta
	var from := global_position
	var to := from + motion

	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var hit := get_world_2d().direct_space_state.intersect_ray(query)
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
	if body == null or not (body is Node):
		queue_free()
		return
	var node := body as Node
	if node.is_in_group("player"):
		return
	var is_target := (
		node.is_in_group("enemy")
		or node.is_in_group("prop_hittable")
		or node.is_in_group("prop_breakable")
	)
	if is_target:
		var id := node.get_instance_id()
		if _hit.has(id):
			queue_free()
			return
		_hit[id] = true
		var origin := global_position
		if node.has_method("try_receive_hit"):
			node.call("try_receive_hit", damage, origin)
		else:
			var dmg := node.get_node_or_null("Damageable")
			if dmg != null and dmg.has_method("take_damage"):
				dmg.take_damage(damage)
	queue_free()
