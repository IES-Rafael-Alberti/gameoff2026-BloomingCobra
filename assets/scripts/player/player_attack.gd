extends Node2D

## Nightmare-only attacks: slash (tap), thrust (half charge), projectile (full).

enum AttackKind { NONE, SLASH, THRUST, PROJECTILE }

@export var charge_time: float = 0.9
@export var half_threshold: float = 0.5
@export var slash_damage: int = 1
@export var thrust_damage: int = 2
@export var projectile_damage: int = 2
@export var slash_active_time: float = 0.12
@export var thrust_active_time: float = 0.14
@export var attack_recover_time: float = 0.22
@export var projectile_speed: float = 160.0
@export var slash_texture: Texture2D
@export var thrust_texture: Texture2D
@export var projectile_texture: Texture2D

var _player: CharacterBody2D
var _charging: bool = false
var _charge: float = 0.0
var _busy: bool = false
var _enabled: bool = true
var _hit_ids: Dictionary = {}

var _slash_hitbox: Area2D
var _thrust_hitbox: Area2D
var _fx: Sprite2D
var _charge_bar: Node2D
var _active_kind: AttackKind = AttackKind.NONE


func setup(player: CharacterBody2D) -> void:
	_player = player
	_build_hitboxes()
	_build_fx()
	_charge_bar = player.get_node_or_null("ChargeBar")


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled:
		_cancel_charge()


func is_busy() -> bool:
	return _busy


func _physics_process(delta: float) -> void:
	if _player == null:
		return
	if not _enabled:
		if _charging:
			_cancel_charge()
		return

	if _busy:
		return

	if Input.is_action_just_pressed("attack"):
		_charging = true
		_charge = 0.0
		if _charge_bar != null and _charge_bar.has_method("show_charge"):
			_charge_bar.show_charge(0.0)

	if _charging:
		if Input.is_action_pressed("attack"):
			_charge = minf(_charge + delta / maxf(charge_time, 0.01), 1.0)
			if _charge_bar != null and _charge_bar.has_method("show_charge"):
				_charge_bar.show_charge(_charge)
		if Input.is_action_just_released("attack"):
			_release_attack()


func _release_attack() -> void:
	_charging = false
	if _charge_bar != null and _charge_bar.has_method("hide_bar"):
		_charge_bar.hide_bar()

	var kind := AttackKind.SLASH
	if _charge >= 1.0:
		kind = AttackKind.PROJECTILE
	elif _charge >= half_threshold:
		kind = AttackKind.THRUST

	_charge = 0.0
	_perform(kind)


func _cancel_charge() -> void:
	_charging = false
	_charge = 0.0
	if _charge_bar != null and _charge_bar.has_method("hide_bar"):
		_charge_bar.hide_bar()


func _perform(kind: AttackKind) -> void:
	_busy = true
	_hit_ids.clear()
	_active_kind = kind
	var facing := _cardinal_facing()

	_player.call("play_attack_animation", facing)
	_play_attack_sfx(kind)

	match kind:
		AttackKind.SLASH:
			await _activate_melee(_slash_hitbox, facing, slash_damage, slash_active_time, slash_texture, 0.85)
		AttackKind.THRUST:
			await _activate_melee(_thrust_hitbox, facing, thrust_damage, thrust_active_time, thrust_texture, 1.0)
		AttackKind.PROJECTILE:
			_spawn_projectile(facing)
			await get_tree().create_timer(attack_recover_time).timeout
		_:
			pass

	_disable_hitboxes()
	_fx.visible = false
	_active_kind = AttackKind.NONE
	_busy = false


func _player_sfx() -> Node:
	if _player == null:
		return null
	return _player.get_node_or_null("SfxPlayer")


func _play_attack_sfx(kind: AttackKind) -> void:
	var sfx := _player_sfx()
	if sfx == null:
		return
	match kind:
		AttackKind.SLASH:
			if sfx.has_method("play_slash"):
				sfx.call("play_slash")
		AttackKind.THRUST:
			if sfx.has_method("play_stab"):
				sfx.call("play_stab")
		AttackKind.PROJECTILE:
			if sfx.has_method("play_projectile"):
				sfx.call("play_projectile")
		_:
			pass


func _play_hit_sfx() -> void:
	var sfx := _player_sfx()
	if sfx == null:
		return
	match _active_kind:
		AttackKind.SLASH:
			if sfx.has_method("play_slash_hit"):
				sfx.call("play_slash_hit")
		AttackKind.THRUST:
			if sfx.has_method("play_stab_hit"):
				sfx.call("play_stab_hit")
		_:
			pass


func _activate_melee(
	hitbox: Area2D,
	facing: Vector2,
	damage: int,
	active_time: float,
	tex: Texture2D,
	fx_scale: float
) -> void:
	_disable_hitboxes()
	hitbox.rotation = facing.angle()
	hitbox.monitoring = true
	hitbox.set_meta("damage", damage)

	_fx.texture = tex
	_fx.rotation = facing.angle()
	_fx.position = facing * 10.0
	_fx.scale = Vector2(fx_scale, fx_scale)
	_fx.visible = true

	# Signals only fire on enter; sweep bodies/areas every physics frame while active.
	var elapsed := 0.0
	while elapsed < active_time and hitbox.monitoring:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		_sweep_hitbox(hitbox)

	hitbox.monitoring = false
	var rest := maxf(attack_recover_time - active_time, 0.0)
	if rest > 0.0:
		await get_tree().create_timer(rest).timeout


func _sweep_hitbox(hitbox: Area2D) -> void:
	for body in hitbox.get_overlapping_bodies():
		if body is Node2D:
			_on_hitbox_body_entered(body as Node2D, hitbox)
	for area in hitbox.get_overlapping_areas():
		if area is Area2D:
			_on_hitbox_area_entered(area as Area2D, hitbox)


func _spawn_projectile(facing: Vector2) -> void:
	var bolt := Area2D.new()
	bolt.set_script(load("res://assets/scripts/player/player_projectile.gd"))
	var sprite := Sprite2D.new()
	sprite.texture = projectile_texture
	bolt.add_child(sprite)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 4.0
	shape.shape = circle
	bolt.add_child(shape)
	bolt.add_to_group("player_hitbox")

	var parent := _player.get_parent()
	if parent == null:
		parent = _player
	parent.add_child(bolt)
	bolt.global_position = _player.global_position + facing * 8.0
	bolt.set("damage", projectile_damage)
	if bolt.has_method("launch"):
		bolt.call("launch", facing, projectile_speed)

	_fx.texture = projectile_texture
	_fx.rotation = facing.angle()
	_fx.position = facing * 8.0
	_fx.visible = true


func _build_hitboxes() -> void:
	_slash_hitbox = _make_hitbox("SlashHitbox")
	var slash_shape := CollisionPolygon2D.new()
	# Arc / wedge facing +X; rotated toward facing at use time.
	slash_shape.polygon = PackedVector2Array([
		Vector2(2, 0),
		Vector2(14, -16),
		Vector2(22, -10),
		Vector2(26, -3),
		Vector2(26, 3),
		Vector2(22, 10),
		Vector2(14, 16),
	])
	_slash_hitbox.add_child(slash_shape)

	_thrust_hitbox = _make_hitbox("ThrustHitbox")
	var thrust_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(36, 10)
	thrust_shape.shape = rect
	thrust_shape.position = Vector2(18, 0)
	_thrust_hitbox.add_child(thrust_shape)


func _make_hitbox(node_name: String) -> Area2D:
	var area := Area2D.new()
	area.name = node_name
	area.collision_layer = 0
	# enemy bodies + breakable props
	area.collision_mask = (1 << 2) | (1 << 6)
	area.monitoring = false
	area.monitorable = false
	area.add_to_group("player_hitbox")
	area.body_entered.connect(_on_hitbox_body_entered.bind(area))
	area.area_entered.connect(_on_hitbox_area_entered.bind(area))
	add_child(area)
	return area


func _build_fx() -> void:
	_fx = Sprite2D.new()
	_fx.name = "AttackFX"
	_fx.visible = false
	_fx.z_index = 1
	add_child(_fx)


func _disable_hitboxes() -> void:
	if _slash_hitbox != null:
		_slash_hitbox.monitoring = false
	if _thrust_hitbox != null:
		_thrust_hitbox.monitoring = false


func _on_hitbox_body_entered(body: Node2D, hitbox: Area2D) -> void:
	if body == null:
		return
	_try_hit_target(body, hitbox)


func _on_hitbox_area_entered(area: Area2D, hitbox: Area2D) -> void:
	if area == null:
		return
	# Prop hurtboxes: damage the owning prop body.
	if area.is_in_group("hurtbox"):
		var owner_body := area.get_parent()
		if owner_body is Node2D:
			_try_hit_target(owner_body as Node2D, hitbox)


func _try_hit_target(target: Node2D, hitbox: Area2D) -> void:
	var is_enemy := target.is_in_group("enemy")
	var is_prop := target.is_in_group("prop_hittable") or target.is_in_group("prop_breakable")
	if not is_enemy and not is_prop:
		return
	var id := target.get_instance_id()
	if _hit_ids.has(id):
		return
	_hit_ids[id] = true
	var amount := int(hitbox.get_meta("damage", slash_damage))
	_play_hit_sfx()
	_apply_hit(target, amount)


func _cardinal_facing() -> Vector2:
	var facing := Vector2.DOWN
	if "facing" in _player and _player.facing is Vector2:
		facing = _player.facing as Vector2
	if facing == Vector2.ZERO:
		return Vector2.DOWN
	if absf(facing.x) >= absf(facing.y):
		return Vector2.RIGHT if facing.x > 0.0 else Vector2.LEFT
	return Vector2.DOWN if facing.y > 0.0 else Vector2.UP


func _apply_hit(target: Node, amount: int) -> void:
	var origin := _player.global_position if _player != null else global_position
	if target.has_method("try_receive_hit"):
		target.call("try_receive_hit", amount, origin)
		return
	var dmg := target.get_node_or_null("Damageable")
	if dmg != null and dmg.has_method("take_damage"):
		dmg.take_damage(amount)
