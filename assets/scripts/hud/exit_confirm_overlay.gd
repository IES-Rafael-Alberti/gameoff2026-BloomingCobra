extends Control

## Isaac-style exit confirm: paper note over a dimmed menu.

signal closed
signal confirmed

const FONT_PATH := "res://assets/fonts/MagicalNeverlandRegular-JpRZ7.ttf"
const SELECTOR_PATH := "res://assets/sprittesheets/HUD/definitivo/Seleccionador.png"
const MenuNavGate := preload("res://assets/scripts/hud/menu_nav_gate.gd")

const PROMPT_TEXT := "Are you sure you want me to wake up?"
const OPTIONS: PackedStringArray = ["YES", "NO"]

@export var title_font_size: int = 34
@export var option_font_size: int = 40
@export var text_color: Color = Color(0.96, 0.92, 0.86, 1.0)
@export var dim_color: Color = Color(0.04, 0.03, 0.05, 0.55)
@export var paper_color: Color = Color(0.12, 0.10, 0.14, 1.0)
@export var paper_border_color: Color = Color(0.55, 0.48, 0.40, 0.85)
@export var shadow_color: Color = Color(0.02, 0.01, 0.03, 0.55)

var _open: bool = false
var _index: int = 1 ## Default to NO, like Isaac.
var _menu_font: Font
var _dim: ColorRect
var _shadow: ColorRect
var _panel: PanelContainer
var _title: Label
var _option_labels: Array[Label] = []
var _option_selectors_left: Array[TextureRect] = []
var _option_selectors_right: Array[TextureRect] = []
var _built: bool = false
var _nav := MenuNavGate.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_menu_font = load(FONT_PATH) as Font
	_build_ui()
	resized.connect(_fit_panel)


func is_open() -> bool:
	return _open


func open() -> void:
	_build_ui()
	_open = true
	_index = 1
	_nav.reset()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	call_deferred("_fit_panel")
	_update_visuals()


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

	# Esc stays unbound for web; gamepad B (ui_cancel) acts as NO / close.
	if event.is_action_pressed("ui_cancel") and event is InputEventJoypadButton:
		close()
		return true

	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_select"):
		_activate()
		return true

	return false


func _process(delta: float) -> void:
	if not _open or not visible:
		return
	_nav.update(delta)
	var step := _nav.poll_step()
	if step.y != 0:
		_move_selection(step.y)


func _build_ui() -> void:
	if _built:
		return
	_built = true

	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = dim_color
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(_on_dim_gui_input)
	add_child(_dim)

	_shadow = ColorRect.new()
	_shadow.name = "Shadow"
	_shadow.color = shadow_color
	_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shadow)

	_panel = PanelContainer.new()
	_panel.name = "Paper"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = paper_color
	panel_style.border_color = paper_border_color
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(2)
	panel_style.content_margin_left = 40.0
	panel_style.content_margin_right = 40.0
	panel_style.content_margin_top = 32.0
	panel_style.content_margin_bottom = 32.0
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)

	var root := VBoxContainer.new()
	root.name = "Root"
	root.add_theme_constant_override("separation", 22)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(root)

	_title = Label.new()
	_title.name = "Prompt"
	_title.text = PROMPT_TEXT
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size = Vector2(360.0, 0.0)
	_apply_font(_title, title_font_size)
	root.add_child(_title)

	var options_block := VBoxContainer.new()
	options_block.name = "Options"
	options_block.add_theme_constant_override("separation", 8)
	options_block.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(options_block)

	_option_labels.clear()
	_option_selectors_left.clear()
	_option_selectors_right.clear()
	var selector_tex := load(SELECTOR_PATH) as Texture2D

	for i in OPTIONS.size():
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 4)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		var row_index := i
		row.gui_input.connect(func(event: InputEvent) -> void:
			_on_option_gui_input(row_index, event)
		)
		row.mouse_entered.connect(func() -> void:
			if _open:
				_index = row_index
				_update_visuals()
		)
		options_block.add_child(row)

		var selector_left := _make_selector(selector_tex, false)
		row.add_child(selector_left)
		_option_selectors_left.append(selector_left)

		var label := Label.new()
		label.text = OPTIONS[i]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.custom_minimum_size = Vector2(72.0, 36.0)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_apply_font(label, option_font_size)
		row.add_child(label)
		_option_labels.append(label)

		var selector_right := _make_selector(selector_tex, true)
		row.add_child(selector_right)
		_option_selectors_right.append(selector_right)


func _make_selector(tex: Texture2D, flip: bool) -> TextureRect:
	var selector := TextureRect.new()
	selector.texture = tex
	selector.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	selector.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	selector.custom_minimum_size = Vector2(28.0, 28.0)
	selector.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	selector.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selector.flip_h = flip
	selector.visible = false
	selector.modulate = Color(1, 1, 1, 0) # Keeps row width stable while hidden.
	return selector


func _apply_font(label: Label, point_size: int) -> void:
	if label == null:
		return
	if _menu_font != null:
		label.add_theme_font_override("font", _menu_font)
	label.add_theme_font_size_override("font_size", point_size)
	label.add_theme_color_override("font_color", text_color)
	label.modulate = Color.WHITE


func _fit_panel() -> void:
	if _panel == null:
		return

	var view := size
	if view.x <= 1.0 or view.y <= 1.0:
		view = get_viewport_rect().size

	var panel_w := clampf(view.x * 0.55, 420.0, 620.0)
	_title.custom_minimum_size = Vector2(panel_w - 80.0, 0.0)

	# Measure natural height from content, like Options overlay.
	_panel.size = Vector2(panel_w, 1.0)
	_panel.reset_size()
	var natural := _panel.get_combined_minimum_size()
	var panel_h := maxf(natural.y, 200.0)
	_panel.size = Vector2(panel_w, panel_h)
	_panel.position = Vector2((view.x - panel_w) * 0.5, (view.y - panel_h) * 0.48)

	_shadow.size = _panel.size
	_shadow.position = _panel.position + Vector2(8.0, 10.0)


func _move_selection(delta: int) -> void:
	if OPTIONS.is_empty():
		return
	_index = wrapi(_index + delta, 0, OPTIONS.size())
	_update_visuals()


func _activate() -> void:
	if _index == 0:
		confirmed.emit()
		get_tree().quit()
	else:
		close()


func _update_visuals() -> void:
	for i in _option_labels.size():
		var selected := i == _index
		var color := text_color if selected else Color(text_color.r, text_color.g, text_color.b, 0.5)
		_option_labels[i].add_theme_color_override("font_color", color)
		var sel_mod := Color.WHITE if selected else Color(1, 1, 1, 0)
		if i < _option_selectors_left.size():
			_option_selectors_left[i].modulate = sel_mod
			_option_selectors_left[i].visible = true
		if i < _option_selectors_right.size():
			_option_selectors_right[i].modulate = sel_mod
			_option_selectors_right[i].visible = true


func _on_option_gui_input(index: int, event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			_index = index
			_update_visuals()
			_activate()
			accept_event()


func _on_dim_gui_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			# Clicks on the paper itself are stopped by the panel; dim = cancel.
			close()
			accept_event()
