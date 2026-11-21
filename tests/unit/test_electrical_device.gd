extends "res://tests/test_case.gd"
## The device electrics on their own: no scene, no nodes, no clicking. Each
## device sits on a real ElectricalPanel and is worked on through its commands.
## Slot 12 and 11 are on L2 (119.6 V), 13 on L1 (121.2 V), 1+3 the range.

const L1 := 121.2
const L2 := 119.6

var p: ElectricalPanel


func before_each() -> void:
	p = ElectricalPanel.new()


func _dev(kind: String, slot: int, role := "") -> ElectricalDevice:
	return ElectricalDevice.new(kind, p, slot, role)


## Plate off, unscrewed from the box, pulled out.
func _open_up(d: ElectricalDevice) -> void:
	for i in d.plate_screws.size():
		d.remove_plate_screw(i)
	for i in d.mount_screws.size():
		if d.mount_screws[i]:
			d.toggle_mount_screw(i)
	d.pull_out()


## Pushed back, screwed down, plate on.
func _put_back(d: ElectricalDevice) -> void:
	d.push_in()
	for i in d.mount_screws.size():
		d.toggle_mount_screw(i)
	d.refit_plate()


## Every wire off, old device out, new one in, every wire landed where `to` says.
func _swap(d: ElectricalDevice, new_kind: String, to: Dictionary) -> String:
	for w: String in d.wires:
		d.loosen(w)
	d.remove_device()
	var why := d.install(new_kind)
	if why != "":
		return why
	for w: String in to:
		d.land(w, to[w])
	return ""


# --- Receptacle ---------------------------------------------------------------------

func test_receptacle_wired_right() -> void:
	var d := _dev("Receptacle", 12)
	near(d.face_volts(), L2)
	eq(d.tester_lights(), [true, true, false])
	eq(d.repair_state(), "ok")
	is_false(d.shorted())


func test_receptacle_breaker_off_is_dead() -> void:
	var d := _dev("Receptacle", 12)
	p.toggle(12)
	near(d.face_volts(), 0.0)
	eq(d.tester_lights(), [false, false, false])
	eq(d.repair_state(), "dead")


func test_receptacle_open_conductors() -> void:
	var d := _dev("Receptacle", 12)
	d.loosen("hot")
	eq(d.tester_lights(), [false, false, false], "open hot: nothing lights")
	eq(d.repair_state(), "dead")
	d = _dev("Receptacle", 12)
	d.loosen("neutral")
	eq(d.tester_lights(), [true, false, false], "open neutral")
	eq(d.repair_state(), "miswired", "it lights the tester, but it's not right")
	near(d.face_volts(), 0.0, "nothing to run a lamp on")
	d = _dev("Receptacle", 12)
	d.loosen("ground")
	eq(d.tester_lights(), [false, true, false], "open ground")
	eq(d.repair_state(), "miswired")
	near(d.face_volts(), L2, "a lamp still works without the ground")


func test_receptacle_hot_and_neutral_reversed() -> void:
	var d := _dev("Receptacle", 12)
	p.toggle(12)                   # live, the first wire moved would meet the other: a short
	d.land("hot", "silver_top")
	d.land("neutral", "brass_top")
	p.toggle(12)
	is_false(d.poll_short(), "swapped, but nothing's shorted")
	eq(d.tester_lights(), [false, true, true], "middle + red")
	near(d.face_volts(), L2, "a lamp works: that's why it's dangerous")
	eq(d.repair_state(), "miswired")


func test_receptacle_bottom_screws_are_the_same() -> void:
	var d := _dev("Receptacle", 12)
	d.land("hot", "brass_bottom")
	d.land("neutral", "silver_bottom")
	eq(d.repair_state(), "ok")


func test_receptacle_hot_on_ground_shorts() -> void:
	var d := _dev("Receptacle", 12)
	p.toggle(12)
	d.loosen("hot")
	is_false(d.land("hot", "green"), "no bang with the breaker off")
	is_true(d.shorted())
	is_false(d.poll_short(), "nothing live yet")
	p.toggle(12)
	is_true(d.poll_short(), "breaker on: bang")
	is_true(p.circuit_at(12).breaker.tripped)
	is_false(d.poll_short(), "once per bang")
	p.toggle(12)
	p.toggle(12)
	is_true(d.poll_short(), "reset it onto the short: bang again")


func test_landing_a_live_hot_on_neutral_trips() -> void:
	var d := _dev("Receptacle", 12)
	d.loosen("neutral")
	is_true(d.land("neutral", "brass_bottom"), "neutral onto the hot screw, live")
	is_true(p.circuit_at(12).breaker.tripped)


func test_receptacle_scorched_and_burnt_wire() -> void:
	var d := _dev("Receptacle", 12)
	d.set_fault("scorched")
	eq(d.repair_state(), "dead", "contacts burnt open")
	is_true(d.burnt["hot"])
	_open_up(d)
	eq(_swap(d, "Receptacle", {"hot": "brass_top", "neutral": "silver_top", "ground": "green"}), "")
	_put_back(d)
	eq(d.repair_state(), "burnt_wire", "new device, same cooked wire")
	_open_up(d)
	d.loosen("hot")
	is_true(d.strip("hot"))
	is_false(d.strip("hot"), "already clean")
	d.land("hot", "brass_top")
	_put_back(d)
	eq(d.repair_state(), "ok")


func test_receptacle_loose_backstab() -> void:
	var d := _dev("Receptacle", 12)
	d.set_fault("loose")
	eq(d.wires["hot"], "back_hot")
	eq(d.repair_state(), "dead", "the backstab let go")
	_open_up(d)
	d.loosen("hot")
	d.land("hot", "brass_top")
	_put_back(d)
	eq(d.repair_state(), "ok", "onto the screw instead")


func test_not_put_back_together_is_open() -> void:
	var d := _dev("Receptacle", 12)
	d.remove_plate_screw(0)
	eq(d.repair_state(), "open", "plate off")
	d.refit_plate()
	d.pull_out()
	eq(d.repair_state(), "open", "hanging out of the wall")
	d.push_in()
	eq(d.repair_state(), "open", "pushed in, not screwed down")
	d.toggle_mount_screw(0)
	d.toggle_mount_screw(1)
	eq(d.repair_state(), "ok")


func test_live_bare_wire() -> void:
	var d := _dev("Receptacle", 12)
	is_true(d.live_bare("hot"))
	is_false(d.live_bare("neutral"), "neutral never bites")
	p.toggle(12)
	is_false(d.live_bare("hot"))


func test_probing() -> void:
	var d := _dev("Receptacle", 12)
	near(d.voltage("face_hot", "face_neutral"), L2)
	near(d.voltage("face_hot", "face_ground"), L2)
	near(d.voltage("term_brass_top", "term_silver_top"), L2)
	near(d.voltage("wire_hot", "wire_neutral"), L2)
	near(d.voltage("bogus", "face_neutral"), 0.0)
	is_true(d.is_hot_point("wire_hot"))
	is_true(d.is_hot_point("term_brass_top"), "the hot's on it")
	is_false(d.is_hot_point("term_silver_top"))
	is_false(d.is_hot_point("face_neutral"))


# --- GFCI --------------------------------------------------------------------------

func test_gfci_test_and_reset() -> void:
	var d := _dev("GFCI", 11)
	eq(d.repair_state(), "ok")
	is_true(d.test_gfci())
	is_true(d.gfci_tripped)
	near(d.face_volts(), 0.0, "tripped: face is dead")
	eq(d.repair_state(), "dead")
	is_false(d.test_gfci(), "already tripped")
	eq(d.reset_gfci(), "reset")
	near(d.face_volts(), L2)
	eq(d.reset_gfci(), "not_tripped")


func test_gfci_protects_its_load_screws() -> void:
	# The LOAD screws feed outlets downstream: a tripped GFCI cuts them too.
	var d := _dev("GFCI", 11)
	near(d.voltage("term_load_brass", "term_load_silver"), L2, "closed: passes power on")
	d.test_gfci()
	near(d.voltage("term_load_brass", "term_load_silver"), 0.0, "tripped: cut off")
	near(d.voltage("term_line_brass", "term_line_silver"), L2, "LINE side's still live")


func test_gfci_wont_reset_without_line_power() -> void:
	var d := _dev("GFCI", 11)
	d.test_gfci()
	p.toggle(11)
	eq(d.reset_gfci(), "no_line")
	is_true(d.gfci_tripped)


func test_bad_gfci_wont_latch() -> void:
	var d := _dev("GFCI", 11)
	d.set_fault("bad_gfci")
	is_true(d.gfci_tripped)
	eq(d.reset_gfci(), "bad")
	eq(d.repair_state(), "dead")
	_open_up(d)
	eq(_swap(d, "GFCI", {"hot": "line_brass", "neutral": "line_silver", "ground": "green"}), "")
	is_true(d.gfci_tripped, "new ones come out of the box tripped")
	_put_back(d)
	eq(d.reset_gfci(), "reset")
	eq(d.repair_state(), "ok")


func test_gfci_fed_on_its_load_screws_is_dead() -> void:
	var d := _dev("GFCI", 11)
	d.land("hot", "load_brass")
	d.land("neutral", "load_silver")
	near(d.face_volts(), 0.0)
	d.test_gfci()
	eq(d.reset_gfci(), "no_line", "LINE screws have nothing")
	eq(d.repair_state(), "dead")


# --- Range receptacle -------------------------------------------------------------------

func test_range_wired_right() -> void:
	var d := _dev("Range", 1)
	is_true(d.range_good())
	near(d.voltage("face_x", "face_y"), L1 + L2, "240 across")
	near(d.face_volts(), L1, "120 to neutral, for the clock")
	eq(d.tester_lights(), [false, false, false], "a plug tester doesn't fit")
	eq(d.repair_state(), "ok")


func test_range_loose_lug() -> void:
	var d := _dev("Range", 1)
	d.set_fault("loose_lug")
	is_false(d.range_good(), "half dead: no Y leg")
	near(d.face_volts(), L1, "the clock still works")
	eq(d.repair_state(), "dead")
	is_false(d.tighten("x"), "not that one")
	is_true(d.tighten("y"))
	eq(d.repair_state(), "ok")


func test_range_both_legs_on_one_lug_shorts() -> void:
	var d := _dev("Range", 1)
	d.land("x", "y_lug")
	is_true(d.shorted())
	is_true(p.circuit_at(1).breaker.tripped, "landed live: the two legs met")


func test_range_scorched() -> void:
	var d := _dev("Range", 1)
	d.set_fault("scorched")
	is_true(d.burnt["x"])
	eq(d.repair_state(), "dead")


# --- Switches and lights -----------------------------------------------------------------

## A ceiling light fed from a wall switch, both on the bedroom circuit.
func _light() -> Array[ElectricalDevice]:
	var f := _dev("Fixture", 13)
	var s := _dev("Switch", 13)
	f.feed = s
	return [s, f]


func test_switch_works_the_light() -> void:
	var pair := _light()
	var s := pair[0]
	var f := pair[1]
	near(f.lamp_volts(), L1)
	eq(s.repair_state(), "ok")
	eq(f.repair_state(), "ok")
	is_true(s.flip())
	near(f.lamp_volts(), 0.0)
	s.flip()
	near(f.lamp_volts(), L1)


func test_switch_cant_flip_pulled_out() -> void:
	var s := _dev("Switch", 13)
	s.pull_out()
	is_false(s.flip())
	is_true(s.switch_on)


func test_worn_switch() -> void:
	var pair := _light()
	pair[0].set_fault("worn")
	near(pair[1].lamp_volts(), 0.0)
	eq(pair[0].repair_state(), "dead")
	_open_up(pair[0])
	eq(_swap(pair[0], "Switch", {"line": "s_top", "load": "s_bottom", "ground": "green"}), "")
	_put_back(pair[0])
	eq(pair[0].repair_state(), "ok")
	near(pair[1].lamp_volts(), L1)


func test_loose_switch_screw() -> void:
	var pair := _light()
	pair[0].set_fault("loose_screw")
	near(pair[1].lamp_volts(), 0.0)
	eq(pair[0].repair_state(), "dead")
	is_true(pair[0].tighten("line"))
	near(pair[1].lamp_volts(), L1)


func test_switch_both_wires_on_one_screw() -> void:
	var pair := _light()
	pair[0].land("load", "s_top")
	eq(pair[0].repair_state(), "miswired")
	pair[0].flip()
	near(pair[1].lamp_volts(), L1, "the light never goes off")


func test_fixture_faults() -> void:
	var pair := _light()
	pair[1].set_fault("scorched")
	near(pair[1].lamp_volts(), 0.0)
	eq(pair[1].repair_state(), "dead")
	pair = _light()
	pair[1].set_fault("loose_nut")
	near(pair[1].lamp_volts(), 0.0)
	eq(pair[1].repair_state(), "dead")
	is_true(pair[1].tighten("hot"))
	eq(pair[1].repair_state(), "ok")


func test_fixture_without_a_switch_is_dark() -> void:
	near(_dev("Fixture", 13).lamp_volts(), 0.0)


func test_dimmer() -> void:
	var pair := _light()
	_open_up(pair[0])
	eq(_swap(pair[0], "Dimmer", {"line": "s_top", "load": "s_bottom", "ground": "green"}), "")
	_put_back(pair[0])
	eq(pair[0].repair_state(), "ok")
	eq(pair[0].light_scale(), 1.0)
	pair[0].slide_dimmer()
	eq(pair[0].light_scale(), 0.6)
	pair[0].slide_dimmer()
	eq(pair[0].light_scale(), 0.3)
	pair[0].slide_dimmer()
	eq(pair[0].light_scale(), 1.0, "and back to the top")
	eq(_dev("Switch", 13).light_scale(), 1.0, "a plain switch is always full")


func test_fan_goes_in_a_light_box() -> void:
	var pair := _light()
	_open_up(pair[1])
	eq(_swap(pair[1], "Fan", {"hot": "nut_black", "neutral": "nut_white", "ground": "f_ground"}), "")
	_put_back(pair[1])
	eq(pair[1].kind, "Fan")
	eq(pair[1].repair_state(), "ok")
	near(pair[1].lamp_volts(), L1)


# --- Three-way switches ---------------------------------------------------------------

## Two 3-ways and the light: [line end, load end, fixture], on the living room circuit.
func _three_way() -> Array[ElectricalDevice]:
	var f := _dev("Fixture", 12)
	var a := _dev("ThreeWay", 12, "line")
	var b := _dev("ThreeWay", 12, "load")
	a.partner = b
	b.partner = a
	f.feed = b
	return [a, b, f]


func test_three_way_works_from_either_end() -> void:
	var t := _three_way()
	for a_on in [true, false]:
		for b_on in [true, false]:
			t[0].switch_on = a_on
			t[1].switch_on = b_on
			near(t[2].lamp_volts(), L2 if a_on == b_on else 0.0, "a %s, b %s" % [a_on, b_on])
	eq(t[0].repair_state(), "ok")
	eq(t[1].repair_state(), "ok")


func test_worn_three_way_only_works_from_the_other_end() -> void:
	var t := _three_way()
	t[0].set_fault("worn")
	eq(t[0].repair_state(), "dead")
	for a_on in [true, false]:
		t[0].switch_on = a_on
		t[1].switch_on = true
		near(t[2].lamp_volts(), L2, "stuck: only the far switch does anything")
		t[1].switch_on = false
		near(t[2].lamp_volts(), 0.0)


func test_three_way_travelers_on_one_screw() -> void:
	var t := _three_way()
	t[0].land("t2", "trav_a")
	eq(t[0].repair_state(), "miswired")


func test_three_way_only_takes_a_three_way() -> void:
	var t := _three_way()
	_open_up(t[0])
	eq(_swap(t[0], "Switch", {}), "three_way_mismatch")
	eq(t[0].install("ThreeWay"), "")
	var s := _dev("Switch", 13)
	s.remove_device()
	eq(s.install("ThreeWay"), "three_way_mismatch", "and the other way round")


func test_line_end_of_a_three_way_has_no_load() -> void:
	# Used to crash in BoxView: the line end has no load wire.
	near(_three_way()[0].load_potential(), 0.0)
	near(_three_way()[0].face_volts(), 0.0)


# --- Installing -------------------------------------------------------------------------

func test_install_checks_what_youre_holding() -> void:
	var d := _dev("Receptacle", 12)
	d.remove_device()
	eq(d.install(""), "nothing")
	eq(d.install("Battery9V"), "not_a_device")
	eq(d.install("Range"), "wrong_family")
	eq(d.install("Switch"), "wrong_family")
	eq(d.kind, "", "still empty")
	eq(d.install("GFCI"), "", "a GFCI goes where a receptacle was")
	is_true(d.pulled_out and not d.mounted, "in your hand, not screwed in yet")


func test_empty_box() -> void:
	var d := _dev("Receptacle", 12)
	d.remove_device()
	eq(d.repair_state(), "empty")
	near(d.face_volts(), 0.0)


func test_taking_apart_a_loose_connection_clears_it() -> void:
	var s := _dev("Switch", 13)
	s.set_fault("loose_screw")
	s.loosen("line")
	eq(s.condition, "", "re-made when it goes back on")


# --- Junction boxes ---------------------------------------------------------------------

## Panel -> up -> j -> receptacle, on the bedroom circuit.
func _chain() -> Array[ElectricalDevice]:
	var up := _dev("JBox", 13)
	var j := _dev("JBox", 13)
	j.junction = up
	var r := _dev("Receptacle", 13)
	r.junction = j
	return [up, j, r]


func test_junction_passes_power_on() -> void:
	var c := _chain()
	is_true(c[0].ok() and c[1].ok())
	near(c[2].face_volts(), L1)
	eq(c[1].repair_state(), "ok")


func test_bad_splice_kills_everything_after_it() -> void:
	var c := _chain()
	c[1].set_fault("bad_splice")
	is_false(c[1].ok())
	is_true(c[0].ok(), "upstream's fine")
	near(c[2].face_volts(), 0.0, "the outlet past it is dead")
	eq(c[2].repair_state(), "dead")
	eq(c[1].repair_state(), "dead")


func test_bad_splice_upstream_too() -> void:
	var c := _chain()
	c[0].set_fault("bad_splice")
	is_false(c[1].ok(), "a good box past a bad one isn't fed")
	near(c[2].face_volts(), 0.0)


func test_remaking_a_bad_splice() -> void:
	var c := _chain()
	var j := c[1]
	j.set_fault("bad_splice")
	_open_up(j)
	j.loosen("hot")
	j.loosen("hot_out")
	eq(j.condition, "", "taking it apart clears the bad nut")
	j.land("hot", "nut_hot")
	j.land("hot_out", "nut_hot")
	_put_back(j)
	eq(j.repair_state(), "burnt_wire", "cooked ends still on")
	_open_up(j)
	j.loosen("hot")
	j.loosen("hot_out")
	j.strip("hot")
	j.strip("hot_out")
	j.land("hot", "nut_hot")
	j.land("hot_out", "nut_hot")
	_put_back(j)
	eq(j.repair_state(), "ok")
	near(c[2].face_volts(), L1)


# --- Smoke detectors --------------------------------------------------------------------

func test_smoke_detector_healthy() -> void:
	var d := _dev("Smoke", 13)
	d.made = 2024
	is_false(d.chirping())
	eq(d.repair_state(), "ok")
	is_true(d.power_led())


func test_smoke_low_battery() -> void:
	var d := _dev("Smoke", 13)
	d.made = 2024
	d.battery_low = true
	is_true(d.chirping())
	eq(d.repair_state(), "dead")
	d.twist()
	eq(d.repair_state(), "open")
	d.toggle_battery_door()
	d.remove_battery()
	is_true(d.chirping(), "no battery chirps too")
	d.insert_battery()
	d.toggle_battery_door()
	d.twist()
	eq(d.repair_state(), "ok")


func test_smoke_expired() -> void:
	var d := _dev("Smoke", 13)
	d.made = 2012
	is_true(d.expired())
	is_true(d.chirping())
	d.remove_battery()
	d.insert_battery()
	is_true(d.chirping(), "a fresh battery doesn't help an old one")
	d.twist()
	d.unplug_harness()
	eq(d.repair_state(), "dead", "off its harness")
	d.take_down_detector()
	d.fit_new_detector()
	eq(d.made, ElectricalDevice.THIS_YEAR)
	is_true(d.plugged)
	d.twist()
	eq(d.repair_state(), "ok")


func test_smoke_power_light() -> void:
	var d := _dev("Smoke", 13)
	p.toggle(13)
	is_false(d.power_led(), "breaker off")
	p.toggle(13)
	var j := _dev("JBox", 13)
	d.junction = j
	is_true(d.power_led())
	j.set_fault("bad_splice")
	is_false(d.power_led(), "bad splice upstream")


func test_new_smoke_detector_has_no_plate() -> void:
	var d := _dev("Smoke", 13)
	is_false(d.plate_on)
	eq(d.plate_screws, [])
	eq(d.mount_screws, [])


# --- Remembering a house ------------------------------------------------------------------

func test_snapshot_and_restore() -> void:
	var d := _dev("Receptacle", 12)
	d.set_fault("scorched")
	_open_up(d)
	d.loosen("hot")
	var saved := d.snapshot()
	var again := _dev("Receptacle", 12)
	again.restore(saved)
	eq(again.snapshot(), saved)
	eq(again.wires["hot"], "")
	is_true(again.burnt["hot"])
	is_true(again.pulled_out)
	d.wires["neutral"] = ""
	eq(again.wires["neutral"], "silver_top", "a copy, not shared")


func test_three_way_partners_dont_leak() -> void:
	var t := _three_way()
	var a: WeakRef = weakref(t[0])
	t.clear()
	is_true(a.get_ref() == null, "two partners pointing at each other still get freed")


# --- Data and view agree ----------------------------------------------------------------------

func test_every_terminal_has_a_place_on_the_model() -> void:
	for kind: String in BoxView.SPEC:
		var model_terms: Array = BoxView.SPEC[kind]["terms"].keys()
		eq(model_terms, Array(DeviceSpec.of(kind).terms), kind)
		for w: String in DeviceSpec.of(kind).wires:
			is_true(BoxView.WIRE_NAME.has(w) and BoxView.WIRE_COLOUR.has(w), "%s wire %s has a look" % [kind, w])
