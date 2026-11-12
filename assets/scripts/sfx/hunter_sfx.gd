extends SfxPlayer

## Hunter: walking fills the room; ambient is proximity (near the hunter).

@export_group("Hunter SFX")
@export var walking: AudioStream ## (R) while moving
@export var standard: AudioStream ## (P) ambient loop — leave empty to disable
@export_range(0.05, 2.0, 0.01) var walking_interval: float = 0.35


func set_active(active: bool) -> void:
	if active:
		start_standard(standard)
	else:
		stop_standard()
		stop_all()


func play_walking() -> void:
	play_room(walking, &"walking", walking_interval)
