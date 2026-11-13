class_name BossHand
extends BossPart

## Left/right boss hand. `side` = -1 left, +1 right (mirrors swipe direction / flip).

@export var side: int = -1
@export var swipe_damage: int = 1
@export var slam_damage: int = 3
@export var swipe_speed: float = 90.0
@export var swipe_edge_margin: float = 24.0
@export var slam_tremble_time: float = 0.6
@export var slam_rise_time: float = 0.35
@export var slam_track_time: float = 1.1
@export var slam_fall_time: float = 0.22
@export var slam_radius: float = 28.0
@export var slam_shadow_start_scale: float = 0.25
@export var slam_shadow_end_scale: float = 1.15

@onready var shadow: Sprite2D = get_node_or_null("Shadow") as Sprite2D

var _slam_shadow_active: bool = false
var _slam_shadow_locked: bool = false
var _slam_shadow_target: Vector2 = Vector2.ZERO


func _ready() -> void:
	super._ready()
	if animated_sprite != null:
		animated_sprite.flip_h = side > 0
	if shadow != null:
		shadow.visible = false
	play_anim(&"Idle")


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _slam_shadow_active and shadow != null and not _slam_shadow_locked:
		var player := get_player()
		if player != null:
			shadow.global_position = player.global_position


func attack_swipe() -> void:
	if not _begin_attack():
		return

	play_anim(&"Cargar", true)
	var player := get_player()
	var arena := get_arena()
	var row_y := global_position.y
	if player != null:
		row_y = player.global_position.y
	if arena.size != Vector2.ZERO:
		row_y = clampf(row_y, arena.position.y + 20.0, arena.end.y - 20.0)

	var start_x: float
	var end_x: float
	if arena.size != Vector2.ZERO:
		if side < 0:
			start_x = arena.position.x + swipe_edge_margin
			end_x = arena.end.x - swipe_edge_margin
		else:
			start_x = arena.end.x - swipe_edge_margin
			end_x = arena.position.x + swipe_edge_margin
	else:
		start_x = _home_position.x
		end_x = _home_position.x + float(-side) * 180.0

	var approach := Vector2(start_x, row_y)
	var tween_in := create_tween()
	tween_in.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween_in.tween_property(self, "global_position", approach, 0.35)
	await tween_in.finished
	if not _can_await():
		_end_attack()
		return

	play_anim(&"Idle")
	contact_damage = swipe_damage
	var dist := absf(end_x - start_x)
	var duration := maxf(dist / maxf(swipe_speed, 1.0), 0.35)
	var tween_swipe := create_tween()
	tween_swipe.set_trans(Tween.TRANS_LINEAR)
	tween_swipe.tween_property(self, "global_position", Vector2(end_x, row_y), duration)
	await tween_swipe.finished
	if not _can_await():
		_end_attack()
		return

	await return_home(0.4)
	play_anim(&"Idle")
	_end_attack()


func attack_slam() -> void:
	if not _begin_attack():
		return

	play_anim(&"Cargar", true)
	if not await _tremble(slam_tremble_time):
		_end_attack()
		return

	var rise_target := _home_position + Vector2(0.0, -220.0)
	if get_arena().size != Vector2.ZERO:
		rise_target.y = minf(rise_target.y, get_arena().position.y - 80.0)
	var tween_rise := create_tween()
	tween_rise.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween_rise.tween_property(self, "global_position", rise_target, slam_rise_time)
	await tween_rise.finished
	if not _can_await():
		_end_attack()
		return

	_start_shadow_tracking()
	var elapsed := 0.0
	var grow_from := slam_shadow_start_scale
	while elapsed < slam_track_time:
		if not await _await_physics():
			_stop_shadow()
			_end_attack()
			return
		var dt := get_physics_process_delta_time()
		elapsed += dt
		if shadow != null:
			var t := clampf(elapsed / maxf(slam_track_time, 0.01), 0.0, 1.0)
			var s := lerpf(grow_from, slam_shadow_end_scale, t)
			shadow.scale = Vector2(s, s * 0.55)

	_slam_shadow_locked = true
	_slam_shadow_target = shadow.global_position if shadow != null else global_position
	if shadow != null:
		shadow.global_position = _slam_shadow_target

	var fall_pos := _slam_shadow_target
	var tween_fall := create_tween()
	tween_fall.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween_fall.tween_property(self, "global_position", fall_pos, slam_fall_time)
	await tween_fall.finished
	if not _can_await():
		_stop_shadow()
		_end_attack()
		return

	var player := get_player()
	if player != null and player.global_position.distance_to(fall_pos) <= slam_radius:
		deal_player_hit(player, slam_damage, contact_knockback * 1.35)

	_stop_shadow()
	await _wait(0.2)
	await return_home(0.45)
	play_anim(&"Idle")
	_end_attack()


func _tremble(duration: float) -> bool:
	if animated_sprite == null:
		return await _wait(duration)
	var base := animated_sprite.position
	var elapsed := 0.0
	while elapsed < duration:
		if not await _await_physics():
			animated_sprite.position = base
			return false
		elapsed += get_physics_process_delta_time()
		animated_sprite.position = base + Vector2(randf_range(-2.5, 2.5), randf_range(-1.5, 1.5))
	animated_sprite.position = base
	return true


func _start_shadow_tracking() -> void:
	_slam_shadow_active = true
	_slam_shadow_locked = false
	if shadow == null:
		return
	shadow.visible = true
	shadow.modulate = Color(0.05, 0.05, 0.08, 0.55)
	shadow.scale = Vector2(slam_shadow_start_scale, slam_shadow_start_scale * 0.55)
	var player := get_player()
	if player != null:
		shadow.global_position = player.global_position


func _stop_shadow() -> void:
	_slam_shadow_active = false
	_slam_shadow_locked = false
	if shadow != null:
		shadow.visible = false
