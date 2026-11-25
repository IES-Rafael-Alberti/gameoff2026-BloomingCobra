extends Node

## Elite enemy brain: idle → aggressive → resting (after charge).

@export var max_health: int = 8
## Held defending pose when the frontal shield blocks a hit (walk/rest only; never cancels charge/spin).
@export var defend_anim_time: float = 0.6

## Pushed from Enemy Stats; used by Idle / Aggressive for aggro and deaggro.
var detection_radius: float = 110.0
var aggro_delay: float = 0.0

var _enemy: CharacterBody2D
var _active: bool = true
var _facing: Vector2 = Vector2.DOWN
var _state_name: StringName = &""
var _states: Dictionary = {}
var _defend_lock: float = 0.0
var _resting_overlay: AnimatedSprite2D = null

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

	_ensure_resting_overlay()
	_setup_modules()
	_setup_states()
	change_state(&"idle")


func set_active(active: bool) -> void:
	_active = active
	if not _active:
		_defend_lock = 0.0
		_enemy.velocity = Vector2.ZERO
		_hide_resting_overlay()
		if charge != null:
			charge.reset()
		if circular != null:
			circular.reset()


func physics_update(delta: float) -> void:
	if not _active or _enemy == null:
		return
	if _defend_lock > 0.0:
		_defend_lock = maxf(_defend_lock - delta, 0.0)
		# Keep the pose only while attacks aren't owning the sprite.
		if not _attack_owns_sprite():
			play_defense_anim()
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
		_trigger_defend_anim()
		return false

	var dmg := _enemy.get_node_or_null("Damageable")
	if dmg != null and dmg.has_method("take_damage"):
		var to_hit: Vector2 = hit_origin - _enemy.global_position
		if to_hit != Vector2.ZERO:
			set_facing(to_hit)
		dmg.take_damage(amount)
		# No hurt clip — definitive art only has defending for shield blocks.
		return true
	return false


func _trigger_defend_anim() -> void:
	# Charge / spin keep ownership of the sprite; only flash defend otherwise.
	if _attack_owns_sprite():
		return
	_defend_lock = defend_anim_time
	play_defense_anim()


func play_walk_anim(dir: Vector2) -> void:
	if _defend_lock > 0.0:
		return
	_hide_resting_overlay()
	_enemy.call("set_attacking", false)
	_enemy.call("play_directional_animation", "walking", dir)


## Windup frames only (everything except the last). Last frame is the dash pose.
func play_charge_windup(dir: Vector2) -> void:
	_defend_lock = 0.0
	_hide_resting_overlay()
	_enemy.call("set_attacking", true)
	_enemy.call("play_directional_animation", "charge", dir)
	_clamp_charge_to_windup()


## Hold the final charge frame while dashing.
func play_charge_dash(dir: Vector2) -> void:
	_defend_lock = 0.0
	_hide_resting_overlay()
	_enemy.call("set_attacking", true)
	_enemy.call("play_directional_animation", "charge", dir)
	var sprite := _main_sprite()
	if sprite == null or sprite.sprite_frames == null:
		return
	var anim := sprite.animation
	var count := sprite.sprite_frames.get_frame_count(anim)
	if count <= 0:
		return
	sprite.frame = count - 1
	sprite.pause()


func play_charge_anim(dir: Vector2) -> void:
	## Legacy entry — treat as windup.
	play_charge_windup(dir)


func play_defense_anim() -> void:
	if _attack_owns_sprite():
		return
	_hide_resting_overlay()
	_enemy.call("set_attacking", true)
	var sprite := _main_sprite()
	if sprite != null and sprite.sprite_frames != null and sprite.sprite_frames.has_animation("defending_down"):
		_enemy.call("play_directional_animation", "defending", _facing)
	elif sprite != null and sprite.sprite_frames != null and sprite.sprite_frames.has_animation("defense_down"):
		_enemy.call("play_directional_animation", "defense", _facing)
	elif sprite != null and sprite.sprite_frames != null and sprite.sprite_frames.has_animation("resting_down"):
		_enemy.call("play_directional_animation", "resting", _facing)
	else:
		_enemy.call("play_directional_animation", "walking", Vector2.ZERO)
	# Single-frame clips: hold the pose instead of letting another anim resume.
	if sprite != null and String(sprite.animation).begins_with("defending"):
		sprite.pause()


func play_resting_anim(dir: Vector2) -> void:
	if _defend_lock > 0.0:
		return
	_hide_resting_overlay()
	_enemy.call("set_attacking", true)
	_enemy.call("play_directional_animation", "resting", dir)


func play_rotate_attack() -> void:
	_defend_lock = 0.0
	_enemy.call("set_attacking", true)
	var sprite := _main_sprite()
	if sprite == null:
		return
	# Only start once — calling play() every frame restarts the anim at frame 0.
	if sprite.animation != &"rotate_attack" or not sprite.is_playing():
		sprite.play("rotate_attack")
	_show_resting_overlay(_facing)


func _attack_owns_sprite() -> bool:
	if charge != null and charge.has_method("is_busy") and charge.is_busy():
		return true
	if circular != null and circular.has_method("is_busy") and circular.is_busy():
		return true
	return false


func clear_rotate_attack_overlay() -> void:
	_hide_resting_overlay()


func _clamp_charge_to_windup() -> void:
	var sprite := _main_sprite()
	if sprite == null or sprite.sprite_frames == null:
		return
	var anim := sprite.animation
	var count := sprite.sprite_frames.get_frame_count(anim)
	if count < 2:
		return
	# Loop windup frames only; never hold on the dash (last) frame.
	if count == 2:
		sprite.frame = 0
		sprite.pause()
		return
	if sprite.frame >= count - 1:
		sprite.frame = 0


func _main_sprite() -> AnimatedSprite2D:
	if _enemy == null:
		return null
	return _enemy.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D


func _ensure_resting_overlay() -> void:
	if _enemy == null:
		return
	_resting_overlay = _enemy.get_node_or_null("RestingOverlay") as AnimatedSprite2D
	if _resting_overlay != null:
		_resting_overlay.visible = false
		return
	var main := _main_sprite()
	_resting_overlay = AnimatedSprite2D.new()
	_resting_overlay.name = "RestingOverlay"
	_resting_overlay.visible = false
	_resting_overlay.z_index = 1
	if main != null:
		_resting_overlay.position = main.position
		_resting_overlay.scale = main.scale
		_resting_overlay.sprite_frames = main.sprite_frames
		_resting_overlay.texture_filter = main.texture_filter
	_enemy.add_child(_resting_overlay)


func _show_resting_overlay(dir: Vector2) -> void:
	_ensure_resting_overlay()
	if _resting_overlay == null or _resting_overlay.sprite_frames == null:
		return
	var facing := dir if dir != Vector2.ZERO else _facing
	var anim := _resting_anim_name(facing)
	if not _resting_overlay.sprite_frames.has_animation(anim):
		return
	var main := _main_sprite()
	if main != null:
		_resting_overlay.position = main.position
		_resting_overlay.scale = main.scale
		_resting_overlay.flip_h = main.flip_h
	_resting_overlay.visible = true
	if _resting_overlay.animation != anim or not _resting_overlay.is_playing():
		_resting_overlay.play(anim)


func _hide_resting_overlay() -> void:
	if _resting_overlay == null:
		return
	_resting_overlay.visible = false
	_resting_overlay.stop()


func _resting_anim_name(dir: Vector2) -> StringName:
	var facing := cardinal_from(dir)
	if facing == Vector2.LEFT:
		return &"resting_left"
	if facing == Vector2.RIGHT:
		return &"resting_right"
	if facing == Vector2.UP:
		return &"resting_up"
	return &"resting_down"


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
