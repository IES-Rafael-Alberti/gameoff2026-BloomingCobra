extends Node

## Persistent audio / display preferences (user://settings.cfg).

const CONFIG_PATH := "user://settings.cfg"
const SECTION := "settings"
const BUS_MASTER := &"Master"

enum DisplayMode {
	WINDOWED,
	BORDERLESS,
	FULLSCREEN,
}

const DISPLAY_LABELS: PackedStringArray = [
	"Windowed",
	"Borderless",
	"Fullscreen",
]

## Linear volume 0.0–1.0 applied to the Master bus.
var master_volume: float = 0.8
var display_mode: int = DisplayMode.WINDOWED


func _ready() -> void:
	load_settings()
	apply_all()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	master_volume = clampf(float(cfg.get_value(SECTION, "master_volume", master_volume)), 0.0, 1.0)
	display_mode = clampi(int(cfg.get_value(SECTION, "display_mode", display_mode)), 0, DisplayMode.FULLSCREEN)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "master_volume", master_volume)
	cfg.set_value(SECTION, "display_mode", display_mode)
	cfg.save(CONFIG_PATH)


func apply_all() -> void:
	apply_volume()
	apply_display_mode()


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
