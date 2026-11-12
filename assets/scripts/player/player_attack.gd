extends Node2D

## Nightmare-only attacks: slash (tap), thrust (half charge), projectile (full).
## Character attack sheet is charge+release (frames 0-1 charge, frame 2 strike).
## Attack FX prefer multi-frame sheets (Array[Texture2D] / auto-sliced sheet).

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
@export var fx_fps: float = 14.0
@export var fx_scale: float = 0.035
## Art offsets: sheets face up; CW rotation aligns with facing.angle() (+X).
@export var slash_fx_angle_offset: float = deg_to_rad(100.0) # 90° + 10° CW
@export var thrust_fx_angle_offset: float = PI * 0.25
@export var slash_fx_distance: float = 10.0
@export var thrust_fx_distance: float = 18.0
@export var slash_fx_scale_mul: float = 1.05
@export var thrust_fx_scale_mul: float = 1.0

@export_group("Slash FX")
## Preferred: ordered frames from a spritesheet (AtlasTexture / cropped frames).
@export var slash_frames: Array[Texture2D] = []
## Optional auto-slice: horizontal/grid sheet when slash_frames is empty.
@export var slash_sheet: Texture2D
@export var slash_frame_size: Vector2i = Vector2i(992, 992)
@export var slash_frame_indices: PackedInt32Array = PackedInt32Array()
## Legacy single-icon fallback.
@export var slash_texture: Texture2D

@export_group("Thrust FX")
@export var thrust_frames: Array[Texture2D] = []
@export var thrust_sheet: Texture2D
@export var thrust_frame_size: Vector2i = Vector2i(992, 992)
@export var thrust_frame_indices: PackedInt32Array = PackedInt32Array()
@export var thrust_texture: Texture2D

@export_group("Projectile FX")
## Frames 0..n-2 loop while flying; last frame plays on impact.
@export var projectile_frames: Array[Texture2D] = []
@export var projectile_sheet: Texture2D
@export var projectile_frame_size: Vector2i = Vector2i(992, 992)
@export var projectile_frame_indices: PackedInt32Array = PackedInt32Array()
@export var projectile_texture: Texture2D

var _player: CharacterBody2D
var _charging: bool = false
var _charge: float = 0.0
var _busy: bool = false
var _enabled: bool = true
var _hit_ids: Dictionary = {}
var _charge_ready_flashed: bool = false

var _slash_hitbox: Area2D
var _thrust_hitbox: Area2D
var _fx: AnimatedSprite2D
var _active_kind: AttackKind = AttackKind.NONE

var _slash_sf: SpriteFrames
var _thrust_sf: SpriteFrames
var _projectile_sf: SpriteFrames


func setup(player: CharacterBody2D) -> void:
	_player = player
	_build_frame_resources()
	_build_hitboxes()
	_build_fx()


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled:
		_cancel_charge()


func is_busy() -> bool:
	return _busy or _charging


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
		_charge_ready_flashed = false
		if _player.has_method("begin_attack_charge"):
			_player.call("begin_attack_charge", _cardinal_facing())

	if _charging:
		if Input.is_action_pressed("attack"):
			var prev := _charge
			_charge = minf(_charge + delta / maxf(charge_time, 0.01), 1.0)
			if _player.has_method("update_attack_charge"):
				_player.call("update_attack_charge", _charge, half_threshold)
			if prev < 1.0 and _charge >= 1.0 and not _charge_ready_flashed:
				_charge_ready_flashed = true
				if _player.has_method("on_attack_charge_ready"):
					_player.call("on_attack_charge_ready")
		if Input.is_action_just_released("attack"):
			_release_attack()


func _release_attack() -> void:
	_charging = false

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
	_charge_ready_flashed = false
	if _player != null and _player.has_method("cancel_attack_charge"):
		_player.call("cancel_attack_charge")


func _perform(kind: AttackKind) -> void:
	_busy = true
	_hit_ids.clear()
	_active_kind = kind
	var facing := _cardinal_facing()

	if _player.has_method("play_attack_release"):
		_player.call("play_attack_release", facing)
	else:
		_player.call("play_attack_animation", facing)
	_play_attack_sfx(kind)

	match kind:
		AttackKind.SLASH:
			await _activate_melee(
				_slash_hitbox,
				facing,
				slash_damage,
				slash_active_time,
				_slash_sf,
				slash_texture,
				slash_fx_scale_mul,
				slash_fx_distance,
				slash_fx_angle_offset
			)
		AttackKind.THRUST:
			await _activate_melee(
				_thrust_hitbox,
				facing,
				thrust_damage,
				thrust_active_time,
				_thrust_sf,
				thrust_texture,
				thrust_fx_scale_mul,
				thrust_fx_distance,
				thrust_fx_angle_offset
			)
		AttackKind.PROJECTILE:
			_spawn_projectile(facing)
			await get_tree().create_timer(attack_recover_time).timeout
		_:
			pass

	_disable_hitboxes()
	_fx.visible = false
	_fx.stop()
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
	frames: SpriteFrames,
	fallback: Texture2D,
	scale_mul: float,
	fx_distance: float,
	fx_angle_offset: float
) -> void:
	_disable_hitboxes()
	hitbox.rotation = facing.angle()
	# Push thrust hitbox a bit farther with the visual.
	hitbox.position = facing * maxf(fx_distance - 10.0, 0.0)
	hitbox.monitoring = true
	hitbox.set_meta("damage", damage)

	_show_fx(frames, fallback, facing, fx_distance, scale_mul, fx_angle_offset)

	var elapsed := 0.0
	while elapsed < active_time and hitbox.monitoring:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		_sweep_hitbox(hitbox)

	hitbox.monitoring = false
	hitbox.position = Vector2.ZERO
	var rest := maxf(attack_recover_time - active_time, 0.0)
	if rest > 0.0:
		await get_tree().create_timer(rest).timeout


func _show_fx(
	frames: SpriteFrames,
	fallback: Texture2D,
	facing: Vector2,
	distance: float,
	scale_mul: float,
	angle_offset: float = 0.0
) -> void:
	_fx.rotation = facing.angle() + angle_offset
	_fx.position = facing * distance
	_fx.scale = Vector2(fx_scale * scale_mul, fx_scale * scale_mul)
	_fx.flip_h = false
	_fx.flip_v = false
	_fx.visible = true

	if frames != null and frames.has_animation(&"fx") and frames.get_frame_count(&"fx") > 0:
		_fx.sprite_frames = frames
		_fx.play(&"fx")
		return

	# Legacy single texture: wrap into a 1-frame SpriteFrames.
	if fallback != null:
		var one := SpriteFrames.new()
		one.add_animation(&"fx")
		one.set_animation_loop(&"fx", false)
		one.set_animation_speed(&"fx", fx_fps)
		one.add_frame(&"fx", fallback)
		_fx.sprite_frames = one
		_fx.play(&"fx")
		return

	_fx.visible = false


func _spawn_projectile(facing: Vector2) -> void:
	var bolt := Area2D.new()
	bolt.set_script(load("res://assets/scripts/player/player_projectile.gd"))

	var sprite := AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.scale = Vector2(fx_scale, fx_scale)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.centered = true
	if _projectile_sf != null:
		sprite.sprite_frames = _projectile_sf
	elif projectile_texture != null:
		sprite.sprite_frames = _make_projectile_sprite_frames([projectile_texture])
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


func _build_frame_resources() -> void:
	_slash_sf = _make_frames(slash_frames, slash_sheet, slash_frame_size, slash_frame_indices, slash_texture)
	_thrust_sf = _make_frames(thrust_frames, thrust_sheet, thrust_frame_size, thrust_frame_indices, thrust_texture)
	_projectile_sf = _make_projectile_sprite_frames(
		_collect_textures(projectile_frames, projectile_sheet, projectile_frame_size, projectile_frame_indices, projectile_texture)
	)


func _collect_textures(
	explicit: Array[Texture2D],
	sheet: Texture2D,
	frame_size: Vector2i,
	indices: PackedInt32Array,
	fallback: Texture2D
) -> Array[Texture2D]:
	var textures: Array[Texture2D] = []
	if explicit != null and not explicit.is_empty():
		for tex in explicit:
			if tex != null:
				textures.append(tex)
	elif sheet != null and frame_size.x > 0 and frame_size.y > 0:
		textures = _slice_sheet(sheet, frame_size, indices)
	elif fallback != null:
		textures.append(fallback)
	return textures


func _make_frames(
	explicit: Array[Texture2D],
	sheet: Texture2D,
	frame_size: Vector2i,
	indices: PackedInt32Array,
	fallback: Texture2D,
	loop: bool = false
) -> SpriteFrames:
	var textures := _collect_textures(explicit, sheet, frame_size, indices, fallback)
	if textures.is_empty():
		return null

	var frames := SpriteFrames.new()
	frames.add_animation(&"fx")
	frames.set_animation_loop(&"fx", loop)
	frames.set_animation_speed(&"fx", fx_fps)
	for tex in textures:
		frames.add_frame(&"fx", tex)
	return frames


## fly = all but last (loop), impact = last frame. With 1 texture, fly+impact share it.
func _make_projectile_sprite_frames(textures: Array[Texture2D]) -> SpriteFrames:
	if textures.is_empty():
		return null

	var frames := SpriteFrames.new()
	frames.add_animation(&"fly")
	frames.set_animation_loop(&"fly", true)
	frames.set_animation_speed(&"fly", fx_fps)
	frames.add_animation(&"impact")
	frames.set_animation_loop(&"impact", false)
	frames.set_animation_speed(&"impact", fx_fps)

	if textures.size() == 1:
		frames.add_frame(&"fly", textures[0])
		frames.add_frame(&"impact", textures[0])
		return frames

	for i in range(textures.size() - 1):
		frames.add_frame(&"fly", textures[i])
	frames.add_frame(&"impact", textures[textures.size() - 1])
	return frames


func _slice_sheet(sheet: Texture2D, frame_size: Vector2i, indices: PackedInt32Array) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	var size := sheet.get_size()
	var cols := maxi(int(size.x) / frame_size.x, 1)
	var rows := maxi(int(size.y) / frame_size.y, 1)
	var total := cols * rows

	var order: PackedInt32Array = indices
	if order.is_empty():
		order = PackedInt32Array()
		for i in total:
			order.append(i)

	for idx in order:
		if idx < 0 or idx >= total:
			continue
		var col := idx % cols
		var row := idx / cols
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(col * frame_size.x, row * frame_size.y, frame_size.x, frame_size.y)
		out.append(atlas)
	return out


func _build_hitboxes() -> void:
	_slash_hitbox = _make_hitbox("SlashHitbox")
	var slash_shape := CollisionPolygon2D.new()
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
	area.collision_mask = (1 << 2) | (1 << 6)
	area.monitoring = false
	area.monitorable = false
	area.add_to_group("player_hitbox")
	area.body_entered.connect(_on_hitbox_body_entered.bind(area))
	area.area_entered.connect(_on_hitbox_area_entered.bind(area))
	add_child(area)
	return area


func _build_fx() -> void:
	_fx = AnimatedSprite2D.new()
	_fx.name = "AttackFX"
	_fx.visible = false
	_fx.z_index = 1
	_fx.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_fx.centered = true
	add_child(_fx)


func _disable_hitboxes() -> void:
	if _slash_hitbox != null:
		_slash_hitbox.monitoring = false
	if _thrust_hitbox != null:
		_thrust_hitbox.monitoring = false


func _sweep_hitbox(hitbox: Area2D) -> void:
	for body in hitbox.get_overlapping_bodies():
		if body is Node2D:
			_on_hitbox_body_entered(body as Node2D, hitbox)
	for area in hitbox.get_overlapping_areas():
		if area is Area2D:
			_on_hitbox_area_entered(area as Area2D, hitbox)


func _on_hitbox_body_entered(body: Node2D, hitbox: Area2D) -> void:
	if body == null:
		return
	_try_hit_target(body, hitbox)


func _on_hitbox_area_entered(area: Area2D, hitbox: Area2D) -> void:
	if area == null:
		return
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
