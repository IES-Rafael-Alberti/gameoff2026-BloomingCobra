extends Area2D

## Player nightmare projectile: damages enemies, stops on world/doors.
## SpriteFrames expect "fly" (loop first frames) and optional "impact" (last frame).

@export var speed: float = 160.0
@export var lifetime: float = 1.5
@export var damage: int = 2
@export var impact_hold: float = 0.12

const MASK_WORLD := 1 << 0
const MASK_ENEMY := 1 << 2
const MASK_DOOR_ENEMY := 1 << 3
const MASK_PROP_BREAKABLE := 1 << 6

var direction: Vector2 = Vector2.RIGHT
var _alive: bool = false
var _resolving: bool = false
var _freed: bool = false
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
	# Art faces up with trail down; +90° CW aligns nose with +X (angle 0).
	rotation = direction.angle() + PI * 0.5
	z_index = 3
	z_as_relative = false
	monitoring = true
	_alive = true
	visible = true
	set_physics_process(true)
	_play_fly()


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
		_expire()


func _on_body_entered(body: Node2D) -> void:
	_handle_hit(body)


func _handle_hit(body: Object) -> void:
	if _resolving or not _alive:
		return
	if body == null or not (body is Node):
		_expire()
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
			_expire()
			return
		_hit[id] = true
		_play_hit_sfx()
		var origin := global_position
		if node.has_method("try_receive_hit"):
			node.call("try_receive_hit", damage, origin)
		else:
			var dmg := node.get_node_or_null("Damageable")
			if dmg != null and dmg.has_method("take_damage"):
				dmg.take_damage(damage)
	_expire()


func _expire() -> void:
	if _resolving:
		return
	_resolving = true
	_alive = false
	# body_entered locks Area2D; defer monitoring changes.
	set_deferred("monitoring", false)
	set_physics_process(false)
	_play_impact_then_free()


func _play_fly() -> void:
	var sprite := get_node_or_null("Sprite") as AnimatedSprite2D
	if sprite == null or sprite.sprite_frames == null:
		return
	if sprite.sprite_frames.has_animation(&"fly"):
		sprite.play(&"fly")
	elif sprite.sprite_frames.has_animation(&"fx"):
		sprite.play(&"fx")


func _play_impact_then_free() -> void:
	# Draw above enemies (player/enemy use z_index >= 2) and keep sparkles upright.
	z_as_relative = false
	z_index = 20
	rotation = 0.0
	var sprite := get_node_or_null("Sprite") as AnimatedSprite2D
	if sprite != null and sprite.sprite_frames != null and sprite.sprite_frames.has_animation(&"impact"):
		sprite.play(&"impact")
		var hold := impact_hold
		var frames := sprite.sprite_frames
		if frames.get_frame_count(&"impact") > 0:
			hold = maxf(hold, 1.0 / maxf(frames.get_animation_speed(&"impact"), 1.0))
		await get_tree().create_timer(hold).timeout
	_finish_free()


func _finish_free() -> void:
	if _freed:
		return
	_freed = true
	queue_free()


func _play_hit_sfx() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var sfx := player.get_node_or_null("SfxPlayer")
	if sfx != null and sfx.has_method("play_projectile_hit"):
		sfx.call("play_projectile_hit")
