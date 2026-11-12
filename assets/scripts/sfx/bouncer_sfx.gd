extends SfxPlayer

## Bouncer: randomized bounce one-shots when hitting a wall (proximity).

@export_group("Bouncer SFX")
@export var bounce_1: AudioStream ## (P)
@export var bounce_2: AudioStream ## (P)
@export var bounce_3: AudioStream ## (P)
@export_range(0.0, 1.0, 0.01) var bounce_interval: float = 0.05


func play_bounce() -> void:
	var streams: Array[AudioStream] = [bounce_1, bounce_2, bounce_3]
	play_proximity_random(streams, &"bounce", bounce_interval)


func set_active(active: bool) -> void:
	if not active:
		stop_all()
