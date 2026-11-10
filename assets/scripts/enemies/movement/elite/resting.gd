extends EliteState

## Post-charge rest. Shield still blocks the front; back is vulnerable.

@export var rest_time: float = 1.4

var _timer: float = 0.0


func enter(_from: StringName = &"") -> void:
	if brain == null:
		return
	_timer = rest_time
	brain.get_enemy().velocity = Vector2.ZERO
	brain.set_shield_active(true)
	brain.play_resting_anim(brain.get_facing())


func physics_update(delta: float) -> void:
	if brain == null:
		return
	brain.get_enemy().velocity = Vector2.ZERO
	brain.play_resting_anim(brain.get_facing())
	_timer -= delta
	if _timer <= 0.0:
		brain.change_state(&"aggressive")
