extends SfxPlayer

## Hunter: walking + optional ambient are proximity so other rooms stay quiet.

@export_group("Hunter SFX")
@export var walking: AudioStream ## (P) while moving
@export var standard: AudioStream ## (P) ambient loop — leave empty to disable
@export_range(0.05, 2.0, 0.01) var walking_interval: float = 0.35

var _walking_voice: AudioStreamPlayer2D


func _ready() -> void:
	super._ready()
	_walking_voice = AudioStreamPlayer2D.new()
	_walking_voice.name = "WalkingVoice"
	_walking_voice.bus = String(bus)
	_apply_proximity(_walking_voice)
	add_child(_walking_voice)


func set_active(active: bool) -> void:
	if active:
		start_standard(standard)
	else:
		stop_standard()
		stop_walking()
		stop_all()


func play_walking() -> void:
	if walking == null or _walking_voice == null:
		return
	_apply_proximity(_walking_voice)
	if not _interval_ok(&"walking", walking_interval):
		return
	_walking_voice.bus = String(bus)
	_walking_voice.stream = walking
	_walking_voice.play()


func stop_walking() -> void:
	if _walking_voice != null and _walking_voice.playing:
		_walking_voice.stop()
