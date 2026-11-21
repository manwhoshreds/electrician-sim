class_name ElectricalPanel
extends RefCounted
## The electrics of a 120/240 V split-phase house panel, with no graphics.
## L1 is a positive potential, L2 a negative one, neutral and ground are zero,
## so the voltage between any two points is just the difference. Two hots on
## opposite legs read about 240 V, a hot to neutral about 120 V.
##
## Slots are numbered like a real panel: odd down the left, even down the right.
## Each row alternates legs: rows 0, 2, 4... are L1, rows 1, 3, 5... are L2.
##
## Each slot's circuit is a Circuit: the wire in the wall plus the Breaker on
## it. Faults a breaker can have are in Breaker.Fault (open, weak, hot). And
## one that isn't the breaker's fault:
##   "overload"  a space heater's plugged in on the circuit as well, so the
##               customer's appliance on top of it goes over the rating.
##
## Current isn't made up: it's what's actually running. The house reports its
## lights, fridge, furnace and so on in `draw`; the customer runs an appliance
## when you ask (`demo`). Idle circuits read nothing.

signal tripped(slot: int)

const HOT_DROP := 24.0           # volts lost across burnt contacts
const HOT_CURRENT := 0.82        # the load draws less on the sagging voltage
const HEATER_AMPS := 12.5
## What the customer's appliances pull when they run one for you.
const APPLIANCE_AMPS := {"toaster": 9.2, "microwave": 10.5, "hair dryer": 12.5, "TV": 0.9, "space heater": 12.5, "freezer": 2.8,
		"kettle": 12.5, "coffee maker": 8.0, "vacuum": 6.0, "curling iron": 1.2,
		"range": 18.6, "fridge": 1.4, "washer": 8.0, "dryer": 22.0,
		"air handler": 4.6, "condenser": 14.2, "water heater": 18.75}

var main_on := true
var service_on := true           # is the meter in? Without it even the line lugs are dead
var main_rating := 100
var v1 := 121.2                  # L1 to neutral
var v2 := 119.6                  # L2 to neutral
var circuits: Array[Circuit] = []
var draw := {}                   # slot -> amps the house is pulling on its own
var demo := {}                   # "slot:appliance" -> seconds left on something the customer's running
## Breakers that tripped from plain overload (more running than the breaker's
## rated for), by slot, since this was last cleared: what was on, how much.
var overload_trips := {}


## A panel with these circuits on it, each with a fresh breaker sized to its
## wire. With none given, the standard house.
func _init(specs: Array[CircuitSpec] = []) -> void:
	if specs.is_empty():
		specs = CircuitSpec.standard_house()
	for s in specs:
		circuits.append(Circuit.new(s))


## How the panel was left, for the save file: the main and every circuit by
## slot. What the house and the customer are running isn't saved.
func to_save() -> Dictionary:
	var by_slot := {}
	for c in circuits:
		by_slot[str(c.slot)] = c.to_save()
	return {"main_on": main_on, "service_on": service_on, "circuits": by_slot}


func load_save(d: Dictionary) -> void:
	main_on = bool(d.get("main_on", true))
	service_on = bool(d.get("service_on", true))
	var by_slot: Dictionary = d.get("circuits", {})
	for c in circuits:
		if by_slot.has(str(c.slot)):
			c.load_save(by_slot[str(c.slot)])


## A standard house's panel, as a save file says it was left.
static func from_save(d: Dictionary) -> ElectricalPanel:
	var p := ElectricalPanel.new()
	p.load_save(d)
	return p


## Circuits with something on them big enough to trip a breaker.
func heavy_candidates(overload := false) -> Array[int]:
	var out: Array[int] = []
	for c in circuits:
		var amps: float = APPLIANCE_AMPS.get(c.appliance, 0.0)
		if amps >= 9.0 and not (overload and c.name == "Microwave"):   # nothing else goes on a microwave circuit
			out.append(c.slot)
	return out


## The customer runs an appliance on a circuit for a while: the circuit's own
## one if you don't say which.
func run_appliance(slot: int, seconds := 45.0, appliance := "") -> void:
	var c := circuit_at(slot)
	demo["%d:%s" % [c.slot, appliance if appliance != "" else c.appliance]] = seconds


func appliance_running(slot: int) -> bool:
	return _running_amps(circuit_at(slot).slot) > 0.0


func _running_amps(slot: int) -> float:
	var a := 0.0
	for key: String in demo:
		var at := key.find(":")
		if int(key.substr(0, at)) == slot:
			a += APPLIANCE_AMPS.get(key.substr(at + 1), 0.0)
	return a


func _overload(c: Circuit, a: float) -> OverloadTrip:
	var t := OverloadTrip.new()
	t.slot = c.slot
	t.amps = a
	t.rating = c.breaker.rating
	for key: String in demo:
		if key.begins_with("%d:" % c.slot) and APPLIANCE_AMPS.get(key.get_slice(":", 1), 0.0) > 0.0:
			t.appliances.append(key.get_slice(":", 1))
	if c.heater > 0.0:
		t.appliances.append("space heater")
	return t


func _stop_appliances(slot: int) -> void:
	for key: String in demo.keys():
		if key.begins_with("%d:" % slot):
			demo.erase(key)


## Breakers a customer could plausibly complain about.
func candidates() -> Array[int]:
	var out: Array[int] = []
	for c in circuits:
		if c.customer != "":
			out.append(c.slot)
	return out


## Sets up a job's fault: "open", "weak" or "hot" on the breaker, or
## "overload", which isn't the breaker at all.
func set_fault(slot: int, kind: String) -> void:
	var c := circuit_at(slot)
	if kind == "overload":
		c.heater = HEATER_AMPS           # not the breaker's fault at all
		c.breaker.tripped = true         # they were drying their hair: that's why they called
		return
	c.breaker.fault = Breaker.fault_named(kind)
	if c.breaker.fault == Breaker.Fault.WEAK:
		c.breaker.tripped = true


## The circuit occupying a slot (either pole of a two-pole), or null.
func circuit_at(slot: int) -> Circuit:
	for c in circuits:
		if slot in c.poles:
			return c
	return null


static func leg_of(slot: int) -> String:
	var row := int((slot - 1) / 2)
	return "L1" if row % 2 == 0 else "L2"


# --- Measurements -----------------------------------------------------------------

## Potential at a test point, or null if it's connected to nothing at all.
## Points: line_L1, line_L2, bus_L1, bus_L2, neutral, neutral2, ground,
## term_<slot>, stab_<slot>.
func potential(point: String) -> Variant:
	match point:
		"line_L1":
			return v1 if service_on else 0.0
		"line_L2":
			return -v2 if service_on else 0.0
		"bus_L1":
			return potential("line_L1") if main_on else 0.0
		"bus_L2":
			return potential("line_L2") if main_on else 0.0
		"neutral", "neutral2", "ground":   # the two neutral bars are strapped together
			return 0.0
	if point.begins_with("term_"):
		return _terminal(int(point.substr(5)))
	if point.begins_with("stab_"):         # the bare bus tab an empty slot exposes
		return potential("bus_" + leg_of(int(point.substr(5))))
	return null


func _terminal(slot: int) -> Variant:
	var c := circuit_at(slot)
	if c == null or not c.breaker.present:
		return null
	if not c.breaker.closed():
		# An open breaker's load side is held at neutral through the load in
		# the house, unless the wire's been taken off, and then it floats.
		return 0.0 if c.wire_landed else null
	var bus: float = potential("bus_" + leg_of(slot))
	if c.breaker.fault == Breaker.Fault.HOT and c.wire_landed and bus_live():
		return bus - signf(bus) * HOT_DROP
	return bus


## What a voltmeter reads between two points.
func voltage(a: String, b: String) -> float:
	var pa: Variant = potential(a)
	var pb: Variant = potential(b)
	if pa == null or pb == null:
		return 0.0
	return absf(float(pa) - float(pb))


func _amps(c: Circuit) -> float:
	if not bus_live() or not c.breaker.closed() or not c.wire_landed:
		return 0.0
	var a: float = draw.get(c.slot, 0.0) + c.heater + _running_amps(c.slot)
	return a * (HOT_CURRENT if c.breaker.fault == Breaker.Fault.HOT else 1.0)


## Customer's done what you asked: the space heater's moved to another circuit.
func move_heater(slot: int) -> bool:
	var c := circuit_at(slot)
	var had := c.heater > 0.0
	c.heater = 0.0
	return had


## What a clamp meter reads. Points: main_L1, main_L2, wire_<slot>.
func current(point: String) -> float:
	if point.begins_with("main_"):
		var leg := point.substr(5)
		var total := 0.0
		for c in circuits:
			for p in c.poles:
				if leg_of(p) == leg:
					total += _amps(c)
		return total
	if point.begins_with("wire_"):
		var c := circuit_at(int(point.substr(5)))
		return 0.0 if c == null else _amps(c)
	return 0.0


## Volts reaching the house on a circuit: what its lights and plugs actually get.
## A two-pole circuit reports one leg to neutral, like a 120 V clock on a range.
func circuit_volts(slot: int) -> float:
	var c := circuit_at(slot)
	if c == null or not c.breaker.present or not c.wire_landed:
		return 0.0
	var p: Variant = _terminal(c.poles[0])
	return absf(float(p)) if p != null else 0.0


## Signed potential on the load side of one pole of a breaker, out in the house:
## L1 positive, L2 negative, 0 when it's off or the wire's off the terminal.
func pole_potential(pole: int) -> float:
	var c := circuit_at(pole)
	if c == null or not c.breaker.present or not c.wire_landed:
		return 0.0
	var p: Variant = _terminal(pole)
	return float(p) if p != null else 0.0


## Would touching this breaker's terminal bite you?
func terminal_live(slot: int) -> bool:
	var p: Variant = _terminal(slot)
	return p != null and absf(float(p)) > 30.0


# --- Hands on the panel -----------------------------------------------------------

## Is there power on the bus? Needs the meter in and the main on.
func bus_live() -> bool:
	return main_on and service_on


func tick(delta: float) -> void:
	if not bus_live():
		return
	for slot in demo.keys():
		demo[slot] -= delta
		if demo[slot] <= 0.0:
			demo.erase(slot)
	for c in circuits:
		var a := _amps(c)
		var brk := c.breaker
		if a > brk.trip_amps() and a > 0.0:
			brk.over_t += delta
			if brk.over_t >= brk.trip_seconds():
				brk.tripped = true
				brk.over_t = 0.0
				if a > brk.rating:          # really too much, not just a worn breaker letting go early
					overload_trips[c.slot] = _overload(c, a)
				_stop_appliances(c.slot)
				tripped.emit(c.slot)
		else:
			brk.over_t = maxf(brk.over_t - delta, 0.0)


## Tripped goes to off, like resetting a real one: off first, then on.
func toggle(slot: int) -> void:
	circuit_at(slot).breaker.toggle()


## A short on the circuit: the breaker trips, if it was on.
func trip(slot: int) -> void:
	var c := circuit_at(slot)
	if c.breaker.closed():
		c.breaker.tripped = true
		tripped.emit(c.slot)


func toggle_main() -> void:
	main_on = not main_on


func set_wire(slot: int, landed: bool) -> void:
	circuit_at(slot).wire_landed = landed


func pull(slot: int) -> void:
	circuit_at(slot).breaker.present = false


## A new breaker goes in switched off, with the wire still to land.
func install(slot: int, rating: int) -> void:
	var c := circuit_at(slot)
	c.breaker.install(rating)
	c.wire_landed = false


## "ok", "oversize", "undersize", "not_fixed", "other_off" or "main_off".
func check_repair(target: int) -> String:
	if not bus_live():
		return "main_off"
	var t := circuit_at(target)
	var tb := t.breaker
	if not tb.present or not t.wire_landed or tb.fault != Breaker.Fault.NONE or not tb.on or tb.tripped or t.heater > 0.0:
		return "not_fixed"
	for c in circuits:
		if not c.breaker.present or not c.wire_landed or not c.breaker.on or c.breaker.tripped:
			return "other_off"
	if tb.rating > t.wire_rating:
		return "oversize"
	if tb.rating < t.wire_rating:
		return "undersize"
	return "ok"
