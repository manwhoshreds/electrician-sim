class_name PauseScreen
extends Control
## The pause screen: the game blurred out behind a dashboard of where you
## stand. A menu down the left, the call you're on in the middle with the
## latest review under it, the business and quick actions on the right.
##
## It only shows a PauseSummary and says which button was pressed; main.gd
## decides what Save, Load, Exit and New game do. Things the game doesn't do
## yet are shown greyed out and marked "Coming soon".

signal resume_pressed
signal save_pressed
signal load_pressed
signal new_game_pressed
signal exit_pressed

const GOLD := Color(0.98, 0.73, 0.16)
const GREEN := Color(0.42, 0.9, 0.42)
const TEXT := Color(0.93, 0.94, 0.95)
const DIM := Color(0.68, 0.71, 0.75)
const SOON := Color(0.42, 0.45, 0.5)
const DARK := Color(0.1, 0.08, 0.02)
const CARD := Color(0.07, 0.1, 0.15, 0.93)
const SIDEBAR := Color(0.04, 0.06, 0.09, 0.9)
const LINE := Color(0.26, 0.3, 0.36, 0.9)
const BLUE := Color(0.55, 0.75, 1.0)

const BLUR_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 3.5).rgb;
	COLOR = vec4(c * 0.42 + vec3(0.01, 0.015, 0.03), 1.0);
}
"""

## What each key does, for the Controls page.
const CONTROLS := [
	["On foot", [["W A S D", "Walk"], ["Shift", "Sprint"], ["Space", "Jump"], ["E", "Use, talk, open"], ["F", "Work on it, run it"],
			["Esc", "Pause"]]],
	["Driving", [["E", "Get in / out"], ["W / S", "Gas / brake and reverse"], ["A / D", "Steer"], ["Space", "Handbrake"],
			["R", "Flip it back over"], ["C", "Inside / chase view"], ["Mouse", "Look around"]]],
	["Close-up work", [["1 - 5", "Pick a tool"], ["Left click", "Use the tool"], ["Right click", "Black probe / snug a screw"],
			["R", "Probes off"], ["Scroll", "Lean in"], ["Tab", "Job notes"], ["Esc", "Step back"]]],
]

var _summary := PauseSummary.new()
var _bold: FontVariation
var _italic: FontVariation
var _date: Label
var _time: Label
var _money: Label
var _call: VBoxContainer
var _status: Label
var _status_pill: PanelContainer
var _review: VBoxContainer
var _business: VBoxContainer
var _directory_button: Button
var _notice: Label
var _overlay: Control
var _modal: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_bold = FontVariation.new()
	_bold.base_font = ThemeDB.fallback_font
	_bold.variation_embolden = 0.7
	_italic = FontVariation.new()
	_italic.base_font = ThemeDB.fallback_font
	_italic.variation_embolden = 0.9
	_italic.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.22, 1), Vector2.ZERO)
	var blur := ColorRect.new()
	blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = BLUR_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	blur.material = mat
	add_child(blur)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	margin.add_theme_constant_override("margin_top", 12)
	add_child(margin)
	var col := _vbox(12)
	margin.add_child(col)
	col.add_child(_build_top_bar())
	var body := _hbox(20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	body.add_child(_build_sidebar())
	var center := _vbox(18)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	center.add_child(_build_call_card())
	center.add_child(_build_review_card())
	var right := _vbox(18)
	right.custom_minimum_size.x = 430
	body.add_child(right)
	right.add_child(_build_business_card())
	right.add_child(_build_actions_card())
	_build_overlay()


# --- Showing it ---------------------------------------------------------------------------

func show_summary(s: PauseSummary) -> void:
	_summary = s if s != null else PauseSummary.new()
	_notice.text = ""
	close_overlay()
	_date.text = _summary.day_text
	_time.text = _summary.time_text
	_money.text = _dollars(_summary.money, true)
	_money.add_theme_color_override("font_color", GREEN if _summary.money >= 0 else Color(1.0, 0.45, 0.4))
	_fill_call()
	_fill_review()
	_fill_business()
	_directory_button.disabled = not _summary.has_job
	visible = true


func hide_screen() -> void:
	close_overlay()
	visible = false


## A line under the menu: "Game saved." and the like.
func notice(text: String) -> void:
	_notice.text = text


## Asks first. `on_yes` runs if they say yes.
func confirm(question: String, yes_label: String, on_yes: Callable) -> void:
	var box := _vbox(18)
	var q := _lbl(question, 22, TEXT)
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.custom_minimum_size.x = 520
	box.add_child(q)
	var row := _hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var yes := _plain_button(yes_label, Color(0.75, 0.2, 0.15), TEXT)
	yes.pressed.connect(func() -> void:
		close_overlay()
		on_yes.call())
	row.add_child(yes)
	var no := _plain_button("Cancel", CARD.lightened(0.15), TEXT)
	no.pressed.connect(close_overlay)
	row.add_child(no)
	_open_overlay("Are you sure?", box, false)


## Closes a page on top (Controls, Reviews...), if one's open. True if it did.
func close_overlay() -> bool:
	if _overlay == null or not _overlay.visible:
		return false
	_overlay.visible = false
	return true


# --- The top bar --------------------------------------------------------------------------

func _build_top_bar() -> Control:
	var bar := _hbox(18)
	bar.custom_minimum_size.y = 64
	var logo := _hbox(10)
	logo.custom_minimum_size.x = 372
	logo.add_child(UiIcon.make("bolt", 52, GOLD))
	var words := _vbox(-8)
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	var top := _lbl("ELECTRICIAN", 30, TEXT)
	top.add_theme_font_override("font", _italic)
	words.add_child(top)
	var bottom := _lbl("S I M U L A T O R", 18, TEXT)
	bottom.add_theme_font_override("font", _bold)
	words.add_child(bottom)
	logo.add_child(words)
	bar.add_child(logo)
	bar.add_child(UiIcon.make("pause", 34, GOLD))
	bar.add_child(_lbl("Game Paused", 36, TEXT, true))
	bar.add_child(_spring())
	var when := _pill()
	var w := _hbox(12)
	when.add_child(w)
	w.add_child(UiIcon.make("calendar", 26, TEXT))
	_date = _lbl("", 22, TEXT)
	w.add_child(_date)
	w.add_child(_gap(18))
	w.add_child(UiIcon.make("clock", 26, TEXT))
	_time = _lbl("", 22, TEXT)
	w.add_child(_time)
	bar.add_child(when)
	var cash := _pill()
	var c := _hbox(12)
	cash.add_child(c)
	c.add_child(UiIcon.make("dollar", 28, GREEN))
	_money = _lbl("", 24, GREEN)
	c.add_child(_money)
	c.add_child(_vline())
	var lv := _vbox(2)
	var lv_row := _hbox(10)
	lv_row.add_child(_lbl("Lv —", 22, SOON))
	var xp := _vbox(0)
	xp.add_child(_lbl("Levels: coming soon", 13, SOON))
	var track := PanelContainer.new()
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.custom_minimum_size = Vector2(150, 10)
	track.add_theme_stylebox_override("panel", _style(Color(0.2, 0.22, 0.26), 5, 0.0))
	xp.add_child(track)
	lv_row.add_child(xp)
	lv.add_child(lv_row)
	c.add_child(lv)
	bar.add_child(cash)
	return bar


# --- The menu down the left -------------------------------------------------------------------

func _build_sidebar() -> Control:
	var side := PanelContainer.new()
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.custom_minimum_size.x = 372
	side.add_theme_stylebox_override("panel", _style(SIDEBAR, 12, 14.0))
	var col := _vbox(6)
	side.add_child(col)
	col.add_child(_menu_button("play", "Resume", resume_pressed.emit, true))
	col.add_child(_menu_button("save", "Save Game", save_pressed.emit))
	col.add_child(_menu_button("folder", "Load Game", load_pressed.emit))
	col.add_child(_menu_button("plus", "New Game", new_game_pressed.emit))
	col.add_child(_menu_button("calendar", "Skip to Monday", Callable(), false, true))
	col.add_child(_rule())
	col.add_child(_menu_button("gear", "Settings", Callable(), false, true))
	col.add_child(_menu_button("gamepad", "Controls", _show_controls))
	col.add_child(_menu_button("help", "Help / Tutorial", Callable(), false, true))
	col.add_child(_rule())
	col.add_child(_menu_button("home", "Return to Main Menu", Callable(), false, true))
	col.add_child(_menu_button("power", "Exit Game", exit_pressed.emit))
	_notice = _lbl("", 18, GOLD)
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.custom_minimum_size.x = 260
	col.add_child(_notice)
	return side


func _menu_button(icon: String, label: String, action: Callable, primary := false, soon := false) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 52
	var fg := DARK if primary else (SOON if soon else TEXT)
	if primary:
		b.add_theme_stylebox_override("normal", _style(GOLD, 8, 0.0, GOLD.lightened(0.3), 2))
		b.add_theme_stylebox_override("hover", _style(GOLD.lightened(0.15), 8, 0.0, GOLD.lightened(0.4), 2))
		b.add_theme_stylebox_override("pressed", _style(GOLD.darkened(0.1), 8, 0.0))
	else:
		b.add_theme_stylebox_override("normal", _style(Color(0, 0, 0, 0), 8, 0.0))
		b.add_theme_stylebox_override("hover", _style(Color(1, 1, 1, 0.07), 8, 0.0))
		b.add_theme_stylebox_override("pressed", _style(Color(1, 1, 1, 0.12), 8, 0.0))
		b.add_theme_stylebox_override("disabled", _style(Color(0, 0, 0, 0), 8, 0.0))
	var row := _hbox(14)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 18
	row.offset_right = -8
	b.add_child(row)
	row.add_child(UiIcon.make(icon, 28, fg))
	var text := _lbl(label, 21, fg)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.clip_text = true
	row.add_child(text)
	if soon:
		b.disabled = true
		row.add_child(_soon_tag())
	elif action.is_valid():
		b.pressed.connect(action)
	return b


# --- The call you're on ------------------------------------------------------------------------

func _build_call_card() -> Control:
	var card := _card(true)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var col := _vbox(10)
	card.add_child(col)
	var head := _hbox(14)
	head.add_child(UiIcon.make("wrench", 32, GOLD))
	head.add_child(_lbl("Current Service Call", 28, TEXT, true))
	head.add_child(_spring())
	_status_pill = PanelContainer.new()
	_status_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_pill.add_theme_stylebox_override("panel", _style(Color(0.06, 0.16, 0.32), 5, 8.0, Color(0.25, 0.5, 0.9)))
	_status = _lbl("", 17, BLUE)
	_status_pill.add_child(_status)
	head.add_child(_status_pill)
	col.add_child(head)
	col.add_child(_rule())
	_call = _vbox(12)
	_call.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_call)
	return card


func _fill_call() -> void:
	_clear(_call)
	var s := _summary
	_status_pill.visible = s.has_job
	if not s.has_job:
		var none := _lbl("No service call right now. The next one comes in shortly.", 22, DIM)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_call.add_child(none)
		return
	_status.text = s.status
	var top := _hbox(24)
	_call.add_child(top)
	top.add_child(_photo_placeholder())
	var info := _vbox(4)
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(_lbl(s.job_title, 28, TEXT, true))
	info.add_child(_icon_line("pin", s.address, TEXT))
	var home := _hbox(10)
	home.add_child(UiIcon.make("house", 22, TEXT))
	home.add_child(_lbl(s.home_type, 21, TEXT))
	home.add_child(_lbl("(built: coming soon)", 17, SOON))
	info.add_child(home)
	var pay := _hbox(10)
	pay.add_child(UiIcon.make("money", 22, GREEN))
	pay.add_child(_lbl("Payout " + _dollars(s.payout), 21, GREEN))
	info.add_child(pay)
	top.add_child(info)
	# Complaint, job type, time.
	var strip := PanelContainer.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_theme_stylebox_override("panel", _style(Color(0.05, 0.08, 0.12, 0.9), 8, 12.0, LINE))
	_call.add_child(strip)
	var cols := _hbox(18)
	strip.add_child(cols)
	var complaint := _column_head("chat", "Customer Complaint")
	var quote := _lbl(s.complaint, 18, TEXT)
	quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quote.custom_minimum_size.x = 330
	complaint.add_child(quote)
	complaint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	complaint.size_flags_stretch_ratio = 1.6
	cols.add_child(complaint)
	cols.add_child(_vline())
	var kind := _column_head("clipboard", "Job Type")
	kind.add_child(_lbl(s.job_type, 19, TEXT))
	kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(kind)
	cols.add_child(_vline())
	var time := _column_head("clock", "Estimated Time")
	time.add_child(_lbl("Coming soon", 19, SOON))
	time.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(time)
	# What to do, and what you know.
	var lower := _hbox(24)
	lower.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_call.add_child(lower)
	var objectives := _column_head("target", "Objectives")
	objectives.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_checklist(objectives, s.objectives)
	lower.add_child(objectives)
	lower.add_child(_vline())
	var known := _column_head("info", "Known Details")
	known.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for d: Array in s.details:
		var row := _hbox(10)
		row.add_child(_lbl("•", 19, DIM))
		var t := _lbl(d[0], 18, GREEN if d[1] else TEXT)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(t)
		known.add_child(row)
	lower.add_child(known)


func _photo_placeholder() -> Control:
	var tile := PanelContainer.new()
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.custom_minimum_size = Vector2(250, 118)
	tile.add_theme_stylebox_override("panel", _style(Color(0.12, 0.15, 0.2), 8, 8.0, LINE))
	var col := _vbox(6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	tile.add_child(col)
	var icon := UiIcon.make("house", 52, SOON)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(icon)
	var caption := _lbl("House photo: coming soon", 15, SOON)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(caption)
	return tile


# --- The latest review -------------------------------------------------------------------------

func _build_review_card() -> Control:
	var card := _card(true)
	var col := _vbox(10)
	card.add_child(col)
	var head := _hbox(14)
	head.add_child(UiIcon.make("star", 32, GOLD))
	head.add_child(_lbl("Latest Review", 28, TEXT, true))
	head.add_child(_spring())
	var all := _plain_button("View All Reviews  →", Color(0, 0, 0, 0), TEXT)
	all.add_theme_stylebox_override("normal", _style(Color(0, 0, 0, 0), 6, 10.0, Color(0.8, 0.82, 0.86, 0.7)))
	all.add_theme_font_size_override("font_size", 18)
	all.pressed.connect(_show_reviews)
	head.add_child(all)
	col.add_child(head)
	_review = _vbox(0)
	col.add_child(_review)
	return card


func _fill_review() -> void:
	_clear(_review)
	if _summary.reviews.is_empty():
		_review.add_child(_lbl("No reviews yet. Finish a job and the customer will leave one.", 20, DIM))
		return
	_review.add_child(_review_row(_summary.reviews[0], true))


func _review_row(r: Dictionary, big: bool) -> Control:
	var inner := PanelContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_stylebox_override("panel", _style(Color(0.05, 0.08, 0.12, 0.9), 8, 12.0, LINE))
	var row := _hbox(22)
	inner.add_child(row)
	var avatar := PanelContainer.new()
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar.custom_minimum_size = Vector2(56, 56) if big else Vector2(44, 44)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	avatar.add_theme_stylebox_override("panel", _style(Color(0.75, 0.77, 0.8), 40, 10.0))
	avatar.add_child(UiIcon.make("person", 40 if big else 26, Color(0.35, 0.38, 0.42)))
	row.add_child(avatar)
	var who := _vbox(4)
	who.custom_minimum_size.x = 230 if big else 200
	who.add_child(_lbl(r.get("name", ""), 22 if big else 19, TEXT))
	var about: String = r.get("about", "")
	who.add_child(_lbl(("Job: " + about) if about != "" else r.get("address", ""), 16, DIM))
	if r.has("day"):
		who.add_child(_lbl("Day %d" % int(r["day"]), 16, DIM))
	row.add_child(who)
	var right := _vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stars := _hbox(4)
	for i in 5:
		stars.add_child(UiIcon.make("star", 26 if big else 22, GOLD if i < int(r.get("stars", 0)) else Color(0.3, 0.32, 0.36)))
	right.add_child(stars)
	var text := _lbl("\"%s\"" % r.get("text", ""), 20 if big else 18, TEXT)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(text)
	row.add_child(right)
	return inner


# --- The business ------------------------------------------------------------------------------

func _build_business_card() -> Control:
	var card := _card(false)
	var col := _vbox(10)
	card.add_child(col)
	var head := _hbox(14)
	head.add_child(UiIcon.make("briefcase", 32, GOLD))
	head.add_child(_lbl("Your Business", 28, TEXT, true))
	col.add_child(head)
	_business = _vbox(0)
	col.add_child(_business)
	return card


func _fill_business() -> void:
	_clear(_business)
	var s := _summary
	var rating := _hbox(6)
	if s.review_count > 0:
		rating.add_child(_lbl("%.1f" % s.rating, 20, TEXT))
		rating.add_child(UiIcon.make("star", 20, GOLD))
		rating.add_child(_lbl("(%d review%s)" % [s.review_count, "" if s.review_count == 1 else "s"], 18, DIM))
	else:
		rating.add_child(_lbl("No reviews yet", 19, DIM))
	_stat("star", "Reputation", rating)
	_stat("list", "Active Calls", _lbl(str(s.active_calls), 20, TEXT))
	_stat("calendar", "Scheduled (Next 7 Days)", _soon_tag(), true)
	_stat("money", "Total Earnings", _lbl(_dollars(s.total_earned, true), 20, TEXT))
	_stat("chart", "This Week", _lbl(_dollars(s.week_earned, true), 20, TEXT), false, true)


func _stat(icon: String, label: String, value: Control, soon := false, last := false) -> void:
	var row := _hbox(14)
	row.custom_minimum_size.y = 46
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_stylebox_override("panel", _style(Color(0.12, 0.15, 0.2), 20, 6.0))
	badge.add_child(UiIcon.make(icon, 22, SOON if soon else GOLD))
	row.add_child(badge)
	var name_label := _lbl(label, 19, SOON if soon else TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	row.add_child(value)
	_business.add_child(row)
	if not last:
		_business.add_child(_rule())


# --- Quick actions -----------------------------------------------------------------------------

func _build_actions_card() -> Control:
	var card := _card(false)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var col := _vbox(12)
	card.add_child(col)
	var head := _hbox(14)
	head.add_child(UiIcon.make("bolt", 32, GOLD))
	head.add_child(_lbl("Quick Actions", 28, TEXT, true))
	col.add_child(head)
	col.add_child(_action("calendar", "View Schedule", Callable(), true))
	col.add_child(_action("box", "Manage Tools & Inventory", _show_inventory))
	col.add_child(_action("mail", "Check Messages", Callable(), true))
	col.add_child(_action("trend", "Business Upgrades", Callable(), true))
	_directory_button = _action("book", "Panel Directory", _show_directory)
	col.add_child(_directory_button)
	return card


func _action(icon: String, label: String, action: Callable, soon := false) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 50
	b.add_theme_stylebox_override("normal", _style(Color(0.08, 0.11, 0.16, 0.9), 6, 0.0, LINE))
	b.add_theme_stylebox_override("hover", _style(Color(0.13, 0.17, 0.23, 0.95), 6, 0.0, GOLD.darkened(0.2)))
	b.add_theme_stylebox_override("pressed", _style(Color(0.16, 0.2, 0.27, 0.95), 6, 0.0, GOLD))
	b.add_theme_stylebox_override("disabled", _style(Color(0.06, 0.08, 0.11, 0.7), 6, 0.0, LINE.darkened(0.3)))
	var row := _hbox(16)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 22
	row.offset_right = -14
	b.add_child(row)
	var fg := SOON if soon else TEXT
	row.add_child(UiIcon.make(icon, 26, fg))
	var text := _lbl(label, 21, fg)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	if soon:
		b.disabled = true
		row.add_child(_soon_tag())
	elif action.is_valid():
		b.pressed.connect(action)
	return b


# --- Pages on top: controls, reviews, the truck, the panel ---------------------------------------

func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible = false
	add_child(_overlay)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(center)
	var card := _card(true)
	center.add_child(card)
	_modal = _vbox(16)
	card.add_child(_modal)


func _open_overlay(title: String, content: Control, scroll := true) -> void:
	_clear(_modal)
	var head := _hbox(14)
	var t := _lbl(title, 28, TEXT, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := _plain_button("Close", CARD.lightened(0.15), TEXT)
	close.custom_minimum_size.x = 120
	close.pressed.connect(close_overlay)
	head.add_child(close)
	_modal.add_child(head)
	_modal.add_child(_rule())
	if scroll:
		var sc := ScrollContainer.new()
		sc.custom_minimum_size = Vector2(760, 560)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(content)
		_modal.add_child(sc)
	else:
		_modal.add_child(content)
	_overlay.visible = true


func _show_controls() -> void:
	var col := _vbox(18)
	for section: Array in CONTROLS:
		col.add_child(_lbl(section[0], 22, GOLD, true))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_theme_constant_override("h_separation", 24)
		grid.add_theme_constant_override("v_separation", 8)
		for pair: Array in section[1]:
			var key := PanelContainer.new()
			key.mouse_filter = Control.MOUSE_FILTER_IGNORE
			key.custom_minimum_size.x = 150
			key.add_theme_stylebox_override("panel", _style(Color(0.1, 0.12, 0.16), 5, 6.0, Color(0.8, 0.82, 0.86, 0.6)))
			var k := _lbl(pair[0], 18, TEXT)
			k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			key.add_child(k)
			grid.add_child(key)
			grid.add_child(_lbl(pair[1], 19, TEXT))
		col.add_child(grid)
	_open_overlay("Controls", col)


func _show_reviews() -> void:
	var col := _vbox(12)
	if _summary.reviews.is_empty():
		col.add_child(_lbl("No reviews yet.", 20, DIM))
	for r: Dictionary in _summary.reviews:
		col.add_child(_review_row(r, false))
	_open_overlay("All Reviews (%d)" % _summary.reviews.size(), col)


func _show_inventory() -> void:
	var s := _summary
	var col := _vbox(12)
	col.add_child(_icon_line("box", "Your %s: %d of %d loaded" % [s.vehicle_word, s.load_used, s.capacity], TEXT))
	col.add_child(_icon_line("wrench", "In your hands: " + (s.in_hand if s.in_hand != "" else "nothing"), TEXT))
	col.add_child(_icon_line("money", s.account, TEXT))
	col.add_child(_rule())
	if s.stock.is_empty():
		col.add_child(_lbl("Nothing on board. Stock up at the supply house downtown.", 19, DIM))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 6)
	for pair: Array in s.stock:
		grid.add_child(_lbl(pair[0], 20, TEXT))
		grid.add_child(_lbl("× %d" % pair[1], 20, GOLD))
	col.add_child(grid)
	col.add_child(_rule())
	col.add_child(_lbl("Tools: hand, screwdriver, clamp meter (volts, ohms, amps), plug tester, strippers, snips, tape measure, 6\" hole saw, drill and bits. Tool upgrades: coming soon.", 17, SOON))
	_open_overlay("Tools & Inventory", col)


func _show_directory() -> void:
	var col := _vbox(10)
	col.add_child(_lbl("%s, 120/240 V panel. Odd slots down the left, even down the right." % _summary.address, 18, DIM))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 6)
	for i in _summary.directory.size():
		grid.add_child(_lbl("%2d   %s" % [i + 1, _summary.directory[i]], 20, TEXT))
	col.add_child(grid)
	_open_overlay("Panel Directory", col)


# --- Building blocks ---------------------------------------------------------------------------

func _card(gold: bool) -> PanelContainer:
	var c := PanelContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_theme_stylebox_override("panel", _style(CARD, 12, 18.0, GOLD.darkened(0.15) if gold else LINE, 2 if gold else 1))
	return c


func _pill() -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_theme_stylebox_override("panel", _style(CARD, 10, 14.0, LINE))
	return p


func _soon_tag() -> Control:
	var tag := PanelContainer.new()
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.add_theme_stylebox_override("panel", _style(Color(0.16, 0.18, 0.22), 4, 5.0))
	tag.add_child(_lbl("SOON", 12, DIM))
	return tag


func _column_head(icon: String, title: String) -> VBoxContainer:
	var col := _vbox(6)
	col.add_child(_icon_line(icon, title, TEXT, GOLD, 22, true))
	return col


func _icon_line(icon: String, text: String, c: Color, icon_color := Color(-1, 0, 0), size_px := 21, bold := false) -> Control:
	var row := _hbox(10)
	row.add_child(UiIcon.make(icon, size_px + 2, c if icon_color.r < 0 else icon_color))
	row.add_child(_lbl(text, size_px, c, bold))
	return row


## The first unfinished line is what you're on, so it gets picked out in gold.
func _checklist(parent: Control, items: Array) -> void:
	var found_current := false
	for item: Array in items:
		var done: bool = item[1]
		var current := not done and not found_current
		found_current = found_current or current
		var row := _hbox(12)
		row.custom_minimum_size.y = 28
		row.add_child(_check_box(done, current))
		var t := _lbl(item[0], 18, GOLD if current else (DIM if done else TEXT))
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(t)
		parent.add_child(row)


func _check_box(done: bool, current: bool) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(24, 24)
	c.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		var edge := GREEN if done else (GOLD if current else DIM)
		c.draw_rect(Rect2(2, 2, 20, 20), edge, false, 2.0)
		if done:
			c.draw_polyline(PackedVector2Array([Vector2(6, 12), Vector2(10, 17), Vector2(19, 6)]), GREEN, 3.0, true))
	return c


func _plain_button(label: String, bg: Color, fg: Color) -> Button:
	var b := Button.new()
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(160, 44)
	b.add_theme_font_size_override("font_size", 20)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(state, fg)
	b.add_theme_stylebox_override("normal", _style(bg, 6, 10.0))
	b.add_theme_stylebox_override("hover", _style(bg.lightened(0.2) if bg.a > 0 else Color(1, 1, 1, 0.08), 6, 10.0))
	b.add_theme_stylebox_override("pressed", _style(bg.darkened(0.15), 6, 10.0))
	return b


func _lbl(text: String, size_px: int, c: Color, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", c)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if bold:
		l.add_theme_font_override("font", _bold)
	return l


func _rule() -> Control:
	var r := ColorRect.new()
	r.color = LINE
	r.custom_minimum_size.y = 1
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _vline() -> Control:
	var r := ColorRect.new()
	r.color = LINE
	r.custom_minimum_size.x = 1
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _gap(px: float) -> Control:
	var g := Control.new()
	g.custom_minimum_size.x = px
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


func _spring() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


func _hbox(sep: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", sep)
	return h


func _vbox(sep: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", sep)
	return v


func _style(bg: Color, radius: int, margin: float, border := Color(0, 0, 0, 0), width := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	if border.a > 0.0:
		s.set_border_width_all(width)
		s.border_color = border
	return s


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


static func _dollars(amount: int, cents := false) -> String:
	var digits := str(absi(amount))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return "%s$%s%s" % ["-" if amount < 0 else "", out, ".00" if cents else ""]
