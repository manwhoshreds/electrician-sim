class_name ElectricalDevice
extends RefCounted
## One electrical box in the house and what's in it, with no graphics: a
## receptacle, GFCI, range receptacle, switch, dimmer, 3-way, light fixture,
## ceiling fan, junction box or smoke detector.
##
## Potentials are signed like ElectricalPanel's: L1 positive, L2 negative,
## neutral and ground zero. A device gets its power from its circuit's breaker,
## or through the boxes it hangs off:
##   feed      a light fixture's switch: the fixture's hot is its load wire
##   partner   the other 3-way at the far end of the travelers
##   junction  the attic junction box it's spliced through, if any
##   source    a new outlet's: the outlet its cable was fished back to. Its
##             power comes off that outlet's spare screws (hot_out, neutral_out,
##             ground_out), so it's only as good as the work done there.
##
## Each wire is on a terminal ("" if it's free). Terminals inside a device are
## tied together onto buses (BUS): a duplex's two brass screws are both "H".
## A closed switch ties its two screws together.
##
## Conditions a device can be in (the job faults):
##   loose        backstabbed hot let go          loose_lug / loose_screw / loose_nut
##   scorched     contacts burnt open             bad_gfci     won't hold a reset
##   worn         switch contacts dead            bad_splice   junction's nut let go

const HOT_WIRES := ["hot", "x", "y", "line", "load", "t1", "t2", "hot_out"]
## Wires heading away from the box: they carry what the box gives them, never a source.
const OUTPUTS := ["load", "hot_out", "neutral_out", "ground_out"]
const DIM_STEPS := [1.0, 0.6, 0.3]
## The wire a "loose" fault leaves sitting slack on its screw, for each fault.
const LOOSE_WIRE := {"loose_lug": "y", "loose_screw": "line", "loose_nut": "hot", "bad_splice": "hot_out"}
## Which terminals are tied together inside the device.
const BUS := {"brass_top": "H", "brass_bottom": "H", "back_hot": "H", "silver_top": "N", "silver_bottom": "N", "back_neutral": "N",
	"green": "G", "line_brass": "LH", "line_silver": "LN", "load_brass": "OH", "load_silver": "ON",
	"x_lug": "X", "y_lug": "Y", "w_lug": "N", "g_lug": "G", "s_top": "S1", "s_bottom": "S2",
	"nut_black": "FH", "nut_white": "FN", "f_ground": "G", "trav_a": "TA", "trav_b": "TB", "common": "C",
	"nut_hot": "JH", "nut_neutral": "JN", "nut_ground": "G"}
## Where each wire's supposed to go: the buses that are right for it.
const RIGHT_BUS := {"hot": ["H", "LH", "FH", "JH"], "x": ["X", "Y"], "y": ["X", "Y"], "neutral": ["N", "LN", "FN", "JN"], "ground": ["G"],
	"hot_out": ["JH", "H", "FH"], "neutral_out": ["JN", "N", "FN"], "ground_out": ["G"],
	"line": ["S1", "S2", "C"], "load": ["S1", "S2", "C"], "t1": ["TA", "TB"], "t2": ["TA", "TB"]}
## A plug tester on a correctly wired outlet: both yellows, no red.
const CORRECT := [true, true, false]
const SMOKE_LIFE := 10
const THIS_YEAR := 2026
## Every field the house remembers between visits (see snapshot()).
const SAVED := ["kind", "condition", "wires", "burnt", "gfci_tripped", "switch_on", "dim", "plate_on", "plate_kind", "plate_screws",
	"mounted", "mount_screws", "pulled_out", "battery_low", "made", "battery_in", "plugged", "door_open"]

# --- Where it is in the house -------------------------------------------------------
var panel: ElectricalPanel
var slot := 0                    # the breaker it's on
var three_way_role := ""         # for a 3-way: "line" (fed from the panel) or "load" (feeds the light)
var feed: ElectricalDevice       # for a light fixture: the switch it hangs off
var junction: ElectricalDevice   # the junction box in the attic this is fed through, if any
var source: ElectricalDevice     # a new outlet: the outlet its cable runs back to
## For a 3-way: the switch at the other end of the travelers. The two point at
## each other, so it's held weakly: otherwise neither would ever be freed.
var partner: ElectricalDevice:
	get:
		return _partner.get_ref() as ElectricalDevice if _partner != null else null
	set(v):
		_partner = weakref(v) if v != null else null
var _partner: WeakRef

# --- What's in the box ----------------------------------------------------------------
var original := ""               # what the box was built for
var kind := ""                   # what's in the box now, "" when it's empty
var family := ""                 # what the box is wired for: see DeviceSpec.family
var condition := ""              # "" or one of the faults above
var wires := {}                  # wire -> the terminal it's on, "" if free
var burnt := {}                  # wire -> true if its end is cooked
var gfci_tripped := false
var switch_on := true
var dim := 1.0                   # for a dimmer: how far up the slider is
# A smoke detector: hardwired, a 9 V for backup, interconnected with the others.
var battery_low := false
var made := 2021                 # the date on the side
var battery_in := true
var plugged := true              # its harness, into the ceiling box
var door_open := false           # the battery door

# --- How it's put together ----------------------------------------------------------------
var plate_on := true
var plate_kind := ""             # the cover plate that's on (or was): the device it came with
var plate_screws: Array = []
var mounted := true
var mount_screws: Array = []
var pulled_out := false

var _shorted_once := false


func _init(kind_: String, panel_: ElectricalPanel, slot_: int, three_way_role_ := "") -> void:
	kind = kind_
	panel = panel_
	slot = slot_
	three_way_role = three_way_role_
	var s := DeviceSpec.of(kind)
	family = s.family
	original = kind
	wires = s.wires.duplicate()
	if three_way_role == "load":
		wires.erase("line")
		wires["load"] = "common"
	for w: String in wires:
		burnt[w] = false
	plate_kind = kind
	for i in s.plate_screws:
		plate_screws.append(true)
	for i in s.mounts:
		mount_screws.append(true)
	if family == "smoke":
		plate_on = false


func spec() -> DeviceSpec:
	return DeviceSpec.of(kind if kind != "" else plate_kind)


# --- Remembering it -------------------------------------------------------------------------

## Everything about how the box was left, so the house remembers it next visit.
func snapshot() -> Dictionary:
	var d := {}
	for key: String in SAVED:
		var v: Variant = get(key)
		d[key] = v.duplicate() if v is Dictionary or v is Array else v
	return d


## Takes back a snapshot(), from this session or a save file (where every
## number comes back as a float).
func restore(d: Dictionary) -> void:
	for key: String in d:
		if not key in SAVED:
			continue
		var v: Variant = d[key]
		if key == "made":
			v = int(v)
		set(key, v.duplicate() if v is Dictionary or v is Array else v)


## A new cable leaving this outlet for one further along: its three wires,
## not on anything yet, sticking out of the box.
func add_cable_out() -> void:
	for w in ["hot_out", "neutral_out", "ground_out"]:
		if not wires.has(w):
			wires[w] = ""
			burnt[w] = false


## A newly cut-in box: nothing in it yet, the cable's three wires hanging out.
func make_new_box() -> void:
	kind = ""
	condition = ""
	for w: String in wires:
		wires[w] = ""
	plate_on = false
	pulled_out = true
	_loose_in_box()


## Nothing holding it in the box yet: each of its mounting screws out. A
## wafer or a blank has none, so there's nothing to do up there.
func _loose_in_box() -> void:
	mount_screws = []
	for i in DeviceSpec.of(kind if kind != "" else original).mounts:
		mount_screws.append(false)
	mounted = mount_screws.is_empty()


## A fault for a job.
func set_fault(fault: String) -> void:
	condition = fault
	match fault:
		"loose":
			wires["hot"] = "back_hot"
			wires["neutral"] = "back_neutral"
		"bad_gfci":
			gfci_tripped = true
		"scorched":
			if family != "ceiling":
				burnt["x" if family == "240" else "hot"] = true
		"bad_splice":
			burnt["hot"] = true      # cooked brown where the nut let go
			burnt["hot_out"] = true


# --- The electrics ----------------------------------------------------------------------

## Signed potential of a wire: L1 is positive, L2 negative, neutral and ground zero.
func wire_potential(w: String) -> float:
	if source != null and w == "hot":
		return source.wire_potential("hot_out")   # whatever the outlet it's fed from passes on
	var poles: Array = panel.circuit_at(slot).poles
	if junction != null and not junction.ok() and family != "ceiling" and w in ["hot", "x", "y", "line"]:
		return 0.0                   # a bad splice upstream in the attic
	if w in OUTPUTS and w != "load":
		if not _conducts(w):
			return 0.0
		var out: Variant = _bus(_bus_of(wires[w]))
		return float(out) if out != null else 0.0
	match w:
		"hot":
			if family == "ceiling":
				return feed.load_potential() if feed != null else 0.0
			return panel.pole_potential(poles[0])
		"x", "line":
			return panel.pole_potential(poles[0])
		"y":
			return panel.pole_potential(poles[-1])
		"load":
			return load_potential()
		"t1", "t2":
			if three_way_role == "load":
				return partner.traveler_potential(w) if partner != null else 0.0
			return traveler_potential(w)
	return 0.0


## On a 3-way: what's on a traveler at this end.
func traveler_potential(w: String) -> float:
	if not _conducts(w):
		return 0.0
	var v: Variant = _bus(_bus_of(wires[w]))
	return float(v) if v != null else 0.0


## How bright the light this switch feeds should be.
func light_scale() -> float:
	return dim if kind == "Dimmer" else 1.0


## A junction box passes power on: its splices are made, and the box feeding it is good.
func ok() -> bool:
	if family != "jbox":
		return true
	for pair in [["hot", "hot_out"], ["neutral", "neutral_out"]]:
		if not _conducts(pair[0]) or not _conducts(pair[1]) or _bus_of(wires[pair[0]]) != _bus_of(wires[pair[1]]):
			return false
	return junction == null or junction.ok()


func switch_closed() -> bool:
	return family == "switch" and kind != "" and switch_on and condition != "worn"


## What the switch sends up its load wire to the light. 0 on anything that
## isn't a switch, or a 3-way at the line end, which has no load wire.
func load_potential() -> float:
	if family != "switch" or not wires.has("load") or not _conducts("load"):
		return 0.0
	var v: Variant = _bus(_bus_of(wires["load"]))
	return float(v) if v != null else 0.0


## Volts across the bulb socket.
func lamp_volts() -> float:
	if family != "ceiling" or kind == "" or kind == "Blank" or condition == "scorched":
		return 0.0
	var h: Variant = _bus("FH")
	var n: Variant = _bus("FN")
	if h == null or n == null:
		return 0.0
	return absf(float(h) - float(n))


## The bus a terminal belongs to. A closed switch ties its two screws together.
func _bus_of(t: String) -> String:
	var b: String = BUS[t]
	if (b == "S1" or b == "S2") and switch_closed():
		return "S"
	if kind == "ThreeWay" and (b == "C" or b == ("TA" if switch_on or condition == "worn" else "TB")):
		return "C"                   # the lever ties the common to one traveler or the other; a worn one's stuck
	return b


## Is any hot wire in the box live?
func any_live() -> bool:
	for w: String in wires:
		if w in HOT_WIRES and absf(wire_potential(w)) > 60.0:
			return true
	return false


## Is this wire actually making contact?
func _conducts(w: String) -> bool:
	var t: String = wires[w]
	if t == "" or kind == "" or not DeviceSpec.of(kind).terms.has(t):
		return false
	if condition == "loose" and t == "back_hot":
		return false
	if source != null and (w == "neutral" or w == "ground") and not (source._conducts(w + "_out") and source._conducts(w)):
		return false                     # its cable's end isn't on anything back at the source, or the source has lost its own
	return LOOSE_WIRE.get(condition, "") != w


## Potential on one of the device's internal buses, or null if nothing feeds it.
func _bus(name: String) -> Variant:
	for w: String in wires:
		var output := w in OUTPUTS or (three_way_role == "line" and (w == "t1" or w == "t2"))
		if not output and _conducts(w) and _bus_of(wires[w]) == name:   # wires heading away aren't a source
			return wire_potential(w)
	if kind == "GFCI" and (name == "OH" or name == "ON") and gfci_closed():
		return _bus("LH" if name == "OH" else "LN")
	return null


## Two different conductors on the same screw or bus, where one's a hot.
func shorted() -> bool:
	var on := {}
	for w: String in wires:
		if _conducts(w):
			var b: String = _bus_of(wires[w])
			if not on.has(b):
				on[b] = []
			on[b].append(w)
	for b: String in on:
		var here: Array = on[b]
		var hots := here.filter(func(w: String) -> bool: return w in HOT_WIRES)
		if not hots.is_empty() and (hots.size() < here.size() or b == "G"):
			return true                  # a hot on a neutral or a ground
		if hots.has("x") and hots.has("y"):
			return true                  # the two legs of a 240 V circuit
	return false


## Call every frame: a short wired with the power off goes bang when the
## breaker comes back on. Trips the breaker and returns true the moment it
## happens; once more each time the power's restored onto it.
func poll_short() -> bool:
	var live := any_live()
	if live and shorted() and not _shorted_once:
		_shorted_once = true
		panel.trip(slot)
		return true
	elif not live:
		_shorted_once = false
	return false


func gfci_closed() -> bool:
	return kind == "GFCI" and not gfci_tripped and condition != "bad_gfci"


## Potential at a slot in the face ("hot", "neutral", "ground", "x", "y"), or null if it goes nowhere.
func face(pin: String) -> Variant:
	if kind == "":
		return null
	if pin == "ground":
		return _bus("G")
	if condition == "scorched":
		return null                  # the contacts behind the face are burnt open
	match kind:
		"GFCI":
			if not gfci_closed():
				return null
			return _bus("LH" if pin == "hot" else "LN")
		"Range":
			return _bus({"x": "X", "y": "Y", "neutral": "N"}[pin])
	return _bus("H" if pin == "hot" else "N")


## Volts an appliance plugged in here would get, hot to neutral.
func face_volts() -> float:
	if family == "switch":
		return absf(load_potential())
	if family == "ceiling":
		return lamp_volts()
	var h: Variant = face("x" if family == "240" else "hot")
	var n: Variant = face("neutral")
	if h == null or n == null:
		return 0.0
	return absf(float(h) - float(n))


## What the three lights on a plug-in tester do: [left yellow, middle yellow, red].
func tester_lights() -> Array:
	if family == "240":
		return [false, false, false]
	var h: Variant = face("hot")
	var n: Variant = face("neutral")
	var g: Variant = face("ground")
	var live := func(v: Variant) -> bool: return v != null and absf(float(v)) > 60.0
	var zero := func(v: Variant) -> bool: return v != null and absf(float(v)) < 5.0
	if live.call(h) and zero.call(n) and zero.call(g):
		return [true, true, false]
	if live.call(h) and zero.call(n):
		return [false, true, false]
	if live.call(h) and zero.call(g):
		return [true, false, false]
	if live.call(n) and zero.call(h):
		return [false, true, true]
	return [false, false, false]


## A stove plugged in here gets both legs: 240 V across, 120 each to neutral.
func range_good() -> bool:
	var x: Variant = face("x")
	var y: Variant = face("y")
	var n: Variant = face("neutral")
	if x == null or y == null or n == null:
		return false
	return absf(float(x) - float(y)) > 200.0 and absf(float(x)) > 100.0 and absf(float(y)) > 100.0


## Every wire on a screw that's right for it.
func _terminations_right() -> bool:
	for w: String in wires:
		if wires[w] == "" or not (BUS[wires[w]] in RIGHT_BUS[w]):
			return false
	return true


# --- Measuring ------------------------------------------------------------------------------

## Potential at a test point, or null if it goes nowhere. Points: face_<pin>,
## wire_<wire> (a free end), term_<terminal>.
func potential(point: String) -> Variant:
	if point.begins_with("face_"):
		return face(point.substr(5))
	if point.begins_with("wire_"):
		return wire_potential(point.substr(5))
	if point.begins_with("term_"):
		return _bus(_bus_of(point.substr(5)))
	return null


## What a voltmeter reads between two points.
func voltage(a: String, b: String) -> float:
	var pa: Variant = potential(a)
	var pb: Variant = potential(b)
	if pa == null or pb == null:
		return 0.0
	return absf(float(pa) - float(pb))


## Is the probe on a hot conductor? (What makes a dead reading proof of anything.)
func is_hot_point(point: String) -> bool:
	if point.begins_with("wire_") or point.begins_with("face_"):
		return point.substr(5) in HOT_WIRES
	if point.begins_with("term_"):
		for w: String in HOT_WIRES:
			if wires.has(w) and wires[w] == point.substr(5):
				return true
	return false


## Would touching this wire bite you?
func live_bare(w: String) -> bool:
	return w in HOT_WIRES and absf(wire_potential(w)) > 30.0


# --- Smoke detectors ------------------------------------------------------------------------

func expired() -> bool:
	return THIS_YEAR - made >= SMOKE_LIFE


func chirping() -> bool:
	return kind != "" and plugged and (battery_low or not battery_in or expired())


## The green power LED: on the harness, and getting power down it.
func power_led() -> bool:
	var fed := junction == null or junction.ok()
	return kind != "" and plugged and fed and panel.circuit_volts(slot) > 100.0


# --- Is it fixed? ---------------------------------------------------------------------------

## "ok", "miswired", "burnt_wire", "dead", "open" (not put back together) or "empty".
func repair_state() -> String:
	if family == "smoke":
		if kind == "" or not plugged:
			return "dead"
		if pulled_out:
			return "open"
		return "dead" if chirping() else "ok"
	if kind == "":
		return "empty"
	if not plate_on or pulled_out or not mounted:
		return "open"
	var works := false
	match family:
		"240":
			works = range_good()
		"switch":
			if kind == "ThreeWay":
				works = condition != "worn" and wires.keys().all(func(w: String) -> bool: return _conducts(w))
				if works and BUS[wires["t1"]] == BUS[wires["t2"]]:
					return "miswired"
			else:
				works = condition != "worn" and _conducts("line") and _conducts("load") and BUS[wires["line"]] != BUS[wires["load"]]
				if _conducts("line") and _conducts("load") and BUS[wires["line"]] == BUS[wires["load"]]:
					return "miswired"    # both on one screw: the light never goes off
		"ceiling":
			works = condition != "scorched" and _conducts("hot") and _conducts("neutral")
		"jbox":
			works = ok()
		_:
			works = tester_lights()[0] or tester_lights()[1]
	if not works:
		return "dead"
	if (family == "120" and tester_lights() != CORRECT) or not _terminations_right():
		return "miswired"
	for w: String in wires:
		if burnt[w] and wires[w] != "":
			return "burnt_wire"
	return "ok"


# --- Hands on it ----------------------------------------------------------------------------
# The commands the player's hands and tools carry out. They change the state
# and say what happened; what you see and hear about it is up to the view.

## The switch on the wall. False if there's nothing to flip (empty, or pulled out).
func flip() -> bool:
	if kind == "" or pulled_out:
		return false
	switch_on = not switch_on
	return true


## Takes out one cover plate screw. True if that was the last and the plate's off.
func remove_plate_screw(i: int) -> bool:
	plate_screws[i] = false
	if not plate_screws.has(true):
		plate_on = false
		return true
	return false


func refit_plate() -> void:
	plate_on = true
	plate_kind = kind
	plate_screws = []
	for i in DeviceSpec.of(kind).plate_screws:
		plate_screws.append(true)


## A light's glass shade, or a fan's: no screws.
func remove_shade() -> void:
	plate_on = false


func toggle_mount_screw(i: int) -> void:
	mount_screws[i] = not mount_screws[i]
	mounted = mount_screws.all(func(b: bool) -> bool: return b)


func pull_out() -> void:
	pulled_out = true


## Back into the box. It's loose in there until it's screwed down again (a
## junction box's splices just fold back in).
func push_in() -> void:
	pulled_out = false
	if family != "jbox":
		_loose_in_box()


## The old device comes out of the box, and its faults go with it.
func remove_device() -> void:
	kind = ""
	condition = ""
	gfci_tripped = false


## Puts a new device in the empty box. Returns "" if it went in, or why not:
## "nothing" (empty hands), "not_a_device", "three_way_mismatch", "wrong_family".
func install(new_kind: String) -> String:
	if new_kind == "":
		return "nothing"
	if not DeviceSpec.has(new_kind):
		return "not_a_device"
	if (new_kind == "ThreeWay") != (original == "ThreeWay"):
		return "three_way_mismatch"
	if DeviceSpec.of(new_kind).family != family:
		return "wrong_family"
	if (new_kind == "Wafer") != (original == "Wafer"):
		return "wafer_mismatch"      # a wafer goes in its own hole; a ceiling box takes a light, a fan or a blank
	kind = new_kind
	condition = ""
	gfci_tripped = kind == "GFCI"   # they come out of the box tripped
	pulled_out = true
	_loose_in_box()
	return ""


## Lands a wire on a terminal. True if that put a live hot onto the wrong
## thing: a dead short, and the breaker trips.
func land(w: String, t: String) -> bool:
	wires[w] = t
	if shorted() and any_live():
		panel.trip(slot)
		return true
	return false


## Takes a wire off its terminal. Taking a bad connection apart clears it:
## it gets re-made when the wire goes back on.
func loosen(w: String) -> void:
	var slack: String = LOOSE_WIRE.get(condition, "")
	if slack != "" and wires.get(slack, "") == wires[w]:
		condition = ""
	wires[w] = ""


## Snugs a terminal up. True if that wire was the loose one.
func tighten(w: String) -> bool:
	if LOOSE_WIRE.get(condition, "") == w:
		condition = ""
		return true
	return false


## Cuts the end off a free wire and strips it fresh. True if it was burnt.
func strip(w: String) -> bool:
	if burnt[w]:
		burnt[w] = false
		return true
	return false


func slide_dimmer() -> void:
	dim = DIM_STEPS[(DIM_STEPS.find(dim) + 1) % DIM_STEPS.size()]


## The GFCI's TEST button. True if it tripped.
func test_gfci() -> bool:
	if gfci_closed():
		gfci_tripped = true
		return true
	return false


## The RESET button: "reset", or "not_tripped", "bad" (won't latch), "no_line" (no power on LINE).
func reset_gfci() -> String:
	if not gfci_tripped:
		return "not_tripped"
	var lh: Variant = _bus("LH")
	var line_ok: bool = lh != null and absf(float(lh)) > 60.0 and _bus("LN") != null
	if condition == "bad_gfci":
		return "bad"
	if not line_ok:
		return "no_line"
	gfci_tripped = false
	return "reset"


# Smoke detectors.

func twist() -> void:
	pulled_out = not pulled_out


func toggle_battery_door() -> void:
	door_open = not door_open


func remove_battery() -> void:
	battery_in = false
	battery_low = false


func insert_battery() -> void:
	battery_in = true
	battery_low = false


func unplug_harness() -> void:
	plugged = false


func plug_harness() -> void:
	plugged = true


## A brand new detector onto the harness, dated this year.
func fit_new_detector() -> void:
	kind = "Smoke"
	made = THIS_YEAR
	battery_in = true
	battery_low = false
	plugged = true


func take_down_detector() -> void:
	kind = ""
