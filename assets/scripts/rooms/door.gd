@tool
class_name Door
extends StaticBody2D

## Drag-drop door prop. Collision when closed, Trigger Area when open,
## sprite swaps between closed/open. Place under Switchable/Pesadilla or
## Switchable/Sueño for mode-scoped doors (like other props).
##
## Orientation is set on this node; [DoorVisual] updates sprite, collision and spawn.
##
## Button unlock is per door: drag [PropButton] nodes into `unlock_buttons` to make
## this door open when its own buttons are pressed. Share a button across several
## doors to open them together.

## Emitted when this door's assigned buttons become satisfied and it opens.
signal button_unlocked

## Layer bits (1-based Godot layers):
## 1 world, 2 player, 3 enemy, 4 door_enemy, 5 door_player
const LAYER_DOOR_ENEMY := 1 << 3
const LAYER_DOOR_PLAYER := 1 << 4
const LAYER_PLAYER := 1 << 1

## North=0, East=1, South=2, West=3 (matches room instance overrides).
const ORIENT_NORTH := 0
const ORIENT_EAST := 1
const ORIENT_SOUTH := 2
const ORIENT_WEST := 3

@export var door_id: StringName = &""
## Destination room scene path (use uid:// or res://). Empty = sealed barrier.
@export_file("*.tscn") var target_room: String = ""
## Door id inside the destination room where the player should spawn.
@export var target_door_id: StringName = &""
@export var starts_open: bool = false

@export_group("Button Unlock")
## Buttons that open this door. Empty = not button-controlled.
## Assign the same button to several doors to make one button open all of them.
@export var unlock_buttons: Array[Area2D] = []
## If true, every assigned button must be pressed. If false, any one is enough.
@export var require_all_buttons: bool = true

@export_group("Orientation")
## Facing of the doorway on the room wall. Updates sprite + collision via DoorVisual.
@export_enum("North", "East", "South", "West") var orientation: int = ORIENT_NORTH:
	get:
		return _orientation
	set(value):
		_orientation = int(value)
		if is_inside_tree():
			_apply_orientation_layout()
## Legacy fallbacks when DoorVisual has no oriented textures.
@export var closed_texture: Texture2D
@export var open_texture: Texture2D

@onready var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D

var _orientation: int = ORIENT_NORTH
var _open: bool = false
var _trigger: Area2D = null
var _spawn: Marker2D = null
var _requesting_transition: bool = false
var _switchable: Node = null
var _buttons_wired: bool = false
var _button_unlock_done: bool = false
var _button_unlock_committed: bool = false


func _ready() -> void:
	add_to_group("door")
	collision_mask = 0
	# Keep receiving mode_changed / deferred applies while under an inactive Sueño/Pesadilla root.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Stay solid even if the parent room pauses with PROCESS_MODE_DISABLED.
	disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	z_index = maxi(z_index, 1)

	if door_id == &"":
		door_id = StringName(name.to_lower())

	# Legacy rooms marked open by disabling the body shape in the editor.
	var shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape != null and shape.disabled:
		starts_open = true

	if sprite == null:
		sprite = get_node_or_null("Sprite2D") as Sprite2D

	_ensure_spawn()
	_ensure_trigger()
	_bind_switchable_mode()
	_setup_button_unlock()
	if not Engine.is_editor_hint():
		set_open(starts_open)
	else:
		_open = starts_open
		_apply_orientation_layout()
	# Switchable._ready runs after children; reconcile once mode roots are applied.
	call_deferred("_apply_state")


func _notification(what: int) -> void:
	# When Sueño/Pesadilla is re-enabled, re-apply in case deferred calls were skipped while disabled.
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		call_deferred("_apply_state")
	elif what == NOTIFICATION_ENTER_TREE:
		call_deferred("_apply_state")


func is_linked() -> bool:
	return not target_room.is_empty()


func get_spawn_position() -> Vector2:
	_ensure_spawn()
	return _spawn.global_position


func set_open(open: bool) -> void:
	_open = open
	_apply_state()


func is_open() -> bool:
	return _open


func toggle_open() -> void:
	set_open(not _open)


## True when this door has buttons assigned to open it.
func has_button_unlock() -> bool:
	return not unlock_buttons.is_empty()


func is_button_unlock_done() -> bool:
	return _button_unlock_done


func is_button_unlock_committed() -> bool:
	return _button_unlock_committed


## True when this door's assigned buttons currently satisfy the unlock condition.
func are_buttons_satisfied() -> bool:
	if unlock_buttons.is_empty():
		return false
	if require_all_buttons:
		for button in unlock_buttons:
			if button == null:
				return false
			if button.has_method("is_pressed"):
				if not bool(button.call("is_pressed")):
					return false
			else:
				return false
		return true
	for button in unlock_buttons:
		if button != null and button.has_method("is_pressed") and bool(button.call("is_pressed")):
			return true
	return false


## Re-evaluate button state. Opens the door once its buttons are satisfied and
## keeps it open until reset_buttons() (void respawn) — matches the room's old
## "unlock once" behaviour.
func refresh_button_state() -> void:
	if unlock_buttons.is_empty() or _button_unlock_committed or _button_unlock_done:
		return
	if not are_buttons_satisfied():
		return
	_button_unlock_done = true
	set_open(true)
	button_unlocked.emit()


## Permanent unlock after leaving the room successfully: buttons stay pressed.
func commit_buttons() -> void:
	if unlock_buttons.is_empty():
		return
	_button_unlock_committed = true
	_button_unlock_done = true
	for button in unlock_buttons:
		if button != null and button.has_method("commit"):
			button.call("commit")
	set_open(true)


## Undo uncommitted button progress (e.g. void respawn).
func reset_buttons() -> void:
	if unlock_buttons.is_empty() or _button_unlock_committed:
		return
	_button_unlock_done = false
	for button in unlock_buttons:
		if button != null and button.has_method("reset"):
			button.call("reset")
	if not starts_open:
		set_open(false)


func _setup_button_unlock() -> void:
	if Engine.is_editor_hint() or _buttons_wired or unlock_buttons.is_empty():
		return
	_buttons_wired = true
	for button in unlock_buttons:
		if button == null:
			continue
		if button.has_signal("pressed") and not button.pressed.is_connected(_on_button_changed):
			button.pressed.connect(_on_button_changed)
		if button.has_signal("released") and not button.released.is_connected(_on_button_changed):
			button.released.connect(_on_button_changed)
	# Buttons may already be committed (room reload); reconcile next frame.
	call_deferred("refresh_button_state")


func _on_button_changed() -> void:
	# Button press arrives during physics flush — update doors next frame.
	call_deferred("refresh_button_state")


## True when this door belongs to the active Switchable mode branch (or is not mode-scoped).
## Place doors under Switchable/Pesadilla or Switchable/Sueño like props to scope them.
func is_mode_present() -> bool:
	if Engine.is_editor_hint():
		return true
	if _switchable == null:
		_switchable = _find_owning_switchable()
	if _switchable == null:
		return true
	var mode_root := _find_mode_variant_root()
	if mode_root == null:
		return true
	if _switchable.has_method("get_mode_root"):
		var active: Node = _switchable.call("get_mode_root")
		return active == mode_root
	return mode_root.visible


func _bind_switchable_mode() -> void:
	if Engine.is_editor_hint():
		return
	_switchable = _find_owning_switchable()
	if _switchable == null:
		return
	if _switchable.has_signal("mode_changed") and not _switchable.mode_changed.is_connected(_on_switchable_mode_changed):
		_switchable.mode_changed.connect(_on_switchable_mode_changed)


func _find_owning_switchable() -> Node:
	var node: Node = get_parent()
	while node != null:
		if node.is_in_group("switchable"):
			return node
		if node is Room:
			return null
		node = node.get_parent()
	return null


func _find_mode_variant_root() -> Node2D:
	## Direct child of Switchable that contains this door (Pesadilla / Sueño).
	if _switchable == null:
		_switchable = _find_owning_switchable()
	if _switchable == null:
		return null
	var node: Node = self
	while node != null:
		var parent := node.get_parent()
		if parent == _switchable:
			return node as Node2D
		if parent is Room:
			return null
		node = parent
	return null


func _on_switchable_mode_changed(_index: int) -> void:
	# Deferred so Switchable finishes toggling variant visibility / collisions first.
	call_deferred("_apply_state")


func _apply_state() -> void:
	var present := is_mode_present()

	for child in get_children():
		if child is CollisionShape2D and child != _trigger_shape():
			# Present: shapes stay enabled; open/closed is handled by layers.
			# Absent: keep disabled so we do not undo Switchable's mode hide.
			child.set_deferred("disabled", not present)

	var layer := 0
	if present:
		layer = LAYER_DOOR_ENEMY if _open else (LAYER_DOOR_ENEMY | LAYER_DOOR_PLAYER)
	set_deferred("collision_layer", layer)

	if _trigger != null:
		var can_transport := present and _open and is_linked()
		_trigger.monitoring = can_transport
		var trigger_shape := _trigger_shape()
		if trigger_shape != null:
			trigger_shape.set_deferred("disabled", not can_transport)

	_update_visual()


func _update_visual() -> void:
	_apply_orientation_layout()


func _apply_orientation_layout() -> void:
	var visual := _door_visual()
	if visual != null and visual.has_oriented_art():
		visual.apply(_orientation, _open)
		return
	_apply_legacy_textures()


func _door_visual() -> DoorVisual:
	return get_node_or_null("DoorVisual") as DoorVisual


func _apply_legacy_textures() -> void:
	if sprite == null:
		sprite = get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return
	# Never force sprite.visible=false for mode hiding — Switchable already toggles the
	# Pesadilla/Sueño parent. Doing so stuck Vigilia doors invisible after mode swaps.
	sprite.visible = true
	sprite.rotation = 0.0
	var tex := open_texture if _open else closed_texture
	if tex != null:
		sprite.texture = tex


func _ensure_spawn() -> void:
	_spawn = get_node_or_null("Spawn") as Marker2D
	if _spawn != null:
		return
	_spawn = Marker2D.new()
	_spawn.name = "Spawn"
	add_child(_spawn)
	var visual := _door_visual()
	if visual != null and visual.has_oriented_art():
		visual.apply(_orientation, _open)
		return
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

	if not Engine.is_editor_hint() and not _trigger.body_entered.is_connected(_on_trigger_body_entered):
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
	if _requesting_transition or not _open or not is_linked() or not is_mode_present():
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
