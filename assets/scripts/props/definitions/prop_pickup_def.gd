class_name PropPickupDef
extends PropDefinition

## Collectible pickup definition (heal, upgrades…).

@export var pickup_type: StringName = &"heal"
@export var amount: int = 25


func _init() -> void:
	placeholder_color = Color(0.35, 0.85, 0.45, 1.0)
	collision_size = Vector2(14, 14)
	if display_name.is_empty():
		display_name = "Pickup"
