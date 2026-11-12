extends SfxPlayer

## Player combat / footsteps / item pickups (UI — always hear yourself).

@export_group("Slash")
@export var slash: AudioStream
@export var slash_hit: AudioStream

@export_group("Stab")
@export var stab: AudioStream
@export var stab_hit: AudioStream

@export_group("Projectile")
@export var projectile: AudioStream
@export var projectile_hit: AudioStream

@export_group("Walking")
@export var steps_vigil: AudioStream ## dream / bubble mode
@export var steps_nightmare: AudioStream

@export_group("Items")
@export var max_health_pickup: AudioStream
@export var memory_pickup: AudioStream
@export var item_pickup: AudioStream

var _steps_voice: AudioStreamPlayer
var _steps_dream: bool = false


func _ready() -> void:
	super._ready()
	_steps_voice = AudioStreamPlayer.new()
	_steps_voice.name = "StepsVoice"
	_steps_voice.bus = String(bus)
	add_child(_steps_voice)


func play_slash() -> void:
	play_global(slash)


func play_slash_hit() -> void:
	play_global(slash_hit)


func play_stab() -> void:
	play_global(stab)


func play_stab_hit() -> void:
	play_global(stab_hit)


func play_projectile() -> void:
	play_global(projectile)


func play_projectile_hit() -> void:
	play_global(projectile_hit)


## Starts / keeps a looping step bed while the player is walking.
func play_steps(in_dream: bool) -> void:
	var stream := steps_vigil if in_dream else steps_nightmare
	if stream == null or _steps_voice == null:
		return
	if _steps_voice.playing and _steps_dream == in_dream:
		return
	_steps_dream = in_dream
	_steps_voice.bus = String(bus)
	_steps_voice.stream = _as_looping(stream)
	_steps_voice.play()


func stop_steps() -> void:
	if _steps_voice != null and _steps_voice.playing:
		_steps_voice.stop()


func play_pickup(pickup_type: StringName) -> void:
	match String(pickup_type):
		"max_health", "maxhealth", "MaxHealth":
			play_global(max_health_pickup)
		"memory", "Memory":
			play_global(memory_pickup)
		_:
			play_global(item_pickup)
