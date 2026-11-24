class_name DoorDebugRoom
extends Room

## Debug arena: closed doors in both modes; any unlock button opens all of them
## (including unlinked ones, so transport links are optional).


func on_button_unlock() -> void:
	cancel_pending_door_close()
	for door in get_doors():
		if door != null:
			door.set_open(true)
