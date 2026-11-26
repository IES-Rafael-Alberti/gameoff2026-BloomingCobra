class_name MemoryInteractable
extends Area2D

## Placeholder memory entity. Interaction UI comes later; for now prints text.
## Collected ids are tracked in RunState and persisted on SafeRoom checkpoints.

signal memory_triggered(text: String)

@export var memory_id: StringName = &""
@export_multiline var memory_text: String = "..."
@export var interact_action: StringName = &"switch"

var _player_inside: bool = false
var _collected: bool = false


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1 << 1 # player
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if memory_id == &"":
		memory_id = _resolve_memory_id()
	if RunState != null and RunState.has_collected_memory(memory_id):
		_apply_collected(false)


func _process(_delta: float) -> void:
	if _collected or not _player_inside:
		return
	# Poll so joypad trigger axes work (same as WorldMode switch).
	if Input.is_action_just_pressed(interact_action):
		trigger()


func trigger() -> void:
	if _collected:
		return
	if memory_id == &"":
		memory_id = _resolve_memory_id()
	_collected = true
	if RunState != null:
		RunState.collect_memory(memory_id)
	print("[Memory] ", memory_text)
	_play_pickup_sfx()
	memory_triggered.emit(memory_text)
	_apply_collected(true)


func is_collected() -> bool:
	return _collected


func _apply_collected(play_fade: bool) -> void:
	_collected = true
	_player_inside = false
	set_deferred("monitoring", false)
	var shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape != null:
		shape.set_deferred("disabled", true)
	if play_fade:
		_fade_out_and_free()
	else:
		visible = false
		queue_free()


func _fade_out_and_free() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)


func _resolve_memory_id() -> StringName:
	var room := _find_owning_room()
	if room != null and room.room_id != &"":
		return room.room_id
	if not name.is_empty():
		return StringName(name)
	return &"memory"


func _find_owning_room() -> Room:
	var node: Node = self
	while node != null:
		if node is Room:
			return node as Room
		node = node.get_parent()
	return null


func _play_pickup_sfx() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var sfx := player.get_node_or_null("SfxPlayer")
	if sfx != null and sfx.has_method("play_pickup"):
		sfx.call("play_pickup", &"memory")


func _on_body_entered(body: Node) -> void:
	if _collected:
		return
	if body != null and body.is_in_group("player"):
		_player_inside = true


func _on_body_exited(body: Node) -> void:
	if body != null and body.is_in_group("player"):
		_player_inside = false
