extends RefCounted
## Wiring scenarios for every kind of box, for pinning down the device
## electrics while they move out of BoxView. Each "rig" is a few boxes on a
## real ElectricalPanel, linked the way HouseInterior links them. Every wire
## of the box under test is taken off, or moved to every terminal, under each
## fault it can have; then the power comes back and every box in the rig is
## observed with every combination of its switches.
##
## Only the ADAPTER section touches BoxView's internals, so a refactor changes
## those few functions and nothing else; the observations must not change.

const GOLDEN := "res://tests/golden/box_scenarios.json"


## The job, remembering every device that went in.
class RecordingJob:
	extends ActiveJob
	var used: Array = []

	func device_used(kind_: String, into: ElectricalDevice) -> void:
		used.append(kind_)
		super(kind_, into)


## Faults each rig's box under test can have.
const FAULTS := {
	"Receptacle": ["", "loose", "scorched"],
	"GFCI": ["", "bad_gfci", "scorched"],
	"Range": ["", "loose_lug", "scorched"],
	"Switch": ["", "worn", "loose_screw"],
	"Dimmer": [""],
	"ThreeWay": ["", "worn"],
	"Fixture": ["", "scorched", "loose_nut"],
	"Fan": [""],
	"JBox": ["", "bad_splice"],
}


## Stands in for HouseInterior as the boxes' parent: detectors ask it to sound every alarm.
class FakeHouse:
	extends Node3D
	var alarms := 0

	func sound_alarms() -> void:
		alarms += 1
		for c in get_children():
			if c is BoxView and c.device.family == "smoke":
				c.alarm()


var lib: Node3D
var root: Node
var house: FakeHouse
var sim: ElectricalPanel
var hands: Inventory
var job: RecordingJob
var nodes: Array[Node] = []


func _init(root_: Node, lib_: Node3D) -> void:
	root = root_
	lib = lib_
	ClampMeter.dial = ClampMeter.Mode.VOLTS     # the scenarios probe for volts


func free_all() -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.free()
	nodes.clear()


# --- ADAPTER: the only part that knows how boxes are built ------------------------------

func make_box(kind: String, slot: int, role := "") -> BoxView:
	var b := BoxView.new()
	b.lib = lib
	b.device = ElectricalDevice.new(kind, sim, slot, role)
	b.inventory = hands
	b.job = job
	b.room = "test"
	house.add_child(b)
	return b


func link_feed(fixture: BoxView, switch: BoxView) -> void:
	fixture.device.feed = switch.device


func link_partners(a: BoxView, b: BoxView) -> void:
	a.device.partner = b.device
	b.device.partner = a.device


func link_junction(dev: BoxView, j: BoxView) -> void:
	dev.device.junction = j.device


func set_fault(b: BoxView, fault: String) -> void:
	b.set_fault(fault)


func wire_names(b: BoxView) -> Array:
	return b.device.wires.keys()


func terminals(b: BoxView) -> Array:
	return DeviceSpec.of(b.device.kind).terms


func move_wire(b: BoxView, w: String, t: String) -> void:
	b.device.wires[w] = t
	b._refresh()


func switches_of(b: BoxView) -> bool:
	return b.device.family == "switch" and b.device.kind != ""


func flip(b: BoxView) -> void:
	b.device.switch_on = not b.device.switch_on
	b._refresh()


func poll(b: BoxView) -> void:
	b._process(0.0)


func observe(b: BoxView) -> Dictionary:
	var d := b.device
	var o := {"kind": d.kind, "repair": d.repair_state(),
			"wires": d.wires.duplicate(), "burnt": d.burnt.duplicate(), "condition": d.condition, "arcs": b.work.arcs}
	# face_volts() on the line end of a 3-way crashes in the original (it has no
	# load wire), and nothing in the game asks it; observe switches by load wire.
	if d.family != "switch" or d.wires.has("load"):
		o["face"] = snappedf(d.face_volts(), 0.1)
	if d.family == "120":
		o["tester"] = d.tester_lights()
		o["gfci"] = d.gfci_tripped
	if d.family == "240":
		o["range_good"] = d.range_good()
	if d.family == "ceiling":
		o["lamp"] = snappedf(d.lamp_volts(), 0.1)
	if d.family == "jbox":
		o["ok"] = d.ok()
	o["shorted"] = d.shorted()
	return o


## What's in your bag: just this one part ("" for nothing), as the scenarios
## were written for one part in your hands.
func _carry(kind: String) -> void:
	hands.bag.clear()
	if kind != "":
		hands.bag.append(kind)


## Swap the box's device for a new one, the way the player does it.
func swap_device(b: BoxView, kind: String) -> void:
	b._click_on({"kind": "remove"}, MOUSE_BUTTON_LEFT)
	_carry(kind)
	b._click_on({"kind": "install"}, MOUSE_BUTTON_LEFT)
	for w: String in b.device.wires:   # land each wire where the new device wants it
		b.device.wires[w] = DeviceSpecDefaults.wire_term(kind, w, b.device.three_way_role)
	b.device.pulled_out = false
	b.device.mounted = true
	b.device.mount_screws = [true, true]
	b._refresh()


func reset_gfci(b: BoxView) -> void:
	b._click_on({"kind": "reset"}, MOUSE_BUTTON_LEFT)


# --- Rigs ------------------------------------------------------------------------------

## Builds the rig for a kind: [box under test, every box in the rig].
func rig(kind: String) -> Array:
	sim = ElectricalPanel.new()
	hands = Inventory.new()
	job = RecordingJob.new()
	house = FakeHouse.new()
	root.add_child(house)
	nodes.append(house)
	match kind:
		"Smoke":
			var a := make_box("Smoke", 13)
			var b := make_box("Smoke", 13)
			return [a, [a, b]]
		"Receptacle":
			var r := make_box("Receptacle", 12)
			return [r, [r]]
		"GFCI":
			var g := make_box("GFCI", 11)
			return [g, [g]]
		"Range":
			var r := make_box("Range", 1)
			return [r, [r]]
		"Switch", "Fixture":
			var f := make_box("Fixture", 13)
			var s := make_box("Switch", 13)
			link_feed(f, s)
			return [s if kind == "Switch" else f, [s, f]]
		"Dimmer":
			var f := make_box("Fixture", 13)
			var s := make_box("Switch", 13)
			link_feed(f, s)
			swap_device(s, "Dimmer")
			return [s, [s, f]]
		"Fan":
			var f := make_box("Fixture", 13)
			var s := make_box("Switch", 13)
			link_feed(f, s)
			swap_device(f, "Fan")
			return [f, [s, f]]
		"ThreeWay":
			var f := make_box("Fixture", 12)
			var a := make_box("ThreeWay", 12, "line")
			var b := make_box("ThreeWay", 12, "load")
			link_partners(a, b)
			link_feed(f, b)
			return [a, [a, b, f]]
		"JBox":
			var up := make_box("JBox", 13)
			var j := make_box("JBox", 13)
			link_junction(j, up)
			var r := make_box("Receptacle", 13)
			link_junction(r, j)
			return [j, [up, j, r]]
	return []


## Every box in the rig, under every combination of its switches.
func observe_all(boxes: Array) -> Array:
	var sw: Array = boxes.filter(func(b: BoxView) -> bool: return switches_of(b))
	var out := []
	for combo in 1 << sw.size():
		for i in sw.size():
			if (combo >> i) & 1 == 1:
				flip(sw[i])
		for b: BoxView in boxes:
			poll(b)
		var seen := boxes.map(func(b: BoxView) -> Dictionary: return observe(b))
		seen.append({"tripped": sim.circuit_at(boxes[0].device.slot).breaker.tripped})
		out.append(seen)
		for i in sw.size():
			if (combo >> i) & 1 == 1:
				flip(sw[i])
		# A short trips the breaker: reset it for the next combination.
		var brk := sim.circuit_at(boxes[0].device.slot).breaker
		if brk.tripped:
			brk.toggle()
			brk.toggle()
	return out


## One scenario: rig, fault, one wire change made dead, then power back on.
func play(kind: String, fault: String, change: String) -> String:
	var built := rig(kind)
	var target: BoxView = built[0]
	var boxes: Array = built[1]
	if fault != "":
		set_fault(target, fault)
	sim.toggle_main()
	if change.begins_with("off:"):
		move_wire(target, change.substr(4), "")
	elif change.begins_with("move:"):
		var parts := change.split(":")
		move_wire(target, parts[1], parts[2])
	sim.toggle_main()
	var seen := observe_all(boxes)
	if target.device.kind == "GFCI":
		reset_gfci(target)
		seen.append(observe_all(boxes))
	var out := JSON.stringify(seen)
	free_all()
	return out


## Every change worth trying on a kind's box under test.
func changes(kind: String) -> Array[String]:
	var built := rig(kind)
	var target: BoxView = built[0]
	var out: Array[String] = ["none"]
	for w: String in wire_names(target):
		out.append("off:" + w)
		for t: String in terminals(target):
			out.append("move:%s:%s" % [w, t])
	free_all()
	return out


# --- Repair flows: the controls, step by step --------------------------------------------

## [rig kind, fault, steps]. Steps: a click ("pull", "grab:hot", "land:brass_top",
## "loosen:hot", "tighten:y", "strip:hot", "mount:0", "plate_screw:0", "probe:wire_hot",
## "probe_r:wire_neutral"...), "brk" (the target's breaker), "main", "carry:GFCI",
## "flip", "poll" (a frame passes), "seed:<slot>" (pick the box of a rig).
const FLOWS := {
	"receptacle_loose_safe": ["Receptacle", "loose", ["brk", "plate_screw:0", "mount:0", "mount:1", "pull", "probe:wire_hot",
			"probe_r:wire_neutral", "loosen:hot", "grab:hot", "land:brass_top", "loosen:neutral", "grab:neutral", "land:silver_top",
			"push", "mount:0", "mount:1", "plate", "brk", "poll", "tester"]],
	"receptacle_loose_live": ["Receptacle", "loose", ["plate_screw:0", "mount:0", "mount:1", "pull", "loosen:hot", "loosen:neutral",
			"grab:neutral", "land:silver_top", "push"]],
	"receptacle_reversed": ["Receptacle", "", ["brk", "plate_screw:0", "mount:0", "mount:1", "pull", "loosen:hot", "loosen:neutral",
			"grab:hot", "land:silver_top", "grab:neutral", "land:brass_top", "push", "mount:0", "mount:1", "plate", "brk", "poll", "tester"]],
	"receptacle_hot_on_ground_then_power": ["Receptacle", "", ["brk", "plate_screw:0", "mount:0", "mount:1", "pull", "loosen:hot",
			"grab:hot", "land:green", "brk", "poll", "poll", "brk", "brk", "poll"]],
	"receptacle_land_live_on_neutral": ["Receptacle", "", ["brk", "plate_screw:0", "mount:0", "mount:1", "pull", "loosen:neutral",
			"grab:neutral", "brk", "land:brass_bottom", "poll"]],
	"receptacle_scorched_swap": ["Receptacle", "scorched", ["brk", "plate_screw:0", "mount:0", "mount:1", "pull", "loosen:hot",
			"loosen:neutral", "loosen:ground", "remove", "carry:Range", "install", "carry:Receptacle", "install", "grab:hot", "land:brass_top",
			"grab:neutral", "land:silver_top", "grab:ground", "land:green", "push", "mount:0", "mount:1", "plate", "brk", "poll", "tester",
			"strip:hot", "brk", "plate_screw:0", "mount:0", "mount:1", "pull", "loosen:hot", "strip:hot", "strip:hot", "grab:hot",
			"land:brass_top", "push", "mount:0", "mount:1", "plate", "brk", "poll"]],
	"gfci_bad_swap": ["GFCI", "bad_gfci", ["reset", "test", "brk", "plate_screw:0", "plate_screw:1", "mount:0", "mount:1", "pull",
			"loosen:hot", "loosen:neutral", "loosen:ground", "remove", "carry:GFCI", "install", "grab:hot", "land:line_brass",
			"grab:neutral", "land:line_silver", "grab:ground", "land:green", "push", "mount:0", "mount:1", "plate", "reset", "brk", "poll",
			"reset", "test", "reset", "tester"]],
	"gfci_on_load_screws": ["GFCI", "", ["brk", "plate_screw:0", "plate_screw:1", "mount:0", "mount:1", "pull", "loosen:hot",
			"loosen:neutral", "grab:hot", "land:load_brass", "grab:neutral", "land:load_silver", "push", "mount:0", "mount:1", "plate",
			"brk", "poll", "reset", "tester"]],
	"range_loose_lug": ["Range", "loose_lug", ["main", "plate_screw:0", "plate_screw:1", "mount:0", "mount:1", "pull",
			"probe:wire_x", "probe_r:wire_y", "tighten:y", "tighten:x", "push", "mount:0", "mount:1", "plate", "main", "poll",
			"probe:face_x", "probe_r:face_y"]],
	"range_x_on_y": ["Range", "", ["main", "plate_screw:0", "plate_screw:1", "mount:0", "mount:1", "pull", "loosen:x", "grab:x",
			"land:y_lug", "push", "mount:0", "mount:1", "plate", "main", "poll"]],
	"switch_worn_swap": ["Switch", "worn", ["flip", "flip", "brk", "plate_screw:0", "plate_screw:1", "mount:0", "mount:1", "pull",
			"loosen:line", "loosen:load", "loosen:ground", "remove", "carry:Switch", "install", "grab:line", "land:s_top", "grab:load",
			"land:s_bottom", "grab:ground", "land:green", "push", "mount:0", "mount:1", "plate", "brk", "poll", "flip", "flip"]],
	"switch_both_on_one_screw": ["Switch", "", ["brk", "plate_screw:0", "plate_screw:1", "mount:0", "mount:1", "pull", "loosen:load",
			"grab:load", "land:s_top", "push", "mount:0", "mount:1", "plate", "brk", "poll", "flip"]],
	"switch_loose_screw": ["Switch", "loose_screw", ["brk", "plate_screw:0", "plate_screw:1", "mount:0", "mount:1", "pull",
			"tighten:load", "tighten:line", "push", "mount:0", "mount:1", "plate", "brk", "poll"]],
	"dimmer_install": ["Switch", "", ["brk", "plate_screw:0", "plate_screw:1", "mount:0", "mount:1", "pull", "loosen:line",
			"loosen:load", "loosen:ground", "remove", "carry:Dimmer", "install", "grab:line", "land:s_top", "grab:load", "land:s_bottom",
			"grab:ground", "land:green", "push", "mount:0", "mount:1", "plate", "brk", "poll", "slide", "slide", "slide", "flip"]],
	"three_way_worn_swap": ["ThreeWay", "worn", ["flip", "brk", "plate_screw:0", "plate_screw:1", "mount:0", "mount:1", "pull",
			"loosen:line", "loosen:t1", "loosen:t2", "loosen:ground", "remove", "carry:Switch", "install", "carry:ThreeWay", "install",
			"grab:line", "land:common", "grab:t1", "land:trav_a", "grab:t2", "land:trav_b", "grab:ground", "land:green", "push",
			"mount:0", "mount:1", "plate", "brk", "poll", "flip", "flip"]],
	"three_way_travelers_on_one_screw": ["ThreeWay", "", ["brk", "plate_screw:0", "plate_screw:1", "mount:0", "mount:1", "pull",
			"loosen:t2", "grab:t2", "land:trav_a", "push", "mount:0", "mount:1", "plate", "brk", "poll", "flip"]],
	"fixture_scorched_swap": ["Fixture", "scorched", ["flip", "shade_off", "brk", "pull", "loosen:hot", "loosen:neutral",
			"loosen:ground", "remove", "carry:Fixture", "install", "grab:hot", "land:nut_black", "grab:neutral", "land:nut_white",
			"grab:ground", "land:f_ground", "push", "mount:0", "mount:1", "plate", "brk", "poll", "flip", "flip"]],
	"fixture_loose_nut": ["Fixture", "loose_nut", ["shade_off", "brk", "pull", "tighten:hot", "push", "mount:0", "mount:1", "plate",
			"brk", "poll"]],
	"fan_install": ["Fixture", "", ["shade_off", "brk", "pull", "loosen:hot", "loosen:neutral", "loosen:ground", "remove",
			"carry:Receptacle", "install", "carry:Fan", "install", "grab:hot", "land:nut_black", "grab:neutral", "land:nut_white",
			"grab:ground", "land:f_ground", "push", "mount:0", "mount:1", "plate", "brk", "poll"]],
	"jbox_bad_splice": ["JBox", "bad_splice", ["main", "plate_screw:0", "plate_screw:1", "pull", "loosen:hot", "loosen:hot_out",
			"strip:hot", "strip:hot_out", "grab:hot", "land:nut_hot", "grab:hot_out", "land:nut_hot", "tighten:hot_out", "push", "plate",
			"main", "poll"]],
	"jbox_live": ["JBox", "bad_splice", ["plate_screw:0", "plate_screw:1", "pull", "loosen:hot", "loosen:hot_out", "loosen:neutral"]],
	"smoke_battery": ["Smoke", "battery_low", ["smoke_test", "twist", "door", "battery_out", "battery_in", "carry:Battery9V",
			"battery_in", "door", "twist", "poll", "smoke_test"]],
	"smoke_expired": ["Smoke", "expired", ["smoke_test", "twist", "door", "battery_out", "carry:Battery9V", "battery_in", "door",
			"harness", "take_away", "harness", "carry:Smoke", "harness", "twist", "smoke_test"]],
	"smoke_left_open": ["Smoke", "", ["twist", "harness"]],
}


func click(b: BoxView, step: String) -> void:
	var parts := step.split(":")
	var k := parts[0]
	var arg := parts[1] if parts.size() > 1 else ""
	match k:
		"brk":
			sim.toggle(b.device.slot)
		"main":
			sim.toggle_main()
		"carry":
			_carry(arg)
		"poll":
			for n in house.get_children():
				poll(n)
		"flip":
			b.flip()
		"plate_screw", "mount":
			b._click_on({"kind": k, "i": int(arg)}, MOUSE_BUTTON_LEFT)
		"grab", "strip":
			b._click_on({"kind": k, "wire": arg}, MOUSE_BUTTON_LEFT)
		"loosen":
			b._click_on({"kind": "loosen", "wire": arg}, MOUSE_BUTTON_LEFT)
		"tighten":
			b._click_on({"kind": "loosen", "wire": arg}, MOUSE_BUTTON_RIGHT)
		"land":
			b._click_on({"kind": "land", "term": arg}, MOUSE_BUTTON_LEFT)
		"probe":
			b._click_on({"kind": "probe", "id": arg}, MOUSE_BUTTON_LEFT)
		"probe_r":
			b._click_on({"kind": "probe", "id": arg}, MOUSE_BUTTON_RIGHT)
		_:
			b._click_on({"kind": k}, MOUSE_BUTTON_LEFT)


## What the controls left behind after a step: the device, and what the job saw.
func observe_flow(b: BoxView) -> Dictionary:
	var o: Dictionary
	var d := b.device
	if d.family == "smoke":
		o = {"kind": d.kind, "repair": d.repair_state(), "chirping": d.chirping(), "battery_in": d.battery_in,
				"battery_low": d.battery_low, "plugged": d.plugged, "pulled_out": d.pulled_out, "door_open": d.door_open,
				"made": d.made, "alarms": house.alarms}
	else:
		o = observe(b)
		o.merge({"plate_on": d.plate_on, "mounted": d.mounted, "pulled_out": d.pulled_out, "held": b._held,
				"switch_on": d.switch_on, "dim": d.dim})
	var w := b.work
	o.merge({"shocks": w.shocks, "arcs": w.arcs, "worked_on": w.worked_on, "verified_dead": w.verified_dead,
			"measured_live": w.measured_live, "tested_after": w.tested_after, "used": job.used.duplicate(),
			"carrying": hands.bag[0] if not hands.bag.is_empty() else "", "tripped": sim.circuit_at(b.device.slot).breaker.tripped})
	return o


func play_flow(name: String) -> String:
	var flow: Array = FLOWS[name]
	var built := rig(flow[0])
	var b: BoxView = built[0]
	match flow[1]:
		"":
			pass
		"battery_low":
			b.device.battery_low = true
		"expired":
			b.device.made = 2012
		var fault:
			set_fault(b, fault)
	var seen := [observe_flow(b)]
	for step: String in flow[2]:
		click(b, step)
		var o := observe_flow(b)
		o["step"] = step
		seen.append(o)
	var out := JSON.stringify(seen)
	free_all()
	return out


func capture() -> Dictionary:
	var out := {}
	for name: String in FLOWS:
		out["flow|" + name] = play_flow(name)
	for kind: String in FAULTS:
		for change in changes(kind):
			for fault: String in FAULTS[kind]:
				out["%s|%s|%s" % [kind, fault, change]] = play(kind, fault, change)
	return out


## Where each wire of a device goes when it's put in right.
class DeviceSpecDefaults:
	static func wire_term(kind: String, w: String, role: String) -> String:
		if kind == "ThreeWay" and role == "load" and w == "load":
			return "common"
		return DeviceSpec.of(kind).wires.get(w, "")
