class_name PickupProp
extends Area2D

## Collectible prop. Heal / buff / shield / max-health pickups.

@export var definition: PropPickupDef:
	set(value):
		definition = value
		notify_property_list_changed()
## Stacks for attack / projectile / shield. -1 = use definition.stacks.
@export_range(-1, 99) var stacks: int = -1
## Heal amount override (heal pickups only). -1 = use the definition amount.
@export_range(-1, 999) var heal_amount: int = -1
## Damage added per attack stack to any hit (melee or projectile). -1 = player default.
@export_range(-1, 999) var attack_damage: int = -1
## Damage of the extra projectile each attack launches. -1 = attack's own projectile damage.
@export_range(-1, 999) var projectile_damage: int = -1
## Vertical float amplitude in pixels.
@export var float_amplitude: float = 2.5
## Full up-down cycles per second.
@export var float_speed: float = 1.35
## Fade-out duration when collected.
@export var collect_fade_time: float = 0.22

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var _collected: bool = false
var _float_phase: float = 0.0
var _sprite_base_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group("prop_pickup")
	collision_layer = 0
	collision_mask = 1 << 1 # player
	# Deferred: pickups may spawn during physics callbacks (boss heal drop, etc.).
	set_deferred("monitoring", true)
	set_deferred("monitorable", false)
	apply_definition()
	_sprite_base_pos = sprite.position
	_float_phase = randf() * TAU
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	# Drops that spawn on top of the player (cat catch) still collect.
	call_deferred("_collect_if_already_overlapping")


func _process(delta: float) -> void:
	if _collected or sprite == null or float_amplitude <= 0.0:
		return
	_float_phase += delta * float_speed * TAU
	sprite.position = _sprite_base_pos + Vector2(0.0, sin(_float_phase) * float_amplitude)


func _collect_if_already_overlapping() -> void:
	if _collected or not monitoring:
		return
	for body in get_overlapping_bodies():
		if body is Node2D:
			_on_body_entered(body as Node2D)
			if _collected:
				return


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


func _validate_property(property: Dictionary) -> void:
	var kind := get_pickup_type()
	match property.name:
		&"heal_amount":
			if kind != &"heal":
				property["usage"] = PROPERTY_USAGE_NO_EDITOR
		&"attack_damage":
			if kind != &"attack_boost" and kind != &"attack":
				property["usage"] = PROPERTY_USAGE_NO_EDITOR
		&"projectile_damage":
			if kind != &"projectile_boost" and kind != &"projectile":
				property["usage"] = PROPERTY_USAGE_NO_EDITOR
		&"stacks":
			var is_stack := (
				kind == &"attack_boost"
				or kind == &"attack"
				or kind == &"projectile_boost"
				or kind == &"projectile"
				or kind == &"shield"
			)
			if not is_stack:
				property["usage"] = PROPERTY_USAGE_NO_EDITOR


func get_pickup_amount() -> int:
	if definition != null:
		return definition.amount
	return 1


func get_heal_amount() -> int:
	if heal_amount >= 0:
		return heal_amount
	return get_pickup_amount()


func get_attack_damage_override() -> int:
	return attack_damage


func get_projectile_damage_override() -> int:
	return projectile_damage


func get_pickup_stacks() -> int:
	if stacks > 0:
		return stacks
	if definition != null:
		if definition.has_method("get_effect_value") and definition.is_stack_pickup():
			return definition.get_effect_value()
		# Legacy .tres that only set amount for shield/boosts.
		return maxi(definition.amount, 1)
	return 1


func _on_body_entered(body: Node2D) -> void:
	if _collected or body == null:
		return
	if not body.is_in_group("player"):
		return
	_collected = true
	set_deferred("monitoring", false)
	if collision_shape != null:
		collision_shape.set_deferred("disabled", true)
	_apply_pickup(body)
	play_collect_sfx()
	_play_collect_fade()


func _play_collect_fade() -> void:
	if sprite == null:
		queue_free()
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "modulate:a", 0.0, collect_fade_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(sprite, "position:y", sprite.position.y - 6.0, collect_fade_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "scale", sprite.scale * 1.15, collect_fade_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)


func _apply_pickup(player: Node) -> void:
	var kind := get_pickup_type()
	var amount := get_pickup_amount()
	var stack_count := get_pickup_stacks()
	match kind:
		&"cat_heal":
			_apply_cat_heal(player)
		&"heal":
			_apply_heal(player, float(get_heal_amount()))
		&"max_health", &"maxhealth":
			_apply_max_health(player, float(amount))
		&"attack_boost", &"attack":
			_apply_attack_boost(player, stack_count)
		&"projectile_boost", &"projectile":
			_apply_projectile_boost(player, stack_count)
		&"shield":
			_apply_shield(player, stack_count)
		_:
			_apply_heal(player, float(amount))


func _apply_heal(player: Node, amount: float) -> void:
	if player.has_method("heal_vitality"):
		player.call("heal_vitality", amount)
		return
	var vit: Node = player.get_node_or_null("Vitality")
	if vit != null and vit.has_method("heal"):
		vit.call("heal", amount)


func _apply_cat_heal(player: Node) -> void:
	if player.has_method("heal_vitality_from_cat"):
		player.call("heal_vitality_from_cat")
		return
	var vit: Node = player.get_node_or_null("Vitality")
	if vit != null and vit.has_method("heal_from_cat"):
		vit.call("heal_from_cat")
		return
	# Fallback: fill the bar.
	if vit != null and "max_vitality" in vit and vit.has_method("heal"):
		vit.call("heal", float(vit.max_vitality))



func _apply_max_health(player: Node, amount: float) -> void:
	if player.has_method("increase_max_vitality"):
		player.call("increase_max_vitality", amount)
		return
	var vit: Node = player.get_node_or_null("Vitality")
	if vit != null and vit.has_method("increase_max"):
		vit.call("increase_max", amount)


func _apply_attack_boost(player: Node, stacks: int) -> void:
	var buffs := _get_buffs(player)
	if buffs != null and buffs.has_method("apply_attack_boost"):
		buffs.call("apply_attack_boost", stacks, get_attack_damage_override())


func _apply_projectile_boost(player: Node, stacks: int) -> void:
	var buffs := _get_buffs(player)
	if buffs != null and buffs.has_method("apply_projectile_boost"):
		buffs.call("apply_projectile_boost", stacks, get_projectile_damage_override())


func _apply_shield(player: Node, hits: int) -> void:
	var buffs := _get_buffs(player)
	if buffs != null and buffs.has_method("apply_shield"):
		buffs.call("apply_shield", hits)


func _get_buffs(player: Node) -> Node:
	if player == null:
		return null
	return player.get_node_or_null("Buffs")


## Call from collect logic when the player picks this up.
func play_collect_sfx() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var sfx := player.get_node_or_null("SfxPlayer")
	if sfx != null and sfx.has_method("play_pickup"):
		sfx.call("play_pickup", get_pickup_type())
