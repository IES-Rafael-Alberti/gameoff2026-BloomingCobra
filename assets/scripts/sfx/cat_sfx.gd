extends SfxPlayer

## Cat: proximity ambient + room caught sting.

@export_group("Cat SFX")
@export var standard: AudioStream ## (P)
@export var caught: AudioStream ## (R)


func set_active(active: bool) -> void:
	if active:
		start_standard(standard)
	else:
		stop_standard()
		stop_all()


func play_caught() -> void:
	stop_standard()
	play_room_detached(caught)
