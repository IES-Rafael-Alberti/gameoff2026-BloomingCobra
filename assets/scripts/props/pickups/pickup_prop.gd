class_name PickupProp
extends Area2D

## Collectible prop. Heal pickups restore vigil vitality.

@export var definition: PropPickupDef

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var _collected: bool = false


func _ready() -> void:
	add_to_group("prop_pickup")
	collision_layer = 0
	collision_mask = 1 << 1 # player
	monitoring = true
	monitorable = false
	apply_definition()
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


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


func _on_body_entered(body: Node2D) -> void:
	if _collected or body == null:
		return
	if not body.is_in_group("player"):
		return
	_collected = true
	_apply_pickup(body)
	play_collect_sfx()
	queue_free()


func _apply_pickup(player: Node) -> void:
	var kind := get_pickup_type()
	var amount := float(get_pickup_amount())
	if kind == &"heal" or kind == &"max_health" or kind == &"maxhealth":
		if player.has_method("heal_vitality"):
			player.call("heal_vitality", amount)
		elif player.has_node("Vitality"):
			var vit: Node = player.get_node("Vitality")
			if vit.has_method("heal"):
				vit.call("heal", amount)


## Call from collect logic when the player picks this up.
func play_collect_sfx() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var sfx := player.get_node_or_null("SfxPlayer")
	if sfx != null and sfx.has_method("play_pickup"):
		sfx.call("play_pickup", get_pickup_type())
