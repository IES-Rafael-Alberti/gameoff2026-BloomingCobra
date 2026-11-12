class_name Enemy
extends CharacterBody2D

@export_group("Stats")
@export var max_health: int = 3
@export var move_speed: float = 55.0
## Seconds between attacks. 0 = this enemy does not use an attack cooldown.
@export var attack_cooldown: float = 0.0
## Aggro / deaggro radius for aggressive enemies (Hunter, Ranger, Elite).
@export var detection_radius: float = 110.0
## Seconds in detection range before entering aggressive. 0 = immediate.
@export var aggro_delay: float = 0.0

@export_group("Contact")
@export var contact_damage: int = 1
@export var contact_cooldown: float = 0.65
@export var contact_knockback: float = 100.0
@export var hurt_anim_time: float = 0.35
## Alpha fade after death (and optional death clip) before freeing.
@export var death_fade_time: float = 0.55

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var damageable: Node2D = $Damageable
@onready var switchable: Node2D = $Switchable
@onready var sfx: Node = get_node_or_null("SfxPlayer")

var _movement: Node = null
var _active: bool = true
var _attacking: bool = false
var _contact_cd: float = 0.0
var _hurtboxes: Array[Area2D] = []
var _hurt_lock: float = 0.0
var _hurt_facing: Vector2 = Vector2.DOWN
var _dying: bool = false


func _ready() -> void:
	add_to_group("enemy")
	# Draw above floor props (spikes use z_index 1).
	z_index = maxi(z_index, 2)
	# world + player + door_enemy + spikes_enemy
	collision_layer = 1 << 2
	collision_mask = (1 << 0) | (1 << 1) | (1 << 3) | (1 << 5)
	_configure_areas()
	_movement = _find_movement()
	if _movement and _movement.has_method("setup"):
		_movement.setup(self)
	_apply_stats()
	if damageable.has_signal("died"):
		damageable.died.connect(_on_died)
	if damageable.has_signal("damaged"):
		damageable.damaged.connect(_on_damaged)
	if switchable.has_signal("mode_changed"):
		switchable.mode_changed.connect(_on_mode_changed)
		_on_mode_changed(switchable.get_mode())


func _apply_stats() -> void:
	if damageable != null:
		damageable.max_health = maxi(max_health, 1)
		damageable.health = damageable.max_health

	var elite_brain := get_node_or_null("Elite")
	if elite_brain != null and "max_health" in elite_brain:
		elite_brain.max_health = damageable.max_health if damageable != null else max_health

	if move_speed > 0.0:
		if _movement != null and "speed" in _movement:
			_movement.speed = move_speed
		var aggressive := get_node_or_null("States/Aggresive")
		if aggressive != null and "move_speed" in aggressive:
			aggressive.move_speed = move_speed

	if attack_cooldown > 0.0:
		if _movement != null:
			if "attack_cooldown" in _movement:
				_movement.attack_cooldown = attack_cooldown
			if "fire_cooldown" in _movement:
				_movement.fire_cooldown = attack_cooldown
		var circular := get_node_or_null("States/Aggresive/Circular")
		if circular != null and "cooldown" in circular:
			circular.cooldown = attack_cooldown

	if _movement != null:
		if "detection_radius" in _movement:
			_movement.detection_radius = maxf(detection_radius, 0.0)
		if "aggro_delay" in _movement:
			_movement.aggro_delay = maxf(aggro_delay, 0.0)
	_push_detection_to_idle(get_node_or_null("States/Idle"))
	if _movement != null:
		_push_detection_to_idle(_movement.get_node_or_null("Idle"))


## Radius drawn by F1 hitbox debug for aggressive brains. 0 = hidden.
func get_detection_debug_radius() -> float:
	if detection_radius <= 0.0 or _movement == null:
		return 0.0
	var brain_name := String(_movement.name)
	if brain_name in ["Hunter", "Ranger", "Elite"]:
		return detection_radius
	return 0.0


func _push_detection_to_idle(idle: Node) -> void:
	if idle == null:
		return
	if "detection_radius" in idle:
		idle.detection_radius = maxf(detection_radius, 0.0)
	if "aggro_delay" in idle:
		idle.aggro_delay = maxf(aggro_delay, 0.0)
	# Legacy Elite export name.
	if "aggro_range" in idle:
		idle.aggro_range = maxf(detection_radius, 0.0)


func _physics_process(delta: float) -> void:
	if _dying:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	_contact_cd = maxf(_contact_cd - delta, 0.0)
	if _hurt_lock > 0.0:
		_hurt_lock = maxf(_hurt_lock - delta, 0.0)
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if not _active or _movement == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if _movement.has_method("physics_update"):
		_movement.physics_update(delta)
	if _uses_generic_contact():
		_try_hurtbox_contact()
	move_and_slide()


func is_active() -> bool:
	return _active and not _dying


func set_attacking(value: bool) -> void:
	_attacking = value


func play_directional_animation(prefix: String, direction: Vector2) -> void:
	if _dying or _hurt_lock > 0.0:
		return
	var frames := animated_sprite.sprite_frames if animated_sprite != null else null
	if frames == null:
		return
	if direction == Vector2.ZERO:
		if not _attacking and frames.has_animation(&"idle"):
			animated_sprite.play(&"idle")
		return

	var anim := _resolve_directional_anim(prefix, direction, frames)
	if anim.is_empty():
		return
	animated_sprite.play(anim)
	if (prefix == "walking" or prefix == "walk") and sfx != null and sfx.has_method("play_walking"):
		sfx.call("play_walking")


## Prefer *_sides / *_up / *_down; fall back to a single shared clip (e.g. walking).
func _resolve_directional_anim(prefix: String, direction: Vector2, frames: SpriteFrames) -> StringName:
	var sides := StringName("%s_sides" % prefix)
	var up := StringName("%s_up" % prefix)
	var down := StringName("%s_down" % prefix)
	var base := StringName(prefix)
	var has_sides := frames.has_animation(sides)
	var has_up := frames.has_animation(up)
	var has_down := frames.has_animation(down)
	var has_base := frames.has_animation(base)

	if absf(direction.x) > absf(direction.y):
		animated_sprite.flip_h = direction.x < 0.0
		if has_sides:
			return sides
		if has_base:
			return base
		return &""

	if direction.y < 0.0:
		if has_up:
			animated_sprite.flip_h = false
			return up
		if has_base:
			if absf(direction.x) > 0.01:
				animated_sprite.flip_h = direction.x < 0.0
			return base
		if has_sides:
			animated_sprite.flip_h = direction.x < 0.0
			return sides
		return &""

	if has_down:
		animated_sprite.flip_h = false
		return down
	if has_base:
		if absf(direction.x) > 0.01:
			animated_sprite.flip_h = direction.x < 0.0
		return base
	if has_sides:
		animated_sprite.flip_h = direction.x < 0.0
		return sides
	return &""


func get_player() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D


## Hit the player (damage + knockback). Shared by contact, attacks, and projectiles.
func deal_player_hit(player: Node2D, amount: int = -1, knockback_force: float = -1.0) -> bool:
	if not _active or player == null or not player.is_in_group("player"):
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


## Optional elite/shielded hit hook. Falls back to flat damage.
func try_receive_hit(amount: int, hit_origin: Vector2) -> bool:
	if _movement != null and _movement.has_method("try_receive_hit"):
		return bool(_movement.call("try_receive_hit", amount, hit_origin))
	if damageable != null and damageable.has_method("take_damage"):
		var toward := hit_origin - global_position
		if toward != Vector2.ZERO:
			_hurt_facing = _cardinal_from(toward)
		damageable.take_damage(amount)
		return true
	return false


func _on_damaged(_amount: int, _current_health: int) -> void:
	# Elite already owns its hurt feedback.
	if get_node_or_null("Elite") != null:
		return
	var divisible := get_node_or_null("Dividisible")
	if divisible != null and divisible.has_method("is_splitting") and bool(divisible.call("is_splitting")):
		return
	_trigger_hurt_anim()


func clear_hurt_lock() -> void:
	_hurt_lock = 0.0


func _trigger_hurt_anim() -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	if not animated_sprite.sprite_frames.has_animation("hurt_down"):
		return
	_hurt_lock = hurt_anim_time
	play_hurt_animation(_hurt_facing)


func play_hurt_animation(direction: Vector2) -> void:
	var dir := direction if direction != Vector2.ZERO else Vector2.DOWN
	var anim_name := "hurt_down"
	if absf(dir.x) > absf(dir.y):
		anim_name = "hurt_sides"
		animated_sprite.flip_h = dir.x < 0.0
	elif dir.y < 0.0:
		anim_name = "hurt_up"
		animated_sprite.flip_h = false
	else:
		animated_sprite.flip_h = false

	var frames := animated_sprite.sprite_frames
	if frames != null and frames.has_animation(anim_name):
		frames.set_animation_loop(anim_name, false)
		animated_sprite.play(anim_name)


func _cardinal_from(dir: Vector2) -> Vector2:
	if absf(dir.x) >= absf(dir.y):
		return Vector2.RIGHT if dir.x > 0.0 else Vector2.LEFT
	return Vector2.DOWN if dir.y > 0.0 else Vector2.UP


func _uses_generic_contact() -> bool:
	# Elite has its own contact / attack damage paths.
	return get_node_or_null("Elite") == null


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


func _find_movement() -> Node:
	for child_name in ["Hunter", "Ranger", "Roamer", "Bouncer", "Runner", "Elite"]:
		var node := get_node_or_null(child_name)
		if node != null and node.get_script() != null:
			return node
	return null


func _on_mode_changed(index: int) -> void:
	if _dying:
		return
	_active = index == 0
	if _movement and _movement.has_method("set_active"):
		_movement.set_active(_active)
	_set_hitboxes_enabled(_active)
	if sfx != null and sfx.has_method("set_active"):
		sfx.call("set_active", _active)
	elif sfx != null and not _active and sfx.has_method("stop_all"):
		# Ensure room-global one-shots (hunter steps, etc.) die on mode flip.
		sfx.call("stop_all")
	if not _active:
		velocity = Vector2.ZERO
		_attacking = false
		if animated_sprite.sprite_frames != null and animated_sprite.sprite_frames.has_animation("inactive"):
			animated_sprite.play("inactive")


func _set_hitboxes_enabled(enabled: bool) -> void:
	var body_shape := _find_body_shape()
	if body_shape != null:
		body_shape.disabled = not enabled

	for child in get_children():
		if child is Area2D and child.name != "Projectile":
			var area := child as Area2D
			area.monitoring = enabled
			area.monitorable = false
			for shape in area.get_children():
				if shape is CollisionShape2D:
					shape.disabled = not enabled


func _find_body_shape() -> CollisionShape2D:
	var named := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if named != null:
		return named
	return get_node_or_null("Hitbox") as CollisionShape2D


func _configure_areas() -> void:
	_hurtboxes.clear()
	_configure_area_tree(self)


func _configure_area_tree(node: Node) -> void:
	for child in node.get_children():
		if child is Area2D:
			var area := child as Area2D
			if area.name == "Projectile":
				area.collision_layer = 0
				area.collision_mask = (1 << 0) | (1 << 1)
			else:
				area.collision_layer = 0
				area.collision_mask = 1 << 1
				area.monitoring = true
				area.monitorable = false
				var lname := area.name.to_lower()
				if lname.contains("hurt") or lname.contains("shield"):
					area.add_to_group("hurtbox")
					if lname.contains("hurt") and area not in _hurtboxes:
						_hurtboxes.append(area)
		_configure_area_tree(child)


func _on_died() -> void:
	if _dying:
		return
	_dying = true
	_active = false
	_attacking = false
	_hurt_lock = 999.0
	velocity = Vector2.ZERO
	_set_hitboxes_enabled(false)
	if sfx != null and sfx.has_method("stop_all"):
		sfx.call("stop_all")
	elif sfx != null and sfx.has_method("stop_standard"):
		sfx.call("stop_standard")

	var played_death := _play_death_animation()
	var fade := create_tween()
	fade.set_parallel(false)
	fade.tween_property(self, "modulate:a", 0.0, maxf(death_fade_time, 0.05))

	if played_death and animated_sprite != null:
		await animated_sprite.animation_finished
	if is_instance_valid(fade) and fade.is_running():
		await fade.finished
	elif modulate.a > 0.0:
		modulate.a = 0.0
	queue_free()


func _play_death_animation() -> bool:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return false
	var frames := animated_sprite.sprite_frames
	for anim_name in [&"dead", &"death", &"die"]:
		if not frames.has_animation(anim_name):
			continue
		frames.set_animation_loop(anim_name, false)
		animated_sprite.play(anim_name)
		return true
	return false
