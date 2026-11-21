extends RefCounted
## Houses left in particular states, for pinning down what Aftercare does in
## the days after a job. Built only through ElectricalPanel's command methods
## (set_fault, toggle, install...), so the same scenarios run unchanged
## against any refactor of how the panel stores its state.
##
## Aftercare rolls dice, so each scenario is played under a range of seeds and
## the events it schedules are compared with a golden capture.

const SEEDS := 24
const GOLDEN := "res://tests/golden/aftercare_simulate.json"
const ADDRESS := "12 Test St"


static func names() -> Array[String]:
	return ["healthy", "weak_microwave_tripped", "weak_microwave_reset", "oversize_kitchen", "undersize_bathroom",
			"oversize_bedrooms", "living_room_off", "laundry_unwired", "overload_heater_left", "box_defects",
			"defects_with_oversize"]


static func panel(name: String) -> ElectricalPanel:
	var p := ElectricalPanel.new()
	match name:
		"weak_microwave_tripped":
			p.set_fault(10, "weak")
		"weak_microwave_reset":
			p.set_fault(10, "weak")
			p.toggle(10)
			p.toggle(10)
		"oversize_kitchen", "defects_with_oversize":
			_replace(p, 9, 30)
		"undersize_bathroom":
			_replace(p, 11, 15)
		"oversize_bedrooms":
			_replace(p, 13, 30)
		"living_room_off":
			p.toggle(12)
		"laundry_unwired":
			p.set_wire(14, false)
		"overload_heater_left":
			p.set_fault(13, "overload")
			p.toggle(13)
			p.toggle(13)
	return p


static func defects(name: String) -> Array:
	if name == "box_defects" or name == "defects_with_oversize":
		return [{"problem": "burnt_wire", "room": "kitchen", "word": "receptacle", "box": 2},
				{"problem": "miswired", "room": "bedroom", "word": "receptacle", "box": 5},
				{"problem": "no_gfci", "room": "bathroom", "word": "receptacle", "box": 7}]
	return []


static func _replace(p: ElectricalPanel, slot: int, rating: int) -> void:
	p.install(slot, rating)
	p.set_wire(slot, true)
	p.toggle(slot)


## What Aftercare schedules for one scenario under one seed, as JSON.
## Uses the tuning script's defaults, not the game's .tres, so tweaking the
## game's knobs doesn't break the golden capture. `tune` can change them.
static func play(name: String, s: int, tune := Callable()) -> String:
	var care := Aftercare.new()
	care.tuning = AftercareTuning.new()
	if tune.is_valid():
		tune.call(care.tuning)
	var p := panel(name)
	seed(s)
	care._simulate(ADDRESS, p, defects(name))
	var out := JSON.stringify(care._events)
	care.free()
	return out


## Every scenario under every seed: "name:seed" -> events JSON.
static func capture() -> Dictionary:
	var out := {}
	for name in names():
		for s in SEEDS:
			out["%s:%d" % [name, s]] = play(name, s)
	return out
