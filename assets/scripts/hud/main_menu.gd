extends Control

## Pantalla de inicio: la cámara sube por inicio_titulo_background y luego aparece la UI.

const GAME_SCENE := "res://assets/scenes/game.tscn"
const FONT_PATH := "res://assets/fonts/MagicalNeverlandRegular-JpRZ7.ttf"

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
@onready var _colgantes: Node = $UI/Colgantes
@onready var _brand: TextureRect = $UI/BloomingCobra
@onready var _menu_row: HBoxContainer = $UI/MenuRow
@onready var _selector_left: TextureRect = $UI/SelectorLeft
@onready var _selector_right: TextureRect = $UI/SelectorRight
@onready var _welcome: TextureRect = $"Welcome title/Logo"
@onready var _welcome_text: Label = $"Welcome title/Label"

var _menu_items: Array[Label] = []
var _selected_index: int = 0
var _input_enabled: bool = false
var _intro_done: bool = false
var _menu_font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_font = load(FONT_PATH) as Font
	_setup_menu_labels()
	_ui.modulate.a = 0.0
	_welcome.modulate.a = 0.0
	_welcome_text.modulate.a = 0.0
	_selector_left.visible = false
	_selector_right.visible = false
	resized.connect(_on_resized)
	_on_resized()
	
	# 
	await _play_intro()
	_input_enabled = true
	_update_selection_visuals()


func _unhandled_input(event: InputEvent) -> void:
	if not _input_enabled or not is_inside_tree():
		return

	if event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		_mark_input_handled()
		_move_selection(-1)
		return
	if event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		_mark_input_handled()
		_move_selection(1)
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

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
	#if event.is_action_pressed("attack"):
		interacted.emit()

func _play_intro() -> void:
	await get_tree().process_frame
	
	await get_tree().create_timer(2).timeout
	
	#await get_tree().create_timer(5).timeout
	var fade_welcome := create_tween()
	fade_welcome.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade_welcome.tween_property(_welcome, "modulate:a", 1.0, 5.0)
	await fade_welcome.finished

	var fade_welcome_text := create_tween()
	fade_welcome_text.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade_welcome_text.tween_property(_welcome_text, "modulate:a", 1.0, 0.5)
	await fade_welcome_text.finished
	
	# wait for key pressed
	await interacted
	
	_welcome_text.modulate.a = 0.0
	
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
			if _input_enabled:
				_selected_index = index
				_update_selection_visuals()
		)
		_menu_row.add_child(label)
		_menu_items.append(label)


func _on_menu_item_gui_input(index: int, event: InputEvent) -> void:
	if not _input_enabled:
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
			get_tree().quit()


func _start_game() -> void:
	_input_enabled = false
	get_tree().change_scene_to_file(GAME_SCENE)


func _open_options() -> void:
	pass


func _update_selection_visuals() -> void:
	if _menu_items.is_empty():
		_selector_left.visible = false
		_selector_right.visible = false
		return

	_selector_left.visible = true
	_selector_right.visible = true
	_selector_right.flip_h = true
	call_deferred("_place_selectors")


func _place_selectors() -> void:
	if _menu_items.is_empty() or _selected_index < 0 or _selected_index >= _menu_items.size():
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

	var gap := 18.0
	var center_y := item_rect.position.y + item_rect.size.y * 0.5 - selector_size.y * 0.5
	_selector_left.global_position = Vector2(item_rect.position.x - selector_size.x - gap, center_y)
	_selector_right.global_position = Vector2(item_rect.position.x + item_rect.size.x + gap, center_y)


func _on_resized() -> void:
	_layout_scroll_background(_intro_done)
	#_fit_logo()
	#_fit_colgantes()
	_fit_brand()
	_fit_menu_row()
	_fit_selectors()
	if _input_enabled:
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
	var side := maxf(36.0, size.y * 0.045)
	_selector_left.custom_minimum_size = Vector2(side, side)
	_selector_right.custom_minimum_size = Vector2(side, side)
	_selector_left.size = Vector2(side, side)
	_selector_right.size = Vector2(side, side)
