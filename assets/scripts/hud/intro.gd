extends Control

## Post-Play intro: book rises on black, text types itself page by page,
## thunder + white flash, book closes over plano1, then "go to sleep?" prompt.

const GAME_SCENE := "res://assets/scenes/game.tscn"
const MAIN_MENU_SCENE := "res://assets/scenes/HUD/main_menu.tscn"
const CONFIRM_SCRIPT := "res://assets/scripts/hud/confirm_overlay.gd"

## Fallback lore, used only when the labels in libro.tscn are left empty.
const INTRO_TEXT := "Some people say that dreams can come true; others say that there are infinite versions of you in equally infinite realities. If you believe these claims, you're already halfway through achieving your wishes. By SHIFTING, you can access these realities. Whenever you're in a deep slumber, you'll be able to reach into the depths of your mind, and if you're brave enough to conquer your fears, you'll be capable of shifting into the reality your heart desires. But be careful: if you stay too long in a light and beautiful dream, you'll eventually wake up."

@export_group("Timing")
@export var book_enter_seconds: float = 1.2
@export var closed_hold_seconds: float = 2.0
@export var book_open_seconds: float = 0.8
## Each page reveals word by word: one word every 1/chars_per_second seconds.
@export var chars_per_second: float = 11.0
@export var min_page_reveal_seconds: float = 1.6
@export var max_page_reveal_seconds: float = 5.0
@export var page_hold_seconds: float = 1.6
@export var page_fade_out_seconds: float = 0.45
@export var page_flip_seconds: float = 0.55
@export var after_text_hold_seconds: float = 0.5
@export var flash_in_seconds: float = 0.12
@export var flash_out_seconds: float = 0.35
@export var book_close_seconds: float = 0.75
## The closed book sinks below the screen before the prompt appears.
@export var book_exit_seconds: float = 1.0
@export var background_fade_seconds: float = 0.8
## Quiet time showing the bedroom so the player reads the context before
## being asked whether to sleep.
@export var background_hold_seconds: float = 3.5

@export_group("Audio")
## Drop the future thunder/WAV here in the inspector. Null is safe.
@export var thunder_sfx: AudioStream
@export var thunder_volume_db: float = 0.0

@export_group("Book")
@export var book_height_ratio: float = 0.78
# The two text blocks (BookText / BookTextRight) live inside libro.tscn,
# so their position, size and font can be adjusted directly in that scene.

@onready var _black: ColorRect = $BlackBg
@onready var _background: TextureRect = $Background
@onready var _book: Node2D = $Book
@onready var _book_sprite: AnimatedSprite2D = $Book/AnimatedSprite2D
@onready var _book_text: Control = $Book/BookText
@onready var _book_text_right: Control = $Book/BookTextRight
@onready var _flash: ColorRect = $FlashLayer/Flash
@onready var _thunder: AudioStreamPlayer = $ThunderPlayer

var _confirm: Control
var _book_center: Vector2 = Vector2.ZERO
var _book_placed: bool = false
var _transitioning: bool = false
# Page rects authored in libro.tscn, in the book's own (unscaled) coordinates.
var _page_local_rect: Array[Rect2] = [Rect2(), Rect2()]
var _page_authored_font: Array[int] = [13, 13]
var _page_authored_line_spacing: Array[int] = [3, 3]
var _page_base_px: Array[int] = [13, 13]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.modulate.a = 0.0
	_background.modulate.a = 0.0
	_capture_text_layout()
	# Pages stay hidden until their turn to reveal.
	for side in 2:
		_page(side).visible = false
		_page(side).reveal = 0.0

	_setup_book()
	_setup_confirm()
	_layout()
	resized.connect(_on_resized)

	await _play_sequence()


func _setup_book() -> void:
	_book_sprite.stop()
	_book_sprite.animation = &"open"
	_book_sprite.frame = 0


func _setup_confirm() -> void:
	var script := load(CONFIRM_SCRIPT) as Script
	if script == null:
		push_error("Intro: missing confirm overlay script")
		return

	_confirm = Control.new()
	_confirm.set_script(script)
	_confirm.name = "SleepConfirm"
	# Configure before add_child so _ready() builds the right prompt.
	_confirm.set("prompt_text", "Do you want to go to sleep?")
	_confirm.set("options", PackedStringArray(["YES", "NO"]))
	_confirm.set("default_index", 0)
	_confirm.set("quit_on_confirm", false)
	$ConfirmLayer.add_child(_confirm)

	if _confirm.has_signal("confirmed"):
		_confirm.confirmed.connect(_on_sleep_confirmed)
	if _confirm.has_signal("closed"):
		_confirm.closed.connect(_on_sleep_declined)


func _layout() -> void:
	var view := size
	if view.x <= 1.0 or view.y <= 1.0:
		view = get_viewport_rect().size

	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var frame_size := Vector2(480.0, 270.0)
	var frames := _book_sprite.sprite_frames
	if frames != null and frames.get_frame_count(&"open") > 0:
		var tex := frames.get_frame_texture(&"open", 0)
		if tex != null:
			frame_size = tex.get_size()

	var book_scale := view.y * book_height_ratio / maxf(frame_size.y, 1.0)
	# Scale only the artwork. Scaling the Book node would also scale the text
	# labels, which makes Godot rasterize the font at 13px and stretch it blurry.
	_book.scale = Vector2.ONE
	_book_sprite.scale = Vector2(book_scale, book_scale)
	_book_center = Vector2(view.x * 0.5, view.y * 0.49)

	if _book_placed:
		_book.position = _book_center
	else:
		_book.position = Vector2(
			_book_center.x,
			view.y + frame_size.y * book_scale * 0.5
		)
	_layout_text(book_scale)


func _capture_text_layout() -> void:
	# Remember the page rects authored in libro.tscn (in book-local units) so
	# they can be mapped to real screen pixels whenever the view resizes.
	for side in 2:
		var page: Control = _page(side)
		_page_local_rect[side] = Rect2(page.position, page.size)
		_page_authored_font[side] = page.font_size
		_page_authored_line_spacing[side] = page.line_spacing


func _layout_text(book_scale: float) -> void:
	# The pages live under an unscaled parent, so their rect and font are set
	# in screen pixels: the text is drawn crisp instead of being upscaled.
	for side in 2:
		var page: Control = _page(side)
		page.position = _page_local_rect[side].position * book_scale
		page.size = _page_local_rect[side].size * book_scale
		_page_base_px[side] = maxi(1, roundi(float(_page_authored_font[side]) * book_scale))
		page.font_size = _page_base_px[side]
		# Keep the same visual line rhythm as the authored 13px layout.
		page.line_spacing = roundi(float(_page_authored_line_spacing[side]) * book_scale)


func _page(side: int) -> Control:
	return _book_text_right if side == 1 else _book_text


func _authored_source() -> String:
	var left := String(_page(0).default_text).strip_edges()
	var right := String(_page(1).default_text).strip_edges()
	if not left.is_empty() and not right.is_empty():
		# Two authored paragraphs: keep them apart so pagination respects them.
		return left + "\n\n" + right
	if not left.is_empty():
		return left
	if not right.is_empty():
		return right
	return INTRO_TEXT


func _type_sheets(spreads: Array) -> void:
	for i in spreads.size():
		var spread: Array = spreads[i]
		# Left page first, then the right one of the same sheet.
		for side in 2:
			var entry: Array = spread[side]
			var words: PackedStringArray = entry[0]
			if words.is_empty():
				continue
			await _reveal_page(words, side, int(entry[1]))
		# Clear both pages before turning, so no text survives the flip.
		if i < spreads.size() - 1:
			await _fade_out_pages()
			await _play_next_page()


func _play_sequence() -> void:
	_book_sprite.speed_scale = _animation_length(&"open") / maxf(book_open_seconds, 0.01)

	var enter := create_tween()
	enter.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	enter.tween_property(_book, "position:y", _book_center.y, book_enter_seconds)
	await enter.finished
	_book_placed = true

	await get_tree().create_timer(closed_hold_seconds).timeout

	var open_finished := _book_sprite.animation_finished
	_book_sprite.play(&"open")
	await open_finished
	_book_sprite.stop()
	_book_sprite.frame = maxi(_book_sprite.sprite_frames.get_frame_count(&"open") - 1, 0)

	# Text authored in libro.tscn always wins; the built-in lore is the fallback.
	# Sentences are never split: pagination only breaks between them.
	var spreads := _paginate(_authored_source())
	await _type_sheets(spreads)

	await get_tree().create_timer(after_text_hold_seconds).timeout
	# The text must be gone before the flash/close, not during it.
	await _fade_out_pages()
	await _flash_in()
	await _close_book_and_reveal_background()
	_open_confirm()


func _animation_length(anim: StringName) -> float:
	var frames := _book_sprite.sprite_frames
	if frames == null:
		return 0.8
	var count := frames.get_frame_count(anim)
	var speed := frames.get_animation_speed(anim)
	if count <= 0 or speed <= 0.0:
		return 0.8
	return float(count) / speed


func _paginate(text: String) -> Array:
	# Returns an array of spreads; each spread is [left_words, right_words].
	# A sentence is never broken: it always lands whole on one page.
	var spreads: Array = []
	var left := PackedStringArray()
	var right := PackedStringArray()
	# Font size each page needs; oversized single sentences shrink their page.
	var left_font := _page_base_px[0]
	var right_font := _page_base_px[1]
	var on_right := false

	for sentence in _split_sentences(text):
		var words := _sentence_words(sentence)
		if words.is_empty():
			continue

		var fits := _fits_on(0, left_font, left, words) if not on_right \
			else _fits_on(1, right_font, right, words)
		if fits:
			if on_right:
				right.append_array(words)
			else:
				left.append_array(words)
			continue

		# Not enough room left. If the current page already has text, continue
		# on the next page (closing the sheet after the right one). If it is
		# still empty, the sentence alone is too big: shrink that page's font.
		var page_empty := right.is_empty() if on_right else left.is_empty()
		if not page_empty:
			if on_right:
				spreads.append([[left, left_font], [right, right_font]])
				left = PackedStringArray()
				right = PackedStringArray()
				left_font = _page_base_px[0]
				right_font = _page_base_px[1]
				on_right = false
			else:
				on_right = true

		var side := 1 if on_right else 0
		var font := _fit_font(side, right_font if on_right else left_font, words)
		if on_right:
			right_font = font
			right.append_array(words)
		else:
			left_font = font
			left.append_array(words)

	# Always emit complete spreads so both pages of a sheet appear together.
	# Each spread is [[words, font], [words, font]] so the reveal can restore
	# the exact size the paginator measured with.
	if not left.is_empty() or not right.is_empty():
		spreads.append([[left, left_font], [right, right_font]])
	if spreads.is_empty():
		spreads.append([[_sentence_words(text), _page_base_px[0]],
			[PackedStringArray(), _page_base_px[1]]])
	return spreads


func _sentence_words(sentence: String) -> PackedStringArray:
	var words := PackedStringArray()
	for raw_word in sentence.split(" ", false):
		var word := String(raw_word).strip_edges()
		if not word.is_empty():
			words.append(word)
	return words


func _fits_on(side: int, font_px: int, existing: PackedStringArray, extra: PackedStringArray) -> bool:
	var merged := existing.duplicate()
	merged.append_array(extra)
	var page: Control = _page(side)
	var previous: int = page.font_size
	page.font_size = font_px
	var fits: bool = page.fits_words(merged)
	page.font_size = previous
	return fits


func _fit_font(side: int, font_px: int, words: PackedStringArray) -> int:
	# Largest size (down to half the base) that still fits these words.
	var page: Control = _page(side)
	var floor_px := maxi(6, _page_base_px[side] / 2)
	var previous: int = page.font_size
	for candidate in range(font_px, floor_px - 1, -1):
		page.font_size = candidate
		if page.fits_words(words):
			page.font_size = previous
			return candidate
	page.font_size = previous
	return floor_px


func _split_sentences(text: String) -> PackedStringArray:
	# Sentences end at . ! ? and paragraphs also break at newlines.
	var sentences := PackedStringArray()
	var buffer := ""
	for i in text.length():
		var ch := text[i]
		if ch == "\n":
			if not buffer.strip_edges().is_empty():
				sentences.append(buffer.strip_edges())
			buffer = ""
			continue
		buffer += ch
		if ch == "." or ch == "!" or ch == "?":
			sentences.append(buffer.strip_edges())
			buffer = ""
	if not buffer.strip_edges().is_empty():
		sentences.append(buffer.strip_edges())
	return sentences


func _reveal_page(words: PackedStringArray, side: int, font_px: int) -> void:
	var page: Control = _page(side)
	# Use the size the paginator measured with, so it never overflows.
	page.font_size = font_px
	page.set_words(words)
	page.visible = true
	# Words come in one after another instead of the whole page at once.
	var duration := clampf(
		float(words.size()) / maxf(chars_per_second, 1.0),
		min_page_reveal_seconds,
		max_page_reveal_seconds
	)
	await page.play_reveal(duration)
	if page_hold_seconds > 0.0:
		await get_tree().create_timer(page_hold_seconds).timeout


func _fade_out_pages() -> void:
	# Everything must be gone before the page turns, or text survives the flip.
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	for side in 2:
		tween.parallel().tween_property(_page(side), "modulate:a", 0.0, page_fade_out_seconds)
	await tween.finished
	for side in 2:
		_page(side).visible = false
		_page(side).reveal = 0.0
		_page(side).modulate.a = 1.0


func _play_next_page() -> void:
	# Use the AnimatedSprite2D "NextPage" animation from libro.tscn.
	var frames := _book_sprite.sprite_frames
	if frames == null or frames.get_frame_count(&"NextPage") <= 0:
		push_warning("Intro: libro.tscn has no NextPage sprite animation")
		return

	# Pages are already faded out by _fade_out_pages before the turn.
	# Drive the duration directly and never await an already-finished signal.
	_book_sprite.speed_scale = _animation_length(&"NextPage") / maxf(page_flip_seconds, 0.01)
	_book_sprite.play(&"NextPage")
	await get_tree().create_timer(page_flip_seconds).timeout
	_book_sprite.stop()
	_book_sprite.frame = maxi(frames.get_frame_count(&"open") - 1, 0)


func _flash_in() -> void:
	if thunder_sfx != null:
		_thunder.stream = thunder_sfx
		_thunder.volume_db = thunder_volume_db
		_thunder.play()

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(_flash, "modulate:a", 1.0, flash_in_seconds)
	await tween.finished


func _close_book_and_reveal_background() -> void:
	# Flash fades while the book closes, so the white wash never hides the book.
	var flash_out := create_tween()
	flash_out.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	flash_out.tween_property(_flash, "modulate:a", 0.0, flash_out_seconds)

	var bg := create_tween()
	bg.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bg.tween_property(_background, "modulate:a", 1.0, background_fade_seconds)

	# Never await a tween signal that may already have fired during the close.
	_book_sprite.speed_scale = _animation_length(&"close") / maxf(book_close_seconds, 0.01)
	_book_sprite.play(&"close")
	await get_tree().create_timer(book_close_seconds).timeout
	_book_sprite.stop()
	# Hold the final closed frame so the book is seen sliding away.
	var close_frames := _book_sprite.sprite_frames
	if close_frames != null:
		_book_sprite.frame = maxi(close_frames.get_frame_count(&"close") - 1, 0)

	var remaining := maxf(background_fade_seconds, flash_out_seconds) - book_close_seconds
	if remaining > 0.0:
		await get_tree().create_timer(remaining).timeout
	_flash.modulate.a = 0.0
	_background.modulate.a = 1.0

	# Slide the shut book down out of view so only the bedroom remains.
	await _sink_book()

	# Let the bedroom sit on screen before asking the question: it carries the
	# context for what happens next.
	if background_hold_seconds > 0.0:
		await get_tree().create_timer(background_hold_seconds).timeout


func _sink_book() -> void:
	var view := size
	if view.x <= 1.0 or view.y <= 1.0:
		view = get_viewport_rect().size
	# Enough to clear the book plus its shadow below the bottom edge.
	var exit_y := view.y + _book_half_height() + view.y * 0.15
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(_book, "position:y", exit_y, maxf(book_exit_seconds, 0.01))
	await tween.finished
	_book.visible = false


func _book_half_height() -> float:
	# The book is a Node2D at _book_center, so its half height in screen pixels
	# comes from the scaled sprite frame.
	var frames := _book_sprite.sprite_frames
	if frames == null or frames.get_frame_count(&"open") <= 0:
		return 0.0
	var tex := frames.get_frame_texture(&"open", 0)
	if tex == null:
		return 0.0
	return tex.get_size().y * _book_sprite.scale.y * 0.5


func _open_confirm() -> void:
	if _confirm != null and _confirm.has_method("open"):
		_confirm.call("open")


func _unhandled_input(event: InputEvent) -> void:
	if _confirm == null or not is_instance_valid(_confirm):
		return
	if _confirm.has_method("is_open") and bool(_confirm.call("is_open")):
		if _confirm.has_method("handle_input") and bool(_confirm.call("handle_input", event)):
			_mark_input_handled()


func _mark_input_handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _on_sleep_confirmed() -> void:
	if _transitioning:
		return
	_transitioning = true

	# begin_new_run() clears the save, so only do it once the player says YES.
	if RunState != null and RunState.has_method("begin_new_run"):
		RunState.begin_new_run()
	elif RunState != null and RunState.has_method("reset"):
		RunState.reset()

	_change_scene(GAME_SCENE, true)


func _on_sleep_declined() -> void:
	if _transitioning:
		return
	_transitioning = true
	# Back to the menu: it is already cached, so a plain fade is enough.
	_change_scene(MAIN_MENU_SCENE, false)


func _change_scene(scene_path: String, show_loading: bool) -> void:
	if SceneTransition != null and SceneTransition.has_method("change_to"):
		# The loading overlay also does the threaded scene load.
		SceneTransition.change_to(scene_path, show_loading)
	else:
		get_tree().change_scene_to_file(scene_path)


func _on_resized() -> void:
	_layout()
