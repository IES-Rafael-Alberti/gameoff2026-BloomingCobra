extends CanvasLayer

## Fade + loading overlay for scene changes (Play → game, etc.).

const FONT_PATH := "res://assets/fonts/MagicalNeverlandRegular-JpRZ7.ttf"
const FADE_SECONDS := 0.4
const MIN_LOADING_SECONDS := 0.55
const READY_TIMEOUT_SECONDS := 8.0
const LOADING_BASE := "Loading"
const OVERLAY_COLOR := Color(0.02, 0.02, 0.05, 1.0)
const TEXT_COLOR := Color(0.96, 0.92, 0.86, 1.0)

var _busy: bool = false
var _show_loading: bool = true
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


## Pass show_loading = false for a plain fade to black (ending → title).
func change_to(scene_path: String, show_loading: bool = true) -> void:
	if _busy:
		return
	if scene_path.is_empty():
		push_warning("SceneTransition.change_to: empty scene path")
		return
	# Keep the coroutine owned by this autoload (survives change_scene).
	_busy = true
	_show_loading = show_loading
	_run_transition(scene_path)


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
	if not _busy or not _show_loading or _label == null or _label.modulate.a < 0.01:
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
	set_process(_show_loading)

	await _fade_overlay(1.0)
	if not is_inside_tree():
		_busy = false
		return
	_label.modulate.a = 1.0 if _show_loading else 0.0

	var load_started_msec := Time.get_ticks_msec()
	var packed := await _load_packed(scene_path)
	if packed == null:
		push_error("SceneTransition: failed to load %s" % scene_path)
		await _abort_overlay()
		return

	# Defer the swap so this autoload coroutine is not interrupted mid-call.
	get_tree().change_scene_to_packed(packed)
	await get_tree().process_frame
	await get_tree().process_frame

	await _wait_until_game_ready()
	await _wait_min_loading(load_started_msec)

	if not is_inside_tree():
		_busy = false
		return

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
	_busy = false


func _abort_overlay() -> void:
	_label.modulate.a = 0.0
	await _fade_overlay(0.0)
	visible = false
	set_process(false)
	_busy = false


func _fade_overlay(target_alpha: float) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_overlay, "color:a", target_alpha, FADE_SECONDS)
	await tween.finished


func _load_packed(path: String) -> PackedScene:
	if ResourceLoader.has_cached(path):
		return ResourceLoader.load(path) as PackedScene

	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		var req_err := ResourceLoader.load_threaded_request(path)
		if req_err != OK:
			# Last resort: may hitch, but keeps the transition moving.
			return ResourceLoader.load(path) as PackedScene

	var wait_start := Time.get_ticks_msec()
	while true:
		var progress: Array = []
		status = ResourceLoader.load_threaded_get_status(path, progress)
		match status:
			ResourceLoader.THREAD_LOAD_LOADED:
				return ResourceLoader.load_threaded_get(path) as PackedScene
			ResourceLoader.THREAD_LOAD_FAILED:
				push_error("SceneTransition: threaded load failed for %s" % path)
				return ResourceLoader.load(path) as PackedScene
			ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				return ResourceLoader.load(path) as PackedScene
			_:
				if Time.get_ticks_msec() - wait_start > 20000:
					push_error("SceneTransition: timed out loading %s" % path)
					return ResourceLoader.load(path) as PackedScene
				await get_tree().process_frame
	return null


func _wait_until_game_ready() -> void:
	# Let the new scene run _ready / deferred bootstrap.
	if get_tree() == null:
		return
	await get_tree().process_frame
	await get_tree().process_frame

	var room_manager := get_tree().get_first_node_in_group("room_manager")
	if room_manager == null:
		await get_tree().create_timer(0.25).timeout
		return

	var wait_start := Time.get_ticks_msec()
	var timeout_msec := int(READY_TIMEOUT_SECONDS * 1000.0)

	# Bootstrap is deferred; wait until the first room transition starts.
	while is_instance_valid(room_manager) and not bool(room_manager.call("is_transitioning")):
		if Time.get_ticks_msec() - wait_start > 1500:
			break
		await get_tree().process_frame

	while is_instance_valid(room_manager) and bool(room_manager.call("is_transitioning")):
		if Time.get_ticks_msec() - wait_start > timeout_msec:
			push_warning("SceneTransition: room ready wait timed out")
			break
		await get_tree().process_frame


func _wait_min_loading(started_msec: int) -> void:
	var elapsed := float(Time.get_ticks_msec() - started_msec) / 1000.0
	var remaining := MIN_LOADING_SECONDS - elapsed
	if remaining > 0.0 and get_tree() != null:
		await get_tree().create_timer(remaining).timeout
