extends SfxPlayer

## Game-level audio: vigil / nightmare music beds + mode-switch sting.
## Both beds stay loaded/playing; mode only crossfades volume (avoids HTML5 decode hitch).

@export_group("Music")
@export var music_vigil: AudioStream
@export var music_nightmare: AudioStream
@export var music_fade_sec: float = 0.12

@export_group("Switch")
@export var switch_sfx: AudioStream

var _music_vigil: AudioStreamPlayer
var _music_nightmare: AudioStreamPlayer
var _mode: int = 0
var _bound: bool = false
var _fade_tween: Tween


func _ready() -> void:
	super._ready()
	add_to_group("sfx_general")
	_music_vigil = _make_music_voice("MusicVigil")
	_music_nightmare = _make_music_voice("MusicNightmare")
	call_deferred("_bind_mode_source")


func play_switch() -> void:
	play_global(switch_sfx, &"mode_switch", 0.05)


func set_mode_music(mode_index: int) -> void:
	_mode = mode_index
	_refresh_music()


func _make_music_voice(voice_name: String) -> AudioStreamPlayer:
	var voice := AudioStreamPlayer.new()
	voice.name = voice_name
	voice.bus = String(bus)
	add_child(voice)
	return voice


func _bind_mode_source() -> void:
	if _bound:
		return
	if not WorldMode.mode_changed.is_connected(_on_mode_changed):
		WorldMode.mode_changed.connect(_on_mode_changed)
	_bound = true
	_ensure_beds_playing()
	_on_mode_changed(WorldMode.mode)


func _on_mode_changed(index: int) -> void:
	set_mode_music(index)


func _ensure_beds_playing() -> void:
	_start_bed(_music_vigil, music_vigil)
	_start_bed(_music_nightmare, music_nightmare)


func _start_bed(voice: AudioStreamPlayer, stream: AudioStream) -> void:
	if voice == null:
		return
	if stream == null:
		voice.stop()
		voice.stream = null
		return
	# Assign once — _as_looping duplicates, so never compare stream identity each fade.
	if voice.stream == null:
		voice.stream = _as_looping(stream)
		voice.bus = String(bus)
		voice.volume_db = -80.0
	voice.bus = String(bus)
	if not voice.playing:
		voice.play()


func _refresh_music() -> void:
	_ensure_beds_playing()
	var vigil_db := 0.0 if _mode == 1 else -80.0
	var night_db := 0.0 if _mode == 0 else -80.0

	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()

	var fade := maxf(music_fade_sec, 0.0)
	if fade <= 0.0:
		if _music_vigil != null:
			_music_vigil.volume_db = vigil_db
		if _music_nightmare != null:
			_music_nightmare.volume_db = night_db
		return

	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	if _music_vigil != null and _music_vigil.stream != null:
		_fade_tween.tween_property(_music_vigil, "volume_db", vigil_db, fade)
	if _music_nightmare != null and _music_nightmare.stream != null:
		_fade_tween.tween_property(_music_nightmare, "volume_db", night_db, fade)
