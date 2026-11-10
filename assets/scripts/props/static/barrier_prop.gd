class_name BarrierProp
extends StaticBody2D

## Indestructible solid barrier driven by PropBarrierDef.

const LAYER_WORLD := 1 << 0
const DEFAULT_DEFINITION := preload("res://assets/resources/props/barrier_stone.tres")

@export var definition: PropBarrierDef = DEFAULT_DEFINITION

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group("prop_barrier")
	z_index = maxi(z_index, 1)
	collision_layer = LAYER_WORLD
	collision_mask = 0
	apply_definition()


func apply_definition() -> void:
	var def: PropBarrierDef = definition if definition != null else DEFAULT_DEFINITION
	def.apply_visual(sprite, self)
	def.apply_collision_shape(collision_shape)
