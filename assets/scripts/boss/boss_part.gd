class_name BossPart
extends CharacterBody2D

## Shared base for boss head / hands. Stays active in both WorldMode modes.

signal attack_finished

@export var contact_damage: int = 1
@export var contact_cooldown: float = 0.55
@export var contact_knockback: float = 110.0

@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D

const _MASK_PLAYER := 1 << 1

var _busy: bool = false
var _cancel_requested: bool = false
var _contact_cd: float = 0.0
var _hazard_active: bool = false
var _hurtboxes: Array[Area2D] = []
var _home_position: Vector2 = Vector2.ZERO
var _arena: Rect2 = Rect2()
var _base_collision_layer: int = 0
var _base_collision_mask: int = 0


func _ready() -> void:
	z_index = maxi(z_index, 3)
	# Layer 3 (enemy). Mask: world + player + door_enemy + spikes_enemy.
	collision_layer = 1 << 2
	collision_mask = (1 << 0) | _MASK_PLAYER | (1 << 3) | (1 << 5)
	_base_collision_layer = collision_layer
	_base_collision_mask = collision_mask
	_home_position = global_position
	_configure_hurtboxes()
	set_hazard_active(false)


func _physics_process(delta: float) -> void:
	_contact_cd = maxf(_contact_cd - delta, 0.0)
	if _busy and _hazard_active:
		_try_hurtbox_contact()


func is_busy() -> bool:
	return _busy


func get_home_position() -> Vector2:
	return _home_position


func set_home_position(pos: Vector2) -> void:
	_home_position = pos


func set_arena(bounds: Rect2) -> void:
	_arena = bounds


func get_arena() -> Rect2:
	return _arena


func get_player() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D


func shake_camera(amplitude: float = 4.0, duration: float = 0.25) -> void:
	var player := get_player()
	if player == null:
		return
	var cam := player.get_node_or_null("Camera2D")
	if cam != null and cam.has_method("shake"):
		cam.call("shake", amplitude, duration)


func deal_player_hit(player: Node2D, amount: int = -1, knockback_force: float = -1.0) -> bool:
	if player == null or not player.is_in_group("player"):
		return false
	if _contact_cd > 0.0:
		return false

	var dmg_amount := contact_damage if amount < 0 else amount
	var force := contact_knockback if knockback_force < 0.0 else knockback_force
	var dmg := player.get_node_or_null("Damageable")
	if dmg == null or not dmg.has_method("take_damage"):
		return false

	_contact_cd = contact_cooldown
	dmg.take_damage(dmg_amount)
	if player.has_method("apply_knockback") and force > 0.0:
		var away: Vector2 = player.global_position - global_position
		if away == Vector2.ZERO:
			away = Vector2.DOWN
		player.apply_knockback(away.normalized(), force)
	return true


func play_anim(anim_name: StringName, force: bool = false) -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	if not animated_sprite.sprite_frames.has_animation(anim_name):
		return
	if not force and animated_sprite.animation == anim_name and animated_sprite.is_playing():
		return
	animated_sprite.play(anim_name)


func return_home(duration: float = 0.35) -> void:
	# Recovering should never hurt or shove the player.
	set_hazard_active(false)
	if duration <= 0.0:
		global_position = _home_position
		return
	if not _can_await():
		global_position = _home_position
		return
	# Slow lift-off, then accelerate as more of the path is covered.
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "global_position", _home_position, duration)
	await tween.finished


func set_hazard_active(active: bool) -> void:
	_hazard_active = active
	for area in _hurtboxes:
		if area == null or not is_instance_valid(area):
			continue
		area.set_deferred("monitoring", active)
	if active:
		collision_layer = _base_collision_layer
		collision_mask = _base_collision_mask
	else:
		# Keep world colliders; drop player body interaction so recovery tweens don't push.
		collision_layer = 0
		collision_mask = _base_collision_mask & ~_MASK_PLAYER


func request_cancel() -> void:
	_cancel_requested = true


func is_cancel_requested() -> bool:
	return _cancel_requested


func _begin_attack() -> bool:
	if _busy:
		return false
	_busy = true
	_cancel_requested = false
	set_hazard_active(false)
	return true


func _end_attack() -> void:
	_busy = false
	_cancel_requested = false
	set_hazard_active(false)
	attack_finished.emit()


func _should_abort() -> bool:
	return _cancel_requested or not _can_await()


func _try_hurtbox_contact() -> void:
	if _contact_cd > 0.0 or _hurtboxes.is_empty():
		return
	for area in _hurtboxes:
		if area == null or not area.monitoring:
			continue
		for body in area.get_overlapping_bodies():
			if body != null and body.is_in_group("player"):
				deal_player_hit(body as Node2D)
				return


func _configure_hurtboxes() -> void:
	_hurtboxes.clear()
	_configure_area_tree(self)


func _configure_area_tree(node: Node) -> void:
	for child in node.get_children():
		if child is Area2D:
			var area := child as Area2D
			var lname := area.name.to_lower()
			if lname.contains("weak") or lname.contains("aoe") or lname == "projectile":
				_configure_area_tree(child)
				continue
			area.collision_layer = 0
			area.collision_mask = 1 << 1
			area.monitoring = true
			area.monitorable = false
			if lname.contains("hurt"):
				area.add_to_group("hurtbox")
				if area not in _hurtboxes:
					_hurtboxes.append(area)
		_configure_area_tree(child)


func _wait(seconds: float) -> bool:
	if not _can_await() or _cancel_requested:
		return false
	if seconds <= 0.0:
		await get_tree().process_frame
		return _can_await() and not _cancel_requested
	var left := seconds
	while left > 0.0:
		if not _can_await() or _cancel_requested:
			return false
		await get_tree().physics_frame
		if not _can_await() or _cancel_requested:
			return false
		left -= get_physics_process_delta_time()
	return _can_await() and not _cancel_requested


func _await_physics() -> bool:
	if not _can_await() or _cancel_requested:
		return false
	await get_tree().physics_frame
	return _can_await() and not _cancel_requested


func _can_await() -> bool:
	return is_instance_valid(self) and is_inside_tree() and get_tree() != null
