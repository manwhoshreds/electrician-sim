extends "res://tests/test_case.gd"
## Characterization tests for ElectricalPanel: they pin down what the panel
## does today, so it can be refactored without changing gameplay. Where a test
## pins behaviour that looks questionable, it says so with "QUIRK" rather
## than quietly fixing it.

const L1 := 121.2
const L2 := 119.6
const HOT_DROP := 24.0

var p: ElectricalPanel


func before_each() -> void:
	p = ElectricalPanel.new()


## Steps the panel in exact half-second ticks.
func _run(seconds: float) -> void:
	for i in int(round(seconds / 0.5)):
		p.tick(0.5)


## A tripped breaker resets like a real one: off first, then on.
func _reset(slot: int) -> void:
	p.toggle(slot)
	p.toggle(slot)


func _b(slot: int) -> Circuit:
	return p.circuit_at(slot)


# --- Layout and content ------------------------------------------------------------

func test_panel_has_the_twelve_circuits() -> void:
	eq(p.circuits.size(), 12, "breaker count")
	var slots: Array = p.circuits.map(func(b: Circuit) -> int: return b.slot)
	eq(slots, [1, 2, 5, 6, 9, 10, 11, 12, 13, 14, 15, 16], "slots")


func test_new_panel_is_healthy_and_matched_to_its_wire() -> void:
	for b in p.circuits:
		eq(b.wire_rating, b.breaker.rating, "%s wire rating" % b.name)
		is_true(b.breaker.closed(), "%s closed" % b.name)
		is_true(b.wire_landed and b.breaker.present, "%s wired and present" % b.name)
		eq(b.breaker.fault, Breaker.Fault.NONE, "%s fault" % b.name)
	is_true(p.main_on and p.service_on and p.bus_live(), "main and service on")
	eq(p.main_rating, 100)


func test_ratings_of_each_circuit() -> void:
	var expect := {1: 40, 2: 30, 5: 30, 6: 30, 9: 20, 10: 20, 11: 20, 12: 15, 13: 15, 14: 20, 15: 15, 16: 15}
	for slot: int in expect:
		eq(_b(slot).breaker.rating, expect[slot], "slot %d rating" % slot)


func test_customer_candidates() -> void:
	eq(p.candidates(), [9, 10, 11, 12, 13, 14] as Array[int])


func test_heavy_candidates_exclude_microwave_for_overload() -> void:
	eq(p.heavy_candidates(false), [9, 10, 11, 13] as Array[int], "weak candidates")
	eq(p.heavy_candidates(true), [9, 11, 13] as Array[int], "overload candidates")


func test_breaker_at_resolves_either_pole_of_a_two_pole() -> void:
	is_true(_b(3) == _b(1), "pole 3 belongs to the range")
	eq(_b(3).name, "Range")
	eq(_b(8).name, "A/C")
	is_true(_b(17) == null, "nothing at slot 17")


func test_legs_alternate_by_row() -> void:
	var expect := {1: "L1", 2: "L1", 3: "L2", 4: "L2", 5: "L1", 6: "L1", 7: "L2", 8: "L2",
			9: "L1", 10: "L1", 11: "L2", 12: "L2", 13: "L1", 14: "L1", 15: "L2", 16: "L2"}
	for slot: int in expect:
		eq(ElectricalPanel.leg_of(slot), expect[slot], "slot %d leg" % slot)


# --- Split-phase voltage -------------------------------------------------------------

func test_split_phase_line_voltages() -> void:
	near(p.voltage("line_L1", "neutral"), L1, "L1-N")
	near(p.voltage("line_L2", "neutral"), L2, "L2-N")
	near(p.voltage("line_L1", "line_L2"), L1 + L2, "L1-L2")
	near(p.voltage("bus_L1", "bus_L2"), L1 + L2, "bus L1-L2")
	near(p.voltage("line_L1", "bus_L1"), 0.0, "same leg")


func test_signs_of_the_legs() -> void:
	near(float(p.potential("line_L1")), L1, "L1 positive")
	near(float(p.potential("line_L2")), -L2, "L2 negative")


func test_neutrals_and_ground_are_zero_and_bonded() -> void:
	for a in ["neutral", "neutral2", "ground"]:
		eq(p.potential(a), 0.0, a)
	near(p.voltage("neutral", "ground"), 0.0)
	near(p.voltage("neutral2", "neutral"), 0.0)
	near(p.voltage("line_L1", "ground"), L1)


func test_terminals_read_their_leg() -> void:
	near(p.voltage("term_9", "neutral"), L1, "slot 9 on L1")
	near(p.voltage("term_11", "neutral"), L2, "slot 11 on L2")
	near(p.voltage("term_9", "term_11"), L1 + L2, "opposite legs")
	near(p.voltage("term_9", "term_10"), 0.0, "same leg")


func test_two_pole_spans_both_legs() -> void:
	near(p.voltage("term_1", "term_3"), L1 + L2, "range pole to pole")
	near(p.pole_potential(1), L1)
	near(p.pole_potential(3), -L2)
	near(p.circuit_volts(1), L1, "two-pole reports its first pole")
	near(p.circuit_volts(5), L1)


func test_main_off_kills_bus_but_not_line() -> void:
	p.toggle_main()
	is_false(p.main_on)
	is_false(p.bus_live())
	near(p.voltage("line_L1", "neutral"), L1, "line lugs still live")
	near(p.voltage("bus_L1", "neutral"), 0.0, "bus dead")
	near(p.voltage("term_9", "neutral"), 0.0, "terminal dead")
	near(p.circuit_volts(9), 0.0)
	is_false(p.terminal_live(9))
	p.toggle_main()
	is_true(p.bus_live(), "main back on")


func test_meter_pulled_kills_everything() -> void:
	p.service_on = false
	near(p.voltage("line_L1", "line_L2"), 0.0, "line lugs dead")
	near(p.voltage("term_9", "neutral"), 0.0)
	is_false(p.bus_live())


func test_bus_stab_reads_the_bus() -> void:
	near(p.voltage("stab_9", "neutral"), L1)
	near(p.voltage("stab_11", "neutral"), L2)
	p.toggle_main()
	near(p.voltage("stab_9", "neutral"), 0.0)


func test_unknown_or_floating_points_read_zero() -> void:
	eq(p.potential("bogus"), null)
	eq(p.potential("term_17"), null, "no breaker there")
	near(p.voltage("bogus", "neutral"), 0.0)


func test_terminal_live_threshold() -> void:
	is_true(p.terminal_live(9))
	p.toggle(9)
	is_false(p.terminal_live(9), "off breaker")


# --- Breaker states ------------------------------------------------------------------

func test_toggle_cycles_on_and_off() -> void:
	p.toggle(9)
	is_false(_b(9).breaker.on)
	is_false(_b(9).breaker.closed())
	p.toggle(9)
	is_true(_b(9).breaker.on)
	is_true(_b(9).breaker.closed())


func test_tripped_breaker_resets_to_off_first() -> void:
	p.trip(9)
	is_true(_b(9).breaker.tripped)
	is_true(_b(9).breaker.on, "handle still says on")
	is_false(_b(9).breaker.closed())
	p.toggle(9)
	is_false(_b(9).breaker.tripped, "reset clears the trip")
	is_false(_b(9).breaker.on, "...and leaves it off")
	p.toggle(9)
	is_true(_b(9).breaker.closed())


func test_trip_only_acts_on_a_closed_breaker_and_signals() -> void:
	var heard: Array[int] = []
	p.tripped.connect(func(slot: int) -> void: heard.append(slot))
	p.toggle(9)
	p.trip(9)
	is_false(_b(9).breaker.tripped, "an off breaker can't trip")
	eq(heard, [] as Array[int])
	p.toggle(9)
	p.trip(9)
	eq(heard, [9] as Array[int])


func test_two_pole_toggles_through_either_pole() -> void:
	p.toggle(3)
	is_false(_b(1).breaker.on)
	near(p.voltage("term_1", "term_3"), 0.0)


func test_off_breaker_terminal_held_at_neutral_through_load() -> void:
	p.toggle(9)
	eq(p.potential("term_9"), 0.0, "held at neutral with the wire on")
	p.set_wire(9, false)
	eq(p.potential("term_9"), null, "floats with the wire off")


func test_main_breaker_does_not_change_branch_handles() -> void:
	p.toggle_main()
	is_true(_b(9).breaker.on)
	is_true(_b(9).breaker.closed(), "closed() is about the breaker, not the bus")


# --- Faults --------------------------------------------------------------------------

func test_open_fault_looks_on_but_is_dead() -> void:
	p.set_fault(9, "open")
	is_true(_b(9).breaker.on, "handle on")
	is_false(_b(9).breaker.tripped, "not tripped")
	is_false(_b(9).breaker.closed())
	eq(p.potential("term_9"), 0.0, "load side at neutral")
	near(p.circuit_volts(9), 0.0)
	p.draw = {9: 5.0}
	near(p.current("wire_9"), 0.0)


func test_open_fault_survives_reset() -> void:
	p.set_fault(9, "open")
	_reset(9)
	is_false(_b(9).breaker.closed())
	near(p.circuit_volts(9), 0.0)


func test_hot_fault_drops_voltage_under_power() -> void:
	p.set_fault(9, "hot")
	near(p.circuit_volts(9), L1 - HOT_DROP, "L1 sag")
	near(float(p.potential("term_9")), L1 - HOT_DROP)
	p.set_fault(11, "hot")
	near(p.circuit_volts(11), L2 - HOT_DROP, "L2 sag")
	near(float(p.potential("term_11")), -(L2 - HOT_DROP), "sag is towards zero")


func test_hot_fault_no_drop_with_wire_off() -> void:
	p.set_fault(9, "hot")
	p.set_wire(9, false)
	near(float(p.potential("term_9")), L1, "no load, no drop")


func test_hot_fault_draws_less_current() -> void:
	p.set_fault(9, "hot")
	p.draw = {9: 10.0}
	near(p.current("wire_9"), 10.0 * ElectricalPanel.HOT_CURRENT)


func test_weak_fault_starts_tripped() -> void:
	p.set_fault(9, "weak")
	eq(_b(9).breaker.fault, Breaker.Fault.WEAK)
	is_true(_b(9).breaker.tripped)


func test_weak_breaker_trips_at_forty_percent_after_two_seconds() -> void:
	p.set_fault(9, "weak")
	_reset(9)
	p.run_appliance(9)                      # toaster, 9.2 A over a 20 A x 0.4 = 8 A limit
	_run(1.5)
	is_false(_b(9).breaker.tripped, "holds for under two seconds")
	_run(0.5)
	is_true(_b(9).breaker.tripped, "lets go at two seconds")


func test_weak_breaker_holds_under_its_reduced_limit() -> void:
	p.set_fault(9, "weak")
	_reset(9)
	p.draw = {9: 7.9}
	_run(10.0)
	is_false(_b(9).breaker.tripped)


func test_weak_kitchen_trips_on_house_draw_alone() -> void:
	# QUIRK: the house's normal 8.4 A on the kitchen is over a weak breaker's 8 A.
	p.set_fault(9, "weak")
	_reset(9)
	p.draw = {9: 8.4}
	_run(2.0)
	is_true(_b(9).breaker.tripped)


func test_healthy_breaker_holds_the_same_appliance() -> void:
	p.run_appliance(9)
	_run(10.0)
	is_false(_b(9).breaker.tripped)


func test_overload_adds_heater_and_trips_but_breaker_is_fine() -> void:
	p.set_fault(9, "overload")
	eq(_b(9).breaker.fault, Breaker.Fault.NONE, "not the breaker's fault")
	near(_b(9).heater, ElectricalPanel.HEATER_AMPS)
	is_true(_b(9).breaker.tripped)


func test_overload_heater_alone_holds() -> void:
	p.set_fault(9, "overload")
	_reset(9)
	near(p.current("wire_9"), 12.5)
	_run(10.0)
	is_false(_b(9).breaker.tripped)


func test_overload_heater_plus_appliance_trips_after_four_seconds() -> void:
	p.set_fault(9, "overload")
	_reset(9)
	p.run_appliance(9)
	near(p.current("wire_9"), 12.5 + 9.2)
	_run(3.5)
	is_false(_b(9).breaker.tripped, "holds under four seconds")
	_run(0.5)
	is_true(_b(9).breaker.tripped, "trips at four")


func test_move_heater_clears_overload_once() -> void:
	p.set_fault(9, "overload")
	is_true(p.move_heater(9), "there was a heater")
	near(_b(9).heater, 0.0)
	is_false(p.move_heater(9), "nothing left to move")
	is_false(p.move_heater(10), "never had one")


# --- Appliances and thermal trips ----------------------------------------------------

func test_run_appliance_defaults_to_the_circuits_own() -> void:
	p.run_appliance(11)
	is_true(p.appliance_running(11))
	near(p.current("wire_11"), 12.5, "hair dryer")


func test_named_appliances_stack() -> void:
	p.run_appliance(9, 30.0, "toaster")
	p.run_appliance(9, 30.0, "kettle")
	near(p.current("wire_9"), 9.2 + 12.5)


func test_appliance_runs_out() -> void:
	p.run_appliance(9, 2.0)
	_run(1.5)
	is_true(p.appliance_running(9))
	_run(0.5)
	is_false(p.appliance_running(9))
	near(p.current("wire_9"), 0.0)


func test_unknown_appliance_draws_nothing() -> void:
	p.run_appliance(9, 30.0, "flux capacitor")
	is_false(p.appliance_running(9))


func test_thermal_trip_on_a_healthy_breaker() -> void:
	var heard: Array[int] = []
	p.tripped.connect(func(slot: int) -> void: heard.append(slot))
	p.draw = {12: 16.0}                     # 15 A living room
	_run(3.5)
	is_false(_b(12).breaker.tripped)
	_run(0.5)
	is_true(_b(12).breaker.tripped)
	eq(heard, [12] as Array[int])
	near(p.current("wire_12"), 0.0, "tripped carries nothing")


func test_trip_stops_that_circuits_appliances_only() -> void:
	p.set_fault(9, "overload")
	_reset(9)
	p.run_appliance(9)
	p.run_appliance(11)
	_run(4.0)
	is_true(_b(9).breaker.tripped)
	is_false(p.appliance_running(9), "kitchen's toaster stopped")
	is_true(p.appliance_running(11), "bathroom unaffected")


func test_over_time_drains_when_current_drops() -> void:
	p.set_fault(9, "overload")
	_reset(9)
	p.run_appliance(9, 3.0)                 # over the limit for 2.5 s, then expires
	_run(3.0)
	is_false(_b(9).breaker.tripped)
	near(_b(9).breaker.over_t, 2.0, "2.5 s over, then 0.5 s draining")
	p.run_appliance(9)
	_run(1.5)
	is_false(_b(9).breaker.tripped)
	_run(0.5)
	is_true(_b(9).breaker.tripped, "carried-over heat trips it sooner")


func test_dead_bus_freezes_timers_and_appliances() -> void:
	p.run_appliance(9, 1.0)
	p.toggle_main()
	_run(5.0)
	is_true(p.demo.has("9:toaster"), "countdown frozen")
	p.toggle_main()
	_run(1.0)
	is_false(p.demo.has("9:toaster"))


# --- Current measurements ------------------------------------------------------------

func test_branch_current_sums_draw_heater_and_appliances() -> void:
	p.set_fault(13, "overload")
	_reset(13)
	p.draw = {13: 2.6}
	p.run_appliance(13, 30.0, "curling iron")
	near(p.current("wire_13"), 2.6 + 12.5 + 1.2)


func test_idle_circuits_read_nothing() -> void:
	for b in p.circuits:
		near(p.current("wire_%d" % b.slot), 0.0, b.name)
	near(p.current("main_L1"), 0.0)


func test_main_legs_sum_their_poles() -> void:
	p.draw = {5: 18.6, 9: 8.4, 11: 6.2}
	near(p.current("main_L1"), 18.6 + 8.4, "water heater pole + kitchen")
	near(p.current("main_L2"), 18.6 + 6.2, "water heater pole + bathroom")


func test_clamping_either_pole_of_a_two_pole() -> void:
	p.draw = {5: 18.6}
	near(p.current("wire_5"), 18.6)
	near(p.current("wire_7"), 18.6)


func test_current_zero_when_cut_off() -> void:
	p.draw = {9: 8.0}
	p.set_wire(9, false)
	near(p.current("wire_9"), 0.0, "wire off")
	p.set_wire(9, true)
	p.toggle(9)
	near(p.current("wire_9"), 0.0, "breaker off")
	p.toggle(9)
	p.toggle_main()
	near(p.current("wire_9"), 0.0, "main off")
	p.toggle_main()
	p.service_on = false
	near(p.current("wire_9"), 0.0, "meter out")


func test_unknown_clamp_points() -> void:
	near(p.current("wire_17"), 0.0)
	near(p.current("bogus"), 0.0)


# --- Wire removal and breaker replacement ---------------------------------------------

func test_wire_off_kills_the_circuit_but_not_the_terminal() -> void:
	p.set_wire(9, false)
	near(p.circuit_volts(9), 0.0, "house side dead")
	near(p.pole_potential(9), 0.0)
	near(p.voltage("term_9", "neutral"), L1, "terminal still live: breaker's on")
	is_true(p.terminal_live(9))


func test_pulled_breaker_floats() -> void:
	p.toggle_main()
	p.pull(9)
	is_false(_b(9).breaker.present)
	eq(p.potential("term_9"), null)
	is_false(_b(9).breaker.closed())
	p.toggle_main()
	near(p.circuit_volts(9), 0.0)
	near(p.voltage("stab_9", "neutral"), L1, "the bare tab is live once the main's on")


func test_install_resets_the_breaker() -> void:
	p.set_fault(9, "weak")
	p.pull(9)
	p.install(9, 15)
	var b := _b(9)
	is_true(b.breaker.present)
	eq(b.breaker.rating, 15)
	eq(b.wire_rating, 20, "the wire in the wall doesn't change")
	is_false(b.breaker.on)
	is_false(b.breaker.tripped)
	eq(b.breaker.fault, Breaker.Fault.NONE)
	is_false(b.wire_landed, "wire still to land")


func test_install_keeps_a_space_heater() -> void:
	# QUIRK: swapping the breaker doesn't unplug the heater.
	p.set_fault(9, "overload")
	p.install(9, 20)
	near(_b(9).heater, 12.5)


func test_full_replacement_brings_the_circuit_back() -> void:
	p.set_fault(9, "open")
	p.toggle_main()
	p.toggle(9)
	p.set_wire(9, false)
	p.pull(9)
	p.install(9, 20)
	p.set_wire(9, true)
	p.toggle(9)
	p.toggle_main()
	near(p.circuit_volts(9), L1)
	eq(p.check_repair(9), "ok")


# --- Repair validation ---------------------------------------------------------------

func _replace(slot: int, rating: int) -> void:
	p.install(slot, rating)
	p.set_wire(slot, true)
	p.toggle(slot)


func test_untouched_panel_is_ok() -> void:
	for slot in p.candidates():
		eq(p.check_repair(slot), "ok", "slot %d" % slot)


func test_main_off_reported_first() -> void:
	p.set_fault(9, "open")
	p.toggle_main()
	eq(p.check_repair(9), "main_off")
	p.toggle_main()
	p.service_on = false
	eq(p.check_repair(9), "main_off", "meter out")


func test_unfixed_faults_are_not_fixed() -> void:
	for kind in ["open", "weak", "hot", "overload"]:
		before_each()
		p.set_fault(9, kind)
		if kind == "weak" or kind == "overload":
			_reset(9)
		eq(p.check_repair(9), "not_fixed", kind)


func test_target_left_off_or_unwired_is_not_fixed() -> void:
	p.toggle(9)
	eq(p.check_repair(9), "not_fixed", "off")
	before_each()
	p.trip(9)
	eq(p.check_repair(9), "not_fixed", "tripped")
	before_each()
	p.set_wire(9, false)
	eq(p.check_repair(9), "not_fixed", "wire off")
	before_each()
	p.pull(9)
	eq(p.check_repair(9), "not_fixed", "pulled")


func test_other_circuit_off_is_reported() -> void:
	p.toggle(12)
	eq(p.check_repair(9), "other_off", "other off")
	before_each()
	p.trip(16)
	eq(p.check_repair(9), "other_off", "other tripped")
	before_each()
	p.set_wire(5, false)
	eq(p.check_repair(9), "other_off", "other unwired")
	before_each()
	p.pull(14)
	eq(p.check_repair(9), "other_off", "other pulled")


func test_not_fixed_beats_other_off() -> void:
	p.set_fault(9, "open")
	p.toggle(12)
	eq(p.check_repair(9), "not_fixed")


func test_other_breakers_faults_are_not_checked() -> void:
	# Only the target's fault counts: another bad-but-on breaker passes.
	p.set_fault(12, "open")
	eq(p.check_repair(9), "ok")


func test_matching_replacement_is_ok() -> void:
	p.set_fault(9, "hot")
	_replace(9, 20)
	eq(p.check_repair(9), "ok")


func test_oversized_breaker() -> void:
	p.set_fault(9, "open")
	_replace(9, 30)
	eq(p.check_repair(9), "oversize")
	near(p.circuit_volts(9), L1, "it works, dangerously")


func test_undersized_breaker() -> void:
	p.set_fault(9, "open")
	_replace(9, 15)
	eq(p.check_repair(9), "undersize")


func test_other_off_beats_oversize() -> void:
	_replace(9, 30)
	p.toggle(12)
	eq(p.check_repair(9), "other_off")


func test_replacement_left_off_is_not_fixed() -> void:
	p.set_fault(9, "open")
	p.install(9, 20)
	p.set_wire(9, true)
	eq(p.check_repair(9), "not_fixed", "new breaker goes in off")


func test_replacing_doesnt_fix_an_overload() -> void:
	p.set_fault(9, "overload")
	_replace(9, 20)
	eq(p.check_repair(9), "not_fixed", "heater's still there")
	p.move_heater(9)
	eq(p.check_repair(9), "ok")


func test_advising_on_overload_without_replacing_is_ok() -> void:
	p.set_fault(9, "overload")
	p.move_heater(9)
	_reset(9)
	eq(p.check_repair(9), "ok")


func test_weak_breaker_reset_still_not_fixed() -> void:
	p.set_fault(9, "weak")
	_reset(9)
	eq(p.check_repair(9), "not_fixed", "fault stays until the breaker's swapped")
	_replace(9, 20)
	eq(p.check_repair(9), "ok")


# --- Overload trips -----------------------------------------------------------------------

func test_an_overload_trip_says_what_was_running() -> void:
	p.run_appliance(9, 35.0, "toaster")
	p.run_appliance(9, 35.0, "kettle")
	_run(4.0)
	is_true(_b(9).breaker.tripped)
	is_true(p.overload_trips.has(9))
	var t: OverloadTrip = p.overload_trips[9]
	near(t.amps, 21.7)
	eq(t.rating, 20)
	eq(t.appliances, ["toaster", "kettle"] as Array[String])
	eq(t.what_was_running(), "the toaster and the kettle together")


func test_a_weak_breaker_letting_go_isnt_an_overload() -> void:
	p.set_fault(11, "weak")
	_reset(11)
	p.run_appliance(11)                     # hair dryer, 12.5 A on a 20 A breaker
	_run(2.0)
	is_true(_b(11).breaker.tripped)
	is_false(p.overload_trips.has(11), "the breaker's at fault, not the load")


func test_a_space_heater_counts_as_running() -> void:
	p.set_fault(13, "overload")
	_reset(13)
	p.run_appliance(13, 30.0, "hair dryer")
	_run(4.0)
	eq((p.overload_trips[13] as OverloadTrip).appliances, ["hair dryer", "space heater"] as Array[String])
