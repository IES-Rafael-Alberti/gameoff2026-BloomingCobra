class_name StartingRoom
extends Room

## Run start: four cardinal doors; south is sealed and leads to the boss.
## Put this script on the room ROOT (not a child node).

@export var door_north: Door
@export var door_east: Door
@export var door_south: Door
@export var door_west: Door
@export var boss_door_area: Area2D
@export_multiline var boss_hint_text: String = "La puerta del jefe está sellada.\nVuelve más tarde."

var _boss_hint_connected: bool = false
var _hint_layer: CanvasLayer
var _hint_label: Label
var _player_in_boss_area: bool = false


func _ready() -> void:
	super._ready()
	_ensure_hint_ui()
	call_deferred("_seal_boss_door")
	call_deferred("_setup_boss_hint")


func on_player_entered(_player: Node2D) -> void:
	_seal_boss_door()
	_setup_boss_hint()


func on_player_exited(_player: Node2D) -> void:
	_player_in_boss_area = false
	_hide_boss_hint()


func _physics_process(_delta: float) -> void:
	if not is_active() or boss_door_area == null or _hint_label == null:
		return
	var inside := _is_player_in_boss_area()
	if inside and not _player_in_boss_area:
		_player_in_boss_area = true
		_seal_boss_door()
		_show_boss_hint()
	elif not inside and _player_in_boss_area:
		_player_in_boss_area = false
		_hide_boss_hint()


func _seal_boss_door() -> void:
	var south := door_south
	if south == null:
		south = _guess_south_door()
	if south != null:
		# Force closed for the player (and enemies).
		south.starts_open = false
		south.set_open(false)


func _setup_boss_hint() -> void:
	if boss_door_area == null:
		boss_door_area = get_node_or_null("BossArea") as Area2D
	if boss_door_area == null:
		return

	# Keep detecting even if the room briefly pauses.
	boss_door_area.process_mode = Node.PROCESS_MODE_ALWAYS
	boss_door_area.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	boss_door_area.collision_layer = 0
	boss_door_area.collision_mask = 1 << 1
	boss_door_area.monitoring = true
	boss_door_area.monitorable = false

	if _boss_hint_connected:
		return
	if not boss_door_area.body_entered.is_connected(_on_boss_area_body_entered):
		boss_door_area.body_entered.connect(_on_boss_area_body_entered)
	if not boss_door_area.body_exited.is_connected(_on_boss_area_body_exited):
		boss_door_area.body_exited.connect(_on_boss_area_body_exited)
	_boss_hint_connected = true


func _on_boss_area_body_entered(body: Node) -> void:
	if body == null or not body.is_in_group("player"):
		return
	_player_in_boss_area = true
	_seal_boss_door()
	_show_boss_hint()


func _on_boss_area_body_exited(body: Node) -> void:
	if body == null or not body.is_in_group("player"):
		return
	_player_in_boss_area = false
	_hide_boss_hint()


func _is_player_in_boss_area() -> bool:
	if boss_door_area == null or not boss_door_area.monitoring:
		return false
	for body in boss_door_area.get_overlapping_bodies():
		if body != null and body.is_in_group("player"):
			return true
	return false


func _ensure_hint_ui() -> void:
	if _hint_layer != null:
		return

	_hint_layer = CanvasLayer.new()
	_hint_layer.name = "BossHintUI"
	_hint_layer.layer = 20
	_hint_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_hint_layer)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_layer.add_child(root)

	_hint_label = Label.new()
	_hint_label.name = "HintLabel"
	_hint_label.visible = false
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.add_theme_font_size_override("font_size", 22)
	_hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hint_label.add_theme_constant_override("outline_size", 6)
	_hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint_label.anchor_left = 0.15
	_hint_label.anchor_right = 0.85
	_hint_label.anchor_top = 0.72
	_hint_label.anchor_bottom = 0.92
	_hint_label.offset_left = 0.0
	_hint_label.offset_right = 0.0
	_hint_label.offset_top = 0.0
	_hint_label.offset_bottom = 0.0
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hint_label)


func _show_boss_hint() -> void:
	_ensure_hint_ui()
	_hint_label.text = boss_hint_text
	_hint_label.visible = true


func _hide_boss_hint() -> void:
	if _hint_label != null:
		_hint_label.visible = false


func _guess_south_door() -> Door:
	var door2 := get_node_or_null("Door2")
	if door2 is Door:
		return door2
	return null
