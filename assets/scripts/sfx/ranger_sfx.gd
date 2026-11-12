extends SfxPlayer

## Ranged: attack one-shots fill the current room only.

@export_group("Ranged SFX")
@export var attack_1: AudioStream ## (R)
@export var attack_2: AudioStream ## (R)


func play_attack() -> void:
	var streams: Array[AudioStream] = [attack_1, attack_2]
	play_room_random(streams, &"attack")
