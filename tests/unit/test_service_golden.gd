extends "res://tests/test_case.gd"
## A seeded run of the job loop (dispatch, conversation, invoices, job sheets,
## truck and supply house), against the golden capture taken before ServiceCall
## was split up.

# Loaded at run time: see tests/tools/capture_service_golden.gd.
const SCENARIOS := "res://tests/support/service_scenarios.gd"


func test_matches_golden_capture() -> void:
	var scenarios: GDScript = load(SCENARIOS)
	var text := FileAccess.get_file_as_string(scenarios.GOLDEN)
	check(text != "", "golden file missing: run tests/tools/capture_service_golden.gd on the reference code")
	if text == "":
		return
	var golden: Dictionary = JSON.parse_string(text)
	var now: Dictionary = scenarios.new(tree).capture()
	eq(now.size(), golden.size(), "entry count")
	var shown := 0
	for key: String in golden:
		if now.get(key, "") != golden[key]:
			shown += 1
			if shown <= 4:
				failures.append(_diff(key, JSON.parse_string(golden[key]), JSON.parse_string(now.get(key, "null"))))
	if shown > 4:
		failures.append("...and %d more entries differ" % (shown - 4))


## The first part of an entry that differs.
static func _diff(path: String, was: Variant, now: Variant) -> String:
	if was is Dictionary and now is Dictionary:
		for k: String in was:
			if JSON.stringify(was[k]) != JSON.stringify(now.get(k)):
				return _diff("%s.%s" % [path, k], was[k], now.get(k))
	if was is Array and now is Array and was.size() == now.size():
		for i in was.size():
			if JSON.stringify(was[i]) != JSON.stringify(now[i]):
				return _diff("%s[%d]" % [path, i], was[i], now[i])
	return "%s\n              was: %s\n              now: %s" % [path, JSON.stringify(was).left(400), JSON.stringify(now).left(400)]
