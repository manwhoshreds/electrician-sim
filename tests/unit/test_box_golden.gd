extends "res://tests/test_case.gd"
## Every box wiring scenario and repair flow, against the golden capture taken
## from the code before the device electrics moved out of BoxView.

# Loaded at run time, not preloaded: a preloaded script with an inner class
# extending a game class is reported as leaked at exit.
const SCENARIOS := "res://tests/support/box_scenarios.gd"


func test_matches_golden_capture() -> void:
	var scenarios: GDScript = load(SCENARIOS)
	var text := FileAccess.get_file_as_string(scenarios.GOLDEN)
	check(text != "", "golden file missing: run tests/tools/capture_box_golden.gd on the reference code")
	if text == "":
		return
	var golden: Dictionary = JSON.parse_string(text)
	var lib: Node3D = (load(HouseInterior.LIBRARY) as PackedScene).instantiate()
	var s: RefCounted = scenarios.new(tree.root, lib)
	var now: Dictionary = s.capture()
	lib.free()
	eq(now.size(), golden.size(), "scenario count")
	var shown := 0
	for key: String in golden:
		if now.get(key, "") != golden[key]:
			shown += 1
			if shown <= 5:
				failures.append(_diff(key, golden[key], now.get(key, "<missing>")))
	if shown > 5:
		failures.append("...and %d more scenarios differ" % (shown - 5))


## The first observation that differs, not the whole scenario.
static func _diff(key: String, was: String, now: String) -> String:
	var a: Variant = JSON.parse_string(was)
	var b: Variant = JSON.parse_string(now)
	if a is Array and b is Array:
		for i in mini(a.size(), b.size()):
			if JSON.stringify(a[i]) != JSON.stringify(b[i]):
				return "%s, step %d\n              was: %s\n              now: %s" % [key, i, JSON.stringify(a[i]), JSON.stringify(b[i])]
	return "%s\n              was: %s\n              now: %s" % [key, was.left(300), now.left(300)]
