extends CanvasLayer

## Fade + loading overlay for scene changes (Play → game, etc.).

const FONT_PATH := "res://assets/fonts/MagicalNeverlandRegular-JpRZ7.ttf"
const FADE_SECONDS := 0.4
const MIN_LOADING_SECONDS := 0.55
const LOADING_BASE := "Loading"
const OVERLAY_COLOR := Color(0.02, 0.02, 0.05, 1.0)
const TEXT_COLOR := Color(0.96, 0.92, 0.86, 1.0)

var _busy: bool = false
var _overlay: ColorRect
var _label: Label
var _dot_index: int = 0
var _dot_accum: float = 0.0


func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false
	set_process(false)


func is_busy() -> bool:
	return _busy


func change_to(scene_path: String) -> void:
	if _busy:
		return
	if scene_path.is_empty():
		push_warning("SceneTransition.change_to: empty scene path")
		return
	_busy = true
	await _run_transition(scene_path)
	_busy = false


func _build_ui() -> void:
	_overlay = ColorRect.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(OVERLAY_COLOR.r, OVERLAY_COLOR.g, OVERLAY_COLOR.b, 0.0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	_label = Label.new()
	_label.name = "LoadingLabel"
	_label.text = LOADING_BASE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := load(FONT_PATH) as Font
	if font != null:
		_label.add_theme_font_override("font", font)
	_label.add_theme_font_size_override("font_size", 48)
	_label.add_theme_color_override("font_color", TEXT_COLOR)
	_label.modulate.a = 0.0
	_overlay.add_child(_label)


func _process(delta: float) -> void:
	if not _busy or _label == null or _label.modulate.a < 0.01:
		return
	_dot_accum += delta
	if _dot_accum < 0.35:
		return
	_dot_accum = 0.0
	_dot_index = (_dot_index + 1) % 4
	_label.text = LOADING_BASE + ".".repeat(_dot_index)


func _run_transition(scene_path: String) -> void:
	visible = true
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_label.text = LOADING_BASE
	_dot_index = 0
	_dot_accum = 0.0
	set_process(true)

	await _fade_overlay(1.0)
	_label.modulate.a = 1.0

	var load_started_msec := Time.get_ticks_msec()
	var packed := await _load_packed(scene_path)
	if packed == null:
		push_error("SceneTransition: failed to load %s" % scene_path)
		_label.modulate.a = 0.0
		await _fade_overlay(0.0)
		visible = false
		set_process(false)
		return

	var err := get_tree().change_scene_to_packed(packed)
	if err != OK:
		push_error("SceneTransition: change_scene failed (%s) for %s" % [error_string(err), scene_path])
		_label.modulate.a = 0.0
		await _fade_overlay(0.0)
		visible = false
		set_process(false)
		return

	await _wait_until_game_ready()
	await _wait_min_loading(load_started_msec)

	var fade_out := create_tween()
	fade_out.set_parallel(true)
	fade_out.tween_property(_label, "modulate:a", 0.0, FADE_SECONDS * 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	fade_out.tween_property(_overlay, "color:a", 0.0, FADE_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await fade_out.finished

	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)


func _fade_overlay(target_alpha: float) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_overlay, "color:a", target_alpha, FADE_SECONDS)
	await tween.finished


func _load_packed(path: String) -> PackedScene:
	if ResourceLoader.has_cached(path):
		return load(path) as PackedScene

	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		var req_err := ResourceLoader.load_threaded_request(path)
		if req_err != OK:
			return load(path) as PackedScene

	while true:
		var progress: Array = []
		status = ResourceLoader.load_threaded_get_status(path, progress)
		match status:
			ResourceLoader.THREAD_LOAD_LOADED:
				return ResourceLoader.load_threaded_get(path) as PackedScene
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				return load(path) as PackedScene
			_:
				await get_tree().process_frame
	return load(path) as PackedScene


func _wait_until_game_ready() -> void:
	# Let the new scene run _ready / deferred bootstrap.
	await get_tree().process_frame
	await get_tree().process_frame

	var room_manager := get_tree().get_first_node_in_group("room_manager")
	if room_manager == null:
		await get_tree().create_timer(0.2).timeout
		return

	# Bootstrap is deferred; wait until the first room transition starts.
	var wait_start := Time.get_ticks_msec()
	while not bool(room_manager.call("is_transitioning")):
		if Time.get_ticks_msec() - wait_start > 1500:
			break
		await get_tree().process_frame
		if not is_instance_valid(room_manager):
			return

	while is_instance_valid(room_manager) and bool(room_manager.call("is_transitioning")):
		await get_tree().process_frame


func _wait_min_loading(started_msec: int) -> void:
	var elapsed := float(Time.get_ticks_msec() - started_msec) / 1000.0
	var remaining := MIN_LOADING_SECONDS - elapsed
	if remaining > 0.0:
		await get_tree().create_timer(remaining).timeout
