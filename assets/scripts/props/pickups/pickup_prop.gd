class_name PickupProp
extends Area2D

## Stub pickup prop. Collect logic comes later.

@export var definition: PropPickupDef

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group("prop_pickup")
	collision_layer = 0
	collision_mask = 1 << 1 # player
	monitoring = true
	monitorable = false
	apply_definition()


func apply_definition() -> void:
	var def := definition
	if def == null:
		def = PropPickupDef.new()
		def.id = &"pickup_default"
	def.apply_visual(sprite, self)
	def.apply_collision_shape(collision_shape)


func get_pickup_type() -> StringName:
	if definition != null:
		return definition.pickup_type
	return &"heal"


func get_pickup_amount() -> int:
	if definition != null:
		return definition.amount
	return 1
