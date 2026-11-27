extends Node2D

## Room 22 bed. Approaching opens a YES/NO paper note; YES leads to the boss.
## If the three Max Health pickups are missing, a second warning note is shown.

const CONFIRM_SCRIPT := preload("res://assets/scripts/hud/confirm_overlay.gd")
const LAYER_PLAYER := 1 << 1
const MAX_HEALTH_AMOUNT := 20.0
## Known one-time Max Health pickups: room id -> node path relative to that room.
const MAX_HEALTH_PICKUP_KEYS := {
	&"1": "PickupMaxHealth",
	&"15": "Switchable/Pesadilla/PickupMaxHealth",
	&"18": "Switchable/Pesadilla/PickupMaxHealth",
}

@export var first_prompt: String = "Do you want to comfront your biggest fears?"
@export var warning_prompt: String = "Are you sure? You are still not as powerful as you could be"
@export var required_max_health_pickups: int = 3
@export var boss_room_scene: String = "res://assets/scenes/rooms/boss/bossRoom.tscn"
@export var boss_entry_door_id: StringName = &"west"
@export var approach_area_path: NodePath = NodePath("ApproachArea")
@export var overlay_layer: int = 110

var _approach_area: Area2D = null
var _first_confirm: Node = null
var _warning_confirm: Node = null
var _active_confirm: Node = null
var _player_near: bool = false
var _prompt_pending: bool = false
var _choice_in_progress: bool = false
var _advancing: bool = false
var _transitioning: bool = false


func _ready() -> void:
	# The room root is disabled while inactive; interact like the doors do.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_approach_area = get_node_or_null(approach_area_path) as Area2D
	_configure_approach_area()


func _configure_approach_area() -> void:
	if _approach_area == null:
		push_warning("FearsBed: approach area not found at %s" % approach_area_path)
		return
	_approach_area.process_mode = Node.PROCESS_MODE_ALWAYS
	_approach_area.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	_approach_area.collision_layer = 0
	_approach_area.collision_mask = LAYER_PLAYER
	_approach_area.monitoring = true
	_approach_area.monitorable = false
	if not _approach_area.body_entered.is_connected(_on_approach_body_entered):
		_approach_area.body_entered.connect(_on_approach_body_entered)
	if not _approach_area.body_exited.is_connected(_on_approach_body_exited):
		_approach_area.body_exited.connect(_on_approach_body_exited)


func _process(_delta: float) -> void:
	if _transitioning or _choice_in_progress:
		return
	_poll_proximity()


# --- Proximity ---------------------------------------------------------------

func _poll_proximity() -> void:
	if _approach_area == null:
		return
	var inside := false
	for body in _approach_area.get_overlapping_bodies():
		if body != null and body.is_in_group("player"):
			inside = true
			break
	if inside:
		if not _player_near:
			# Edge-triggered: one prompt per entry, like the hub gate.
			_player_near = true
			_prompt_pending = true
		if _prompt_pending and _show_first_confirm():
			_prompt_pending = false
	elif _player_near:
		_player_near = false
		_prompt_pending = false
		_cancel_active()


func _on_approach_body_entered(body: Node) -> void:
	if body != null and body.is_in_group("player") and not _player_near:
		_player_near = true
		_prompt_pending = true


func _on_approach_body_exited(body: Node) -> void:
	if body != null and body.is_in_group("player"):
		_player_near = false
		_prompt_pending = false
		_cancel_active()


# --- Confirm overlays --------------------------------------------------------

func _ensure_overlays() -> void:
	if _first_confirm != null:
		return
	var layer := CanvasLayer.new()
	layer.name = "FearsBedConfirmLayer"
	layer.layer = overlay_layer
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)

	_first_confirm = _make_confirm(first_prompt, "FearsConfirm")
	_warning_confirm = _make_confirm(warning_prompt, "PowerWarningConfirm")
	layer.add_child(_first_confirm)
	layer.add_child(_warning_confirm)

	_connect_confirm(_first_confirm, _on_first_confirmed)
	_connect_confirm(_warning_confirm, _on_warning_confirmed)


func _make_confirm(prompt: String, node_name: String) -> Node:
	var confirm := CONFIRM_SCRIPT.new()
	confirm.name = node_name
	# Configure before add_child so _ready() builds the correct prompt.
	confirm.set("prompt_text", prompt)
	confirm.set("options", PackedStringArray(["YES", "NO"]))
	confirm.set("default_index", 1)
	confirm.set("quit_on_confirm", false)
	confirm.set("fade_in_seconds", 0.3)
	return confirm


func _connect_confirm(confirm: Node, confirmed_callable: Callable) -> void:
	if confirm == null:
		return
	if confirm.has_signal("confirmed"):
		confirm.connect("confirmed", confirmed_callable)
	if confirm.has_signal("closed"):
		confirm.connect("closed", Callable(self, "_on_confirm_closed"))


func _show_first_confirm() -> bool:
	if _choice_in_progress or _transitioning:
		return false
	var manager := get_tree().get_first_node_in_group("room_manager")
	if manager != null and manager.has_method("is_transitioning") and bool(manager.call("is_transitioning")):
		return false
	_choice_in_progress = true
	_ensure_overlays()
	_show_confirm(_first_confirm)
	return true


func _show_confirm(confirm: Node) -> void:
	_active_confirm = confirm
	if confirm != null and confirm.has_method("open"):
		confirm.call("open")


func _close_active() -> void:
	if _active_confirm != null and _active_confirm.has_method("close"):
		_active_confirm.call("close")
	_active_confirm = null


func _cancel_active() -> void:
	if _active_confirm == null:
		return
	_choice_in_progress = false
	_close_active()


func _on_confirm_closed() -> void:
	if _advancing:
		return
	# NO / gamepad cancel: the player declined this step.
	_choice_in_progress = false
	_active_confirm = null


func _on_first_confirmed() -> void:
	if _transitioning:
		return
	_advancing = true
	_close_active()
	_advancing = false
	if _collected_max_health_count() >= maxi(required_max_health_pickups, 1):
		_travel_to_boss()
	else:
		_show_confirm(_warning_confirm)


func _on_warning_confirmed() -> void:
	if _transitioning:
		return
	_advancing = true
	_close_active()
	_advancing = false
	_travel_to_boss()


func _input(event: InputEvent) -> void:
	if _active_confirm == null:
		return
	if not bool(_active_confirm.call("is_open")):
		return
	if event.is_action_pressed("ui_cancel"):
		_cancel_active()
		get_viewport().set_input_as_handled()
		return
	if bool(_active_confirm.call("handle_input", event)):
		get_viewport().set_input_as_handled()


# --- Progress / transition ---------------------------------------------------

func _collected_max_health_count() -> int:
	if RunState == null:
		return 0
	var count := 0
	if RunState.has_method("has_collected_pickup"):
		for room_id in MAX_HEALTH_PICKUP_KEYS.keys():
			var key := String(MAX_HEALTH_PICKUP_KEYS[room_id])
			if bool(RunState.call("has_collected_pickup", room_id, key)):
				count += 1
	# Fallback for saves where the bonus exists but room keys were not recorded.
	if RunState.has_method("get_permanent_max_vitality_bonus"):
		var bonus := float(RunState.call("get_permanent_max_vitality_bonus"))
		count = maxi(count, int(round(bonus / MAX_HEALTH_AMOUNT)))
	return count


func _travel_to_boss() -> void:
	if _transitioning:
		return
	var manager := get_tree().get_first_node_in_group("room_manager")
	if manager == null or not manager.has_method("go_to"):
		push_error("FearsBed: room_manager not found")
		_choice_in_progress = false
		return
	if manager.has_method("is_transitioning") and bool(manager.call("is_transitioning")):
		_choice_in_progress = false
		return
	_transitioning = true
	_choice_in_progress = false
	manager.call("go_to", boss_room_scene, boss_entry_door_id)
