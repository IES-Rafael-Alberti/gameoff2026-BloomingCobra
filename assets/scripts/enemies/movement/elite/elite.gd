extends Node

## Elite enemy brain: idle → aggressive → resting (after charge).

@export var max_health: int = 8
@export var hurt_anim_time: float = 0.4

## Pushed from Enemy Stats; used by Idle / Aggressive for aggro and deaggro.
var detection_radius: float = 110.0
var aggro_delay: float = 0.0

var _enemy: CharacterBody2D
var _active: bool = true
var _facing: Vector2 = Vector2.DOWN
var _state_name: StringName = &""
var _states: Dictionary = {}
var _hurt_lock: float = 0.0

var shield: Node
var charge: Node
var circular: Node


func setup(enemy: CharacterBody2D) -> void:
	_enemy = enemy
	_enemy.collision_layer = 1 << 2
	# world + enemy + door_enemy + spikes_enemy
	_enemy.collision_mask = (1 << 0) | (1 << 2) | (1 << 3) | (1 << 5)

	var dmg := _enemy.get_node_or_null("Damageable")
	if dmg != null and "max_health" in dmg:
		dmg.max_health = max_health
		dmg.health = max_health
	if dmg != null and dmg.has_signal("damaged") and not dmg.damaged.is_connected(_on_damaged):
		dmg.damaged.connect(_on_damaged)

	_setup_modules()
	_setup_states()
	change_state(&"idle")


func set_active(active: bool) -> void:
	_active = active
	if not _active:
		_hurt_lock = 0.0
		_enemy.velocity = Vector2.ZERO
		if charge != null:
			charge.reset()
		if circular != null:
			circular.reset()


func physics_update(delta: float) -> void:
	if not _active or _enemy == null:
		return
	# Keep hurt animation visible; don't let states overwrite it immediately.
	if _hurt_lock > 0.0:
		_hurt_lock = maxf(_hurt_lock - delta, 0.0)
		_enemy.velocity = Vector2.ZERO
		play_hurt_anim(_facing)
		return
	var state: EliteState = _states.get(_state_name) as EliteState
	if state != null:
		state.physics_update(delta)


func change_state(next: StringName) -> void:
	if next == _state_name:
		return
	var current: EliteState = _states.get(_state_name) as EliteState
	if current != null:
		current.exit(next)
	var previous := _state_name
	_state_name = next
	var state: EliteState = _states.get(_state_name) as EliteState
	if state != null:
		state.enter(previous)


func on_charge_finished() -> void:
	change_state(&"resting")


func get_enemy() -> CharacterBody2D:
	return _enemy


func get_player() -> Node2D:
	return _enemy.get_tree().get_first_node_in_group("player") as Node2D


func get_facing() -> Vector2:
	return _facing


func set_facing(dir: Vector2) -> void:
	if dir == Vector2.ZERO:
		return
	_facing = cardinal_from(dir)
	if shield != null and shield.has_method("update_facing"):
		shield.update_facing(_facing)


func set_shield_active(active: bool) -> void:
	if shield != null and shield.has_method("set_shield_active"):
		shield.set_shield_active(active)


func cardinal_from(dir: Vector2) -> Vector2:
	if dir == Vector2.ZERO:
		return _facing if _facing != Vector2.ZERO else Vector2.DOWN
	if absf(dir.x) >= absf(dir.y):
		return Vector2.RIGHT if dir.x > 0.0 else Vector2.LEFT
	return Vector2.DOWN if dir.y > 0.0 else Vector2.UP


## Called by player attacks. Returns true if damage was applied.
func try_receive_hit(amount: int, hit_origin: Vector2) -> bool:
	if not _active:
		return false
	if shield != null and shield.has_method("blocks_hit_from") and shield.blocks_hit_from(hit_origin):
		var player := get_player()
		if shield.has_method("apply_block_to_player"):
			shield.apply_block_to_player(player)
		play_defense_anim()
		return false

	var dmg := _enemy.get_node_or_null("Damageable")
	if dmg != null and dmg.has_method("take_damage"):
		# Face the attacker so the correct directional hurt plays.
		var to_hit: Vector2 = hit_origin - _enemy.global_position
		if to_hit != Vector2.ZERO:
			set_facing(to_hit)
		dmg.take_damage(amount)
		_trigger_hurt_anim()
		return true
	return false


func _on_damaged(_amount: int, _current_health: int) -> void:
	# Backup path if damage bypasses try_receive_hit.
	if _hurt_lock <= 0.0:
		_trigger_hurt_anim()


func _trigger_hurt_anim() -> void:
	_hurt_lock = hurt_anim_time
	play_hurt_anim(_facing)


func play_walk_anim(dir: Vector2) -> void:
	_enemy.call("set_attacking", false)
	_enemy.call("play_directional_animation", "walking", dir)


func play_charge_anim(dir: Vector2) -> void:
	_enemy.call("set_attacking", true)
	_enemy.call("play_directional_animation", "charge", dir)


func play_defense_anim() -> void:
	# Idle/defend uses resting frames as guarded stance when defense_* is absent.
	_enemy.call("set_attacking", true)
	var sprite := _enemy.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite != null and sprite.sprite_frames != null and sprite.sprite_frames.has_animation("resting_down"):
		_enemy.call("play_directional_animation", "resting", _facing)
	elif sprite != null and sprite.sprite_frames != null and sprite.sprite_frames.has_animation("defense_down"):
		_enemy.call("play_directional_animation", "defense", _facing)
	else:
		_enemy.call("play_directional_animation", "walking", Vector2.ZERO)


func play_hurt_anim(dir: Vector2) -> void:
	_enemy.call("set_attacking", true)
	var hurt_dir := dir if dir != Vector2.ZERO else _facing
	_enemy.call("play_directional_animation", "hurt", hurt_dir)


func play_resting_anim(dir: Vector2) -> void:
	_enemy.call("set_attacking", true)
	_enemy.call("play_directional_animation", "resting", dir)


func play_rotate_attack() -> void:
	_enemy.call("set_attacking", true)
	var sprite := _enemy.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null:
		return
	# Only start once — calling play() every frame restarts the anim at frame 0.
	if sprite.animation != &"rotate_attack" or not sprite.is_playing():
		sprite.play("rotate_attack")


func _setup_modules() -> void:
	var defend := _enemy.get_node_or_null("States/Aggresive/Defend")
	var shield_area := _enemy.get_node_or_null("States/Aggresive/Defend/shield") as Area2D
	if defend != null and defend.has_method("setup"):
		shield = defend
		shield.setup(self, shield_area)

	var charge_node := _enemy.get_node_or_null("States/Aggresive/Charge")
	var charge_hurt := _enemy.get_node_or_null("States/Aggresive/Charge/hurtbox") as Area2D
	if charge_node != null and charge_node.has_method("setup"):
		charge = charge_node
		charge.setup(self, charge_hurt)

	var circular_node := _enemy.get_node_or_null("States/Aggresive/Circular")
	var circular_area := _enemy.get_node_or_null("States/Aggresive/Circular/attack") as Area2D
	if circular_node != null and circular_node.has_method("setup"):
		circular = circular_node
		circular.setup(self, circular_area)


func _setup_states() -> void:
	_register_state(&"idle", "States/Idle")
	_register_state(&"aggressive", "States/Aggresive")
	_register_state(&"resting", "States/Resting")


func _register_state(key: StringName, path: String) -> void:
	var node := _enemy.get_node_or_null(path)
	if node == null:
		push_warning("Elite missing state node: %s" % path)
		return
	if node.has_method("setup"):
		node.setup(self)
	_states[key] = node
