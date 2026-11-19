extends CanvasLayer

## In-game pause (E). Transparent overlay: Resume / Options / Main Menu.
## Web-safe: never uses Esc. Options closes only via Back.

const MAIN_MENU_SCENE := "res://assets/scenes/HUD/main_menu.tscn"
const FONT_PATH := "res://assets/fonts/MagicalNeverlandRegular-JpRZ7.ttf"
const MENU_LABELS: PackedStringArray = ["Resume", "Options", "Main Menu"]

@export var menu_font_size: int = 48
@export var menu_color: Color = Color(0.96, 0.92, 0.86, 1.0)
@export var dim_color: Color = Color(0.04, 0.03, 0.05, 0.32)

var _open: bool = false
var _selected_index: int = 0
var _menu_font: Font
var _root: Control
var _dim: ColorRect
var _menu_column: VBoxContainer
var _menu_items: Array[Label] = []
var _options: Control


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_menu_font = load(FONT_PATH) as Font
	_build_ui()
	visible = false
	_open = false


func is_open() -> bool:
	return _open


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_pause") and not event.is_echo():
		if _options != null and _options.has_method("is_open") and bool(_options.call("is_open")):
			# While options are open, E does nothing (Back only).
			_mark_input_handled()
			return
		_set_open(not _open)
		_mark_input_handled()
		return

	if not _open:
		return

	if _options != null and _options.has_method("is_open") and bool(_options.call("is_open")):
		if _options.has_method("handle_input") and bool(_options.call("handle_input", event)):
			_mark_input_handled()
		return

	if event.is_action_pressed("ui_up") or event.is_action_pressed("move_up"):
		_move_selection(-1)
		_mark_input_handled()
		return
	if event.is_action_pressed("ui_down") or event.is_action_pressed("move_down"):
		_move_selection(1)
		_mark_input_handled()
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_select"):
		_activate_selection()
		_mark_input_handled()
		return


func _mark_input_handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = dim_color
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_dim)

	_menu_column = VBoxContainer.new()
	_menu_column.name = "MenuColumn"
	_menu_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu_column.add_theme_constant_override("separation", 18)
	_menu_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_menu_column)

	_menu_items.clear()
	for i in MENU_LABELS.size():
		var label := Label.new()
		label.text = MENU_LABELS[i]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		if _menu_font != null:
			label.add_theme_font_override("font", _menu_font)
		label.add_theme_font_size_override("font_size", menu_font_size)
		label.add_theme_color_override("font_color", menu_color)
		var index := i
		label.gui_input.connect(func(event: InputEvent) -> void:
			_on_item_gui_input(index, event)
		)
		label.mouse_entered.connect(func() -> void:
			if _open and (_options == null or not bool(_options.call("is_open"))):
				_selected_index = index
				_update_selection_visuals()
		)
		_menu_column.add_child(label)
		_menu_items.append(label)

	var options_script := load("res://assets/scripts/hud/options_overlay.gd") as Script
	_options = Control.new()
	_options.set_script(options_script)
	_options.name = "OptionsOverlay"
	_root.add_child(_options)
	if _options.has_signal("closed"):
		_options.closed.connect(_on_options_closed)

	_root.resized.connect(_fit_menu)
	call_deferred("_fit_menu")


func _fit_menu() -> void:
	if _menu_column == null or _root == null:
		return
	var view := _root.size
	if view.x <= 1.0 or view.y <= 1.0:
		view = get_viewport().get_visible_rect().size
	_menu_column.reset_size()
	var col_size := _menu_column.get_combined_minimum_size()
	if col_size.x <= 1.0:
		col_size = Vector2(view.x * 0.4, float(menu_font_size + 12) * MENU_LABELS.size())
	_menu_column.size = col_size
	_menu_column.position = Vector2((view.x - col_size.x) * 0.5, (view.y - col_size.y) * 0.5)


func _set_open(open: bool) -> void:
	if open == _open:
		return
	_open = open
	visible = open

	if open:
		_close_map_if_open()
		_selected_index = 0
		if _options != null and _options.has_method("is_open") and bool(_options.call("is_open")):
			_options.call("close")
		_update_selection_visuals()
		_fit_menu()
		get_tree().paused = true
	else:
		if _options != null and _options.has_method("is_open") and bool(_options.call("is_open")):
			_options.call("close")
		get_tree().paused = false


func _close_map_if_open() -> void:
	var map := get_tree().get_first_node_in_group("map_overlay")
	if map == null:
		var game := get_tree().current_scene
		if game != null:
			map = game.get_node_or_null("MapOverlay")
	if map != null and map.has_method("close_overlay"):
		map.call("close_overlay")
	elif map != null:
		map.visible = false


func _move_selection(delta: int) -> void:
	if _menu_items.is_empty():
		return
	_selected_index = wrapi(_selected_index + delta, 0, _menu_items.size())
	_update_selection_visuals()


func _activate_selection() -> void:
	match _selected_index:
		0:
			_set_open(false)
		1:
			_open_options()
		2:
			_go_main_menu()


func _open_options() -> void:
	if _options != null and _options.has_method("open"):
		_options.call("open")
	_update_selection_visuals()


func _on_options_closed() -> void:
	_update_selection_visuals()


func _go_main_menu() -> void:
	get_tree().paused = false
	_open = false
	visible = false
	if RunState != null and RunState.has_method("reset"):
		RunState.reset()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _on_item_gui_input(index: int, event: InputEvent) -> void:
	if not _open:
		return
	if _options != null and _options.has_method("is_open") and bool(_options.call("is_open")):
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			_selected_index = index
			_update_selection_visuals()
			_activate_selection()
			_mark_input_handled()


func _update_selection_visuals() -> void:
	var options_open := _options != null and _options.has_method("is_open") and bool(_options.call("is_open"))
	for i in _menu_items.size():
		var selected := (not options_open) and i == _selected_index
		var color := menu_color if selected else Color(menu_color, 0.45)
		_menu_items[i].add_theme_color_override("font_color", color)
		_menu_items[i].visible = not options_open
	if _menu_column != null:
		_menu_column.visible = not options_open
