class_name PropPickupDef
extends PropDefinition

## Collectible pickup definition (heal, upgrades…).
## `amount` — heal / cat_heal / max_health vitality points.
## `stacks` — attack_boost / projectile_boost / shield accumulations (not timed).

@export var pickup_type: StringName = &"heal"
@export var amount: int = 25
## Stacks granted for attack / projectile / shield pickups.
@export_range(1, 99) var stacks: int = 1


func is_stack_pickup() -> bool:
	match pickup_type:
		&"attack_boost", &"attack", &"projectile_boost", &"projectile", &"shield":
			return true
		_:
			return false


func get_effect_value() -> int:
	if is_stack_pickup():
		return maxi(stacks, 1)
	return amount


func _init() -> void:
	placeholder_color = Color(0.35, 0.85, 0.45, 1.0)
	collision_size = Vector2(14, 14)
	sprite_scale = 0.18
	if display_name.is_empty():
		display_name = "Pickup"
