class_name PropSpikes
extends Area2D

## Floor spikes: damage ticks while the player stands on them.
## Solid only for enemies (avoidance). Present in dream and nightmare.

const LAYER_SPIKES_ENEMY := 1 << 5 # physics layer 6

@export var damage: int = 1
## Seconds between damage ticks while the player remains on the spikes.
@export var damage_interval: float = 0.55
@export var texture: Texture2D = preload("res://assets/sprites/props/static/spikes.png")

@onready var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D

var _players_on: Array[Node2D] = []
var _tick_left: float = 0.0


func _ready() -> void:
	add_to_group("prop_spikes")
	z_index = 1
	# Stay detectable even if a parent room pauses briefly.
	disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	collision_layer = 0
	collision_mask = 1 << 1 # player body
	monitoring = true
	monitorable = false
	set_physics_process(true)
	if sprite != null and texture != null:
		sprite.texture = texture
	_ensure_enemy_blocker()
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)


func _physics_process(delta: float) -> void:
	_prune_players()
	if _players_on.is_empty():
		_tick_left = 0.0
		return

	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left = maxf(damage_interval, 0.05)
	for player in _players_on:
		_damage_player(player)


func _on_body_entered(body: Node2D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	if body in _players_on:
		return
	_players_on.append(body)
	# Immediate tick on step-on, then keep ticking while standing still.
	_damage_player(body)
	_tick_left = maxf(damage_interval, 0.05)


func _on_body_exited(body: Node2D) -> void:
	if body == null:
		return
	_players_on.erase(body)


func _damage_player(player: Node2D) -> void:
	if player == null or not is_instance_valid(player):
		return
	var dmg := player.get_node_or_null("Damageable")
	if dmg != null and dmg.has_method("take_damage"):
		dmg.take_damage(damage)


func _prune_players() -> void:
	_players_on = _players_on.filter(
		func(p: Node2D) -> bool: return p != null and is_instance_valid(p)
	)


func _ensure_enemy_blocker() -> void:
	var blocker := get_node_or_null("EnemyBlocker") as StaticBody2D
	if blocker == null:
		blocker = StaticBody2D.new()
		blocker.name = "EnemyBlocker"
		add_child(blocker)
	blocker.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	# Only enemies collide with this; the player walks through and takes damage via Area2D.
	blocker.collision_layer = LAYER_SPIKES_ENEMY
	blocker.collision_mask = 0

	var shape := blocker.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape == null:
		shape = CollisionShape2D.new()
		shape.name = "CollisionShape2D"
		blocker.add_child(shape)
	var area_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if area_shape != null and area_shape.shape != null:
		shape.shape = area_shape.shape
		shape.position = area_shape.position
	elif shape.shape == null:
		var rect := RectangleShape2D.new()
		rect.size = Vector2(14, 14)
		shape.shape = rect
