extends SfxPlayer

## Duplicator: proximity ambient + room duplication sting.

@export_group("Duplicator SFX")
@export var standard: AudioStream ## (P)
@export var duplication: AudioStream ## (R) on split / spawn copies


func set_active(active: bool) -> void:
	if active:
		start_standard(standard)
	else:
		stop_standard()
		stop_all()


func play_duplication() -> void:
	play_room_detached(duplication)
