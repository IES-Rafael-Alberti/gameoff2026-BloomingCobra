class_name BossHead
extends BossPart

## Boss body/head: weakpoint, lasers, AoE, and shift projectile burst.

signal weakpoint_broken
signal weakpoint_damaged(amount: int, current_health: int)

@export var weakpoint_max_hp: int = 8
@export var laser_damage: int = 3
@export var aoe_damage: int = 2
@export var laser_sweep_duration: float = 1.6
@export var laser_length: float = 260.0
@export var laser_edge_margin: float = 18.0
@export var laser_hit_cooldown: float = 0.35
## How many wall hits before the beam stops growing.
@export var bounce_collisions: int = 3
@export var bounce_travel_speed: float = 240.0
@export var bounce_spread_deg: float = 28.0
@export var aoe_grow_duration: float = 2.8
@export var aoe_max_radius: float = 160.0
@export var aoe_warn_time: float = 0.55
@export var shift_burst_count: int = 5
@export var shift_burst_speed: float = 130.0
@export var projectile_scene: PackedScene
@export_group("Fall / Return")
@export var fall_duration: float = 0.55
@export var impact_hold_time: float = 0.08
@export var impact_tremble_time: float = 0.55
@export var float_home_duration: float = 0.9
@export var impact_shake_amplitude: float = 3.8
@export var impact_shake_duration: float = 0.32
@export_group("Hit Feedback")
@export var hit_knockback: float = 40.0
@export var hit_knockback_decay: float = 900.0
@export var hit_flash_time: float = 0.14

@onready var weakpoint: Area2D = get_node_or_null("Weakpoint") as Area2D
@onready var weakpoint_shape: CollisionShape2D = get_node_or_null("Weakpoint/CollisionShape2D") as CollisionShape2D
@onready var weakpoint_visual: CanvasItem = get_node_or_null("Weakpoint/Visual") as CanvasItem
@onready var laser_line: Line2D = get_node_or_null("LaserLine") as Line2D
@onready var laser_ray: RayCast2D = get_node_or_null("LaserLine/RayCast2D") as RayCast2D
@onready var aoe_area: Area2D = get_node_or_null("AoeArea") as Area2D
@onready var aoe_shape: CollisionShape2D = get_node_or_null("AoeArea/CollisionShape2D") as CollisionShape2D
@onready var aoe_visual: Node2D = get_node_or_null("AoeArea/Visual") as Node2D
@onready var damageable: Node2D = get_node_or_null("Damageable") as Node2D

var _weakpoint_exposed: bool = false
var _laser_active: bool = false
var _laser_hit_cd: float = 0.0
var _projectiles_parent: Node = null
var _knockback: Vector2 = Vector2.ZERO
var _last_hit_origin: Vector2 = Vector2.ZERO
var _has_hit_origin: bool = false
var _flash_mat: ShaderMaterial
var _hit_flash: float = 0.0
var _laser_line_b: Line2D = null
var _charging_aoe: bool = false
var _aoe_base_modulate: Color = Color.WHITE
var _fallen_in_arena: bool = false
var _sprite_base_scale: Vector2 = Vector2.ONE
var _sprite_base_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	super._ready()
	# Head can be hit by player attacks while weakpoint is exposed.
	add_to_group("enemy")
	_setup_white_flash_material()
	if damageable != null:
		damageable.max_health = weakpoint_max_hp
		damageable.health = weakpoint_max_hp
		damageable.immortal = false
		if damageable.has_signal("damaged") and not damageable.damaged.is_connected(_on_weakpoint_damaged):
			damageable.damaged.connect(_on_weakpoint_damaged)
		if damageable.has_signal("died") and not damageable.died.is_connected(_on_weakpoint_died):
			damageable.died.connect(_on_weakpoint_died)
	if weakpoint != null:
		weakpoint.add_to_group("hurtbox")
	if aoe_shape != null and aoe_shape.shape != null:
		aoe_shape.shape = aoe_shape.shape.duplicate()
	if aoe_visual != null:
		_aoe_base_modulate = aoe_visual.modulate
	_ensure_second_laser_line()
	if animated_sprite != null:
		_sprite_base_scale = animated_sprite.scale
		_sprite_base_pos = animated_sprite.position
	hide_weakpoint()
	_hide_laser()
	_hide_aoe()
	play_anim(&"Idle")


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_laser_hit_cd = maxf(_laser_hit_cd - delta, 0.0)
	_update_hit_flash(delta)
	if _knockback.length() > 3.0:
		global_position += _knockback * delta
		_knockback = _knockback.move_toward(Vector2.ZERO, hit_knockback_decay * delta)
	if _laser_active:
		_tick_laser_damage()


func set_projectiles_parent(node: Node) -> void:
	_projectiles_parent = node


func reset_weakpoint_hp() -> void:
	if damageable == null:
		return
	damageable.max_health = weakpoint_max_hp
	damageable.health = weakpoint_max_hp


func is_weakpoint_exposed() -> bool:
	return _weakpoint_exposed


func expose_weakpoint() -> void:
	request_cancel()
	interrupt_charge()
	_hide_laser()
	_hide_aoe()
	_knockback = Vector2.ZERO
	play_anim(&"Cargar", true)
	await _fall_into_arena()
	if not _can_await():
		return
	_set_weakpoint_active(true)
	play_anim(&"Cargar", true)


func hide_weakpoint() -> void:
	_set_weakpoint_active(false)
	if animated_sprite != null:
		animated_sprite.scale = _sprite_base_scale
		animated_sprite.position = _sprite_base_pos
	play_anim(&"Idle")


## After the weakpoint HP is depleted: float back to the northern perch.
func retreat_to_perch() -> void:
	_set_weakpoint_active(false)
	_knockback = Vector2.ZERO
	if animated_sprite != null:
		animated_sprite.scale = _sprite_base_scale
		animated_sprite.position = _sprite_base_pos
	play_anim(&"Idle")
	if _fallen_in_arena:
		await _float_to_home()
	_fallen_in_arena = false


func _set_weakpoint_active(active: bool) -> void:
	_weakpoint_exposed = active
	if weakpoint != null:
		weakpoint.visible = active
		weakpoint.set_deferred("monitoring", active)
		weakpoint.set_deferred("monitorable", active)
	if weakpoint_shape != null:
		weakpoint_shape.set_deferred("disabled", not active)
	if weakpoint_visual != null:
		weakpoint_visual.visible = active


func _arena_drop_position() -> Vector2:
	var arena := get_arena()
	if arena.size != Vector2.ZERO:
		return arena.get_center()
	return _home_position + Vector2(0.0, 170.0)


func _fall_into_arena() -> void:
	var target := _arena_drop_position()
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "global_position", target, fall_duration)
	await tween.finished
	if not _can_await():
		return
	_fallen_in_arena = true
	await _play_impact()


func _play_impact() -> void:
	shake_camera(impact_shake_amplitude, impact_shake_duration)
	# Squash on hit, then tremble.
	if animated_sprite != null:
		var squash := Vector2(_sprite_base_scale.x * 1.22, _sprite_base_scale.y * 0.72)
		var tween := create_tween()
		tween.tween_property(animated_sprite, "scale", squash, impact_hold_time)
		tween.tween_property(animated_sprite, "scale", _sprite_base_scale, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		await tween.finished
		if not _can_await():
			return
	await _tremble_sprite(impact_tremble_time)


func _tremble_sprite(duration: float) -> void:
	if animated_sprite == null:
		await _wait(duration)
		return
	var elapsed := 0.0
	while elapsed < duration:
		if not await _await_physics():
			animated_sprite.position = _sprite_base_pos
			return
		elapsed += get_physics_process_delta_time()
		var decay := 1.0 - clampf(elapsed / maxf(duration, 0.01), 0.0, 1.0)
		animated_sprite.position = _sprite_base_pos + Vector2(
			randf_range(-5.0, 5.0) * decay,
			randf_range(-3.5, 3.5) * decay
		)
	animated_sprite.position = _sprite_base_pos


func _float_to_home() -> void:
	if not _can_await():
		global_position = _home_position
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "global_position", _home_position, float_home_duration)
	# Soft bob while rising.
	if animated_sprite != null:
		var bob := create_tween()
		bob.set_loops(maxi(int(float_home_duration / 0.2), 1))
		bob.tween_property(animated_sprite, "position:y", _sprite_base_pos.y - 3.0, 0.1)
		bob.tween_property(animated_sprite, "position:y", _sprite_base_pos.y + 2.0, 0.1)
	await tween.finished
	if animated_sprite != null:
		animated_sprite.position = _sprite_base_pos
	global_position = _home_position


## Player attacks call this via the enemy group. Only lands while exposed.
func try_receive_hit(amount: int, hit_origin: Vector2) -> bool:
	if not _weakpoint_exposed or amount <= 0:
		return false
	if damageable == null or not damageable.has_method("take_damage"):
		return false
	_last_hit_origin = hit_origin
	_has_hit_origin = true
	damageable.take_damage(amount)
	return true


func is_charging_aoe() -> bool:
	return _charging_aoe


func interrupt_charge() -> void:
	if not _charging_aoe:
		return
	request_cancel()
	_hide_aoe()
	_charging_aoe = false
	if animated_sprite != null:
		animated_sprite.modulate = Color.WHITE


func attack_laser_sweep() -> void:
	if not _begin_attack():
		return
	play_anim(&"Cargar", true)
	if not await _wait(0.45):
		_end_attack()
		return

	var go_right := randf() > 0.5
	var start_angle: float
	var end_angle: float
	if go_right:
		start_angle = deg_to_rad(-20.0)
		end_angle = deg_to_rad(100.0)
	else:
		start_angle = deg_to_rad(200.0)
		end_angle = deg_to_rad(80.0)

	_show_laser()
	_laser_active = true
	contact_damage = laser_damage
	var elapsed := 0.0
	while elapsed < laser_sweep_duration:
		if _should_abort() or not await _await_physics():
			_laser_active = false
			_hide_laser()
			_end_attack()
			return
		var dt := get_physics_process_delta_time()
		elapsed += dt
		var t := clampf(elapsed / maxf(laser_sweep_duration, 0.01), 0.0, 1.0)
		var angle := lerpf(start_angle, end_angle, t)
		_update_laser_beam(Vector2.from_angle(angle))

	_laser_active = false
	_hide_laser()
	play_anim(&"Idle")
	_end_attack()


func attack_laser_bounce() -> void:
	if not _begin_attack():
		return
	play_anim(&"Cargar", true)
	if not await _wait(0.4):
		_end_attack()
		return

	var player := get_player()
	var base_dir := Vector2.DOWN
	if player != null:
		base_dir = (player.global_position - global_position).normalized()
		if base_dir == Vector2.ZERO:
			base_dir = Vector2.DOWN

	var spread := deg_to_rad(bounce_spread_deg)
	var paths: Array[PackedVector2Array] = [
		_build_bounce_path(base_dir.rotated(-spread)),
		_build_bounce_path(base_dir.rotated(spread)),
	]
	var path_lengths: Array[float] = []
	var max_len := 0.0
	for path in paths:
		var plen := _polyline_length(path)
		path_lengths.append(plen)
		max_len = maxf(max_len, plen)

	_show_laser()
	_laser_active = true
	contact_damage = laser_damage

	# Advance both beams by travel distance so a shorter path does not freeze the other.
	var duration := maxf(max_len / maxf(bounce_travel_speed, 1.0), 0.25)
	var elapsed := 0.0
	while elapsed < duration:
		if _should_abort() or not await _await_physics():
			_laser_active = false
			_hide_laser()
			_end_attack()
			return
		elapsed += get_physics_process_delta_time()
		var traveled := elapsed * bounce_travel_speed
		_set_laser_points(_polyline_until(paths[0], minf(traveled, path_lengths[0])), laser_line)
		if paths.size() > 1:
			_set_laser_points(_polyline_until(paths[1], minf(traveled, path_lengths[1])), _laser_line_b)

	await _wait(0.18)
	_laser_active = false
	_hide_laser()
	play_anim(&"Idle")
	_end_attack()


func attack_aoe() -> void:
	if not _begin_attack():
		return
	_charging_aoe = true
	play_anim(&"Cargar", true)
	if not await _wait(0.2):
		_abort_aoe()
		return

	_show_aoe()
	# Warning pulse before the ring expands.
	var warn_elapsed := 0.0
	while warn_elapsed < aoe_warn_time:
		if _should_abort() or WorldMode.get_mode() != WorldMode.MODE_PESADILLA:
			_abort_aoe()
			return
		if not await _await_physics():
			_abort_aoe()
			return
		warn_elapsed += get_physics_process_delta_time()
		_set_aoe_radius_world(14.0 + 6.0 * sin(warn_elapsed * 18.0))
		if aoe_visual != null:
			var pulse := 0.55 + 0.45 * absf(sin(warn_elapsed * 14.0))
			aoe_visual.modulate = Color(1.0, 0.35, 0.2, pulse)

	var max_r_world := aoe_max_radius
	var arena := get_arena()
	if arena.size != Vector2.ZERO:
		var to_corner := arena.get_center().distance_to(arena.position)
		max_r_world = maxf(max_r_world, to_corner + 20.0)

	var elapsed := 0.0
	while elapsed < aoe_grow_duration:
		if _should_abort() or WorldMode.get_mode() != WorldMode.MODE_PESADILLA:
			_abort_aoe()
			return
		if not await _await_physics():
			_abort_aoe()
			return
		elapsed += get_physics_process_delta_time()
		var t := clampf(elapsed / maxf(aoe_grow_duration, 0.01), 0.0, 1.0)
		_set_aoe_radius_world(lerpf(12.0, max_r_world, t))
		if aoe_visual != null:
			var pulse := 0.65 + 0.35 * absf(sin(elapsed * 10.0))
			aoe_visual.modulate = Color(1.0, 0.25 + 0.35 * t, 0.15, pulse)
		if animated_sprite != null:
			animated_sprite.modulate = Color(1.0, 1.0 - 0.25 * t, 1.0 - 0.35 * t)

	# Impact only if the charge finished cleanly in Pesadilla.
	if (
		_charging_aoe
		and not _cancel_requested
		and WorldMode.get_mode() == WorldMode.MODE_PESADILLA
	):
		var player := get_player()
		if player != null:
			var radius := _aoe_radius_world()
			if player.global_position.distance_to(global_position) <= radius:
				deal_player_hit(player, aoe_damage, contact_knockback)

	if _should_abort() or not await _wait(0.2):
		_abort_aoe()
		return
	_hide_aoe()
	_charging_aoe = false
	if animated_sprite != null:
		animated_sprite.modulate = Color.WHITE
	play_anim(&"Idle")
	_end_attack()


func _abort_aoe() -> void:
	_hide_aoe()
	_charging_aoe = false
	_knockback = Vector2.ZERO
	if animated_sprite != null:
		animated_sprite.modulate = Color.WHITE
	play_anim(&"Idle")
	_end_attack()


func _build_bounce_path(dir: Vector2) -> PackedVector2Array:
	var travel_dir := dir.normalized() if dir != Vector2.ZERO else Vector2.DOWN
	var points := PackedVector2Array([global_position])
	var arena := get_arena()
	var bounds := arena.grow(-4.0) if arena.size != Vector2.ZERO else Rect2()
	# Enter the arena first so the northern wall does not eat the beam.
	var tip := _arena_cast_origin(global_position, travel_dir)
	if bounds.size != Vector2.ZERO:
		tip = _clamp_point_to_rect(tip, bounds)
	if tip.distance_squared_to(global_position) > 1.0:
		points.append(tip)

	# Grow until N wall collisions, then stop at the last hit.
	var hits_left := maxi(bounce_collisions, 1)
	while hits_left > 0:
		if bounds.size == Vector2.ZERO:
			points.append(tip + travel_dir * 200.0)
			break
		var hit := _ray_rect_bounds(tip, travel_dir, bounds)
		if hit.is_empty():
			break
		var hit_pos: Vector2 = hit.position
		var normal: Vector2 = hit.normal
		hits_left -= 1
		if hits_left <= 0:
			# Final collision: stop growing here.
			points.append(hit_pos)
			break
		# Nudge inside so the next cast does not re-hit the same edge.
		hit_pos = _clamp_point_to_rect(hit_pos + normal * 2.0, bounds)
		points.append(hit_pos)
		travel_dir = travel_dir.bounce(normal).normalized()
		if travel_dir == Vector2.ZERO:
			travel_dir = normal
		tip = hit_pos
	return points


func _ray_rect_bounds(from: Vector2, dir: Vector2, rect: Rect2) -> Dictionary:
	var direction := dir.normalized() if dir != Vector2.ZERO else Vector2.DOWN
	var best_t := INF
	var best_normal := Vector2.ZERO
	if direction.x < -0.0001:
		var t := (rect.position.x - from.x) / direction.x
		if t > 0.001 and t < best_t:
			best_t = t
			best_normal = Vector2.RIGHT
	if direction.x > 0.0001:
		var t2 := (rect.end.x - from.x) / direction.x
		if t2 > 0.001 and t2 < best_t:
			best_t = t2
			best_normal = Vector2.LEFT
	if direction.y < -0.0001:
		var t3 := (rect.position.y - from.y) / direction.y
		if t3 > 0.001 and t3 < best_t:
			best_t = t3
			best_normal = Vector2.DOWN
	if direction.y > 0.0001:
		var t4 := (rect.end.y - from.y) / direction.y
		if t4 > 0.001 and t4 < best_t:
			best_t = t4
			best_normal = Vector2.UP
	if best_t == INF:
		return {}
	return {
		"position": from + direction * best_t,
		"normal": best_normal,
		"distance": best_t,
	}


func _clamp_point_to_rect(point: Vector2, rect: Rect2) -> Vector2:
	return Vector2(
		clampf(point.x, rect.position.x, rect.end.x),
		clampf(point.y, rect.position.y, rect.end.y)
	)


func _polyline_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total


func _polyline_until(points: PackedVector2Array, distance: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if points.is_empty():
		return out
	out.append(points[0])
	if points.size() == 1 or distance <= 0.0:
		return out
	var left := distance
	for i in range(1, points.size()):
		var a: Vector2 = points[i - 1]
		var b: Vector2 = points[i]
		var seg := a.distance_to(b)
		if seg <= 0.0001:
			continue
		if left >= seg:
			out.append(b)
			left -= seg
			continue
		out.append(a.lerp(b, left / seg))
		return out
	return out


func _path_prefix(points: PackedVector2Array, seg_i: int, t: float) -> PackedVector2Array:
	if points.is_empty():
		return PackedVector2Array()
	if seg_i + 1 >= points.size():
		return points.duplicate()
	var a: Vector2 = points[seg_i]
	var b: Vector2 = points[seg_i + 1]
	return _prefix_points(points, seg_i, a.lerp(b, t))


func fire_shift_burst() -> void:
	if projectile_scene == null:
		return
	var parent := _projectiles_parent if _projectiles_parent != null else get_parent()
	if parent == null:
		return
	var player := get_player()
	var base_dir := Vector2.DOWN
	if player != null:
		base_dir = (player.global_position - global_position).normalized()
		if base_dir == Vector2.ZERO:
			base_dir = Vector2.DOWN

	var count := maxi(shift_burst_count, 1)
	for i in count:
		var spread := lerpf(-0.55, 0.55, float(i) / float(maxi(count - 1, 1)))
		var dir := base_dir.rotated(spread)
		var bolt := projectile_scene.instantiate()
		parent.add_child(bolt)
		if bolt is Node2D:
			(bolt as Node2D).global_position = global_position
		if bolt.has_method("launch"):
			bolt.call("launch", dir, shift_burst_speed, self)


func _on_weakpoint_damaged(amount: int, current_health: int) -> void:
	weakpoint_damaged.emit(amount, current_health)
	_apply_hit_feedback()


func _apply_hit_feedback() -> void:
	var dir := _resolve_hit_knockback_dir()
	if hit_knockback > 0.0 and dir != Vector2.ZERO:
		_knockback = dir * hit_knockback
	_play_hit_flash()


func _resolve_hit_knockback_dir() -> Vector2:
	if _has_hit_origin:
		var away := global_position - _last_hit_origin
		_has_hit_origin = false
		if away != Vector2.ZERO:
			return away.normalized()
	var player := get_player()
	if player != null:
		var from_player := global_position - player.global_position
		if from_player != Vector2.ZERO:
			return from_player.normalized()
	return Vector2.UP


func _setup_white_flash_material() -> void:
	if animated_sprite == null:
		return
	var shader := load("res://assets/shaders/white_flash.gdshader") as Shader
	if shader == null:
		return
	_flash_mat = ShaderMaterial.new()
	_flash_mat.shader = shader
	_flash_mat.set_shader_parameter("flash", 0.0)
	animated_sprite.material = _flash_mat


func _play_hit_flash() -> void:
	_hit_flash = maxf(hit_flash_time, 0.01)
	_set_white_flash(1.0)
	if animated_sprite != null:
		animated_sprite.modulate = Color(1.8, 1.8, 1.8, 1.0)


func _set_white_flash(amount: float) -> void:
	if _flash_mat == null:
		return
	_flash_mat.set_shader_parameter("flash", clampf(amount, 0.0, 1.0))


func _update_hit_flash(delta: float) -> void:
	if _hit_flash <= 0.0:
		return
	_hit_flash = maxf(_hit_flash - delta, 0.0)
	var t := _hit_flash / maxf(hit_flash_time, 0.01)
	_set_white_flash(t)
	if animated_sprite != null:
		if t <= 0.0:
			animated_sprite.modulate = Color.WHITE
		else:
			animated_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0).lerp(Color(1.8, 1.8, 1.8, 1.0), t)


func _on_weakpoint_died() -> void:
	hide_weakpoint()
	weakpoint_broken.emit()


func _ensure_second_laser_line() -> void:
	if _laser_line_b != null or laser_line == null:
		return
	_laser_line_b = laser_line.duplicate() as Line2D
	_laser_line_b.name = "LaserLineB"
	_laser_line_b.visible = false
	_laser_line_b.z_index = 20
	_laser_line_b.z_as_relative = false
	_laser_line_b.clear_points()
	add_child(_laser_line_b)
	_configure_laser_line(laser_line)
	_configure_laser_line(_laser_line_b)


func _configure_laser_line(line: Line2D) -> void:
	if line == null:
		return
	line.z_index = 20
	line.z_as_relative = false
	# Keep world-space drawing stable even while the head is scaled.
	line.top_level = true


func _show_laser() -> void:
	if laser_line != null:
		laser_line.visible = true
		laser_line.clear_points()
	if _laser_line_b != null:
		_laser_line_b.visible = true
		_laser_line_b.clear_points()
	if laser_ray != null:
		laser_ray.enabled = true


func _hide_laser() -> void:
	_laser_active = false
	if laser_line != null:
		laser_line.visible = false
		laser_line.clear_points()
	if _laser_line_b != null:
		_laser_line_b.visible = false
		_laser_line_b.clear_points()
	if laser_ray != null:
		laser_ray.enabled = false


func _update_laser_beam(dir: Vector2) -> void:
	var direction := dir.normalized() if dir != Vector2.ZERO else Vector2.DOWN
	var visual_from := global_position
	var cast_from := _arena_cast_origin(visual_from, direction)
	var end := cast_from + direction * laser_length
	var hit := _ray_wall(cast_from, direction * laser_length)
	if not hit.is_empty():
		end = hit.position
	_set_laser_points(PackedVector2Array([visual_from, end]), laser_line)
	if _laser_line_b != null:
		_laser_line_b.visible = false
		_laser_line_b.clear_points()


func _set_laser_points(points: PackedVector2Array, line: Line2D = null) -> void:
	var target := laser_line if line == null else line
	if target == null:
		return
	if target.top_level:
		target.global_position = Vector2.ZERO
		target.global_rotation = 0.0
		target.scale = Vector2.ONE
	target.clear_points()
	for p in points:
		target.add_point(target.to_local(p))


func _prefix_points(points: PackedVector2Array, up_to: int, tip: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(up_to + 1):
		out.append(points[i])
	out.append(tip)
	return out


func _tick_laser_damage() -> void:
	if _laser_hit_cd > 0.0:
		return
	var player := get_player()
	if player == null:
		return
	var lines: Array[Line2D] = [laser_line, _laser_line_b]
	for line in lines:
		if line == null or not line.visible or line.get_point_count() < 2:
			continue
		for i in range(line.get_point_count() - 1):
			var a: Vector2 = line.to_global(line.get_point_position(i))
			var b: Vector2 = line.to_global(line.get_point_position(i + 1))
			if _dist_point_to_segment(player.global_position, a, b) <= 8.0:
				if deal_player_hit(player, laser_damage, contact_knockback * 1.2):
					_laser_hit_cd = laser_hit_cooldown
				return


func _dist_point_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq <= 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _arena_cast_origin(from: Vector2, dir: Vector2) -> Vector2:
	var arena := get_arena()
	if arena.size == Vector2.ZERO:
		return from
	var inner := arena.grow(-3.0)
	if inner.has_point(from):
		return from
	var direction := dir.normalized() if dir != Vector2.ZERO else Vector2.DOWN
	var entry := _segment_rect_entry(from, from + direction * 4000.0, inner)
	if entry == Vector2.INF:
		return Vector2(inner.get_center().x, inner.position.y + 4.0)
	return entry


func _segment_rect_entry(from: Vector2, to: Vector2, rect: Rect2) -> Vector2:
	if rect.has_point(from):
		return from
	var edges: Array[PackedVector2Array] = [
		PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y)]),
		PackedVector2Array([Vector2(rect.end.x, rect.position.y), rect.end]),
		PackedVector2Array([rect.end, Vector2(rect.position.x, rect.end.y)]),
		PackedVector2Array([Vector2(rect.position.x, rect.end.y), rect.position]),
	]
	var best_d := INF
	var best := Vector2.INF
	for edge in edges:
		var hit: Variant = Geometry2D.segment_intersects_segment(from, to, edge[0], edge[1])
		if hit == null:
			continue
		var point: Vector2 = hit
		var d := from.distance_squared_to(point)
		if d < best_d:
			best_d = d
			best = point
	if best == Vector2.INF:
		return best
	var inward := (to - from).normalized()
	if inward == Vector2.ZERO:
		inward = rect.get_center() - best
		if inward != Vector2.ZERO:
			inward = inward.normalized()
	return best + inward * 2.0


func _ray_wall(from: Vector2, cast_to: Vector2) -> Dictionary:
	var world := get_world_2d()
	if world == null:
		return {}
	var space := world.direct_space_state
	if space == null:
		return {}
	var origin := from
	var remaining := cast_to
	var arena := get_arena()
	if arena.size != Vector2.ZERO and not arena.grow(-3.0).has_point(origin):
		var entry := _arena_cast_origin(origin, remaining)
		remaining = (from + cast_to) - entry
		origin = entry
		if remaining.length_squared() < 0.25:
			return {}
	var query := PhysicsRayQueryParameters2D.create(origin, origin + remaining)
	query.collision_mask = 1 << 0 # world
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	return space.intersect_ray(query)


func _show_aoe() -> void:
	if aoe_area != null:
		aoe_area.visible = true
		aoe_area.monitoring = false
	_set_aoe_radius_world(8.0)


func _hide_aoe() -> void:
	if aoe_area != null:
		aoe_area.visible = false
	if aoe_visual != null:
		aoe_visual.modulate = _aoe_base_modulate
	_set_aoe_radius_world(8.0)


func _part_scale() -> float:
	return maxf(maxf(absf(global_scale.x), absf(global_scale.y)), 0.001)


func _aoe_radius_world() -> float:
	if aoe_shape != null and aoe_shape.shape is CircleShape2D:
		return (aoe_shape.shape as CircleShape2D).radius * _part_scale()
	return 0.0


func _set_aoe_radius_world(radius_world: float) -> void:
	var local_r := radius_world / _part_scale()
	if aoe_shape != null and aoe_shape.shape is CircleShape2D:
		(aoe_shape.shape as CircleShape2D).radius = local_r
	if aoe_visual != null:
		var s := local_r / 32.0
		aoe_visual.scale = Vector2(s, s)
