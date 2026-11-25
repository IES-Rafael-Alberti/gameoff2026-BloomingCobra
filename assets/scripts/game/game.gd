extends Node2D

## 1 = fondo pegado a la cámara (sin parallax). Valores más bajos = se mueve más lento.
@export_range(0.0, 1.0, 0.01) var background_parallax: float = 0.85
## Escala mínima del arte 3840x2160 (vista jugable con zoom 4).
@export var background_base_scale: float = 0.12
## Multiplicador sobre el viewport: deja margen para parallax antes de clampear.
@export_range(1.0, 2.0, 0.01) var background_cover_margin: float = 1.2
## Seconds before the player can shift again after a successful switch.
@export_range(0.0, 10.0, 0.05) var shift_cooldown: float = 1.5

const BOSS_ROOM_SCENE := "res://assets/scenes/rooms/boss/bossRoom.tscn"
const ROOMS_DIR := "res://assets/scenes/rooms/"
## Colores de borde del arte, para no ver el clear gris de Godot si algo se escapa.
const _BG_CLEAR_PESADILLA := Color(0.0, 0.04, 0.16)
const _BG_CLEAR_SUENO := Color(0.02, 0.04, 0.45)

var _hitbox_debug: Node2D
var _bg_pesadilla: Sprite2D
var _bg_sueno: Sprite2D
var _player: Node2D
var _bg_anchor: Vector2 = Vector2.ZERO
var _bg_anchor_ready: bool = false
var _debug_room_panel: VBoxContainer = null
var _debug_room_menu_open: bool = false

@onready var sfx_general: Node = get_node_or_null("SfxGeneral")
@onready var room_manager: Node = get_node_or_null("RoomManager")


func _ready() -> void:
	_hitbox_debug = Node2D.new()
	_hitbox_debug.name = "HitboxDebug"
	_hitbox_debug.set_script(load("res://assets/scripts/game/hitbox_debug.gd"))
	add_child(_hitbox_debug)
	_setup_debug_room_ui()
	_setup_world_backgrounds()
	_sync_shift_cooldown()
	if room_manager != null and room_manager.has_signal("room_changed"):
		if not room_manager.room_changed.is_connected(_on_room_changed_backgrounds):
			room_manager.room_changed.connect(_on_room_changed_backgrounds)
	set_process(true)


func _process(_delta: float) -> void:
	_sync_shift_cooldown()
	# Triggers are axes: poll just_pressed here (event.is_action_pressed is unreliable).
	if Input.is_action_just_pressed("switch"):
		if WorldMode.toggle():
			if sfx_general != null and sfx_general.has_method("play_switch"):
				sfx_general.call("play_switch")

	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	if _player == null:
		return
	_update_backgrounds(_background_follow_target())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen") and not event.is_echo():
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("debug_hitboxes") and not event.is_echo():
		if _hitbox_debug != null and _hitbox_debug.has_method("toggle"):
			var on: bool = _hitbox_debug.toggle()
			print("[Debug] Hitboxes visible: ", on)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("debug_god_mode") and not event.is_echo():
		var player := get_tree().get_first_node_in_group("player")
		var vit: Node = null
		if player != null:
			vit = player.get_node_or_null("Vitality")
		if vit != null and vit.has_method("toggle_invulnerable"):
			var on: bool = bool(vit.call("toggle_invulnerable"))
			print("[Debug] God mode (no vitality loss): ", on)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("debug_boss_room") and not event.is_echo():
		_debug_teleport_to_boss()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_F4:
			_toggle_debug_room_menu()
			get_viewport().set_input_as_handled()
			return
		if key.keycode == KEY_F5:
			_debug_toggle_reveal_map()
			get_viewport().set_input_as_handled()
			return


func _debug_toggle_reveal_map() -> void:
	var map := get_tree().get_first_node_in_group("map_overlay")
	if map == null:
		return
	var enabled := false
	if map.has_method("toggle_debug_reveal_all"):
		enabled = bool(map.call("toggle_debug_reveal_all"))
	elif map.has_method("set_debug_reveal_all"):
		enabled = not bool(map.get("debug_reveal_all"))
		map.call("set_debug_reveal_all", enabled)
	# Open the map so the reveal is visible immediately.
	if enabled and map.has_method("open_overlay"):
		map.call("open_overlay")
	elif enabled and map.has_method("refresh"):
		map.call("refresh")


func _setup_debug_room_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DebugUI"
	layer.layer = 100
	add_child(layer)

	var boss_button := Button.new()
	boss_button.name = "DebugBossTeleport"
	boss_button.text = "Boss Room (F3)"
	boss_button.position = Vector2(12, 12)
	boss_button.custom_minimum_size = Vector2(140, 28)
	boss_button.focus_mode = Control.FOCUS_NONE
	boss_button.pressed.connect(_debug_teleport_to_boss)
	layer.add_child(boss_button)

	var rooms_button := Button.new()
	rooms_button.name = "DebugRoomsMenu"
	rooms_button.text = "Rooms (F4)"
	rooms_button.position = Vector2(160, 12)
	rooms_button.custom_minimum_size = Vector2(120, 28)
	rooms_button.focus_mode = Control.FOCUS_NONE
	rooms_button.pressed.connect(_toggle_debug_room_menu)
	layer.add_child(rooms_button)

	var map_button := Button.new()
	map_button.name = "DebugRevealMap"
	map_button.text = "Reveal Map (F5)"
	map_button.position = Vector2(288, 12)
	map_button.custom_minimum_size = Vector2(140, 28)
	map_button.focus_mode = Control.FOCUS_NONE
	map_button.pressed.connect(_debug_toggle_reveal_map)
	layer.add_child(map_button)

	_debug_room_panel = VBoxContainer.new()
	_debug_room_panel.name = "DebugRoomList"
	_debug_room_panel.position = Vector2(12, 48)
	_debug_room_panel.visible = false
	_debug_room_panel.add_theme_constant_override("separation", 2)
	layer.add_child(_debug_room_panel)
	_rebuild_debug_room_list()


func _toggle_debug_room_menu() -> void:
	_debug_room_menu_open = not _debug_room_menu_open
	if _debug_room_panel != null:
		if _debug_room_menu_open:
			_rebuild_debug_room_list()
		_debug_room_panel.visible = _debug_room_menu_open


func _rebuild_debug_room_list() -> void:
	if _debug_room_panel == null:
		return
	for child in _debug_room_panel.get_children():
		child.queue_free()
	var rooms := _list_room_scenes()
	for path in rooms:
		var button := Button.new()
		button.text = path.get_file().get_basename()
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(220, 24)
		button.pressed.connect(_debug_go_to_room.bind(path))
		_debug_room_panel.add_child(button)


func _list_room_scenes() -> PackedStringArray:
	var result: PackedStringArray = []
	_collect_room_scenes(ROOMS_DIR, result)
	result.sort()
	return result


func _collect_room_scenes(path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			if file_name != "." and file_name != ".." and not file_name.begins_with("."):
				_collect_room_scenes(path.path_join(file_name), out)
		elif file_name.ends_with(".tscn") and not file_name.ends_with(".tscn.tscn"):
			if file_name != "habitacion_enemy_test.tscn":
				out.append(path.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()


func _debug_go_to_room(scene_path: String) -> void:
	if room_manager != null and room_manager.has_method("go_to"):
		room_manager.call("go_to", scene_path, &"")
		print("[Debug] go_to ", scene_path)
	_debug_room_menu_open = false
	if _debug_room_panel != null:
		_debug_room_panel.visible = false



func _debug_teleport_to_boss() -> void:
	_debug_go_to_room(BOSS_ROOM_SCENE)


func _sync_shift_cooldown() -> void:
	if WorldMode != null and WorldMode.has_method("set_switch_cooldown"):
		WorldMode.set_switch_cooldown(shift_cooldown)


func _toggle_fullscreen() -> void:
	if GameSettings != null and GameSettings.has_method("toggle_fullscreen_shortcut"):
		GameSettings.toggle_fullscreen_shortcut()
		return
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _setup_world_backgrounds() -> void:
	var root := get_node_or_null("WorldBackgrounds") as Node2D
	if root == null:
		root = Node2D.new()
		root.name = "WorldBackgrounds"
		root.z_index = -100
		add_child(root)
		move_child(root, 0)

	_bg_pesadilla = root.get_node_or_null("BackgroundPesadilla") as Sprite2D
	_bg_sueno = root.get_node_or_null("BackgroundSueño") as Sprite2D

	if _bg_pesadilla == null:
		_bg_pesadilla = _make_bg_sprite(
			"BackgroundPesadilla",
			preload("res://assets/scenary/fondopedasilla.png")
		)
		root.add_child(_bg_pesadilla)
	if _bg_sueno == null:
		_bg_sueno = _make_bg_sprite(
			"BackgroundSueño",
			preload("res://assets/scenary/fondopevigilia.png")
		)
		root.add_child(_bg_sueno)

	if not WorldMode.mode_changed.is_connected(_on_world_mode_changed_backgrounds):
		WorldMode.mode_changed.connect(_on_world_mode_changed_backgrounds)
	_on_world_mode_changed_backgrounds(WorldMode.get_mode())


func _make_bg_sprite(node_name: String, texture: Texture2D) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.texture = texture
	sprite.z_index = -100
	sprite.centered = true
	# 3840x2160 art; scale real se ajusta en _fit_backgrounds_to_view.
	sprite.scale = Vector2(background_base_scale, background_base_scale)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	return sprite


func _on_world_mode_changed_backgrounds(mode: int) -> void:
	if _bg_pesadilla != null:
		_bg_pesadilla.visible = mode == WorldMode.MODE_PESADILLA
	if _bg_sueno != null:
		_bg_sueno.visible = mode == WorldMode.MODE_SUENO
	_apply_background_clear_color(mode)
	_recenter_backgrounds(_background_follow_target())


func _apply_background_clear_color(mode: int) -> void:
	var clear := _BG_CLEAR_PESADILLA if mode == WorldMode.MODE_PESADILLA else _BG_CLEAR_SUENO
	RenderingServer.set_default_clear_color(clear)


func _background_follow_target() -> Vector2:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	if _player == null:
		return Vector2.ZERO
	var cam := _player.get_node_or_null("Camera2D") as Camera2D
	if cam != null and cam.is_current():
		return cam.get_screen_center_position()
	return _player.global_position


func _active_camera() -> Camera2D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	if _player == null:
		return null
	var cam := _player.get_node_or_null("Camera2D") as Camera2D
	if cam != null and cam.is_current():
		return cam
	return null


func _half_view_extents(cam: Camera2D) -> Vector2:
	if cam == null:
		return get_viewport_rect().size * 0.5
	return cam.get_viewport_rect().size * 0.5 / cam.zoom.abs()


func _fit_backgrounds_to_view(half_view: Vector2) -> void:
	var needed := half_view * maxf(background_cover_margin, 1.0)
	for sprite in [_bg_pesadilla, _bg_sueno]:
		if sprite == null or sprite.texture == null:
			continue
		var tex_size: Vector2 = sprite.texture.get_size()
		if tex_size.x <= 0.0 or tex_size.y <= 0.0:
			continue
		var cover: float = maxf(needed.x / (tex_size.x * 0.5), needed.y / (tex_size.y * 0.5))
		var s: float = maxf(background_base_scale, cover)
		sprite.scale = Vector2(s, s)


func _bg_half_extents(sprite: Sprite2D) -> Vector2:
	if sprite == null or sprite.texture == null:
		return Vector2.ZERO
	var tex_size: Vector2 = sprite.texture.get_size()
	return tex_size * sprite.scale.abs() * 0.5


func _parallax_background_position(camera_pos: Vector2) -> Vector2:
	if not _bg_anchor_ready:
		_bg_anchor = camera_pos
		_bg_anchor_ready = true
	# 1 = sigue a la cámara; <1 = se desplaza menos (parallax).
	return _bg_anchor.lerp(camera_pos, clampf(background_parallax, 0.0, 1.0))


## Evita que el borde del sprite entre en pantalla (salas anchas / viewport grande).
func _clamp_background_to_view(bg_pos: Vector2, camera_pos: Vector2, half_view: Vector2, half_bg: Vector2) -> Vector2:
	var slack := half_bg - half_view
	if slack.x < 0.0 or slack.y < 0.0:
		return camera_pos
	return Vector2(
		clampf(bg_pos.x, camera_pos.x - slack.x, camera_pos.x + slack.x),
		clampf(bg_pos.y, camera_pos.y - slack.y, camera_pos.y + slack.y)
	)


func _place_backgrounds(pos: Vector2) -> void:
	if _bg_pesadilla != null:
		_bg_pesadilla.global_position = pos
	if _bg_sueno != null:
		_bg_sueno.global_position = pos


func _update_backgrounds(camera_pos: Vector2) -> void:
	var cam := _active_camera()
	var half_view := _half_view_extents(cam)
	_fit_backgrounds_to_view(half_view)
	var desired := _parallax_background_position(camera_pos)
	var half_bg := _bg_half_extents(_bg_pesadilla if _bg_pesadilla != null and _bg_pesadilla.visible else _bg_sueno)
	_place_backgrounds(_clamp_background_to_view(desired, camera_pos, half_view, half_bg))


func _recenter_backgrounds(pos: Vector2) -> void:
	_bg_anchor = pos
	_bg_anchor_ready = true
	var cam := _active_camera()
	var half_view := _half_view_extents(cam)
	_fit_backgrounds_to_view(half_view)
	_place_backgrounds(pos)


func _on_room_changed_backgrounds(_previous: Room, _next: Room) -> void:
	_recenter_backgrounds(_background_follow_target())
