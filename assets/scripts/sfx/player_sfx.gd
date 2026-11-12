extends SfxPlayer

## Player combat / footsteps / item pickups (all treated as room-global UI/player feedback).

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
@export_range(0.05, 2.0, 0.01) var steps_interval: float = 0.28

@export_group("Items")
@export var max_health_pickup: AudioStream
@export var memory_pickup: AudioStream
@export var item_pickup: AudioStream


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


func play_steps(in_dream: bool) -> void:
	var stream := steps_vigil if in_dream else steps_nightmare
	play_global(stream, &"steps", steps_interval)


func play_pickup(pickup_type: StringName) -> void:
	match String(pickup_type):
		"max_health", "maxhealth", "MaxHealth":
			play_global(max_health_pickup)
		"memory", "Memory":
			play_global(memory_pickup)
		_:
			play_global(item_pickup)
