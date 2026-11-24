extends SfxPlayer

## Game-level audio: vigil / nightmare music beds + room overrides + mode-switch sting.
## Beds stay loaded/playing; context only crossfades volume (avoids HTML5 decode hitch).

const ROOM_NONE := &""
const ROOM_SAFE_ZONE := &"safe_zone"
const ROOM_MEMORIES := &"memories"

@export_group("Music")
@export var music_vigil: AudioStream
@export var music_nightmare: AudioStream
@export var music_safe_zone: AudioStream
@export var music_memories: AudioStream
@export var music_fade_sec: float = 0.12

@export_group("Switch")
@export var switch_sfx: AudioStream

var _music_vigil: AudioStreamPlayer
var _music_nightmare: AudioStreamPlayer
var _music_safe_zone: AudioStreamPlayer
var _music_memories: AudioStreamPlayer
var _mode: int = 0
var _room_music: StringName = ROOM_NONE
var _bound: bool = false
var _fade_tween: Tween


func _ready() -> void:
	super._ready()
	add_to_group("sfx_general")
	_music_vigil = _make_music_voice("MusicVigil")
	_music_nightmare = _make_music_voice("MusicNightmare")
	_music_safe_zone = _make_music_voice("MusicSafeZone")
	_music_memories = _make_music_voice("MusicMemories")
	call_deferred("_bind_mode_source")


func play_switch() -> void:
	play_global(switch_sfx, &"mode_switch", 0.05)


func set_mode_music(mode_index: int) -> void:
	_mode = mode_index
	_refresh_music()


## Override mode beds while inside a special room. Pass ROOM_NONE to restore.
func set_room_music(kind: StringName) -> void:
	if _room_music == kind:
		_refresh_music()
		return
	_room_music = kind
	_refresh_music()


func clear_room_music() -> void:
	set_room_music(ROOM_NONE)


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
	_start_bed(_music_safe_zone, music_safe_zone)
	_start_bed(_music_memories, music_memories)


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

	var vigil_db := -80.0
	var night_db := -80.0
	var safe_db := -80.0
	var mem_db := -80.0

	match _room_music:
		ROOM_SAFE_ZONE:
			safe_db = 0.0
		ROOM_MEMORIES:
			mem_db = 0.0
		_:
			vigil_db = 0.0 if _mode == 1 else -80.0
			night_db = 0.0 if _mode == 0 else -80.0

	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()

	var fade := maxf(music_fade_sec, 0.0)
	if fade <= 0.0:
		_apply_volumes(vigil_db, night_db, safe_db, mem_db)
		return

	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	_tween_voice(_music_vigil, vigil_db, fade)
	_tween_voice(_music_nightmare, night_db, fade)
	_tween_voice(_music_safe_zone, safe_db, fade)
	_tween_voice(_music_memories, mem_db, fade)


func _apply_volumes(vigil_db: float, night_db: float, safe_db: float, mem_db: float) -> void:
	if _music_vigil != null:
		_music_vigil.volume_db = vigil_db
	if _music_nightmare != null:
		_music_nightmare.volume_db = night_db
	if _music_safe_zone != null:
		_music_safe_zone.volume_db = safe_db
	if _music_memories != null:
		_music_memories.volume_db = mem_db


func _tween_voice(voice: AudioStreamPlayer, target_db: float, fade: float) -> void:
	if voice == null or voice.stream == null:
		return
	_fade_tween.tween_property(voice, "volume_db", target_db, fade)
