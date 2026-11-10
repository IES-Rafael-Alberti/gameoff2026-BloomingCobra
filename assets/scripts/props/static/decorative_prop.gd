class_name DecorativeProp
extends StaticBody2D

## Decorative prop; collision optional via PropDecorativeDef.blocks_movement.

const LAYER_WORLD := 1 << 0
const DEFAULT_DEFINITION := preload("res://assets/resources/props/decorative_lamp.tres")

@export var definition: PropDecorativeDef = DEFAULT_DEFINITION

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group("prop_decorative")
	z_index = maxi(z_index, 1)
	apply_definition()


func apply_definition() -> void:
	var def: PropDecorativeDef = definition if definition != null else DEFAULT_DEFINITION
	def.apply_visual(sprite, self)
	def.apply_collision_shape(collision_shape)
	if def.blocks_movement:
		collision_layer = LAYER_WORLD
		collision_mask = 0
		if collision_shape != null:
			collision_shape.disabled = false
	else:
		collision_layer = 0
		collision_mask = 0
		if collision_shape != null:
			collision_shape.disabled = true
