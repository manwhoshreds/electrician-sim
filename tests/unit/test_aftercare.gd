extends "res://tests/test_case.gd"
## Characterization of what Aftercare makes of a house after you leave:
## callbacks, inspections and fires, under fixed seeds, against a golden
## capture taken before the Phase 2 refactor. Plus the parts that don't
## depend on the dice.

const Scenarios := preload("res://tests/support/aftercare_scenarios.gd")


func _events(name: String, s: int) -> Array:
	return JSON.parse_string(Scenarios.play(name, s))


func test_matches_golden_capture() -> void:
	var text := FileAccess.get_file_as_string(Scenarios.GOLDEN)
	check(text != "", "golden file missing: run tests/tools/capture_golden.gd on the reference code")
	if text == "":
		return
	var golden: Dictionary = JSON.parse_string(text)
	var now := Scenarios.capture()
	eq(now.size(), golden.size(), "scenario count")
	for key: String in golden:
		if now.get(key, "") != golden[key]:
			failures.append("%s\n              was: %s\n              now: %s" % [key, golden[key], now.get(key, "<missing>")])


func test_breaker_left_off_calls_back_the_same_day() -> void:
	# Whatever else the dice do, a dead customer circuit is noticed on day 0.
	for s in Scenarios.SEEDS:
		var ev := _events("laundry_unwired", s)
		var calls := ev.filter(func(e: Dictionary) -> bool: return e["kind"] == "callback")
		eq(calls.size(), 1, "seed %d: one callback per house" % s)
		eq(calls[0]["due"], 0.0, "seed %d: day 0" % s)


func test_weak_breaker_always_calls_back() -> void:
	for s in Scenarios.SEEDS:
		var ev := _events("weak_microwave_reset", s)
		is_true(ev.any(func(e: Dictionary) -> bool: return e["kind"] == "callback" and e["why"] == "trip"), "seed %d" % s)


func test_oversize_is_a_violation_only_inspections_see() -> void:
	var inspected := 0
	for s in Scenarios.SEEDS:
		for e: Dictionary in _events("oversize_kitchen", s):
			if e["kind"] == "inspection":
				inspected += 1
				eq(e["violations"], ["30 A breaker on 20 A wire (Kitchen counter)"], "seed %d" % s)
	is_true(inspected > 0 and inspected < Scenarios.SEEDS, "inspections are a dice roll (%d of %d)" % [inspected, Scenarios.SEEDS])


func test_undersize_on_a_20_amp_required_circuit_is_a_violation() -> void:
	var seen := false
	for s in Scenarios.SEEDS:
		for e: Dictionary in _events("undersize_bathroom", s):
			if e["kind"] == "inspection":
				seen = true
				eq(e["violations"], ["15 A breaker on a 20 A required circuit (Bathroom)"])
	is_true(seen)


func _with_good_work_percent(percent: float) -> Callable:
	return func(t: AftercareTuning) -> void: t.good_work_callback_percent = percent


func test_healthy_house_never_inspected_or_burns() -> void:
	for s in Scenarios.SEEDS:
		for e: Dictionary in _events("healthy", s):
			check(e["kind"] == "callback" and e["why"] == "trip", "seed %d: only trip callbacks, got %s" % [s, e])


func test_good_work_never_called_back_at_zero_percent() -> void:
	for s in Scenarios.SEEDS:
		eq(Scenarios.play("healthy", s, _with_good_work_percent(0.0)), "[]", "seed %d" % s)


func test_good_work_always_called_back_at_hundred_percent() -> void:
	for s in Scenarios.SEEDS:
		var ev: Array = JSON.parse_string(Scenarios.play("healthy", s, _with_good_work_percent(100.0)))
		eq(ev.size(), 1, "seed %d: exactly one callback" % s)
		if ev.size() == 1:
			eq(ev[0]["why"], "trip")
			is_true(ev[0]["target"] in [9.0, 10.0, 11.0, 12.0, 13.0, 14.0], "a circuit they'd phone about")
			is_true(ev[0]["due"] >= 0.0 and ev[0]["due"] < 3.0, "within the days played")


func test_good_work_percent_is_roughly_honoured() -> void:
	var called := 0
	var runs := 400
	for s in runs:
		if Scenarios.play("healthy", 1000 + s, _with_good_work_percent(25.0)) != "[]":
			called += 1
	var percent := 100.0 * called / runs
	is_true(percent > 18.0 and percent < 32.0, "25%% asked, got %.1f%%" % percent)


func test_mistakes_still_get_the_real_day() -> void:
	# The good-work knob at 0 doesn't hide your own mistakes.
	for s in Scenarios.SEEDS:
		var ev: Array = JSON.parse_string(Scenarios.play("weak_microwave_reset", s, _with_good_work_percent(0.0)))
		is_true(ev.any(func(e: Dictionary) -> bool: return e["why"] == "trip" and e["target"] == 10.0), "seed %d: weak breaker trips" % s)
	var heater_trips := 0
	for s in Scenarios.SEEDS:
		var ev: Array = JSON.parse_string(Scenarios.play("overload_heater_left", s, _with_good_work_percent(0.0)))
		if ev.any(func(e: Dictionary) -> bool: return e["why"] == "trip" and e["target"] == 13.0):
			heater_trips += 1
	is_true(heater_trips > 0, "heater left on the bedrooms trips some days (%d of %d)" % [heater_trips, Scenarios.SEEDS])


func test_game_uses_the_tuning_file() -> void:
	var care := Aftercare.new()
	is_true(care.tuning.resource_path == "res://data/aftercare_tuning.tres")
	care.free()


func test_every_day_you_can_set_has_words() -> void:
	# The days-played slider goes to 7; every day needs a "when" for the story.
	for day in 8:
		is_true(Aftercare._when(day) != "", "day %d" % day)
	eq(Aftercare._when(0), "this morning")
	eq(Aftercare._when(6), "last week")


func test_a_long_week_of_callbacks_doesnt_crash() -> void:
	for s in Scenarios.SEEDS:
		var ev: Array = JSON.parse_string(Scenarios.play("weak_microwave_reset", s, func(t: AftercareTuning) -> void:
				t.days_played = 7
				t.good_work_callback_percent = 100.0))
		is_true(ev.all(func(e: Dictionary) -> bool: return e["kind"] != "callback" or (e["story"] as String) != ""), "seed %d" % s)
