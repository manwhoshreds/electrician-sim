extends "res://tests/test_case.gd"
## The pause screen: the numbers behind it (earnings, the summary) and the
## screen itself (it builds, shows a summary, its buttons say what they are).


# --- Earnings ---------------------------------------------------------------------------

func test_earnings_all_time_and_this_week() -> void:
	var s := BusinessStats.new()
	s.record(200, 600.0)                       # day 1
	s.record(-50, 3000.0)                      # day 3: a bad one
	eq(s.total_earned, 150)
	eq(s.this_week(3000.0), 150)
	var next_week := BusinessStats.MINUTES_PER_WEEK + 600.0
	eq(s.this_week(next_week), 0, "a new week starts at nothing")
	s.record(80, next_week)
	eq(s.this_week(next_week), 80)
	eq(s.total_earned, 230)
	var back := BusinessStats.new()
	back.load_save(JSON.parse_string(JSON.stringify(s.to_save())))
	eq(back.to_save(), s.to_save())


# --- The summary --------------------------------------------------------------------------

func _game() -> Array:
	SaveGame.enabled = false
	Engine.time_scale = 0.0
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_node(main)
	return [main, main.service]


func after_each() -> void:
	super()
	Engine.time_scale = 1.0
	SaveGame.enabled = true


func test_between_jobs() -> void:
	var s: ServiceCall = _game()[1]
	var p := s.pause_summary()
	is_false(p.has_job)
	eq(p.active_calls, 0)
	is_true(p.can_save)
	eq(p.money, 150)
	eq(p.day_text, "Tue, Day 1")
	eq(p.time_text, "8:00 AM")
	eq(p.stock.size(), 6, "the six things a new truck carries (the garden hose takes no room)")
	check(p.account.begins_with("No supply house account yet (0 of 50"), p.account)


func test_on_a_job() -> void:
	seed(3)
	var s: ServiceCall = _game()[1]
	s.start_job()
	var p := s.pause_summary()
	is_true(p.has_job)
	eq(p.active_calls, 1)
	is_false(p.can_save, "mid-job: nothing to save until it's done")
	eq(p.address, s.job.address)
	check(p.job_title.ends_with(" Residence"), p.job_title)
	check(p.complaint.begins_with("Dispatch says: "), "before you've met: " + p.complaint)
	eq(p.payout, s.job.quoted(s.tuning))
	eq(p.objectives.size(), 6)
	eq(p.directory.size(), 16)
	is_true(p.details.size() >= 3)
	s._on_customer(null)
	p = s.pause_summary()
	eq(p.complaint, "\"%s\"" % s.job.notes[0], "after: what they told you")
	eq(p.objectives[0], ["Talk to the customer", true])


func test_reviews_newest_first_and_earnings() -> void:
	seed(4)
	var s: ServiceCall = _game()[1]
	s.start_job()
	s._on_customer(null)
	s._go_to_work()
	s._pay("ok", true)
	var paid := s.stats.total_earned
	is_true(paid > 0, "the job sheet's total went on the books")
	s._finish()
	var p := s.pause_summary()
	eq(p.total_earned, paid)
	eq(p.week_earned, paid)
	eq(p.reviews.size(), 1)
	check((p.reviews[0]["about"] as String) != "", "the review says what the job was")
	eq(p.reviews[0]["day"], 1)


# --- The screen -------------------------------------------------------------------------------

func test_screen_shows_a_summary_and_hides() -> void:
	var screen := PauseScreen.new()
	add_node(screen)
	is_false(screen.visible)
	var p := PauseSummary.new()
	p.day_text = "Wed, Day 2"
	p.money = -40
	screen.show_summary(p)
	is_true(screen.visible)
	eq(screen._date.text, "Wed, Day 2")
	eq(screen._money.text, "-$40.00")
	screen.hide_screen()
	is_false(screen.visible)
	screen.show_summary(null)
	is_true(screen.visible, "an empty summary is fine too")


func test_buttons_say_what_they_are() -> void:
	var screen := PauseScreen.new()
	add_node(screen)
	var heard: Array[String] = []
	for sig in ["resume_pressed", "save_pressed", "load_pressed", "new_game_pressed", "exit_pressed"]:
		screen.connect(sig, func() -> void: heard.append(sig))
	var buttons := screen.find_children("*", "Button", true, false)
	var by_label := {}
	for b: Button in buttons:
		for l: Label in b.find_children("*", "Label", true, false):
			by_label[l.text] = b
	for label in ["Resume", "Save Game", "Load Game", "New Game", "Exit Game"]:
		(by_label[label] as Button).pressed.emit()
	eq(heard, ["resume_pressed", "save_pressed", "load_pressed", "new_game_pressed", "exit_pressed"] as Array[String])
	for soon in ["Skip to Monday", "Settings", "Help / Tutorial", "Return to Main Menu", "View Schedule", "Check Messages", "Business Upgrades"]:
		is_true((by_label[soon] as Button).disabled, soon + " is coming soon")


func test_pages_open_and_close() -> void:
	var screen := PauseScreen.new()
	add_node(screen)
	screen.show_summary(PauseSummary.new())
	screen._show_controls()
	is_true(screen._overlay.visible)
	is_true(screen.close_overlay())
	is_false(screen.close_overlay(), "nothing left to close")
	var said_yes := [false]
	screen.confirm("Sure?", "Yes", func() -> void: said_yes[0] = true)
	is_true(screen._overlay.visible)
	is_false(said_yes[0], "asked, not done")
	for b: Button in screen._overlay.find_children("*", "Button", true, false):
		if b.text == "Yes":
			b.pressed.emit()
	is_true(said_yes[0])
	is_false(screen._overlay.visible)
