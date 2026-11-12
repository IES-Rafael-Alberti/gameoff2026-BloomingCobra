extends SfxPlayer

## Ranged: randomized attack one-shots when firing (room-global).

@export_group("Ranged SFX")
@export var attack_1: AudioStream ## (G)
@export var attack_2: AudioStream ## (G)


func play_attack() -> void:
	var streams: Array[AudioStream] = [attack_1, attack_2]
	play_global_random(streams, &"attack")
