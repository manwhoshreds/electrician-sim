class_name PhoneScreen
extends CanvasLayer
## Your phone. Tab gets it out of your pocket (on foot), Tab or Esc puts it
## away. It comes up in the bottom right corner and the mouse is yours; the
## clock keeps running while you look at it.
##
## Home screen: the time, then four apps.
##   Messages: texts from dispatch, customers, the inspector, deliveries.
##   Jobs: the call you're on, and what's booked on the board after it.
##   Mail: the same inbox as the computer at home.
##   Wallet: money, rating, jobs done.
##
## The data is ServiceCall's (phone_texts, phone_jobs, phone_wallet, inbox);
## this only shows it.

signal closed

const GOLD := Color(0.98, 0.73, 0.16)
const TEXT := Color(0.95, 0.96, 0.97)
const DIM := Color(0.66, 0.69, 0.74)
const CARD := Color(1, 1, 1, 0.07)
const RED := Color(0.92, 0.25, 0.2)
const SIZE := Vector2(390, 720)
const APPS := [["messages", "Messages", "chat", Color(0.25, 0.75, 0.38)], ["jobs", "Jobs", "clipboard", Color(0.98, 0.62, 0.12)],
		["mail", "Mail", "mail", Color(0.25, 0.55, 0.95)], ["wallet", "Wallet", "money", Color(0.55, 0.42, 0.9)]]

var service: ServiceCall
var is_open := false
var app := "home"                # "home" or one of APPS

var _frame: Control
var _clock: Label
var _content: VBoxContainer
var _tick := 0.0


func _ready() -> void:
	layer = 3
	visible = false
	_build()


func _process(delta: float) -> void:
	if not is_open:
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = 1.0
		_clock.text = _time()
		if app == "home" or app == "jobs":
			refresh()               # the countdowns and badges move on


## Out of your pocket, on the home screen.
func open() -> void:
	if is_open:
		return
	is_open = true
	visible = true
	app = "home"
	refresh()
	_frame.position.y = _rest_y() + SIZE.y
	create_tween().tween_property(_frame, "position:y", _rest_y(), 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Back in your pocket.
func close() -> void:
	if not is_open:
		return
	is_open = false
	var t := create_tween()
	t.tween_property(_frame, "position:y", _rest_y() + SIZE.y, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void: visible = is_open)
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_TAB):
		if app != "home" and event.is_action_pressed("ui_cancel"):
			show_app("home")             # Esc backs out of an app first
		else:
			close()
		get_viewport().set_input_as_handled()


func show_app(which: String) -> void:
	app = which
	if which == "messages":
		service.read_texts()
	refresh()


# --- What's on screen ----------------------------------------------------------------------

func refresh() -> void:
	if service == null:
		return
	_clock.text = _time()
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	match app:
		"home":
			_home()
		"messages":
			_messages()
		"jobs":
			_jobs()
		"mail":
			_mail()
		"wallet":
			_wallet()


func _home() -> void:
	var big := _label(_time(), 64, TEXT)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(_gap(30))
	_content.add_child(big)
	var day := _label(service.day_text(), 18, DIM)
	day.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(day)
	_content.add_child(_gap(40))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 22)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_content.add_child(grid)
	for a: Array in APPS:
		grid.add_child(_app_button(a[0], a[1], a[2], a[3]))


func _app_button(id: String, title: String, icon: String, colour: Color) -> Control:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(120, 118)
	b.pressed.connect(show_app.bind(id))
	var tile := PanelContainer.new()
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_theme_stylebox_override("panel", _style(colour, 22, 14.0))
	tile.position = Vector2(26, 6)
	tile.custom_minimum_size = Vector2(68, 68)
	tile.add_child(UiIcon.make(icon, 40, Color.WHITE))
	b.add_child(tile)
	var name := _label(title, 16, TEXT)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.position = Vector2(0, 84)
	name.size = Vector2(120, 24)
	b.add_child(name)
	var unread := service.unread_texts() if id == "messages" else 0
	if unread > 0:
		var badge := PanelContainer.new()
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_stylebox_override("panel", _style(RED, 12, 4.0))
		badge.position = Vector2(82, 0)
		badge.custom_minimum_size = Vector2(24, 24)
		var n := _label(str(unread), 14, Color.WHITE)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.add_child(n)
		b.add_child(badge)
	return b


func _messages() -> void:
	var list := _app_page("Messages")
	var texts := service.phone_texts()
	if texts.is_empty():
		list.add_child(_label("No messages yet.", 17, DIM))
	for t: Array in texts:
		var card := _card(list)
		var head := HBoxContainer.new()
		card.add_child(head)
		var from := _label(t[0], 17, GOLD if t[3] else TEXT)
		from.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(from)
		head.add_child(_label(t[1], 13, DIM))
		card.add_child(_wrapped(t[2], 15, TEXT))


func _jobs() -> void:
	var list := _app_page("Jobs")
	var data := service.phone_jobs()
	var current: Dictionary = data["current"]
	list.add_child(_label("ON THE CLOCK", 13, GOLD))
	if current.is_empty():
		list.add_child(_label("Nothing right now.", 16, DIM))
	else:
		_job_card(list, current)
	list.add_child(_gap(6))
	list.add_child(_label("UP NEXT", 13, GOLD))
	if (data["board"] as Array).is_empty():
		list.add_child(_label("Nothing on the board.", 16, DIM))
	for j: Dictionary in data["board"]:
		_job_card(list, j)


func _job_card(list: VBoxContainer, j: Dictionary) -> void:
	var card := _card(list)
	var head := HBoxContainer.new()
	card.add_child(head)
	var who := _label(j["who"], 17, TEXT)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(who)
	if j["urgent"]:
		head.add_child(_label("EMERGENCY", 12, RED))
	card.add_child(_label(j["address"], 14, DIM))
	if String(j["what"]) != "":
		card.add_child(_wrapped("\"%s\"" % j["what"], 15, TEXT))
	card.add_child(_label(j["when"], 14, GOLD))


func _mail() -> void:
	var list := _app_page("Mail")
	var mails := service.inbox()
	if mails.is_empty():
		list.add_child(_label("No mail yet.", 17, DIM))
	for m: Array in mails:
		var card := _card(list)
		card.add_child(_wrapped(m[0], 13, DIM))
		card.add_child(_wrapped(m[1], 16, TEXT))
		card.add_child(_wrapped(m[2], 14, DIM))


func _wallet() -> void:
	var list := _app_page("Wallet")
	var w := service.phone_wallet()
	var card := _card(list)
	card.add_child(_label("Balance", 14, DIM))
	var money := int(w["money"])
	card.add_child(_label("%s$%s" % ["-" if money < 0 else "", ComputerScreen._commas(absi(money))], 40, TEXT if money >= 0 else RED))
	var stats := _card(list)
	for row: Array in [["Rating", w["rating"]], ["Reviews", str(w["reviews"])], ["Jobs done", str(w["jobs"])]]:
		var line := HBoxContainer.new()
		stats.add_child(line)
		var k := _label(row[0], 16, DIM)
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(k)
		line.add_child(_label(row[1], 16, TEXT))


## An app's page: back arrow and title, then a scrolling list (returned).
func _app_page(title: String) -> VBoxContainer:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_content.add_child(head)
	var back := Button.new()
	back.text = "<"
	back.flat = true
	back.focus_mode = Control.FOCUS_NONE
	back.add_theme_font_size_override("font_size", 24)
	back.add_theme_color_override("font_color", GOLD)
	back.pressed.connect(show_app.bind("home"))
	head.add_child(back)
	head.add_child(_label(title, 24, TEXT))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	return list


func _time() -> String:
	return service.date_and_time().get_slice("  ", 1) if service != null else ""


# --- Building it -----------------------------------------------------------------------------

func _rest_y() -> float:
	return _frame.get_viewport_rect().size.y - SIZE.y - 78.0     # clear of the key hints along the bottom


func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# The phone: a black body, the screen inset in it.
	_frame = PanelContainer.new()
	_frame.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_frame.custom_minimum_size = SIZE
	_frame.size = SIZE
	_frame.offset_left = -SIZE.x - 40.0
	_frame.offset_right = -40.0
	var body := _style(Color(0.05, 0.05, 0.06), 44, 12.0)
	body.set_border_width_all(3)
	body.border_color = Color(0.3, 0.31, 0.34)
	_frame.add_theme_stylebox_override("panel", body)
	root.add_child(_frame)
	var screen := PanelContainer.new()
	screen.add_theme_stylebox_override("panel", _style(Color(0.07, 0.09, 0.13), 34, 16.0))
	_frame.add_child(screen)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	screen.add_child(col)
	# Status bar: the time, then signal and battery.
	var status := HBoxContainer.new()
	col.add_child(status)
	_clock = _label("", 15, TEXT)
	_clock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.add_child(_clock)
	var bars := Control.new()
	bars.custom_minimum_size = Vector2(48, 16)
	bars.draw.connect(func() -> void:
		for i in 4:
			bars.draw_rect(Rect2(Vector2(i * 5, 12 - i * 3), Vector2(3, 3 + i * 3)), TEXT)
		bars.draw_rect(Rect2(Vector2(24, 2), Vector2(20, 11)), TEXT, false, 1.5)
		bars.draw_rect(Rect2(Vector2(26, 4), Vector2(14, 7)), Color(0.4, 0.85, 0.45)))
	status.add_child(bars)
	_content = VBoxContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	col.add_child(_content)
	# The home bar along the bottom: back to the home screen.
	var home := Button.new()
	home.flat = true
	home.focus_mode = Control.FOCUS_NONE
	home.custom_minimum_size = Vector2(0, 22)
	home.pressed.connect(show_app.bind("home"))
	var pill := ColorRect.new()
	pill.color = Color(1, 1, 1, 0.6)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.size = Vector2(120, 5)
	pill.position = Vector2((SIZE.x - 24.0 - 32.0) / 2.0 - 60.0, 9)
	home.add_child(pill)
	col.add_child(home)


func _card(list: VBoxContainer) -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(CARD, 14, 12.0))
	list.add_child(p)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	p.add_child(box)
	return box


func _label(text: String, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _wrapped(text: String, size: int, c: Color) -> Label:
	var l := _label(text, size, c)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(SIZE.x - 90.0, 0)
	return l


func _gap(h: float) -> Control:
	var g := Control.new()
	g.custom_minimum_size = Vector2(0, h)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


func _style(bg: Color, radius: int, margin: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s
