extends "res://assets/scripts/hud/confirm_overlay.gd"

## Main-menu Exit prompt. Keeps the original behaviour: YES quits the game.


func _ready() -> void:
	prompt_text = "Are you sure you want me to wake up?"
	options = PackedStringArray(["YES", "NO"])
	default_index = 1
	quit_on_confirm = true
	super._ready()
