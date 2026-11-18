class_name Door
extends StaticBody2D

## Layer bits (1-based Godot layers):
## 1 world, 2 player, 3 enemy, 4 door_enemy, 5 door_player
const LAYER_DOOR_ENEMY := 1 << 3
const LAYER_DOOR_PLAYER := 1 << 4
const LAYER_PLAYER := 1 << 1

@export var door_id: StringName = &""
## Destination room scene path (use uid:// or res://). Empty = sealed barrier.
@export_file("*.tscn") var target_room: String = ""
## Door id inside the destination room where the player should spawn.
@export var target_door_id: StringName = &""
@export var starts_open: bool = false

var _open: bool = false
var _trigger: Area2D = null
var _spawn: Marker2D = null
var _requesting_transition: bool = false


func _ready() -> void:
	add_to_group("door")
	collision_mask = 0
	# Stay solid even if the parent room pauses with PROCESS_MODE_DISABLED.
	disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE

	if door_id == &"":
		door_id = StringName(name.to_lower())

	var shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape != null and shape.disabled:
		starts_open = true

	_ensure_spawn()
	_ensure_trigger()
	set_open(starts_open)


func is_linked() -> bool:
	return not target_room.is_empty()


func get_spawn_position() -> Vector2:
	_ensure_spawn()
	return _spawn.global_position


func set_open(open: bool) -> void:
	_open = open
	for child in get_children():
		if child is CollisionShape2D and child != _trigger_shape():
			# Shapes stay enabled; open/closed is handled by layers.
			# Defer in case this is called from a physics body_entered callback.
			child.set_deferred("disabled", false)

	# Only enemies collide when open — player can pass.
	var layer := LAYER_DOOR_ENEMY if _open else (LAYER_DOOR_ENEMY | LAYER_DOOR_PLAYER)
	set_deferred("collision_layer", layer)

	if _trigger != null:
		_trigger.monitoring = _open and is_linked()


func is_open() -> bool:
	return _open


func toggle_open() -> void:
	set_open(not _open)


func _ensure_spawn() -> void:
	_spawn = get_node_or_null("Spawn") as Marker2D
	if _spawn != null:
		return
	_spawn = Marker2D.new()
	_spawn.name = "Spawn"
	add_child(_spawn)
	# Default: a short step inward from the door collision center toward room origin.
	var door_center := _collision_local_center()
	var inward := -door_center.normalized() if door_center.length_squared() > 0.01 else Vector2.DOWN
	_spawn.position = door_center + inward * 40.0


func _ensure_trigger() -> void:
	_trigger = get_node_or_null("Trigger") as Area2D
	if _trigger == null:
		_trigger = Area2D.new()
		_trigger.name = "Trigger"
		add_child(_trigger)

		var shape_node := CollisionShape2D.new()
		shape_node.name = "CollisionShape2D"
		var rect := RectangleShape2D.new()
		var source := get_node_or_null("CollisionShape2D") as CollisionShape2D
		if source != null and source.shape is RectangleShape2D:
			var src_rect := source.shape as RectangleShape2D
			rect.size = src_rect.size * 1.4
			shape_node.position = source.position
		else:
			rect.size = Vector2(48, 48)
			shape_node.position = _collision_local_center()
		shape_node.shape = rect
		_trigger.add_child(shape_node)

	_trigger.collision_layer = 0
	_trigger.collision_mask = LAYER_PLAYER
	_trigger.monitoring = false
	_trigger.monitorable = false
	_trigger.process_mode = Node.PROCESS_MODE_ALWAYS
	_trigger.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE

	if not _trigger.body_entered.is_connected(_on_trigger_body_entered):
		_trigger.body_entered.connect(_on_trigger_body_entered)


func _trigger_shape() -> CollisionShape2D:
	if _trigger == null:
		return null
	return _trigger.get_node_or_null("CollisionShape2D") as CollisionShape2D


func _collision_local_center() -> Vector2:
	var shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape != null:
		return shape.position
	return Vector2.ZERO


func _on_trigger_body_entered(body: Node) -> void:
	if _requesting_transition or not _open or not is_linked():
		return
	if body == null or not body.is_in_group("player"):
		return
	var manager := get_tree().get_first_node_in_group("room_manager")
	if manager == null or not manager.has_method("go_to"):
		return
	if manager.has_method("is_enter_grace_active") and bool(manager.call("is_enter_grace_active")):
		return
	if manager.has_method("is_transitioning") and bool(manager.call("is_transitioning")):
		return
	_requesting_transition = true
	manager.call("go_to", target_room, target_door_id)
	# go_to is async; allow a later re-entry if the transition was skipped.
	_requesting_transition = false
