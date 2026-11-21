class_name Hud
extends CanvasLayer
## The whole on-screen layer while you walk and drive: money and rating top
## left with your next appointment under them, where you are top centre, the
## day and time top right, the crosshair, the interaction prompt, the
## speedometer, messages and toasts, key hints, plus the pause screen.
##
## Everything you can interact with gets the same tag: a dark pill with a gold
## left edge, the key in a circle, then what it does (draw_tag). The prompt sits
## next to the thing you're looking at, not in the middle of the screen. The
## close-up views draw their hover labels with it too.

const GOLD := Color(0.98, 0.73, 0.16)
const GREEN := Color(0.42, 0.9, 0.42)
const TEXT := Color(0.96, 0.96, 0.97)
const DIM := Color(0.78, 0.8, 0.84)
const GLASS := Color(0.04, 0.05, 0.07, 0.78)   # the dark see-through behind every card
const WALK_KEYS := [["E", "Interact"], ["Shift", "Sprint"], ["Space", "Jump"], ["Esc", "Pause"]]
const MARGIN := 24.0
const TAG_FONT := 22

var _prompts: Array[Dictionary] = []   # [{key, text}], from "[E] Get in the truck"
var _prompt_at := Vector3.INF          # the thing they're about, in the world
var _prompt_text := ""
var _speed: Label
var _message: Label
var _toast: Label
var _cross: Label
var _money: Label
var _rating: Label
var _day: Label
var _time: Label
var _feeling: Label
var _place: Label
var _appt: PanelContainer
var _appt_title: Label
var _appt_line: Label
var _badge: PanelContainer
var _badge_count: Label
var _phone_hint: PanelContainer
var _msg_t := 0.0
var _toast_t := 0.0

## The pause screen. main.gd listens to its buttons.
var pause: PauseScreen
var _keys: HBoxContainer
var _closeup := false
var _corners: Array[Control] = []      # the cards round the edge, hidden while paused
var _tags: Control


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_cross = _label(root, 26, Control.PRESET_CENTER)
	_cross.text = "·"
	_tags = Control.new()
	_tags.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tags.draw.connect(_draw_prompt)
	root.add_child(_tags)
	_speed = _label(root, 34, Control.PRESET_CENTER_BOTTOM)
	_speed.position.y -= 70
	_message = _label(root, 38, Control.PRESET_CENTER_TOP)
	_message.position.y += 150
	_toast = _label(root, 24, Control.PRESET_CENTER_TOP)
	_toast.position.y += 100
	_build_corners(root)
	_keys = HBoxContainer.new()
	_keys.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_keys.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_keys.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_keys.offset_right = -MARGIN
	_keys.offset_bottom = -MARGIN
	_keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keys.add_theme_constant_override("separation", 10)
	root.add_child(_keys)
	set_keys(WALK_KEYS)
	pause = PauseScreen.new()
	root.add_child(pause)


func _process(delta: float) -> void:
	_msg_t -= delta
	_toast_t -= delta
	_message.modulate.a = clampf(_msg_t, 0.0, 1.0)
	_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	if not _prompts.is_empty():
		_tags.queue_redraw()


# --- Calls from the game ----------------------------------------------------------

## What you can do with what you're looking at: lines like "[E] Get in the
## truck", and where it is in the world (the tag sits beside it on screen).
func set_prompt(lines: Array, at := Vector3.INF) -> void:
	_prompt_at = at
	var joined := "\n".join(lines)
	if joined == _prompt_text:
		return
	_prompt_text = joined
	_prompts.clear()
	for line: String in lines:
		if line != "":
			_prompts.append(split_prompt(line))
	_tags.queue_redraw()


## "[E] Get in the truck" -> {key: "E", text: "Get in the truck"}.
static func split_prompt(line: String) -> Dictionary:
	if line.begins_with("[") and line.contains("]"):
		var close := line.find("]")
		return {"key": line.substr(1, close - 1), "text": line.substr(close + 1).strip_edges()}
	return {"key": "", "text": line}


func set_speed(text: String) -> void:
	_speed.text = text
	_cross.visible = text == "" and not _closeup
	_tags.visible = text == "" and not _closeup


func set_money(money: int) -> void:
	_money.text = _dollars(money)
	_money.add_theme_color_override("font_color", TEXT if money >= 0 else Color(1.0, 0.45, 0.4))


## Your star rating, next to the money.
func set_rating(text: String) -> void:
	_rating.text = text


## The day and the time, top right, and how tired you are under them ("" for fine).
func set_when(day: String, time: String, feeling := "") -> void:
	_day.text = day
	_time.text = time
	_feeling.text = feeling
	_feeling.visible = feeling != ""


## Unread texts: the number on the phone's badge (hidden at 0).
func set_unread(count: int) -> void:
	_badge.visible = count > 0
	_badge_count.text = str(count) if count < 100 else "99+"


## Where you are, top centre: "Home – 214 Maple St".
func set_place(text: String) -> void:
	_place.text = text


## The card under the money: "Next Appointment: Mrs. Okafor" over "10:30 AM  (47 min)".
## An empty title hides it.
func set_appointment(title: String, line := "") -> void:
	_appt.visible = title != "" and not pause.visible
	_appt_title.text = title
	_appt_line.text = line


## On with what to show (from ServiceCall.pause_summary()), or off.
func set_paused(on: bool, summary: PauseSummary = null) -> void:
	if on:
		pause.show_summary(summary)
	else:
		pause.hide_screen()
	for c in _corners:
		c.visible = not on               # the pause screen has its own
	_appt.visible = not on and _appt_title.text != ""
	_keys.visible = not on
	_message.visible = not on
	_toast.visible = not on


## Black, then the world fading back in: waking up.
func fade_from_black(seconds: float) -> void:
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 1)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(black)
	move_child(black, 0)
	var t := create_tween()
	t.tween_property(black, "color:a", 0.0, seconds)
	t.tween_callback(black.queue_free)


func show_message(text: String, seconds := 3.0) -> void:
	_message.text = text
	_msg_t = seconds


func show_toast(text: String, seconds := 2.5) -> void:
	_toast.text = text
	_toast_t = seconds


## Up close the mouse is free, so the crosshair and prompt get out of the way.
func set_closeup(on: bool, keys: Array = WALK_KEYS) -> void:
	_closeup = on
	_phone_hint.visible = not on and not pause.visible
	_cross.visible = not on
	_tags.visible = not on
	set_keys(keys)


func set_keys(keys: Array) -> void:
	for c in _keys.get_children():
		_keys.remove_child(c)
		c.queue_free()
	for pair: Array in keys:
		var chip := PanelContainer.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_theme_stylebox_override("panel", _card_style(0.0, 8.0))
		_keys.add_child(chip)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 8)
		chip.add_child(row)
		row.add_child(_key_cap(pair[0]))
		row.add_child(_text(pair[1], 17, TEXT))


# --- The tag everything you can use gets -----------------------------------------------

## Draws one interaction tag with its left edge at `at` (vertically centred on
## it), kept on screen: the key in a circle (if there is one), then the words.
## Returns the rect it drew in.
static func draw_tag(ci: CanvasItem, at: Vector2, text: String, key := "") -> Rect2:
	var font := ThemeDB.fallback_font
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_FONT).x
	var key_w := 0.0
	if key != "":
		key_w = maxf(30.0, font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 16.0) + 10.0
	var size := Vector2(16.0 + key_w + text_w + 18.0, 46.0)
	var screen := ci.get_viewport_rect().size
	var pos := (at - Vector2(0, size.y / 2.0)).clamp(Vector2(8, 8), screen - size - Vector2(8, 8))
	var rect := Rect2(pos, size)
	var box := StyleBoxFlat.new()
	box.bg_color = GLASS
	box.set_corner_radius_all(12)
	box.border_width_left = 4                      # gold down the left edge, like the other cards
	box.border_color = GOLD
	ci.draw_style_box(box, rect)
	var mid_y := rect.position.y + size.y / 2.0
	var x := rect.position.x + 16.0
	if key != "":
		var w := key_w - 10.0
		var cap := StyleBoxFlat.new()
		cap.bg_color = Color(0, 0, 0, 0)
		cap.set_corner_radius_all(15)
		cap.set_border_width_all(2)
		cap.border_color = TEXT
		ci.draw_style_box(cap, Rect2(Vector2(x, mid_y - 15.0), Vector2(w, 30.0)))
		ci.draw_string(font, Vector2(x, mid_y + 6.0), key, HORIZONTAL_ALIGNMENT_CENTER, w, 16, TEXT)
		x += key_w
	ci.draw_string(font, Vector2(x, mid_y + 8.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_FONT, TEXT)
	return rect


## The prompt, beside what it's about: a little right of it on screen, one tag
## per thing you can do. Below the crosshair if it's behind you or unknown.
func _draw_prompt() -> void:
	if _prompts.is_empty():
		return
	var screen := _tags.get_viewport_rect().size
	var at := screen / 2.0 + Vector2(36, 0)
	var cam := _tags.get_viewport().get_camera_3d()
	if _prompt_at != Vector3.INF and cam != null and not cam.is_position_behind(_prompt_at):
		at = cam.unproject_position(_prompt_at) + Vector2(36, 0)
	at.y -= (_prompts.size() - 1) * 27.0
	for p in _prompts:
		draw_tag(_tags, at, p["text"], p["key"])
		at.y += 54.0


# --- Building it ------------------------------------------------------------------

func _build_corners(root: Control) -> void:
	# Top left: money and rating, and under them your next appointment.
	var left := VBoxContainer.new()
	left.position = Vector2(MARGIN, MARGIN)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_theme_constant_override("separation", 12)
	root.add_child(left)
	var money := _card(left)
	var money_row := _row(money, 12)
	money_row.add_child(UiIcon.make("money", 30, GOLD))
	_money = _text("$0", 26, TEXT)
	money_row.add_child(_money)
	money_row.add_child(_divider())
	money_row.add_child(UiIcon.make("star", 22, GOLD))
	_rating = _text("", 19, DIM)
	money_row.add_child(_rating)
	_corners.append(money)
	_appt = _card(left, 14.0)
	var appt_row := _row(_appt, 14)
	appt_row.add_child(UiIcon.make("calendar", 34, GOLD))
	var appt_text := VBoxContainer.new()
	appt_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	appt_text.add_theme_constant_override("separation", 0)
	appt_row.add_child(appt_text)
	_appt_title = _text("", 20, TEXT)
	appt_text.add_child(_appt_title)
	_appt_line = _text("", 18, DIM)
	appt_text.add_child(_appt_line)
	_appt.visible = false

	# Top centre: where you are.
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = MARGIN
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var place := _card(top)
	var place_row := _row(place, 10)
	place_row.add_child(UiIcon.make("pin", 26, GOLD))
	_place = _text("", 21, TEXT)
	place_row.add_child(_place)
	_corners.append(top)

	# Top right: the day and the time, how tired you are under them.
	var right := VBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.offset_right = -MARGIN
	right.offset_top = MARGIN
	right.alignment = BoxContainer.ALIGNMENT_END
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_theme_constant_override("separation", 6)
	root.add_child(right)
	var when := _card(right)
	var when_row := _row(when, 10)
	when_row.add_child(UiIcon.make("calendar", 26, TEXT))
	_day = _text("", 21, TEXT)
	when_row.add_child(_day)
	when_row.add_child(_divider())
	when_row.add_child(UiIcon.make("clock", 26, TEXT))
	_time = _text("", 21, TEXT)
	when_row.add_child(_time)
	_feeling = _text("", 18, Color(1.0, 0.72, 0.4))
	_feeling.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_feeling.add_theme_constant_override("outline_size", 6)
	_feeling.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_feeling.visible = false
	right.add_child(_feeling)
	_corners.append(right)
	# Your phone, under the clock, with a red badge for unread texts.
	var phone := Control.new()
	phone.custom_minimum_size = Vector2(64, 64)
	phone.size_flags_horizontal = Control.SIZE_SHRINK_END
	phone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(phone)
	var disc := PanelContainer.new()
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var disc_style := _card_style(0.0, 0.0)
	disc_style.set_corner_radius_all(18)
	disc.add_theme_stylebox_override("panel", disc_style)
	disc.custom_minimum_size = Vector2(58, 58)
	disc.position = Vector2(0, 6)
	phone.add_child(disc)
	var handset := Control.new()
	handset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	handset.draw.connect(func() -> void:
		var r := Rect2(Vector2(19, 10), Vector2(20, 36))
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0, 0, 0, 0)
		s.set_corner_radius_all(4)
		s.set_border_width_all(2)
		s.border_color = TEXT
		handset.draw_style_box(s, r)
		handset.draw_line(Vector2(26, 41), Vector2(32, 41), TEXT, 2.0))
	disc.add_child(handset)
	_badge = PanelContainer.new()
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = GOLD
	badge_style.set_corner_radius_all(13)
	badge_style.set_content_margin_all(2.0)
	_badge.add_theme_stylebox_override("panel", badge_style)
	_badge.custom_minimum_size = Vector2(26, 26)
	_badge.position = Vector2(42, 0)
	_badge_count = _text("", 15, Color(0.1, 0.08, 0.02))
	_badge_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.add_child(_badge_count)
	_badge.visible = false
	phone.add_child(_badge)

	# Bottom left: how to get the phone out.
	_phone_hint = PanelContainer.new()
	_phone_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_phone_hint.add_theme_stylebox_override("panel", _card_style(0.0, 10.0))
	_phone_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_phone_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_phone_hint.offset_left = MARGIN
	_phone_hint.offset_bottom = -MARGIN
	root.add_child(_phone_hint)
	var hint_row := _row(_phone_hint, 10)
	hint_row.add_child(_key_cap("Tab"))
	hint_row.add_child(_text("Open Phone", 19, TEXT))
	_corners.append(_phone_hint)


## A key in a white ring: "E", "Tab", "Shift".
func _key_cap(key: String) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.set_corner_radius_all(14)
	s.set_border_width_all(2)
	s.border_color = TEXT
	s.content_margin_left = 8.0
	s.content_margin_right = 8.0
	s.content_margin_top = 1.0
	s.content_margin_bottom = 1.0
	cap.add_theme_stylebox_override("panel", s)
	cap.add_child(_text(key, 15, TEXT))
	return cap


## A dark see-through card with a gold edge down its left side.
func _card(parent: Control, margin := 10.0) -> PanelContainer:
	var c := PanelContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	c.add_theme_stylebox_override("panel", _card_style(4.0, margin))
	parent.add_child(c)
	return c


func _card_style(gold_edge: float, margin: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = GLASS
	s.set_corner_radius_all(12)
	s.border_width_left = int(gold_edge)
	s.border_color = GOLD
	s.content_margin_left = margin + 6.0
	s.content_margin_right = margin + 8.0
	s.content_margin_top = margin * 0.7
	s.content_margin_bottom = margin * 0.7
	return s


func _row(parent: Control, gap: int) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_constant_override("separation", gap)
	parent.add_child(r)
	return r


func _divider() -> Control:
	var d := ColorRect.new()
	d.color = Color(1, 1, 1, 0.35)
	d.custom_minimum_size = Vector2(2, 24)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


func _text(text: String, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _label(root: Control, size: int, preset: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_KEEP_SIZE)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(l)
	return l


func _dollars(amount: int) -> String:
	var digits := str(absi(amount))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return "%s$%s" % ["-" if amount < 0 else "", out]
