@tool
class_name MemoryInteractable
extends Area2D

## Memory pickup. Place the shared scene and pick which of the 3 sprites to show
## in the inspector (`memory_sprite`), or drag a custom Texture2D into `sprite_override`.

signal memory_triggered(text: String)

@export var memory_id: StringName = &""
@export_multiline var memory_text: String = "..."
@export var interact_action: StringName = &"switch"
## Which frame from the shared memory spritesheet (animations "1" / "2" / "3").
@export_enum("1", "2", "3") var memory_sprite: int = 0:
	set(value):
		memory_sprite = clampi(value, 0, 2)
		_apply_visual()
## Optional: drag any Texture2D here to replace the sheet frame on this instance.
@export var sprite_override: Texture2D:
	set(value):
		sprite_override = value
		_apply_visual()

@onready var _anim: AnimatedSprite2D = get_node_or_null("Sprite2D") as AnimatedSprite2D

var _player_inside: bool = false
var _collected: bool = false
var _default_frames: SpriteFrames


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1 << 1 # player
	_cache_default_frames()
	if not Engine.is_editor_hint():
		if not body_entered.is_connected(_on_body_entered):
			body_entered.connect(_on_body_entered)
		if not body_exited.is_connected(_on_body_exited):
			body_exited.connect(_on_body_exited)
		if memory_id == &"":
			memory_id = _resolve_memory_id()
		if RunState != null and RunState.has_collected_memory(memory_id):
			_apply_collected(false)
	_apply_visual()


func _cache_default_frames() -> void:
	if _anim == null:
		_anim = get_node_or_null("Sprite2D") as AnimatedSprite2D
	if _anim != null and _anim.sprite_frames != null and _default_frames == null:
		_default_frames = _anim.sprite_frames


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _collected or not _player_inside:
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


func _apply_visual() -> void:
	if _anim == null:
		_anim = get_node_or_null("Sprite2D") as AnimatedSprite2D
	if _anim == null:
		return
	_cache_default_frames()

	if sprite_override != null:
		# Show a one-off texture dragged onto this instance.
		var frames := SpriteFrames.new()
		frames.add_animation(&"override")
		frames.add_frame(&"override", sprite_override)
		_anim.sprite_frames = frames
		_anim.animation = &"override"
		if not Engine.is_editor_hint():
			_anim.play(&"override")
		return

	if _default_frames != null:
		_anim.sprite_frames = _default_frames
	var anim_name := StringName(str(memory_sprite + 1))
	if _anim.sprite_frames != null and _anim.sprite_frames.has_animation(anim_name):
		_anim.animation = anim_name
		if not Engine.is_editor_hint():
			_anim.play(anim_name)
		else:
			_anim.frame = 0


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
