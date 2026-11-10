class_name PropPickupDef
extends PropDefinition

## Stub for future pickups (heals, upgrades…). No collect logic yet.

@export var pickup_type: StringName = &"heal"
@export var amount: int = 1


func _init() -> void:
	placeholder_color = Color(0.95, 0.85, 0.25, 1.0)
	collision_size = Vector2(12, 12)
	if display_name.is_empty():
		display_name = "Pickup"
