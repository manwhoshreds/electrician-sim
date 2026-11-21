extends "res://tests/test_case.gd"
## Characterization of PanelView as a controller: built headless, driven
## through its real click handler (_click_on), checked against the panel's
## state and the visuals it syncs. Pins the safety rules it enforces (arc
## flash, shocks) and the job flags it raises (measured, tested dead).

const L1 := 121.2


## The job, remembering every breaker that went in.
class RecordingJob:
	extends ActiveJob
	var used: Array = []

	func part_used(slot: int, rating: int) -> void:
		used.append([slot, rating])
		super(slot, rating)


var p: ElectricalPanel
var view: PanelView
var hands: Inventory
var job: RecordingJob


func before_each() -> void:
	p = ElectricalPanel.new()
	hands = Inventory.new()
	job = RecordingJob.new()
	job.target = 9
	job.circuit = p.circuit_at(9)
	view = PanelView.new()
	view.sim = p
	view.target_slot = 9
	view.inventory = hands
	view.job = job
	add_node(view)
	ClampMeter.dial = ClampMeter.Mode.VOLTS


func _click(kind: String, extra := {}) -> void:
	var pick := {"kind": kind}
	pick.merge(extra)
	view._click_on(pick, MOUSE_BUTTON_LEFT)


func _open_up() -> void:
	_click("door")
	_click("screw", {"i": 0})


func _probe(red: String, black: String) -> void:
	view._red = ""
	view._black = ""
	view._click_on({"kind": "probe", "id": red}, MOUSE_BUTTON_LEFT)
	view._click_on({"kind": "probe", "id": black}, MOUSE_BUTTON_RIGHT)


# State reads go through here, so a change in how the panel stores breakers
# only touches these lines.
func _on(slot: int) -> bool:
	return p.circuit_at(slot).breaker.on


func _present(slot: int) -> bool:
	return p.circuit_at(slot).breaker.present


func _wired(slot: int) -> bool:
	return p.circuit_at(slot).wire_landed


func _rating(slot: int) -> int:
	return p.circuit_at(slot).breaker.rating


func _state_text(slot: int) -> String:
	return (view._visuals[slot]["state_text"] as Label3D).text


# --- Opening up ------------------------------------------------------------------

func test_door_and_cover() -> void:
	is_false(view.door_open)
	is_true(view.cover_on)
	_open_up()
	is_true(view.door_open)
	is_false(view.cover_on)
	is_true(view.cover_removed)


func test_hints_walk_you_in() -> void:
	eq(view._hint(), "Buttoned up. Step back and go talk to the customer.", "nothing wrong yet")
	p.set_fault(9, "open")
	eq(view._hint(), "Click the door to open the panel.")
	_click("door")
	eq(view._hint(), "Screwdriver: take out the cover screw.")
	_click("screw", {"i": 0})
	check(view._hint().begins_with("Find the circuit"), "then measure")


# --- Breaker handles ----------------------------------------------------------------

func test_hand_toggles_breaker_and_syncs_the_model() -> void:
	_open_up()
	eq(_state_text(9), "ON")
	_click("breaker", {"slot": 9})
	is_false(_on(9))
	eq(_state_text(9), "OFF")
	_click("breaker", {"slot": 9})
	eq(_state_text(9), "ON")


func test_tripped_breaker_shows_trip_and_resets_off() -> void:
	p.trip(9)
	view._sync()
	eq(_state_text(9), "TRIP")
	_click("breaker", {"slot": 9})
	eq(_state_text(9), "OFF")


func test_main_handle() -> void:
	_click("main")
	is_false(p.main_on)
	_click("main")
	is_true(p.main_on)


func test_hot_fault_shows_scorch() -> void:
	p.set_fault(9, "hot")
	view._sync()
	is_true((view._visuals[9]["scorch"] as MeshInstance3D).visible)
	is_false((view._visuals[10]["scorch"] as MeshInstance3D).visible)


# --- Safety -----------------------------------------------------------------------

func test_pulling_a_breaker_with_the_main_on_arcs() -> void:
	_open_up()
	_click("breaker", {"slot": 9})            # off
	p.set_wire(9, false)
	_click("breaker", {"slot": 9})            # hand on an unwired breaker: pull it
	eq(view.work.arcs, 1)
	is_true(_present(9), "still in")


func test_pulling_a_breaker_dead() -> void:
	_open_up()
	_click("main")
	_click("terminal", {"slot": 9})
	is_false(_wired(9), "wire off")
	eq(view.work.shocks, 0, "dead terminal")
	_click("breaker", {"slot": 9})
	is_false(_present(9), "pulled")
	is_false((view._visuals[9]["root"] as Node3D).visible, "model gone")
	eq(view.work.arcs, 0)


func test_unscrewing_a_live_terminal_shocks() -> void:
	_open_up()
	_click("terminal", {"slot": 9})
	eq(view.work.shocks, 1)
	is_true(_wired(9), "wire stays on")


func test_breaker_off_is_not_enough_for_a_hot_fault() -> void:
	# An open breaker's terminal is dead, so this one's safe to unscrew.
	_open_up()
	_click("breaker", {"slot": 9})
	_click("terminal", {"slot": 9})
	eq(view.work.shocks, 0)
	is_false(_wired(9))


func test_two_pole_terminals_are_off_limits() -> void:
	_open_up()
	_click("main")
	_click("terminal", {"slot": 1})
	is_true(_wired(1), "range wire untouched")


func test_clipping_in_needs_a_breaker_in_hand_and_a_dead_bus() -> void:
	_open_up()
	_click("main")
	_click("terminal", {"slot": 9})
	_click("breaker", {"slot": 9})
	_click("slot", {"slot": 9})
	is_false(_present(9), "nothing in hand")
	hands.bag.append("breaker20")
	_click("main")
	_click("slot", {"slot": 9})
	eq(view.work.arcs, 1, "bus live")
	is_false(_present(9))
	_click("main")
	_click("slot", {"slot": 9})
	is_true(_present(9), "clipped in")
	eq(_rating(9), 20)
	eq(job.used, [[9, 20]])
	is_true(hands.hands_empty(), "out of your bag")
	eq(_state_text(9), "OFF")


func test_full_replacement_through_the_controls() -> void:
	p.set_fault(9, "open")
	_open_up()
	_click("main")
	_click("breaker", {"slot": 9})            # handle off (open fault: it was showing on)
	_click("terminal", {"slot": 9})
	_click("breaker", {"slot": 9})
	hands.bag.append("breaker20")
	_click("slot", {"slot": 9})
	_click("terminal", {"slot": 9})
	_click("breaker", {"slot": 9})
	_click("main")
	eq(p.check_repair(9), "ok")
	eq(view.work.arcs + view.work.shocks, 0)
	check(view._hint().begins_with("Check it reads right"), "hint: %s" % view._hint())


# --- Measuring --------------------------------------------------------------------

func test_measuring_target_voltage() -> void:
	_open_up()
	_probe("term_9", "neutral")
	is_true(view.work.measured_target)
	is_false(view.work.verified_dead, "it's live")
	check(view._readings[0].contains("121.2 V"), view._readings[0])


func test_probing_another_circuit_doesnt_count() -> void:
	_open_up()
	_probe("term_10", "neutral")
	is_false(view.work.measured_target)


func test_test_dead_needs_the_main_off() -> void:
	_open_up()
	_click("breaker", {"slot": 9})
	_probe("term_9", "neutral")
	is_false(view.work.verified_dead, "breaker off isn't proof: bus is live")
	_click("main")
	_probe("neutral", "term_9")
	is_true(view.work.verified_dead)


func test_test_dead_on_the_bus() -> void:
	_open_up()
	_click("main")
	_probe("bus_L1", "ground")
	is_true(view.work.verified_dead)


func test_clamping_the_target() -> void:
	_open_up()
	p.draw = {9: 8.4}
	ClampMeter.dial = ClampMeter.Mode.AMPS
	_click("clamp", {"id": "wire_10"})
	is_false(view.work.measured_amps)
	_click("clamp", {"id": "wire_9"})
	is_true(view.work.measured_amps)
	check(view._readings[0].contains("8.4 A"), view._readings[0])


func test_terminal_and_stab_points_follow_the_breaker() -> void:
	is_true(view._point_exists("term_9"))
	is_false(view._point_exists("stab_9"))
	p.pull(9)
	is_false(view._point_exists("term_9"))
	is_true(view._point_exists("stab_9"))
