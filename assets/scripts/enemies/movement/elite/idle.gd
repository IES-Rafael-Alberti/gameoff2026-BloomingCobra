extends EliteState

## Waits until the player stays in detection range for aggro_delay.

@export var aggro_range: float = 110.0
var detection_radius: float = 110.0
var aggro_delay: float = 0.0

var _aggro_timer: float = 0.0


func enter(_from: StringName = &"") -> void:
	_aggro_timer = 0.0
	if brain == null:
		return
	brain.get_enemy().velocity = Vector2.ZERO
	brain.set_shield_active(true)
	brain.play_defense_anim()


func exit(_to: StringName = &"") -> void:
	_aggro_timer = 0.0


func physics_update(delta: float) -> void:
	if brain == null:
		return
	brain.get_enemy().velocity = Vector2.ZERO
	brain.play_defense_anim()
	var player: Node2D = brain.get_player()
	if player == null:
		_aggro_timer = 0.0
		return

	var radius: float = _get_detection_radius()
	var delay: float = _get_aggro_delay()
	var dist: float = brain.get_enemy().global_position.distance_to(player.global_position)
	if dist > radius:
		_aggro_timer = 0.0
		return

	if delay <= 0.0:
		brain.change_state(&"aggressive")
		return

	_aggro_timer += delta
	if _aggro_timer >= delay:
		brain.change_state(&"aggressive")


func _get_detection_radius() -> float:
	if brain != null and "detection_radius" in brain:
		return float(brain.detection_radius)
	if detection_radius > 0.0:
		return detection_radius
	return aggro_range


func _get_aggro_delay() -> float:
	if brain != null and "aggro_delay" in brain:
		return float(brain.aggro_delay)
	return aggro_delay
