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
	_rebind_key_action(&"switch", [KEY_SHIFT])
	_bind_key_action(&"toggle_map", [KEY_TAB])
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
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	else:
		InputMap.add_action(action)
	for keycode in keycodes:
		var ev := InputEventKey.new()
		ev.physical_keycode = keycode as Key
		InputMap.action_add_event(action, ev)


func _bind_mouse_action(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
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
