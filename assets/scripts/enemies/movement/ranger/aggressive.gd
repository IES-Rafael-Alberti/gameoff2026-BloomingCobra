extends Node

## Align to an axis and fire projectiles while the player stays in detection range.

var brain: Node = null
var _cooldown_left: float = 0.0


func setup(ranger_brain: Node) -> void:
	brain = ranger_brain


func enter(_from: StringName = &"") -> void:
	_cooldown_left = 0.0


func exit(_to: StringName = &"") -> void:
	_cooldown_left = 0.0
	if brain == null:
		return
	var enemy: CharacterBody2D = brain.get_enemy()
	if enemy != null:
		enemy.call("set_attacking", false)


func physics_update(delta: float) -> void:
	if brain == null:
		return
	var enemy: CharacterBody2D = brain.get_enemy()
	if enemy == null:
		return

	_cooldown_left = maxf(_cooldown_left - delta, 0.0)

	var player: Node2D = brain.get_player()
	if player == null:
		brain.change_state(&"idle")
		return

	var detection_radius: float = float(brain.detection_radius) if "detection_radius" in brain else 110.0
	var to_player: Vector2 = player.global_position - enemy.global_position
	if to_player.length() > detection_radius:
		brain.change_state(&"idle")
		return

	var axis_align_tolerance: float = float(brain.axis_align_tolerance) if "axis_align_tolerance" in brain else 8.0
	var aligned_h := absf(to_player.y) <= axis_align_tolerance
	var aligned_v := absf(to_player.x) <= axis_align_tolerance
	var axis_aligned := aligned_h or aligned_v

	if axis_aligned:
		_update_aligned(to_player, aligned_h)
	else:
		_update_seek_alignment(player.global_position)


func _update_aligned(to_player: Vector2, aligned_horizontal: bool) -> void:
	var enemy: CharacterBody2D = brain.get_enemy()
	var speed: float = float(brain.speed) if "speed" in brain else 45.0
	var preferred_distance: float = float(brain.preferred_distance) if "preferred_distance" in brain else 80.0
	var attack_range: float = float(brain.attack_range) if "attack_range" in brain else 120.0
	var fire_cooldown: float = float(brain.fire_cooldown) if "fire_cooldown" in brain else 1.2

	var axis_dir := Vector2.ZERO
	var axis_distance := 0.0

	if aligned_horizontal:
		axis_distance = absf(to_player.x)
		axis_dir = Vector2(signf(to_player.x), 0.0) if to_player.x != 0.0 else Vector2.RIGHT
	else:
		axis_distance = absf(to_player.y)
		axis_dir = Vector2(0.0, signf(to_player.y)) if to_player.y != 0.0 else Vector2.DOWN

	# Keep preferred distance on the shooting axis only.
	if axis_distance < preferred_distance * 0.85:
		enemy.velocity = -axis_dir * speed
		enemy.call("play_directional_animation", "walking", -axis_dir)
		enemy.call("set_attacking", false)
	elif axis_distance > preferred_distance * 1.15:
		enemy.velocity = axis_dir * speed
		enemy.call("play_directional_animation", "walking", axis_dir)
		enemy.call("set_attacking", false)
	else:
		enemy.velocity = Vector2.ZERO
		enemy.call("play_directional_animation", "walking", Vector2.ZERO)

	if axis_distance <= attack_range and _cooldown_left <= 0.0 and axis_dir != Vector2.ZERO:
		_cooldown_left = fire_cooldown
		enemy.call("set_attacking", true)
		enemy.call("play_directional_animation", "attacking", axis_dir)
		var sfx := enemy.get_node_or_null("SfxPlayer")
		if sfx != null and sfx.has_method("play_attack"):
			sfx.call("play_attack")
		_fire(axis_dir)
	elif axis_distance > attack_range:
		enemy.call("set_attacking", false)


func _update_seek_alignment(player_pos: Vector2) -> void:
	var enemy: CharacterBody2D = brain.get_enemy()
	var speed: float = float(brain.speed) if "speed" in brain else 45.0
	enemy.call("set_attacking", false)
	var target := _pick_alignment_spot(player_pos)
	var to_target: Vector2 = target - enemy.global_position
	if to_target.length() <= 4.0:
		enemy.velocity = Vector2.ZERO
		enemy.call("play_directional_animation", "walking", Vector2.ZERO)
		return

	# Move on one axis at a time so we never "slide" diagonally into a shot.
	var move_dir := Vector2.ZERO
	if absf(to_target.x) >= absf(to_target.y):
		move_dir = Vector2(signf(to_target.x), 0.0)
	else:
		move_dir = Vector2(0.0, signf(to_target.y))

	enemy.velocity = move_dir * speed
	enemy.call("play_directional_animation", "walking", move_dir)


func _pick_alignment_spot(player_pos: Vector2) -> Vector2:
	var enemy: CharacterBody2D = brain.get_enemy()
	var preferred_distance: float = float(brain.preferred_distance) if "preferred_distance" in brain else 80.0
	var enemy_pos := enemy.global_position
	var side_x := signf(enemy_pos.x - player_pos.x)
	if side_x == 0.0:
		side_x = 1.0
	var side_y := signf(enemy_pos.y - player_pos.y)
	if side_y == 0.0:
		side_y = 1.0

	# Same Y as player, caution distance on X → horizontal shot.
	var horizontal_spot := Vector2(player_pos.x + side_x * preferred_distance, player_pos.y)
	# Same X as player, caution distance on Y → vertical shot.
	var vertical_spot := Vector2(player_pos.x, player_pos.y + side_y * preferred_distance)

	# Prefer the spot that needs less travel from the current position.
	if enemy_pos.distance_squared_to(horizontal_spot) <= enemy_pos.distance_squared_to(vertical_spot):
		return horizontal_spot
	return vertical_spot


func _fire(direction: Vector2) -> void:
	var enemy: CharacterBody2D = brain.get_enemy()
	var template: Area2D = brain.get_projectile_template() if brain.has_method("get_projectile_template") else null
	if template == null or enemy == null:
		return
	var projectile_speed: float = float(brain.projectile_speed) if "projectile_speed" in brain else 120.0
	var bolt: Area2D = template.duplicate() as Area2D
	enemy.get_parent().add_child(bolt)
	bolt.global_position = enemy.global_position
	if bolt.has_method("launch"):
		bolt.launch(direction, projectile_speed, enemy)
