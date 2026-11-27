extends Control

## Pantalla de inicio: la cámara sube por inicio_titulo_background y luego aparece la UI.

const GAME_SCENE := "res://assets/scenes/game.tscn"
const FONT_PATH := "res://assets/fonts/MagicalNeverlandRegular-JpRZ7.ttf"
const MenuNavGate := preload("res://assets/scripts/hud/menu_nav_gate.gd")

const INTRO_SLIDE_SECONDS := 2.8
const UI_FADE_SECONDS := 0.85
const MENU_LABELS: PackedStringArray = ["Play", "Options", "Exit"]

@export var menu_font_size: int = 26
@export var menu_color: Color = Color(0.96, 0.92, 0.86, 1.0)
@export var logo_max_width_ratio: float = 0.48
@export var colgantes_width_ratio: float = 0.92

@onready var _scroll_bg: TextureRect = $Background/ScrollBackground
@onready var _ui: Control = $UI
@onready var _logo: TextureRect = $UI/Logo
@onready var _brand: TextureRect = $UI/BloomingCobra
@onready var _menu_row: HBoxContainer = $UI/MenuRow
@onready var _selector_left: TextureRect = $UI/SelectorLeft
@onready var _selector_right: TextureRect = $UI/SelectorRight
@onready var _welcome: TextureRect = $"Welcome title/Logoblanco"
@onready var _welcome_text: Label = $"Welcome title/Label"


var _menu_items: Array[Label] = []
var _selected_index: int = 0
var _input_enabled: bool = false
var _intro_done: bool = false
var _menu_font: Font
var _options: Control
var _exit_confirm: Control
var _nav := MenuNavGate.new()



# Voy a intentar que las estrellas bajen con el fondo con un await para que no empiecen hasta que presiones algun botón ("press any button")
# No he sabido


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_font = load(FONT_PATH) as Font
	_setup_menu_labels()
	_setup_options()
	_setup_exit_confirm()
	_ui.modulate.a = 0.0
	_welcome.modulate.a = 0.0
	_welcome_text.modulate.a = 0.0
	_selector_left.visible = false
	_selector_right.visible = false
	resized.connect(_on_resized)
	_on_resized()
	
	
	await _play_intro()
	_input_enabled = true
	_update_selection_visuals()


func _process(delta: float) -> void:
	if not _input_enabled or not is_inside_tree():
		return
	if _is_options_open() or _is_exit_confirm_open():
		return
	_nav.update(delta)
	var step := _nav.poll_step()
	if step.x != 0:
		_move_selection(step.x)


func _unhandled_input(event: InputEvent) -> void:
	if not _input_enabled or not is_inside_tree():
		return

	if _exit_confirm != null and _exit_confirm.has_method("is_open") and bool(_exit_confirm.call("is_open")):
		if _exit_confirm.has_method("handle_input") and bool(_exit_confirm.call("handle_input", event)):
			_mark_input_handled()
		return

	if _options != null and _options.has_method("is_open") and bool(_options.call("is_open")):
		if _options.has_method("handle_input") and bool(_options.call("handle_input", event)):
			_mark_input_handled()
		return

	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_select"):
		_mark_input_handled()
		_activate_selection()
		return


func _mark_input_handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


signal interacted

# detect key pressed activating signal 'interacted'
# interacted is used to wait any key
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		interacted.emit()

# used for dissolve tween
func shader_dissolve(value: float):
	_welcome.material.set_shader_parameter("dissolve", value)

func _play_intro() -> void:
	await get_tree().process_frame
	
	# wait 2 seconds before logo fade in 
	await get_tree().create_timer(1).timeout
	
	_welcome.modulate.a = 1.0
	
	# inverted dissolve for logo fade in
	var fade_welcome := create_tween()
	fade_welcome.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade_welcome.tween_method(shader_dissolve, 1.0, 0.0, 3.0)
	await fade_welcome.finished

	# fade in welcome text: 'Press any key'
	var fade_welcome_text := create_tween()
	fade_welcome_text.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade_welcome_text.tween_property(_welcome_text, "modulate:a", 1.5, 1.0)
	await fade_welcome_text.finished
	
	# wait for any key pressed
	await interacted
	
	# remove welcome text
	#_welcome_text.modulate.a = 0.0
	
	#remove welcome text pero con un fade
	var fadeout_welcome_text := create_tween()
	fadeout_welcome_text.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fadeout_welcome_text.tween_property(_welcome_text, "modulate:a", 0.0, 1.0)
	
	#me ha salío oleee :D
	
	
	_layout_scroll_background(false)

	var start_y := _scroll_start_y()
	var end_y := 0.0
	_scroll_bg.position.y = start_y

	var slide := create_tween()
	slide.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	slide.tween_property(_scroll_bg, "position:y", end_y, INTRO_SLIDE_SECONDS)
	await slide.finished

	_intro_done = true
	_layout_scroll_background(true)

	var fade := create_tween()
	fade.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade.tween_property(_ui, "modulate:a", 1.0, UI_FADE_SECONDS)
	await fade.finished


func _scroll_start_y() -> float:
	# Parte baja del fondo visible al inicio; al llegar a 0 se ve arriba del todo.
	return size.y - _scroll_bg.size.y


func _layout_scroll_background(at_top: bool) -> void:
	var view_size := size
	if view_size.x <= 1.0 or view_size.y <= 1.0:
		view_size = get_viewport_rect().size

	var tex := _scroll_bg.texture
	var aspect := 2.0
	if tex != null:
		var tex_size := tex.get_size()
		if tex_size.x > 0.0:
			aspect = tex_size.y / tex_size.x

	_scroll_bg.anchor_left = 0.0
	_scroll_bg.anchor_top = 0.0
	_scroll_bg.anchor_right = 0.0
	_scroll_bg.anchor_bottom = 0.0
	_scroll_bg.size = Vector2(view_size.x, view_size.x * aspect)
	_scroll_bg.position.x = 0.0
	_scroll_bg.position.y = 0.0 if at_top else _scroll_start_y()


func _setup_menu_labels() -> void:
	for child in _menu_row.get_children():
		child.queue_free()
	_menu_items.clear()

	for i in MENU_LABELS.size():
		var label := Label.new()
		label.text = MENU_LABELS[i]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		if _menu_font != null:
			label.add_theme_font_override("font", _menu_font)
		label.add_theme_font_size_override("font_size", menu_font_size)
		label.add_theme_color_override("font_color", menu_color)
		label.focus_mode = Control.FOCUS_NONE
		var index := i
		label.gui_input.connect(func(event: InputEvent) -> void:
			_on_menu_item_gui_input(index, event)
		)
		label.mouse_entered.connect(func() -> void:
			if _input_enabled and not _is_options_open() and not _is_exit_confirm_open():
				_selected_index = index
				_update_selection_visuals()
		)
		_menu_row.add_child(label)
		_menu_items.append(label)


func _setup_options() -> void:
	var options_script := load("res://assets/scripts/hud/options_overlay.gd") as Script
	_options = Control.new()
	_options.set_script(options_script)
	_options.name = "OptionsOverlay"
	add_child(_options)
	if _options.has_signal("closed"):
		_options.closed.connect(_on_options_closed)


func _setup_exit_confirm() -> void:
	var exit_script := load("res://assets/scripts/hud/exit_confirm_overlay.gd") as Script
	_exit_confirm = Control.new()
	_exit_confirm.set_script(exit_script)
	_exit_confirm.name = "ExitConfirmOverlay"
	add_child(_exit_confirm)
	if _exit_confirm.has_signal("closed"):
		_exit_confirm.closed.connect(_on_exit_confirm_closed)


func _is_options_open() -> bool:
	return _options != null and _options.has_method("is_open") and bool(_options.call("is_open"))


func _is_exit_confirm_open() -> bool:
	return _exit_confirm != null and _exit_confirm.has_method("is_open") and bool(_exit_confirm.call("is_open"))


func _on_menu_item_gui_input(index: int, event: InputEvent) -> void:
	if not _input_enabled or _is_options_open() or _is_exit_confirm_open():
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			_selected_index = index
			_update_selection_visuals()
			_activate_selection()
			accept_event()


func _move_selection(delta: int) -> void:
	if _menu_items.is_empty():
		return
	_selected_index = wrapi(_selected_index + delta, 0, _menu_items.size())
	_update_selection_visuals()


func _activate_selection() -> void:
	match _selected_index:
		0:
			_start_game()
		1:
			_open_options()
		2:
			_open_exit_confirm()


func _start_game() -> void:
	_input_enabled = false
	if RunState != null and RunState.has_method("begin_new_run"):
		RunState.begin_new_run()
	elif RunState != null and RunState.has_method("reset"):
		RunState.reset()
	# Call the autoload directly so the async transition survives change_scene.
	# (Object.call on a freeing menu node can stall the loading overlay.)
	if SceneTransition != null and SceneTransition.has_method("change_to"):
		SceneTransition.change_to(GAME_SCENE)
	else:
		get_tree().change_scene_to_file(GAME_SCENE)


func _open_options() -> void:
	if _options != null and _options.has_method("open"):
		_options.call("open")
	_selector_left.visible = false
	_selector_right.visible = false


func _open_exit_confirm() -> void:
	if _exit_confirm != null and _exit_confirm.has_method("open"):
		_exit_confirm.call("open")
	_selector_left.visible = false
	_selector_right.visible = false


func _on_options_closed() -> void:
	_update_selection_visuals()


func _on_exit_confirm_closed() -> void:
	_update_selection_visuals()


func _update_selection_visuals() -> void:
	if _is_options_open() or _is_exit_confirm_open():
		_selector_left.visible = false
		_selector_right.visible = false
		return

	if _menu_items.is_empty():
		_selector_left.visible = false
		_selector_right.visible = false
		return

	_selector_left.visible = true
	_selector_right.visible = true
	_selector_right.flip_h = true
	call_deferred("_place_selectors")


func _place_selectors() -> void:
	if _is_options_open() or _is_exit_confirm_open() or _menu_items.is_empty() or _selected_index < 0 or _selected_index >= _menu_items.size():
		return

	var selected := _menu_items[_selected_index]
	if not is_instance_valid(selected):
		return

	var item_rect := selected.get_global_rect()
	var selector_size := _selector_left.size
	if selector_size.x <= 1.0:
		selector_size = _selector_left.get_combined_minimum_size()
		if selector_size.x <= 1.0 and _selector_left.texture != null:
			selector_size = _selector_left.texture.get_size()

	var gap := 5.0
	var center_y := item_rect.position.y + item_rect.size.y * 0.5 - selector_size.y * 0.5
	_selector_left.global_position = Vector2(item_rect.position.x - selector_size.x - gap, center_y)
	_selector_right.global_position = Vector2(item_rect.position.x + item_rect.size.x + gap, center_y)


func _on_resized() -> void:
	_layout_scroll_background(_intro_done)
	#_fit_logo()
	#_fit_colgantes()
	#_fit_brand()
	_fit_menu_row()
	_fit_selectors()
	if _input_enabled and not _is_options_open() and not _is_exit_confirm_open():
		_update_selection_visuals()


func _fit_logo() -> void:
	if _logo.texture == null:
		return
	var tex_size := _logo.texture.get_size()
	var target_w := size.x * logo_max_width_ratio
	var scale_factor := target_w / tex_size.x
	var target_h := tex_size.y * scale_factor
	_logo.size = Vector2(target_w, target_h)
	_logo.position = Vector2((size.x - target_w) * 0.5, size.y * 0.12)


#func _fit_colgantes() -> void:
	#if _colgantes.texture == null:
		#return
	#var tex_size := _colgantes.texture.get_size()
	#var target_w := size.x * colgantes_width_ratio
	#var scale_factor := target_w / tex_size.x
	#var target_h := tex_size.y * scale_factor
	#_colgantes.size = Vector2(target_w, target_h)
	#_colgantes.position = Vector2((size.x - target_w) * 0.5, -size.y * 0.02)


func _fit_brand() -> void:
	if _brand.texture == null:
		return
	var tex_size := _brand.texture.get_size()
	var target_w := minf(160.0, size.x * 0.12)
	var scale_factor := target_w / tex_size.x
	var target_h := tex_size.y * scale_factor
	_brand.size = Vector2(target_w, target_h)
	_brand.position = Vector2(size.x - target_w - 28.0, size.y - target_h - 22.0)


func _fit_menu_row() -> void:
	_menu_row.reset_size()
	var row_size := _menu_row.get_combined_minimum_size()
	if row_size.x <= 1.0:
		row_size = Vector2(size.x * 0.55, float(menu_font_size) + 12.0)
	_menu_row.size = row_size
	_menu_row.position = Vector2((size.x - row_size.x) * 0.5, size.y * 0.78)


func _fit_selectors() -> void:
	#var side := maxf(36.0, size.y * 0.045)
	var side := 30.0
	_selector_left.custom_minimum_size = Vector2(side, side)
	_selector_right.custom_minimum_size = Vector2(side, side)
	_selector_left.size = Vector2(side, side)
	_selector_right.size = Vector2(side, side)
