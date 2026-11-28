class_name BreakableProp
extends CharacterBody2D

## Breakable prop driven by a PropBreakableDef. Uses CharacterBody2D so player
## melee Areas detect it the same way they detect enemies.

const LAYER_WORLD := 1 << 0
const LAYER_ENEMY := 1 << 2
const LAYER_PROP_BREAKABLE := 1 << 6 # physics layer 7
const DEFAULT_DEFINITION := preload("res://assets/resources/props/breakable_crate.tres")

@export var definition: PropBreakableDef = DEFAULT_DEFINITION
## When set, the prop stays in the scene showing this sprite after breaking
## instead of being freed. Region/scale should match the intact sprite.
@export var broken_texture: Texture2D
@export var broken_sprite_offset: Vector2 = Vector2.ZERO

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var damageable: Node2D = $Damageable
@onready var hurtbox: Area2D = $Hurtbox


func _ready() -> void:
	add_to_group("prop_breakable")
	add_to_group("prop_hittable")
	z_index = maxi(z_index, 1)
	# World blocks movement; enemy + prop_breakable make melee/projectiles connect.
	collision_layer = LAYER_WORLD | LAYER_ENEMY | LAYER_PROP_BREAKABLE
	collision_mask = 0
	motion_mode = MOTION_MODE_FLOATING
	if collision_shape != null:
		collision_shape.disabled = false
	_configure_hurtbox()
	apply_definition()
	if damageable != null:
		if damageable.has_signal("died") and not damageable.died.is_connected(_on_died):
			damageable.died.connect(_on_died)


func _configure_hurtbox() -> void:
	if hurtbox == null:
		return
	hurtbox.add_to_group("hurtbox")
	hurtbox.collision_layer = LAYER_PROP_BREAKABLE
	hurtbox.collision_mask = 0
	hurtbox.monitoring = false
	hurtbox.monitorable = true
	hurtbox.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	var shape := hurtbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape != null and collision_shape != null and collision_shape.shape != null:
		shape.shape = collision_shape.shape.duplicate()
		shape.disabled = false


func apply_definition() -> void:
	var def: PropBreakableDef = definition if definition != null else DEFAULT_DEFINITION
	def.apply_visual(sprite, self)
	def.apply_collision_shape(collision_shape)
	if hurtbox != null:
		var shape := hurtbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if shape != null:
			def.apply_collision_shape(shape)
			shape.disabled = false
	if damageable != null:
		if "max_health" in damageable:
			damageable.max_health = maxi(def.max_health, 1)
		if "health" in damageable:
			damageable.health = damageable.max_health
		if "invulnerability_time" in damageable:
			damageable.invulnerability_time = def.hit_invulnerability_time


func try_receive_hit(amount: int, _hit_origin: Vector2) -> bool:
	if damageable != null and damageable.has_method("take_damage"):
		damageable.take_damage(amount)
		return true
	return false


func _on_died() -> void:
	# Death arrives inside a physics query flush (melee hitbox body_entered), so
	# collider/Area2D state must not change here. Mark the prop dead right away —
	# those are not physics state — and let the rest run on the next idle frame.
	if damageable != null and "immortal" in damageable:
		damageable.immortal = true
	remove_from_group("prop_breakable")
	remove_from_group("prop_hittable")
	var def: PropBreakableDef = definition if definition != null else DEFAULT_DEFINITION
	_try_spawn_loot.call_deferred()
	if broken_texture != null:
		_show_broken_state.call_deferred()
		return
	if def.destroy_on_death:
		queue_free.call_deferred()


## Leaves the debris on the floor and makes the prop non-interactive.
func _show_broken_state() -> void:
	if sprite != null:
		sprite.texture = broken_texture
		sprite.position += broken_sprite_offset
	if damageable != null and "immortal" in damageable:
		damageable.immortal = true
	collision_layer = 0
	collision_mask = 0
	if collision_shape != null:
		collision_shape.set_deferred("disabled", true)
	if hurtbox != null:
		hurtbox.collision_layer = 0
		hurtbox.collision_mask = 0
		hurtbox.set_deferred("monitoring", false)
		hurtbox.remove_from_group("hurtbox")
		var shape := hurtbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if shape != null:
			shape.set_deferred("disabled", true)
	remove_from_group("prop_breakable")
	remove_from_group("prop_hittable")


func _try_spawn_loot() -> void:
	var def: PropBreakableDef = definition if definition != null else DEFAULT_DEFINITION
	if def.loot_scene == null:
		return
	if randf() > def.loot_chance:
		return
	var loot: Node = def.loot_scene.instantiate()
	var parent := get_parent()
	if parent == null:
		return
	parent.add_child(loot)
	if loot is Node2D:
		(loot as Node2D).global_position = global_position
