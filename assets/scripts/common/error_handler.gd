extends Node

## Autoload that captures engine/script errors and appends them to a log file
## created or updated on every game run.

var _logger: _FileErrorLogger


func _init() -> void:
	_logger = _FileErrorLogger.new()
	_logger.begin_session()
	OS.add_logger(_logger)


func _ready() -> void:
	_ensure_input_actions()


## Guarantees gameplay actions exist even if Project Settings input map failed to load.
func _ensure_input_actions() -> void:
	_bind_key_action(&"move_left", [KEY_A, KEY_LEFT])
	_bind_key_action(&"move_right", [KEY_D, KEY_RIGHT])
	_bind_key_action(&"move_up", [KEY_W, KEY_UP])
	_bind_key_action(&"move_down", [KEY_S, KEY_DOWN])
	_bind_joypad_axis_action(&"move_left", JOY_AXIS_LEFT_X, -1.0)
	_bind_joypad_axis_action(&"move_right", JOY_AXIS_LEFT_X, 1.0)
	_bind_joypad_axis_action(&"move_up", JOY_AXIS_LEFT_Y, -1.0)
	_bind_joypad_axis_action(&"move_down", JOY_AXIS_LEFT_Y, 1.0)
	_bind_joypad_axis_action(&"aim_left", JOY_AXIS_RIGHT_X, -1.0)
	_bind_joypad_axis_action(&"aim_right", JOY_AXIS_RIGHT_X, 1.0)
	_bind_joypad_axis_action(&"aim_up", JOY_AXIS_RIGHT_Y, -1.0)
	_bind_joypad_axis_action(&"aim_down", JOY_AXIS_RIGHT_Y, 1.0)
	# Keep Shift + RT; do not wipe joypad when forcing the keyboard bind.
	_rebind_key_action(&"switch", [KEY_SHIFT])
	_bind_joypad_axis_action(&"switch", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_bind_key_action(&"toggle_map", [KEY_TAB])
	_bind_key_action(&"toggle_pause", [KEY_E])
	_bind_joypad_button_action(&"toggle_map", JOY_BUTTON_BACK)
	_bind_joypad_button_action(&"toggle_pause", JOY_BUTTON_START)
	# Menus: Xbox A confirm, B back (also covers PS Cross / Circle via SDL map).
	_bind_joypad_button_action(&"ui_accept", JOY_BUTTON_A)
	_bind_joypad_button_action(&"ui_select", JOY_BUTTON_A)
	_bind_joypad_button_action(&"ui_cancel", JOY_BUTTON_B)
	_bind_key_action(&"debug_hitboxes", [KEY_F1])
	_bind_key_action(&"debug_god_mode", [KEY_F2])
	_bind_key_action(&"debug_boss_room", [KEY_F3])
	_bind_mouse_action(&"attack", MOUSE_BUTTON_LEFT)


func _bind_key_action(action: StringName, keycodes: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for keycode in keycodes:
		var ev := InputEventKey.new()
		ev.physical_keycode = keycode as Key
		if not InputMap.action_has_event(action, ev):
			InputMap.action_add_event(action, ev)


func _rebind_key_action(action: StringName, keycodes: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	else:
		# Only replace keyboard binds — preserve joypad / mouse events.
		for existing in InputMap.action_get_events(action):
			if existing is InputEventKey:
				InputMap.action_erase_event(action, existing)
	for keycode in keycodes:
		var ev := InputEventKey.new()
		ev.physical_keycode = keycode as Key
		if not InputMap.action_has_event(action, ev):
			InputMap.action_add_event(action, ev)


func _bind_mouse_action(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	if not InputMap.action_has_event(action, ev):
		InputMap.action_add_event(action, ev)


func _bind_joypad_axis_action(action: StringName, axis: JoyAxis, axis_value: float) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = axis_value
	if not InputMap.action_has_event(action, ev):
		InputMap.action_add_event(action, ev)


func _bind_joypad_button_action(action: StringName, button: JoyButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	if not InputMap.action_has_event(action, ev):
		InputMap.action_add_event(action, ev)


func _exit_tree() -> void:
	if _logger != null:
		_logger.end_session()
		OS.remove_logger(_logger)
		_logger = null


## Manual error entry for gameplay/code paths that want an explicit record.
func log_error(message: String, context: String = "") -> void:
	if _logger == null:
		return
	_logger.write_manual("ERROR", message, context)


func log_warning(message: String, context: String = "") -> void:
	if _logger == null:
		return
	_logger.write_manual("WARNING", message, context)


func get_log_path() -> String:
	if _logger == null:
		return ""
	return _logger.log_path


class _FileErrorLogger extends Logger:
	const LOG_FILE_NAME := "errors.log"
	const LOG_DIR_NAME := "logs"

	var log_path: String = ""
	var _mutex := Mutex.new()
	var _file: FileAccess


	func begin_session() -> void:
		log_path = _resolve_log_path()
		_mutex.lock()
		_open_file()
		if _file != null:
			_file.store_line("")
			_file.store_line("========== SESSION %s ==========" % _timestamp())
			_file.store_line("log_path=%s" % log_path)
			_file.flush()
		_mutex.unlock()


	func end_session() -> void:
		_mutex.lock()
		if _file != null:
			_file.store_line("========== END SESSION %s ==========" % _timestamp())
			_file.flush()
			_file = null
		_mutex.unlock()


	func write_manual(level: String, message: String, context: String = "") -> void:
		var line := "[%s] [%s] %s" % [_timestamp(), level, message]
		if not context.is_empty():
			line += " | context=%s" % context
		_append_line(line)


	func _log_message(message: String, error: bool) -> void:
		if not error:
			return
		_append_line("[%s] [STDERR] %s" % [_timestamp(), message.strip_edges()])


	func _log_error(
		function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		error_type: int,
		script_backtraces: Array[ScriptBacktrace]
	) -> void:
		var type_name := _error_type_name(error_type)
		var detail := rationale if not rationale.is_empty() else code
		var entry := "[%s] [%s] %s\n  at %s() (%s:%d)" % [
			_timestamp(),
			type_name,
			detail,
			function,
			file,
			line,
		]
		if not code.is_empty() and code != rationale:
			entry += "\n  code: %s" % code
		for backtrace in script_backtraces:
			if backtrace != null and not backtrace.is_empty():
				entry += "\n%s" % backtrace.format(2)
		_append_line(entry)


	func _append_line(text: String) -> void:
		_mutex.lock()
		if _file == null:
			_open_file()
		if _file != null:
			_file.store_line(text)
			_file.flush()
		_mutex.unlock()


	func _open_file() -> void:
		if log_path.is_empty():
			log_path = _resolve_log_path()
		if FileAccess.file_exists(log_path):
			_file = FileAccess.open(log_path, FileAccess.READ_WRITE)
			if _file != null:
				_file.seek_end()
		else:
			_file = FileAccess.open(log_path, FileAccess.WRITE)


	func _resolve_log_path() -> String:
		var dir_path: String
		if OS.has_feature("editor"):
			dir_path = ProjectSettings.globalize_path("res://%s" % LOG_DIR_NAME)
		else:
			dir_path = OS.get_user_data_dir().path_join(LOG_DIR_NAME)
		DirAccess.make_dir_recursive_absolute(dir_path)
		return dir_path.path_join(LOG_FILE_NAME)


	func _timestamp() -> String:
		return Time.get_datetime_string_from_system(false, true)


	func _error_type_name(error_type: int) -> String:
		match error_type:
			ERROR_TYPE_ERROR:
				return "ERROR"
			ERROR_TYPE_WARNING:
				return "WARNING"
			ERROR_TYPE_SCRIPT:
				return "SCRIPT"
			ERROR_TYPE_SHADER:
				return "SHADER"
			_:
				return "UNKNOWN"
