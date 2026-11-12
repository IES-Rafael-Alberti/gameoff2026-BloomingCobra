extends SfxPlayer

## Bouncer: bounce one-shots fill the current room only.

@export_group("Bouncer SFX")
@export var bounce_1: AudioStream ## (R)
@export var bounce_2: AudioStream ## (R)
@export var bounce_3: AudioStream ## (R)
@export_range(0.0, 1.0, 0.01) var bounce_interval: float = 0.05


func play_bounce() -> void:
	var streams: Array[AudioStream] = [bounce_1, bounce_2, bounce_3]
	play_room_random(streams, &"bounce", bounce_interval)


func set_active(active: bool) -> void:
	if not active:
		stop_all()
