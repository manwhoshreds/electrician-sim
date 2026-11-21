class_name WaterHeater
extends RefCounted
## An electric tank water heater, as an electrician meets one: 240 V in on
## the top screws of the upper thermostat, through the high-limit (ECO), and
## the two thermostats taking turns. The upper one heats the top of the tank
## first; only when that's hot does it hand the power down to the lower one.
## So a burnt-out upper element means no hot water at all, and a burnt-out
## lower one means a little, that runs out fast.
##
## Its own disconnect on the wall beside it: pull the handle out and the
## heater's dead, whatever the breaker's doing. The line side of it (from the
## panel) stays live.
##
## Test points, for the meter (volts with the power on, ohms with it off):
##   "dl1", "dl2"    the disconnect's line lugs, from the panel: always live with the breaker on
##   "l1", "l2"      the supply on the upper thermostat's top screws
##   "u_a", "u_b"    the upper element's two screws
##   "lo_a", "lo_b"  the lower element's two screws
##   "tank"          bare metal: the tank, which is grounded
##
## The tank: shut the cold off, put a garden hose on the drain and run it
## outside, and open the drain to bring the water down below an element before
## you take it out. Power an element that's out of the water and it burns out
## in seconds ("dry fire").
##
## Get it wrong and the water goes on the floor: the drain open with no hose
## on it, or an element out with water above the hole (and with the cold still
## on, the street's pressure behind it). Enough on the floor and it's a flood
## ("flood" in events).

## Which of the two: "upper" or "lower".
const ELEMENTS: Array[String] = ["upper", "lower"]
## A good 4500 W element at 240 V.
const ELEMENT_OHMS := 12.8
const ELEMENT_AMPS := 18.75
## Where each element sits, as a share of the tank's height: the water has to
## be above it before it's safe to power, and below it to unscrew it.
const ELEMENT_LEVEL := {"upper": 0.73, "lower": 0.33}
## Game seconds to drain the tank down, and to fill it back up.
const DRAIN_SECONDS := 50.0
const FILL_SECONDS := 35.0
## Game seconds for a tank's worth to pour out of an element's hole.
const HOLE_SECONDS := 8.0
## How much on the floor, as a share of the tank, before it's a flood.
const FLOOD := 0.08
## Game seconds for each half of the tank to heat up from cold.
const HEAT_SECONDS := 90.0
const FAULTS: Array[String] = ["upper_element", "lower_element", "eco"]

## Each element: "ok", "open" (burnt out) or "out" (unscrewed).
var element := {"upper": "ok", "lower": "ok"}
## Each element's wires on its screws.
var wired := {"upper": true, "lower": true}
var eco_tripped := false
## How hot the top and bottom of the tank are, 0 cold to 1 up to temperature.
var heat_top := 1.0
var heat_bottom := 1.0
## Water in the tank, 0 empty to 1 full.
var level := 1.0
var cold_open := true
var drain_open := false
## The disconnect's pull-out handle, in (on) or out (off).
var disconnect_in := true
## A garden hose on the drain, run outside: what comes out of it goes in the yard.
var hose := false
## Water on the floor so far, as a share of the tank, and whether it's a flood yet.
var spilled := 0.0
var flooded := false
var cover_on := {"upper": true, "lower": true}
## The panel it's on, and its breaker's two poles. With a panel, the supply
## comes from it; without one (a bench test), from leg1 and leg2.
var panel: ElectricalPanel
const POLES := [5, 7]
## The supply's two legs (signed volts to ground) when there's no panel: L1
## positive, L2 negative, 0 when the breaker's off.
var leg1 := 0.0
var leg2 := 0.0
## Things that happened, for the close-up to show: "dry_fire:upper"...
var events: Array[String] = []


## Breaks it the way a job says.
func set_fault(fault: String) -> void:
	match fault:
		"upper_element":
			element["upper"] = "open"
			heat_top = 0.0
			heat_bottom = 0.0
		"lower_element":
			element["lower"] = "open"
			heat_top = 1.0
			heat_bottom = 0.0
		"eco":
			eco_tripped = true
			heat_top = 0.0
			heat_bottom = 0.0


## What's coming from the panel to the disconnect.
func _supply(i: int) -> float:
	if panel != null:
		return panel.pole_potential(POLES[i])
	return leg1 if i == 0 else leg2


## What gets past the disconnect to the heater.
func _leg(i: int) -> float:
	return _supply(i) if disconnect_in else 0.0


func powered() -> bool:
	return absf(_leg(0)) > 60.0 and absf(_leg(1)) > 60.0


## Which element the thermostats are calling for heat on, or "".
func calling() -> String:
	if heat_top < 1.0:
		return "upper"
	if heat_bottom < 1.0:
		return "lower"
	return ""


## Is this element getting 240 V right now?
func element_live(which: String) -> bool:
	return powered() and not eco_tripped and calling() == which and wired[which]


## Is this element heating water: live, good, and in the water?
func heating(which: String) -> bool:
	return element_live(which) and element[which] == "ok"


## Amps the heater's pulling off its breaker.
func amps() -> float:
	return ELEMENT_AMPS if heating("upper") or heating("lower") else 0.0


func tick(delta: float) -> void:
	if cold_open and not drain_open:
		level = minf(level + delta / FILL_SECONDS, 1.0)
	elif drain_open and not cold_open:
		level = maxf(level - delta / DRAIN_SECONDS, 0.0)
	# Out of the drain (with the cold on it just runs through): outside down the
	# hose, or across the floor without one.
	if drain_open and not hose and (cold_open or level > 0.0):
		_spill(delta / DRAIN_SECONDS)
	# Out of an empty element hole, down to the hole, or for as long as the cold's on.
	for which in ELEMENTS:
		if element[which] == "out" and (cold_open or level > ELEMENT_LEVEL[which]):
			var out := delta / HOLE_SECONDS
			if not cold_open:
				out = minf(out, level - ELEMENT_LEVEL[which])
				level -= out
			_spill(out)
	for which in ELEMENTS:
		if heating(which) and level < ELEMENT_LEVEL[which]:
			element[which] = "open"        # dry fire: it glows and burns through in seconds
			events.append("dry_fire:" + which)
	# Fresh cold water coming in cools the tank off.
	if level < 1.0:
		heat_top = 0.0
		heat_bottom = 0.0
	if heating("upper"):
		heat_top = minf(heat_top + delta / HEAT_SECONDS, 1.0)
	elif heating("lower"):
		heat_bottom = minf(heat_bottom + delta / HEAT_SECONDS, 1.0)


## Can this element come out without water pouring out of the hole?
func can_unscrew(which: String) -> bool:
	return level < ELEMENT_LEVEL[which] - 0.05


## Out it comes, wires off first. Under water, it comes out anyway, and the
## water follows it (see tick).
func unscrew(which: String) -> bool:
	if wired[which] or element[which] == "out":
		return false
	element[which] = "out"
	return true


## Water coming out of this element's empty hole right now.
func pouring(which: String) -> bool:
	return element[which] == "out" and (cold_open or level > ELEMENT_LEVEL[which])


## Water coming out of the drain onto the floor (no hose on it) right now.
func drain_spilling() -> bool:
	return drain_open and not hose and (cold_open or level > 0.0)


func _spill(amount: float) -> void:
	spilled += amount
	if spilled >= FLOOD and not flooded:
		flooded = true
		events.append("flood")


## A new element in the hole.
func fit(which: String) -> bool:
	if element[which] != "out":
		return false
	element[which] = "ok"
	return true


func reset_eco() -> void:
	eco_tripped = false


## Hot water at the taps, and nothing left open: the job's done.
func fixed() -> bool:
	return element["upper"] == "ok" and element["lower"] == "ok" and wired["upper"] and wired["lower"] \
			and not eco_tripped and level >= 1.0 and cold_open and not drain_open and powered()


## Covers on, so nobody can touch the screws.
func buttoned_up() -> bool:
	return cover_on["upper"] and cover_on["lower"]


# --- The meter ---------------------------------------------------------------------------

## Signed volts at a test point, or null if it's connected to nothing live.
func potential(point: String) -> Variant:
	match point:
		"tank":
			return 0.0
		"dl1":
			return _supply(0)
		"dl2":
			return _supply(1)
		"l1":
			return _leg(0)
		"l2":
			return _leg(1)
	var which := "upper" if point.begins_with("u_") else "lower"
	if not wired[which]:
		return null
	# Side B of each element comes straight off L2 through the ECO; side A
	# from L1 through the ECO and the thermostat, when it's calling for that one.
	var b: Variant = _leg(1) if not eco_tripped else null
	var a: Variant = _leg(0) if not eco_tripped and calling() == which else null
	# A good element joins its two screws: a dead side sits at the live side's
	# voltage through it.
	if element[which] == "ok":
		if a == null:
			a = b
		elif b == null:
			b = a
	return a if point.ends_with("_a") else b


## What a voltmeter reads between two points.
func voltage(p: String, q: String) -> float:
	var a: Variant = potential(p)
	var b: Variant = potential(q)
	if a == null or b == null:
		return 0.0
	return absf(float(a) - float(b))


## Is there anything that could bite you on this point?
func is_live(point: String) -> bool:
	return voltage(point, "tank") > 30.0


## What an ohmmeter reads between two points: -1.0 for open (OL).
func ohms(p: String, q: String) -> float:
	for which in ELEMENTS:
		var pair := ["u_a", "u_b"] if which == "upper" else ["lo_a", "lo_b"]
		if p in pair and q in pair and p != q:
			return ELEMENT_OHMS if element[which] == "ok" else -1.0
	return -1.0


## Which element a test point's on, or "".
static func element_of(point: String) -> String:
	if point.begins_with("u_"):
		return "upper"
	if point.begins_with("lo_"):
		return "lower"
	return ""


func to_save() -> Dictionary:
	return {"element": element.duplicate(), "wired": wired.duplicate(), "eco_tripped": eco_tripped, "heat_top": heat_top,
		"heat_bottom": heat_bottom, "level": level, "cold_open": cold_open, "drain_open": drain_open, "cover_on": cover_on.duplicate(),
		"hose": hose, "spilled": spilled, "flooded": flooded, "disconnect_in": disconnect_in}


func load_save(d: Dictionary) -> void:
	for which in ELEMENTS:
		element[which] = String(d.get("element", {}).get(which, "ok"))
		wired[which] = bool(d.get("wired", {}).get(which, true))
		cover_on[which] = bool(d.get("cover_on", {}).get(which, true))
	eco_tripped = bool(d.get("eco_tripped", false))
	heat_top = float(d.get("heat_top", 1.0))
	heat_bottom = float(d.get("heat_bottom", 1.0))
	level = float(d.get("level", 1.0))
	cold_open = bool(d.get("cold_open", true))
	drain_open = bool(d.get("drain_open", false))
	hose = bool(d.get("hose", false))
	disconnect_in = bool(d.get("disconnect_in", true))
	spilled = float(d.get("spilled", 0.0))
	flooded = bool(d.get("flooded", false))
