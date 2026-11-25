class_name PropPickupDef
extends PropDefinition

## Collectible pickup definition (heal, upgrades…).
## `amount` meaning depends on pickup_type:
## - heal / cat_heal: vitality restored
## - max_health: max vitality gained (also heals that much)
## - attack_boost / projectile_boost: damage stacks added (permanent)
## - shield: number of hits absorbed
## `duration` is unused (kept for older .tres files).

@export var pickup_type: StringName = &"heal"
@export var amount: int = 25
@export var duration: float = 0.0


func _init() -> void:
	placeholder_color = Color(0.35, 0.85, 0.45, 1.0)
	collision_size = Vector2(14, 14)
	sprite_scale = 0.18
	if display_name.is_empty():
		display_name = "Pickup"
