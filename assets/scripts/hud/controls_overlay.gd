extends Control

## Rebind gameplay inputs. Auto-switches keyboard / gamepad labels from last device used.

signal closed

const FONT_PATH := "res://assets/fonts/MagicalNeverlandRegular-JpRZ7.ttf"
const MenuNavGate := preload("res://assets/scripts/hud/menu_nav_gate.gd")

@export var font_size: int = 26
@export var text_color: Color = Color(0.96, 0.92, 0.86, 1.0)
@export var dim_color: Color = Color(0.04, 0.03, 0.05, 0.72)
@export var panel_color: Color = Color(0.10, 0.08, 0.12, 0.94)

var _open: bool = false
var _index: int = 0
var _listening: bool = false
var _gamepad_scheme: bool = false
var _menu_font: Font
var _dim: ColorRect
var _panel: PanelContainer
var _scroll: ScrollContainer
var _list: VBoxContainer
var _title: Label
var _scheme_label: Label
var _hint_label: Label
var _row_labels: Array[Label] = []
var _value_labels: Array[Label] = []
var _row_controls: Array[Control] = []
var _built: bool = false
var _nav := MenuNavGate.new()
var _rows: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_menu_font = load(FONT_PATH) as Font
	_build_rows()
	_build_ui()
	resized.connect(_fit_panel)
	_fit_panel()


func is_open() -> bool:
	return _open


func open() -> void:
	if not _built:
		_build_ui()
	_open = true
	_listening = false
	_index = 0
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_nav.reset()
	_detect_initial_scheme()
	_refresh_values()
	_update_visuals()
	_fit_panel()


func close() -> void:
	if not _open:
		return
	_open = false
	_listening = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nav.reset()
	closed.emit()


func _build_rows() -> void:
	_rows.clear()
	if GameSettings != null:
		for entry in GameSettings.REMAPPABLE_ACTIONS:
			_rows.append(entry)
	_rows.append({&"action": &"", &"label": "Back"})


func _process(delta: float) -> void:
	if not _open or _listening:
		return
	_nav.update(delta)
	var step := _nav.poll_step()
	if step.y != 0:
		_move_selection(step.y)


func _input(event: InputEvent) -> void:
	if not _open:
		return
	_update_scheme_from_event(event)

	if _listening:
		if _try_capture(event):
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_cancel") and event is InputEventJoypadButton:
		close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_select"):
		_activate_selection()
		get_viewport().set_input_as_handled()


func handle_input(_event: InputEvent) -> bool:
	# Logic runs in _input; this only tells Options to treat the event as consumed.
	return _open


func _detect_initial_scheme() -> void:
	_gamepad_scheme = not Input.get_connected_joypads().is_empty()
	# Prefer keyboard if no pad activity yet this session and pads aren't the only hint.
	for pad in Input.get_connected_joypads():
		if Input.is_joy_known(pad):
			_gamepad_scheme = true
			break


func _update_scheme_from_event(event: InputEvent) -> void:
	if GameSettings == null:
		return
	var changed := false
	if GameSettings.is_gamepad_event(event):
		if event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) < 0.55:
			return
		if not _gamepad_scheme:
			_gamepad_scheme = true
			changed = true
	elif GameSettings.is_keyboard_event(event) and event.is_pressed():
		if _gamepad_scheme:
			_gamepad_scheme = false
			changed = true
	if changed and not _listening:
		_refresh_values()
		_update_scheme_label()


func _try_capture(event: InputEvent) -> bool:
	if GameSettings == null:
		_listening = false
		_refresh_values()
		return true

	# Cancel listen with B / ui_cancel (pad) without binding it.
	if event.is_action_pressed("ui_cancel") and event is InputEventJoypadButton:
		_listening = false
		_refresh_values()
		_update_visuals()
		return true

	var usable: InputEvent = null
	if event is InputEventKey and event.pressed and not event.echo:
		usable = event
	elif event is InputEventMouseButton and event.pressed:
		usable = event
	elif event is InputEventJoypadButton and event.pressed:
		usable = event
	elif event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if absf(motion.axis_value) >= 0.6:
			var captured := InputEventJoypadMotion.new()
			captured.axis = motion.axis
			captured.axis_value = 1.0 if motion.axis_value > 0.0 else -1.0
			usable = captured

	if usable == null:
		return false
	if _gamepad_scheme and not GameSettings.is_gamepad_event(usable):
		return true
	if not _gamepad_scheme and not GameSettings.is_keyboard_event(usable):
		return true

	var action: StringName = _rows[_index][&"action"]
	if action == &"":
		_listening = false
		return true
	GameSettings.rebind_action(action, usable, _gamepad_scheme)
	_listening = false
	_refresh_values()
	_update_visuals()
	return true


func _build_ui() -> void:
	if _built:
		return
	_built = true

	_dim = ColorRect.new()
	_dim.color = dim_color
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.clip_contents = true
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = panel_color
	panel_style.border_color = Color(text_color, 0.35)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	panel_style.content_margin_left = 20.0
	panel_style.content_margin_right = 20.0
	panel_style.content_margin_top = 16.0
	panel_style.content_margin_bottom = 16.0
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(root)

	_title = Label.new()
	_title.text = "Controls"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(_title, font_size + 6)
	root.add_child(_title)

	_scheme_label = Label.new()
	_scheme_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(_scheme_label, font_size - 4)
	root.add_child(_scheme_label)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	root.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)

	_row_labels.clear()
	_value_labels.clear()
	_row_controls.clear()
	for i in _rows.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		var row_index := i
		row.gui_input.connect(func(event: InputEvent) -> void:
			_on_row_gui_input(row_index, event)
		)
		row.mouse_entered.connect(func() -> void:
			if _open and not _listening:
				_index = row_index
				_update_visuals()
		)
		_list.add_child(row)
		_row_controls.append(row)

		var name_label := Label.new()
		name_label.text = str(_rows[i][&"label"])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_apply_font(name_label, font_size)
		row.add_child(name_label)
		_row_labels.append(name_label)

		var value_label := Label.new()
		value_label.custom_minimum_size = Vector2(160.0, 0.0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_apply_font(value_label, font_size)
		row.add_child(value_label)
		_value_labels.append(value_label)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_apply_font(_hint_label, maxi(font_size - 8, 16))
	root.add_child(_hint_label)


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
	var margin := 24.0
	var panel_w := minf(view.x - margin * 2.0, 560.0)
	var panel_h := minf(view.y - margin * 2.0, view.y * 0.88)
	panel_w = maxf(panel_w, 320.0)
	panel_h = maxf(panel_h, 280.0)
	_panel.size = Vector2(panel_w, panel_h)
	_panel.position = Vector2((view.x - panel_w) * 0.5, (view.y - panel_h) * 0.5)
	_ensure_selection_visible()


func _on_row_gui_input(index: int, event: InputEvent) -> void:
	if not _open or _listening:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			_index = index
			_update_visuals()
			_activate_selection()
			accept_event()


func _move_selection(delta: int) -> void:
	if _rows.is_empty():
		return
	_index = wrapi(_index + delta, 0, _rows.size())
	_update_visuals()
	_ensure_selection_visible()


func _ensure_selection_visible() -> void:
	call_deferred("_ensure_selection_visible_deferred")


func _ensure_selection_visible_deferred() -> void:
	if _scroll == null or _index < 0 or _index >= _row_controls.size():
		return
	var row := _row_controls[_index]
	if row == null or not is_instance_valid(row):
		return
	_scroll.ensure_control_visible(row)


func _activate_selection() -> void:
	if _rows.is_empty():
		return
	var action: StringName = _rows[_index][&"action"]
	if action == &"":
		close()
		return
	_listening = true
	_refresh_values()
	_update_visuals()


func _refresh_values() -> void:
	_update_scheme_label()
	if _hint_label != null:
		if _listening:
			_hint_label.text = "Press a new %s binding… (B to cancel)" % ("gamepad" if _gamepad_scheme else "keyboard/mouse")
		else:
			_hint_label.text = "Confirm to rebind. Device view switches automatically."
	for i in _rows.size():
		if i >= _value_labels.size() or _value_labels[i] == null:
			continue
		var action: StringName = _rows[i][&"action"]
		if action == &"":
			_value_labels[i].text = ""
		elif _listening and i == _index:
			_value_labels[i].text = "…"
		elif GameSettings != null:
			_value_labels[i].text = GameSettings.binding_label(action, _gamepad_scheme)
		else:
			_value_labels[i].text = "—"


func _update_scheme_label() -> void:
	if _scheme_label == null:
		return
	_scheme_label.text = "Showing: Gamepad" if _gamepad_scheme else "Showing: Keyboard / Mouse"


func _update_visuals() -> void:
	for i in _row_labels.size():
		var selected := i == _index
		var color := text_color if selected else Color(text_color, 0.55)
		if _listening and selected:
			color = Color(1.0, 0.85, 0.45, 1.0)
		_row_labels[i].add_theme_color_override("font_color", color)
		if i < _value_labels.size() and _value_labels[i] != null:
			_value_labels[i].add_theme_color_override("font_color", color)
