extends Control

## Shared Volume / Display options. Close only via Back (no Esc — web-safe).

signal closed

const FONT_PATH := "res://assets/fonts/MagicalNeverlandRegular-JpRZ7.ttf"
const OPTIONS_ROWS: PackedStringArray = ["Volume", "Display", "Back"]
const VOLUME_STEP := 0.05

@export var font_size: int = 42
@export var text_color: Color = Color(0.96, 0.92, 0.86, 1.0)
@export var dim_color: Color = Color(0.05, 0.04, 0.06, 0.45)
@export var panel_color: Color = Color(0.12, 0.1, 0.14, 0.78)

var _open: bool = false
var _index: int = 0
var _menu_font: Font
var _dim: ColorRect
var _panel: PanelContainer
var _row_labels: Array[Label] = []
var _value_labels: Array[Label] = []
var _volume_slider: HSlider
var _built: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_menu_font = load(FONT_PATH) as Font
	_build_ui()
	resized.connect(_fit_panel)
	_fit_panel()


func is_open() -> bool:
	return _open


func open() -> void:
	if not _built:
		_build_ui()
	_open = true
	_index = 0
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_refresh_values()
	_update_visuals()
	_fit_panel()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	closed.emit()


func handle_input(event: InputEvent) -> bool:
	if not _open:
		return false

	# Web-safe: never close with Esc / ui_cancel. Use Back only.
	if event.is_action_pressed("ui_up") or event.is_action_pressed("move_up"):
		_move_selection(-1)
		return true
	if event.is_action_pressed("ui_down") or event.is_action_pressed("move_down"):
		_move_selection(1)
		return true
	if event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		_adjust_value(-1)
		return true
	if event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		_adjust_value(1)
		return true
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_select"):
		_activate_selection()
		return true
	return false


func _build_ui() -> void:
	if _built:
		return
	_built = true

	_dim = ColorRect.new()
	_dim.color = dim_color
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(_on_dim_gui_input)
	add_child(_dim)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = panel_color
	panel_style.border_color = Color(text_color, 0.35)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	panel_style.content_margin_left = 36.0
	panel_style.content_margin_right = 36.0
	panel_style.content_margin_top = 28.0
	panel_style.content_margin_bottom = 28.0
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "Options"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(title, font_size + 8)
	vbox.add_child(title)

	_row_labels.clear()
	_value_labels.clear()

	for i in OPTIONS_ROWS.size():
		var row_name := OPTIONS_ROWS[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 24)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		var row_index := i
		row.gui_input.connect(func(event: InputEvent) -> void:
			_on_row_gui_input(row_index, event)
		)
		row.mouse_entered.connect(func() -> void:
			if _open:
				_index = row_index
				_update_visuals()
		)
		vbox.add_child(row)

		var name_label := Label.new()
		name_label.text = row_name
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_apply_font(name_label, font_size)
		row.add_child(name_label)
		_row_labels.append(name_label)

		if row_name == "Volume":
			_volume_slider = HSlider.new()
			_volume_slider.min_value = 0.0
			_volume_slider.max_value = 1.0
			_volume_slider.step = VOLUME_STEP
			_volume_slider.custom_minimum_size = Vector2(220.0, 28.0)
			_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_volume_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_volume_slider.focus_mode = Control.FOCUS_NONE
			_volume_slider.value_changed.connect(_on_volume_slider_changed)
			row.add_child(_volume_slider)

			var value_label := Label.new()
			value_label.custom_minimum_size = Vector2(72.0, 0.0)
			value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_apply_font(value_label, font_size)
			row.add_child(value_label)
			_value_labels.append(value_label)
		elif row_name == "Display":
			var value_label := Label.new()
			value_label.custom_minimum_size = Vector2(220.0, 0.0)
			value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_apply_font(value_label, font_size)
			row.add_child(value_label)
			_value_labels.append(value_label)
		else:
			var spacer := Control.new()
			spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(spacer)
			_value_labels.append(null)


func _apply_font(label: Label, size: int) -> void:
	if _menu_font != null:
		label.add_theme_font_override("font", _menu_font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", text_color)


func _fit_panel() -> void:
	if _panel == null:
		return
	var view := size
	if view.x <= 1.0 or view.y <= 1.0:
		view = get_viewport_rect().size
	var panel_w := clampf(view.x * 0.52, 420.0, 640.0)
	var panel_h := clampf(view.y * 0.42, 260.0, 360.0)
	_panel.size = Vector2(panel_w, panel_h)
	_panel.position = Vector2((view.x - panel_w) * 0.5, (view.y - panel_h) * 0.5)


func _on_dim_gui_input(event: InputEvent) -> void:
	# Dim clicks do not close — Back only (web-safe, no Esc shortcut).
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed:
			accept_event()


func _on_row_gui_input(index: int, event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			_index = index
			_update_visuals()
			_activate_selection()
			accept_event()


func _move_selection(delta: int) -> void:
	_index = wrapi(_index + delta, 0, OPTIONS_ROWS.size())
	_update_visuals()


func _activate_selection() -> void:
	match OPTIONS_ROWS[_index]:
		"Display":
			_adjust_value(1)
		"Back":
			close()
		_:
			pass


func _adjust_value(direction: int) -> void:
	match OPTIONS_ROWS[_index]:
		"Volume":
			if GameSettings != null:
				GameSettings.adjust_master_volume(float(direction) * VOLUME_STEP)
			_refresh_values()
		"Display":
			if GameSettings != null:
				GameSettings.cycle_display_mode(direction)
			_refresh_values()
		_:
			pass


func _on_volume_slider_changed(value: float) -> void:
	if not _open:
		return
	if GameSettings != null:
		GameSettings.set_master_volume(value)
	_refresh_values(false)


func _refresh_values(sync_slider: bool = true) -> void:
	if GameSettings == null:
		return
	if _volume_slider != null and sync_slider:
		_volume_slider.set_value_no_signal(GameSettings.master_volume)
	if _value_labels.size() >= 1 and _value_labels[0] != null:
		_value_labels[0].text = "%d%%" % int(round(GameSettings.master_volume * 100.0))
	if _value_labels.size() >= 2 and _value_labels[1] != null:
		_value_labels[1].text = GameSettings.display_mode_label()


func _update_visuals() -> void:
	for i in _row_labels.size():
		var selected := i == _index
		var color := text_color if selected else Color(text_color, 0.55)
		_row_labels[i].add_theme_color_override("font_color", color)
		if i < _value_labels.size() and _value_labels[i] != null:
			_value_labels[i].add_theme_color_override("font_color", color)
