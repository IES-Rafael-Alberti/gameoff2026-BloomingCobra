extends Node2D

## Hub gate over the south door. Stays locked until every memory is collected.
## Uses the paper-note style of confirm_overlay.gd for the locked message.

const CONFIRM_SCRIPT := preload("res://assets/scripts/hud/confirm_overlay.gd")
const LAYER_PLAYER := 1 << 1

@export var required_memories: int = 3
@export var south_door_path: NodePath = NodePath("../DoorSur")
@export var approach_area_path: NodePath = NodePath("ApproachArea")
@export var locked_message: String = "You're not ready yet, gather the 3 memories."
@export_range(0.1, 6.0, 0.1) var fade_seconds: float = 1.8
@export_range(0.5, 10.0, 0.1) var message_duration: float = 3.0

var _door: Door = null
var _approach_area: Area2D = null
var _message: Node = null
var _message_timer: Timer = null
var _player_near: bool = false
var _message_shown: bool = false
var _unlocked: bool = false


func _ready() -> void:
	# The room root is PROCESS_MODE_DISABLED while inactive; the gate must keep
	# reacting (like the doors themselves).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_door = get_node_or_null(south_door_path) as Door
	_approach_area = get_node_or_null(approach_area_path) as Area2D
	if _door == null:
		push_warning("MemoriesGate: south door not found at %s" % south_door_path)
	_configure_approach_area()
	if _has_all_memories():
		_finish_unlock()
	else:
		_close_south_door()


func _configure_approach_area() -> void:
	if _approach_area == null:
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
	if _unlocked:
		return
	if _has_all_memories():
		_begin_unlock()
		return
	# Keep the door sealed even if room logic opens it while we are locked.
	if _door != null and _door.is_open():
		_close_south_door()
	_poll_proximity()


func _has_all_memories() -> bool:
	if RunState == null:
		return false
	return RunState.collected_memories.size() >= maxi(required_memories, 1)


func _close_south_door() -> void:
	if _door == null:
		return
	_door.starts_open = false
	_door.set_open(false)


func _begin_unlock() -> void:
	if _unlocked:
		return
	_unlocked = true
	_hide_message()
	if _approach_area != null:
		_approach_area.monitoring = false
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "modulate:a", 0.0, maxf(fade_seconds, 0.01))
	tween.tween_callback(_finish_unlock)


func _finish_unlock() -> void:
	_unlocked = true
	_hide_message()
	if _approach_area != null:
		_approach_area.monitoring = false
	modulate.a = 0.0
	visible = false
	if _door != null:
		_door.starts_open = true
		_door.set_open(true)


# --- Proximity / message -----------------------------------------------------

func _poll_proximity() -> void:
	if _approach_area == null:
		return
	var inside := false
	for body in _approach_area.get_overlapping_bodies():
		if body != null and body.is_in_group("player"):
			inside = true
			break
	if inside and not _player_near:
		_player_near = true
		_show_message()
	elif not inside and _player_near:
		_player_near = false
		_hide_message()


func _on_approach_body_entered(body: Node) -> void:
	if body == null or not body.is_in_group("player"):
		return
	if not _player_near:
		_player_near = true
		_show_message()


func _on_approach_body_exited(body: Node) -> void:
	if body == null or not body.is_in_group("player"):
		return
	if _player_near:
		_player_near = false
		_hide_message()


func _ensure_message() -> void:
	if _message != null:
		return
	var layer := CanvasLayer.new()
	layer.name = "GateMessageLayer"
	layer.layer = 110
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)

	_message = CONFIRM_SCRIPT.new()
	_message.set("prompt_text", locked_message)
	_message.set("options", PackedStringArray(["OK"]))
	_message.set("default_index", 0)
	_message.set("quit_on_confirm", false)
	_message.set("fade_in_seconds", 0.25)
	layer.add_child(_message)
	_message.connect("confirmed", Callable(self, "_hide_message"))

	_message_timer = Timer.new()
	_message_timer.name = "GateMessageTimer"
	_message_timer.one_shot = true
	_message_timer.wait_time = maxf(message_duration, 0.1)
	_message_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_message_timer.timeout.connect(_hide_message)
	add_child(_message_timer)


func _show_message() -> void:
	if _unlocked or _message_shown:
		return
	_message_shown = true
	_ensure_message()
	if _message != null and _message.has_method("open"):
		_message.call("open")
	if _message_timer != null:
		_message_timer.start()


func _hide_message() -> void:
	_message_shown = false
	if _message_timer != null:
		_message_timer.stop()
	if _message != null and _message.has_method("close"):
		_message.call("close")


func _input(event: InputEvent) -> void:
	if not _message_shown or _message == null:
		return
	if not _message.has_method("is_open") or not bool(_message.call("is_open")):
		return
	if event.is_action_pressed("ui_cancel"):
		_hide_message()
		get_viewport().set_input_as_handled()
		return
	if _message.has_method("handle_input") and bool(_message.call("handle_input", event)):
		get_viewport().set_input_as_handled()
