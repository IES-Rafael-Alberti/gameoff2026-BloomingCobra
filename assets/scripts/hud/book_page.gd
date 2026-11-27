extends Control

## A book page that draws its text manually so every word can fade in on its
## own. Wrapping and measuring use the same code, so pagination and rendering
## can never disagree about how many lines a page holds.

const FONT_PATH := "res://assets/fonts/MagicalNeverlandRegular-JpRZ7.ttf"

@export var font_size: int = 13:
	set(value):
		if font_size == value:
			return
		font_size = value
		_relayout()
		queue_redraw()
@export var line_spacing: int = 3
@export var text_color: Color = Color(0.44, 0.29, 0.17, 1.0)
## How many words are fading at once while the page reveals itself.
@export var fade_words: float = 1.6

## Authored text for this page; the intro splits both pages into words.
@export_multiline var default_text: String = ""

var reveal: float = 1.0:
	set(value):
		reveal = clampf(value, 0.0, 1.0)
		queue_redraw()

var _font: Font
var _words := PackedStringArray()
var _placed: Array = []
var _line_count := 0


func _ready() -> void:
	_font = load(FONT_PATH) as Font
	resized.connect(_relayout)
	_relayout()


func set_words(words: PackedStringArray) -> void:
	_words = words
	_relayout()
	queue_redraw()


func words() -> PackedStringArray:
	return _words


func _scaled_size() -> int:
	return maxi(1, font_size)


func _line_height() -> float:
	if _font == null:
		return 0.0
	return float(_font.get_height(_scaled_size()))


func _content_height() -> float:
	if _line_count <= 0:
		return 0.0
	return _line_count * _line_height() + maxi(_line_count - 1, 0) * float(line_spacing)


func _wrap_lines(words: PackedStringArray, max_width: float) -> int:
	if _font == null or max_width <= 1.0:
		return 1
	var space_w := _font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, _scaled_size()).x
	var x := 0.0
	var lines := 1
	for word in words:
		if word.is_empty():
			continue
		var w := _font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, _scaled_size()).x
		if x > 0.0 and x + w > max_width:
			lines += 1
			x = 0.0
		x += w + space_w
	return lines


## True when these words fit inside this page's rectangle at the current size.
func fits_words(words: PackedStringArray) -> bool:
	if _font == null or size.x <= 1.0 or size.y <= 1.0:
		return true
	var lines := _wrap_lines(words, size.x)
	var needed := lines * _line_height() + maxi(lines - 1, 0) * float(line_spacing)
	return needed <= size.y - 1.0


## Largest size still larger than the floor that lets the current words fit.
func shrink_to_fit(min_size: int) -> void:
	for candidate in range(font_size - 1, min_size - 1, -1):
		font_size = candidate
		if fits_words(_words):
			return
	font_size = min_size


func _relayout() -> void:
	_placed.clear()
	_line_count = 0
	if _font == null or size.x <= 1.0:
		return

	var fs := _scaled_size()
	var line_h := _line_height()
	var space_w := _font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var ascent := _font.get_ascent(fs)
	var x := 0.0
	var line := 0

	for word in _words:
		if word.is_empty():
			continue
		var w := _font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if x > 0.0 and x + w > size.x:
			line += 1
			x = 0.0
		var y := line * (line_h + float(line_spacing)) + ascent
		_placed.append({"text": word, "pos": Vector2(x, y)})
		x += w + space_w
	_line_count = line + 1


func _draw() -> void:
	if _font == null or _placed.is_empty():
		return
	var fs := _scaled_size()
	var total := float(_placed.size())
	var revealed := reveal * total
	for i in _placed.size():
		var alpha := clampf((revealed - float(i)) / maxf(fade_words, 0.01), 0.0, 1.0)
		if alpha <= 0.0:
			continue
		var entry: Dictionary = _placed[i]
		var color := Color(text_color.r, text_color.g, text_color.b, text_color.a * alpha)
		draw_string(_font, entry["pos"], entry["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


## Fades the words in one after another over the given duration.
func play_reveal(seconds: float) -> void:
	reveal = 0.0
	queue_redraw()
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.tween_property(self, "reveal", 1.0, maxf(seconds, 0.01))
	await tween.finished
	reveal = 1.0
