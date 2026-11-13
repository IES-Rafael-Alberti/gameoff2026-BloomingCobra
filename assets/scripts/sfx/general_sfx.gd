extends SfxPlayer

## Game-level audio: vigil / nightmare music beds + mode-switch sting.
## Drop streams in the inspector; empty music slots simply stay silent.

@export_group("Music")
@export var music_vigil: AudioStream
@export var music_nightmare: AudioStream

@export_group("Switch")
@export var switch_sfx: AudioStream

var _music: AudioStreamPlayer
var _music_source: AudioStream
var _mode: int = 0
var _bound: bool = false


func _ready() -> void:
	super._ready()
	add_to_group("sfx_general")
	_music = AudioStreamPlayer.new()
	_music.name = "MusicVoice"
	_music.bus = String(bus)
	add_child(_music)
	call_deferred("_bind_mode_source")


func play_switch() -> void:
	play_global(switch_sfx, &"mode_switch", 0.05)


func set_mode_music(mode_index: int) -> void:
	_mode = mode_index
	_refresh_music()


func _bind_mode_source() -> void:
	if _bound:
		return
	if not WorldMode.mode_changed.is_connected(_on_mode_changed):
		WorldMode.mode_changed.connect(_on_mode_changed)
	_bound = true
	_on_mode_changed(WorldMode.mode)


func _on_mode_changed(index: int) -> void:
	set_mode_music(index)


func _refresh_music() -> void:
	if _music == null:
		return
	var stream := music_vigil if _mode == 1 else music_nightmare
	if stream == null:
		_music_source = null
		if _music.playing:
			_music.stop()
		_music.stream = null
		return
	if _music.playing and _music_source == stream:
		return
	_music_source = stream
	_music.bus = String(bus)
	_music.stream = _as_looping(stream)
	_music.play()
