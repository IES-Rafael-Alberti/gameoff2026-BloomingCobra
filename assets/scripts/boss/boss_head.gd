class_name BossHead
extends BossPart

## Boss body/head: weakpoint, lasers, AoE, and shift projectile burst.

signal weakpoint_broken
signal weakpoint_damaged(amount: int, current_health: int)

@export var weakpoint_max_hp: int = 8
@export var laser_damage: int = 3
@export var aoe_damage: int = 2
@export var laser_sweep_duration: float = 1.35
@export var laser_length: float = 220.0
@export var laser_edge_margin: float = 18.0
@export var laser_hit_cooldown: float = 0.35
@export var bounce_bounces: int = 3
@export var bounce_segment_length: float = 160.0
@export var bounce_travel_speed: float = 280.0
@export var aoe_grow_duration: float = 2.2
@export var aoe_max_radius: float = 160.0
@export var shift_burst_count: int = 5
@export var shift_burst_speed: float = 130.0
@export var projectile_scene: PackedScene

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


func _ready() -> void:
	super._ready()
	# Head can be hit by player attacks while weakpoint is exposed.
	add_to_group("enemy")
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
	hide_weakpoint()
	_hide_laser()
	_hide_aoe()
	play_anim(&"Idle")


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_laser_hit_cd = maxf(_laser_hit_cd - delta, 0.0)
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
	_weakpoint_exposed = true
	if weakpoint != null:
		weakpoint.visible = true
		weakpoint.monitoring = true
		weakpoint.monitorable = true
	if weakpoint_shape != null:
		weakpoint_shape.set_deferred("disabled", false)
	if weakpoint_visual != null:
		weakpoint_visual.visible = true
	play_anim(&"Cargar", true)


func hide_weakpoint() -> void:
	_weakpoint_exposed = false
	if weakpoint != null:
		weakpoint.visible = false
		weakpoint.monitoring = false
		weakpoint.monitorable = false
	if weakpoint_shape != null:
		weakpoint_shape.set_deferred("disabled", true)
	if weakpoint_visual != null:
		weakpoint_visual.visible = false
	play_anim(&"Idle")


## Player attacks call this via the enemy group. Only lands while exposed.
func try_receive_hit(amount: int, _hit_origin: Vector2) -> bool:
	if not _weakpoint_exposed or amount <= 0:
		return false
	if damageable == null or not damageable.has_method("take_damage"):
		return false
	damageable.take_damage(amount)
	return true


func attack_laser_sweep() -> void:
	if not _begin_attack():
		return
	play_anim(&"Cargar", true)
	await _wait(0.35)

	var arena := get_arena()
	var go_right := randf() > 0.5
	var start_angle: float
	var end_angle: float
	if go_right:
		start_angle = deg_to_rad(-20.0)
		end_angle = deg_to_rad(100.0)
	else:
		start_angle = deg_to_rad(200.0)
		end_angle = deg_to_rad(80.0)
	if arena.size != Vector2.ZERO:
		# Prefer sweeping toward an arena edge from the head.
		pass

	_show_laser()
	_laser_active = true
	contact_damage = laser_damage
	var elapsed := 0.0
	while elapsed < laser_sweep_duration:
		if not await _await_physics():
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
	await _wait(0.3)

	var player := get_player()
	var dir := Vector2.DOWN
	if player != null:
		dir = (player.global_position - global_position).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.DOWN

	_show_laser()
	_laser_active = true
	contact_damage = laser_damage

	var origin := global_position
	var points: PackedVector2Array = PackedVector2Array([origin])
	var remaining := bounce_bounces
	var travel_dir := dir
	var tip := origin

	# Build full polyline first, then animate the tip along it.
	while remaining >= 0:
		var cast_to := travel_dir * bounce_segment_length
		var hit := _ray_wall(tip, cast_to)
		if hit.is_empty():
			tip = tip + cast_to
			points.append(tip)
			break
		var hit_pos: Vector2 = hit.position
		# Nudge off the wall so the next ray doesn't re-hit immediately.
		hit_pos -= travel_dir * 1.5
		points.append(hit_pos)
		var normal: Vector2 = hit.normal
		travel_dir = travel_dir.bounce(normal).normalized()
		tip = hit_pos
		remaining -= 1

	# Animate along segments.
	for i in range(1, points.size()):
		var a: Vector2 = points[i - 1]
		var b: Vector2 = points[i]
		var seg_len := a.distance_to(b)
		var dur := maxf(seg_len / maxf(bounce_travel_speed, 1.0), 0.05)
		var elapsed := 0.0
		while elapsed < dur:
			if not await _await_physics():
				_laser_active = false
				_hide_laser()
				_end_attack()
				return
			elapsed += get_physics_process_delta_time()
			var t := clampf(elapsed / dur, 0.0, 1.0)
			var cur := a.lerp(b, t)
			_set_laser_points(_prefix_points(points, i - 1, cur))

	await _wait(0.15)
	_laser_active = false
	_hide_laser()
	play_anim(&"Idle")
	_end_attack()


func attack_aoe() -> void:
	if not _begin_attack():
		return
	play_anim(&"Cargar", true)
	await _wait(0.25)
	_show_aoe()

	var max_r := aoe_max_radius
	var arena := get_arena()
	if arena.size != Vector2.ZERO:
		var to_corner := arena.get_center().distance_to(arena.position)
		max_r = maxf(max_r, to_corner + 20.0)

	var elapsed := 0.0
	while elapsed < aoe_grow_duration:
		if not await _await_physics():
			_hide_aoe()
			_end_attack()
			return
		elapsed += get_physics_process_delta_time()
		var t := clampf(elapsed / maxf(aoe_grow_duration, 0.01), 0.0, 1.0)
		_set_aoe_radius(lerpf(8.0, max_r, t))

	# Impact: only damages if the player is still in Pesadilla (mode 0).
	if WorldMode.get_mode() == WorldMode.MODE_PESADILLA:
		var player := get_player()
		if player != null and aoe_area != null:
			var radius := 0.0
			if aoe_shape != null and aoe_shape.shape is CircleShape2D:
				radius = (aoe_shape.shape as CircleShape2D).radius
			if player.global_position.distance_to(global_position) <= radius:
				deal_player_hit(player, aoe_damage, contact_knockback)

	await _wait(0.2)
	_hide_aoe()
	play_anim(&"Idle")
	_end_attack()


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
	if animated_sprite != null:
		var flash := create_tween()
		flash.tween_property(animated_sprite, "modulate", Color(1.4, 0.6, 0.6), 0.05)
		flash.tween_property(animated_sprite, "modulate", Color.WHITE, 0.12)


func _on_weakpoint_died() -> void:
	hide_weakpoint()
	weakpoint_broken.emit()


func _show_laser() -> void:
	if laser_line != null:
		laser_line.visible = true
		laser_line.clear_points()
	if laser_ray != null:
		laser_ray.enabled = true


func _hide_laser() -> void:
	_laser_active = false
	if laser_line != null:
		laser_line.visible = false
		laser_line.clear_points()
	if laser_ray != null:
		laser_ray.enabled = false


func _update_laser_beam(dir: Vector2) -> void:
	var direction := dir.normalized() if dir != Vector2.ZERO else Vector2.DOWN
	var end := global_position + direction * laser_length
	var hit := _ray_wall(global_position, direction * laser_length)
	if not hit.is_empty():
		end = hit.position
	_set_laser_points(PackedVector2Array([global_position, end]))


func _set_laser_points(points: PackedVector2Array) -> void:
	if laser_line == null:
		return
	laser_line.clear_points()
	for p in points:
		laser_line.add_point(laser_line.to_local(p))


func _prefix_points(points: PackedVector2Array, up_to: int, tip: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(up_to + 1):
		out.append(points[i])
	out.append(tip)
	return out


func _tick_laser_damage() -> void:
	if _laser_hit_cd > 0.0 or laser_line == null or laser_line.get_point_count() < 2:
		return
	var player := get_player()
	if player == null:
		return
	# Approximate: distance from player to each laser segment.
	for i in range(laser_line.get_point_count() - 1):
		var a := laser_line.to_global(laser_line.get_point_position(i))
		var b := laser_line.to_global(laser_line.get_point_position(i + 1))
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


func _ray_wall(from: Vector2, cast_to: Vector2) -> Dictionary:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, from + cast_to)
	query.collision_mask = 1 << 0 # world
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	return space.intersect_ray(query)


func _show_aoe() -> void:
	if aoe_area != null:
		aoe_area.visible = true
		aoe_area.monitoring = false
	_set_aoe_radius(8.0)


func _hide_aoe() -> void:
	if aoe_area != null:
		aoe_area.visible = false
	_set_aoe_radius(8.0)


func _set_aoe_radius(radius: float) -> void:
	if aoe_shape != null and aoe_shape.shape is CircleShape2D:
		(aoe_shape.shape as CircleShape2D).radius = radius
	if aoe_visual != null:
		var s := radius / 32.0
		aoe_visual.scale = Vector2(s, s)
