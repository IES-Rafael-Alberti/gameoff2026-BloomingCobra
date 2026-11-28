extends Node

var _frames: int = 0
var _triggered: bool = false


func _ready() -> void:
	print("AUDIO probe ready")
	process_mode = Node.PROCESS_MODE_ALWAYS


func _make_stream() -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	var data := PackedByteArray()
	for i in range(2205):
		var sample: int = int(sin(float(i) * 0.2) * 12000.0)
		data.append(sample & 0xFF)
		data.append((sample >> 8) & 0xFF)
	wav.data = data
	return wav


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 10:
		_setup()
	if _frames == 420 and not _triggered:
		_triggered = true
		_trigger()


func _setup() -> void:
	var menu := get_tree().root.find_child("MainMenu", true, false)
	if menu == null:
		print("AUDIO menu missing")
		return
	var wav := _make_stream()
	menu.set("night_ambience_stream", wav)
	menu.set("button_piano_sting_stream", wav)
	menu.call("_start_night_ambience")
	var night := menu.get_node_or_null("NightAmbiencePlayer") as AudioStreamPlayer
	print("AUDIO night_playing=", night.playing if night != null else null, " has_stream=", night.stream != null if night != null else false)


func _trigger() -> void:
	var menu := get_tree().root.find_child("MainMenu", true, false)
	if menu == null:
		get_tree().quit()
		return
	var night := menu.get_node_or_null("NightAmbiencePlayer") as AudioStreamPlayer
	var sting := menu.get_node_or_null("ButtonPianoStingPlayer") as AudioStreamPlayer
	menu.call("emit_signal", "interacted")
	await get_tree().process_frame
	await get_tree().process_frame
	print("AUDIO sting_playing=", sting.playing if sting != null else null,
		" night_still_playing=", night.playing if night != null else null,
		" separate_players=", night != sting)
	print("AUDIO probe done")
	get_tree().quit()
