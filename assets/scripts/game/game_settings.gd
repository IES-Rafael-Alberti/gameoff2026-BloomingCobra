extends Node

## Persistent audio / display / camera / input preferences (user://settings.cfg).

const CONFIG_PATH := "user://settings.cfg"
const SECTION := "settings"
const SECTION_INPUT := "input_bindings"
const BUS_MASTER := &"Master"

enum DisplayMode {
	WINDOWED,
	BORDERLESS,
	FULLSCREEN,
}

enum CameraMode {
	FIXED,
	FOLLOW,
	DEAD_ZONE,
}

const DISPLAY_LABELS: PackedStringArray = [
	"Windowed",
	"Borderless",
	"Fullscreen",
]

const CAMERA_LABELS: PackedStringArray = [
	"Fixed",
	"Follow",
	"Dead Zone",
]

const CAMERA_DESCRIPTIONS: PackedStringArray = [
	"Camera stays locked on the player.",
	"Camera smoothly lags behind as you move.",
	"Camera only moves when you leave the center area.",
]

## Actions the player can rebind from Options → Controls.
const REMAPPABLE_ACTIONS: Array[Dictionary] = [
	{&"action": &"move_left", &"label": "Move Left"},
	{&"action": &"move_right", &"label": "Move Right"},
	{&"action": &"move_up", &"label": "Move Up"},
	{&"action": &"move_down", &"label": "Move Down"},
	{&"action": &"attack", &"label": "Attack"},
	{&"action": &"switch", &"label": "Switch"},
	{&"action": &"toggle_pause", &"label": "Pause"},
	{&"action": &"toggle_map", &"label": "Map"},
]

## Linear volume 0.0–1.0 applied to the Master bus.
var master_volume: float = 0.8
var display_mode: int = DisplayMode.WINDOWED
var camera_mode: int = CameraMode.FOLLOW


func _ready() -> void:
	load_settings()
	apply_all()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	master_volume = clampf(float(cfg.get_value(SECTION, "master_volume", master_volume)), 0.0, 1.0)
	display_mode = clampi(int(cfg.get_value(SECTION, "display_mode", display_mode)), 0, DisplayMode.FULLSCREEN)
	camera_mode = clampi(int(cfg.get_value(SECTION, "camera_mode", camera_mode)), 0, CameraMode.DEAD_ZONE)
	_load_input_bindings(cfg)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	# Keep existing input section if present, then rewrite known keys.
	cfg.load(CONFIG_PATH)
	cfg.set_value(SECTION, "master_volume", master_volume)
	cfg.set_value(SECTION, "display_mode", display_mode)
	cfg.set_value(SECTION, "camera_mode", camera_mode)
	_save_input_bindings(cfg)
	cfg.save(CONFIG_PATH)


func apply_all() -> void:
	apply_volume()
	apply_display_mode()
	apply_camera_mode()


func apply_volume() -> void:
	var bus_idx := AudioServer.get_bus_index(BUS_MASTER)
	if bus_idx < 0:
		return
	AudioServer.set_bus_volume_db(bus_idx, linear_to_db(maxf(master_volume, 0.0001)))
	AudioServer.set_bus_mute(bus_idx, master_volume <= 0.001)


func set_master_volume(value: float, persist: bool = true) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	apply_volume()
	if persist:
		save_settings()


func adjust_master_volume(delta: float, persist: bool = true) -> void:
	set_master_volume(master_volume + delta, persist)


func apply_display_mode() -> void:
	match display_mode:
		DisplayMode.WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayMode.BORDERLESS:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		DisplayMode.FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func set_display_mode(mode: int, persist: bool = true) -> void:
	display_mode = clampi(mode, 0, DisplayMode.FULLSCREEN)
	apply_display_mode()
	if persist:
		save_settings()


func cycle_display_mode(delta: int = 1, persist: bool = true) -> void:
	var next := wrapi(display_mode + delta, 0, DISPLAY_LABELS.size())
	set_display_mode(next, persist)


func display_mode_label() -> String:
	var idx := clampi(display_mode, 0, DISPLAY_LABELS.size() - 1)
	return DISPLAY_LABELS[idx]


func apply_camera_mode() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	var player := tree.get_first_node_in_group("player")
	if player == null:
		return
	var cam := player.get_node_or_null("Camera2D")
	if cam != null and cam.has_method("set_mode"):
		cam.call("set_mode", camera_mode)


func set_camera_mode(mode: int, persist: bool = true) -> void:
	camera_mode = clampi(mode, 0, CameraMode.DEAD_ZONE)
	apply_camera_mode()
	if persist:
		save_settings()


func cycle_camera_mode(delta: int = 1, persist: bool = true) -> void:
	var next := wrapi(camera_mode + delta, 0, CAMERA_LABELS.size())
	set_camera_mode(next, persist)


func camera_mode_label() -> String:
	var idx := clampi(camera_mode, 0, CAMERA_LABELS.size() - 1)
	return CAMERA_LABELS[idx]


func camera_mode_description() -> String:
	var idx := clampi(camera_mode, 0, CAMERA_DESCRIPTIONS.size() - 1)
	return CAMERA_DESCRIPTIONS[idx]


func sync_from_window() -> void:
	## Keep stored mode aligned after F11 / OS changes.
	var mode := DisplayServer.window_get_mode()
	match mode:
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			display_mode = DisplayMode.FULLSCREEN
		DisplayServer.WINDOW_MODE_FULLSCREEN:
			display_mode = DisplayMode.BORDERLESS
		_:
			display_mode = DisplayMode.WINDOWED
	save_settings()


func toggle_fullscreen_shortcut() -> void:
	## Same behaviour as the in-game F11 toggle, but persisted.
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		set_display_mode(DisplayMode.WINDOWED)
	else:
		set_display_mode(DisplayMode.FULLSCREEN)


## --- Input rebinding -------------------------------------------------------

func is_gamepad_event(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


func is_keyboard_event(event: InputEvent) -> bool:
	return event is InputEventKey or event is InputEventMouseButton


func binding_label(action: StringName, gamepad: bool) -> String:
	if not InputMap.has_action(action):
		return "—"
	# Attack on gamepad defaults to right-stick aim when no pad button is bound.
	if gamepad and action == &"attack" and not _action_has_gamepad_event(action):
		return "Right Stick"
	var parts: PackedStringArray = []
	for ev in InputMap.action_get_events(action):
		if gamepad and is_gamepad_event(ev):
			parts.append(event_to_label(ev))
		elif not gamepad and is_keyboard_event(ev):
			parts.append(event_to_label(ev))
	if parts.is_empty() and gamepad and action.begins_with("move_"):
		return "Left Stick"
	if parts.is_empty() and gamepad and action == &"switch":
		return "RT"
	return " / ".join(parts) if not parts.is_empty() else "—"


func event_to_label(event: InputEvent) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return OS.get_keycode_string(code)
	if event is InputEventMouseButton:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				return "LMB"
			MOUSE_BUTTON_RIGHT:
				return "RMB"
			MOUSE_BUTTON_MIDDLE:
				return "MMB"
			_:
				return "Mouse %d" % (event as InputEventMouseButton).button_index
	if event is InputEventJoypadButton:
		return _joy_button_label((event as InputEventJoypadButton).button_index)
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return _joy_axis_label(motion.axis, motion.axis_value)
	return "?"


func rebind_action(action: StringName, event: InputEvent, gamepad: bool) -> bool:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if gamepad and not is_gamepad_event(event):
		return false
	if not gamepad and not is_keyboard_event(event):
		return false
	# Replace only events for this device family.
	for existing in InputMap.action_get_events(action):
		if gamepad and is_gamepad_event(existing):
			InputMap.action_erase_event(action, existing)
		elif not gamepad and is_keyboard_event(existing):
			InputMap.action_erase_event(action, existing)
	# Avoid duplicate shared binds on the same device family for other actions.
	_clear_event_from_other_actions(action, event, gamepad)
	InputMap.action_add_event(action, event)
	save_settings()
	return true


func _action_has_gamepad_event(action: StringName) -> bool:
	for ev in InputMap.action_get_events(action):
		if is_gamepad_event(ev):
			return true
	return false


func _clear_event_from_other_actions(keep_action: StringName, event: InputEvent, gamepad: bool) -> void:
	for entry in REMAPPABLE_ACTIONS:
		var other: StringName = entry[&"action"]
		if other == keep_action or not InputMap.has_action(other):
			continue
		for existing in InputMap.action_get_events(other):
			if not _events_match(existing, event):
				continue
			if gamepad and is_gamepad_event(existing):
				InputMap.action_erase_event(other, existing)
			elif not gamepad and is_keyboard_event(existing):
				InputMap.action_erase_event(other, existing)


func _events_match(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		var ak := a as InputEventKey
		var bk := b as InputEventKey
		return ak.physical_keycode == bk.physical_keycode and ak.keycode == bk.keycode
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		return (a as InputEventJoypadButton).button_index == (b as InputEventJoypadButton).button_index
	if a is InputEventJoypadMotion and b is InputEventJoypadMotion:
		var am := a as InputEventJoypadMotion
		var bm := b as InputEventJoypadMotion
		return am.axis == bm.axis and signf(am.axis_value) == signf(bm.axis_value)
	return false


func _joy_button_label(button: int) -> String:
	match button as JoyButton:
		JOY_BUTTON_A:
			return "A"
		JOY_BUTTON_B:
			return "B"
		JOY_BUTTON_X:
			return "X"
		JOY_BUTTON_Y:
			return "Y"
		JOY_BUTTON_LEFT_SHOULDER:
			return "LB"
		JOY_BUTTON_RIGHT_SHOULDER:
			return "RB"
		JOY_BUTTON_BACK:
			return "Select"
		JOY_BUTTON_START:
			return "Start"
		JOY_BUTTON_LEFT_STICK:
			return "L3"
		JOY_BUTTON_RIGHT_STICK:
			return "R3"
		JOY_BUTTON_DPAD_UP:
			return "D-Up"
		JOY_BUTTON_DPAD_DOWN:
			return "D-Down"
		JOY_BUTTON_DPAD_LEFT:
			return "D-Left"
		JOY_BUTTON_DPAD_RIGHT:
			return "D-Right"
		_:
			return "Btn %d" % button


func _joy_axis_label(axis: int, axis_value: float) -> String:
	var sign_label := "+" if axis_value >= 0.0 else "-"
	match axis as JoyAxis:
		JOY_AXIS_LEFT_X:
			return "L-Stick %s" % ("Right" if axis_value >= 0.0 else "Left")
		JOY_AXIS_LEFT_Y:
			return "L-Stick %s" % ("Down" if axis_value >= 0.0 else "Up")
		JOY_AXIS_RIGHT_X:
			return "R-Stick %s" % ("Right" if axis_value >= 0.0 else "Left")
		JOY_AXIS_RIGHT_Y:
			return "R-Stick %s" % ("Down" if axis_value >= 0.0 else "Up")
		JOY_AXIS_TRIGGER_LEFT:
			return "LT"
		JOY_AXIS_TRIGGER_RIGHT:
			return "RT"
		_:
			return "Axis %d%s" % [axis, sign_label]


func _save_input_bindings(cfg: ConfigFile) -> void:
	for entry in REMAPPABLE_ACTIONS:
		var action: StringName = entry[&"action"]
		if not InputMap.has_action(action):
			continue
		var encoded: PackedStringArray = []
		for ev in InputMap.action_get_events(action):
			var s := _encode_event(ev)
			if not s.is_empty():
				encoded.append(s)
		cfg.set_value(SECTION_INPUT, String(action), encoded)


func _load_input_bindings(cfg: ConfigFile) -> void:
	for entry in REMAPPABLE_ACTIONS:
		var action: StringName = entry[&"action"]
		if not cfg.has_section_key(SECTION_INPUT, String(action)):
			continue
		var encoded: Variant = cfg.get_value(SECTION_INPUT, String(action), PackedStringArray())
		if typeof(encoded) != TYPE_PACKED_STRING_ARRAY and typeof(encoded) != TYPE_ARRAY:
			continue
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		for item in encoded:
			var ev := _decode_event(str(item))
			if ev != null:
				InputMap.action_add_event(action, ev)


func _encode_event(event: InputEvent) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return "key:%d" % int(code)
	if event is InputEventMouseButton:
		return "mouse:%d" % int((event as InputEventMouseButton).button_index)
	if event is InputEventJoypadButton:
		return "joybtn:%d" % int((event as InputEventJoypadButton).button_index)
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return "joyaxis:%d:%.1f" % [int(motion.axis), motion.axis_value]
	return ""


func _decode_event(data: String) -> InputEvent:
	var parts := data.split(":")
	if parts.is_empty():
		return null
	match parts[0]:
		"key":
			if parts.size() < 2:
				return null
			var ev := InputEventKey.new()
			ev.physical_keycode = int(parts[1]) as Key
			return ev
		"mouse":
			if parts.size() < 2:
				return null
			var mev := InputEventMouseButton.new()
			mev.button_index = int(parts[1]) as MouseButton
			return mev
		"joybtn":
			if parts.size() < 2:
				return null
			var jev := InputEventJoypadButton.new()
			jev.button_index = int(parts[1]) as JoyButton
			return jev
		"joyaxis":
			if parts.size() < 3:
				return null
			var aev := InputEventJoypadMotion.new()
			aev.axis = int(parts[1]) as JoyAxis
			aev.axis_value = float(parts[2])
			return aev
		_:
			return null
