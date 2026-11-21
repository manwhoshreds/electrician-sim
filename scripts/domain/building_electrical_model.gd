class_name BuildingElectricalModel
extends RefCounted
## The electrical installation in one house without its rooms or graphics.
## Stable equipment ids let dispatch inspect an unloaded house; HouseInterior
## attaches views to these same devices when the player arrives.

## Places in a house where a customer might want a new outlet, and the room
## each is in. Where exactly on the wall is the house layout's business.
const INSTALL_SPOTS := {"bedroom_desk": {"room": "master bedroom", "where": "under the window, for a desk"},
	"living_room_lamp": {"room": "living room", "where": "by the hall doorway, for a reading lamp"}}

var building_id := ""
## "residential" for now; commercial and industrial properties come later.
var property_type := "residential"
var two_story := false
var panel: ElectricalPanel
var devices := {}                 # stable id -> ElectricalDevice
var rooms := {}                   # stable id -> customer-facing room
var box_ids: Array[String] = []
var detector_ids: Array[String] = []
var junction_ids: Array[String] = []
var water_heater: WaterHeater
## New outlets customers asked for: id -> {"spot", "room", "source" (the outlet
## its cable's fished from, "" until the box is cut in)}. Each one's device is
## in `devices`, built empty.
var installs := {}
## Recessed lights the customer asked for in place of a ceiling light (see
## request_recessed): {"fixture" (the old light's id), "wafers" (ids),
## "marks" ([x, z] pencil marks on the ceiling, house-local, [] till laid
## out), "cut" (a hole at each mark?), "runs" ([{from, to, how, feet}])}.
## `how` is "bay" (along a joist bay), "bored" (through the joists), "guarded"
## (over the tops, stapled to a guard strip) or "bare" (over the tops with
## nothing: a code violation in an attic with pull-down stairs).
var recessed := {}


static func residential(id: String, panel_: ElectricalPanel, two_story := false) -> BuildingElectricalModel:
	var m := BuildingElectricalModel.new()
	m.building_id = id
	m.panel = panel_
	m.two_story = two_story
	m.water_heater = WaterHeater.new()
	m.water_heater.panel = panel_
	# This order is the old HouseInterior.boxes order. Saves and callbacks rely on it.
	for spec in [
		["Range", 1, "kitchen", ""], ["Receptacle", 10, "kitchen", ""], ["Receptacle", 16, "kitchen", ""],
		["Receptacle", 9, "kitchen", ""], ["Receptacle", 9, "kitchen", ""],
		["Fixture", 12, "kitchen", ""], ["Switch", 12, "kitchen", ""],
		["Receptacle", 12, "living room", ""], ["Receptacle", 12, "living room", ""],
		["Receptacle", 12, "living room", ""], ["Fixture", 12, "living room", ""],
		["ThreeWay", 12, "living room", "line"], ["ThreeWay", 12, "living room", "load"],
		["GFCI", 11, "bathroom", ""], ["Fixture", 11, "bathroom", ""], ["Switch", 11, "bathroom", ""],
		["Receptacle", 13, "master bedroom", ""], ["Receptacle", 13, "master bedroom", ""],
		["Fixture", 13, "master bedroom", ""], ["Switch", 13, "master bedroom", ""],
		["Receptacle", 13, "front bedroom", ""], ["Receptacle", 13, "front bedroom", ""],
		["Fixture", 13, "front bedroom", ""], ["Switch", 13, "front bedroom", ""],
		# The selected ranch plan adds a second bathroom and a laundry room.
		["GFCI", 11, "hall bathroom", ""], ["Fixture", 11, "hall bathroom", ""], ["Switch", 11, "hall bathroom", ""],
		["Receptacle", 14, "laundry", ""], ["Fixture", 12, "laundry", ""], ["Switch", 12, "laundry", ""],
	]:
		m._add("box_%02d" % m.box_ids.size(), spec[0], spec[1], spec[2], spec[3], m.box_ids)
	for room in ["living room", "master bedroom", "front bedroom"]:
		m._add("detector_%02d" % m.detector_ids.size(), "Smoke", 13, room, "", m.detector_ids)
	if not two_story:
		for spec in [[13, "both bedrooms"], [13, "the far bedroom"], [12, "the living room and kitchen lights"], [11, "the bathroom"]]:
			m._add("junction_%02d" % m.junction_ids.size(), "JBox", spec[0], spec[1], "", m.junction_ids)
	m._link()
	return m


func _add(id: String, kind: String, slot: int, room: String, role: String, order: Array[String]) -> void:
	devices[id] = ElectricalDevice.new(kind, panel, slot, role)
	rooms[id] = room
	order.append(id)


func _link() -> void:
	# Fixtures and their switches.
	device("box_05").feed = device("box_06")
	device("box_10").feed = device("box_12")
	device("box_11").partner = device("box_12")
	device("box_12").partner = device("box_11")
	device("box_14").feed = device("box_15")
	device("box_18").feed = device("box_19")
	device("box_22").feed = device("box_23")
	device("box_25").feed = device("box_26")
	device("box_28").feed = device("box_29")
	if junction_ids.is_empty():
		return
	var near := device("junction_00")
	var far := device("junction_01")
	far.junction = near
	for id in box_ids + detector_ids:
		var d := device(id)
		match d.slot:
			13:
				d.junction = near if id in ["box_16", "box_17", "box_18", "box_19", "detector_01"] else far
			12:
				d.junction = device("junction_02")
			11:
				d.junction = device("junction_03")


## Is a box in `actual` in the room a job asks for? "bedroom" is either
## bedroom; "master bedroom" is only that one. "" is anywhere.
static func in_room(actual: String, wanted: String) -> bool:
	return wanted == "" or actual == wanted or actual.ends_with(" " + wanted)


func has_attic() -> bool:
	return not junction_ids.is_empty()


# --- New outlets ------------------------------------------------------------------------

## Install spots nobody's asked for yet.
func open_install_spots() -> Array[String]:
	var taken := installs.values().map(func(i: Dictionary) -> String: return i["spot"])
	var out: Array[String] = []
	for spot: String in INSTALL_SPOTS:
		if not spot in taken and not source_candidates_in(INSTALL_SPOTS[spot]["room"]).is_empty():
			out.append(spot)
	return out


## Working outlets in a room that a new one could be fed from: plain
## receptacles, not a GFCI or a dedicated appliance circuit.
func source_candidates_in(room: String) -> Array[String]:
	var out: Array[String] = []
	for id in box_ids:
		var d := device(id)
		if in_room(rooms[id], room) and d.kind == "Receptacle" and d.repair_state() == "ok" and panel.circuit_at(d.slot).appliance != "toaster":
			out.append(id)
	return out


## What the customer wants: a new outlet at this spot. Its box isn't cut in
## yet. Returns its id.
func request_install(spot: String, kind := "Receptacle") -> String:
	var id := "new_%02d" % installs.size()
	var room: String = INSTALL_SPOTS[spot]["room"]
	var d := ElectricalDevice.new(kind, panel, device(source_candidates_in(room)[0]).slot)
	d.make_new_box()
	devices[id] = d
	rooms[id] = room
	installs[id] = {"spot": spot, "room": room, "source": ""}
	return id


## Takes a request back off the books (a call that couldn't be made).
func withdraw_install(id: String) -> void:
	installs.erase(id)
	devices.erase(id)
	rooms.erase(id)


## The box is cut in and the cable fished back to `source_id`, a working
## outlet in the same room. Its end is in that outlet's box, not on anything yet.
## "" if done, or why not.
func rough_in(id: String, source_id: String) -> String:
	if not installs.has(id):
		return "no_such_install"
	if installs[id]["source"] != "":
		return "already_roughed_in"
	if not source_id in source_candidates_in(installs[id]["room"]):
		return "not_a_source"
	var d := device(id)
	var s := device(source_id)
	d.source = s
	d.slot = s.slot
	s.add_cable_out()
	installs[id]["source"] = source_id
	return ""


# --- Recessed lights ----------------------------------------------------------------------

## The ceiling light that comes down for wafers: the master bedroom's, on a
## plain switch with the attic over it.
const RECESSED_FIXTURE := "box_18"


func can_add_recessed() -> bool:
	if not has_attic() or not recessed.is_empty():
		return false
	var f := device(RECESSED_FIXTURE)
	return f != null and f.kind == "Fixture" and f.repair_state() == "ok" and panel.circuit_volts(f.slot) > 100.0


## They want `count` wafers in place of the old light, on its switch. Nothing
## changes in the house till you lay them out, cut and wire them. Their ids.
func request_recessed(count: int) -> Array[String]:
	var f := device(RECESSED_FIXTURE)
	var ids: Array[String] = []
	for i in count:
		var id := "wafer_%02d" % i
		var d := ElectricalDevice.new("Wafer", panel, f.slot)
		d.make_new_box()
		devices[id] = d
		rooms[id] = rooms[RECESSED_FIXTURE]
		ids.append(id)
	recessed = {"fixture": RECESSED_FIXTURE, "wafers": ids.duplicate(), "marks": [], "cut": [], "runs": []}
	return ids


func withdraw_recessed() -> void:
	for id: String in recessed.get("wafers", []):
		devices.erase(id)
		rooms.erase(id)
	recessed = {}


func wafer_ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(recessed.get("wafers", []))
	return out


## The pencil marks are down, one per wafer. Clears any you'd cut (you can't).
func lay_out(marks: Array) -> void:
	recessed["marks"] = marks.map(func(m: Variant) -> Array: return [float(m[0]), float(m[1])])
	recessed["cut"] = marks.map(func(_m: Variant) -> bool: return false)


func laid_out() -> bool:
	return not recessed.get("marks", []).is_empty()


func any_cut() -> bool:
	return (recessed.get("cut", []) as Array).has(true)


func cut_hole(i: int) -> void:
	recessed["cut"][i] = true


func hole_cut(i: int) -> bool:
	var cut: Array = recessed.get("cut", [])
	return i < cut.size() and cut[i]


## Has this point (the old light or a wafer) got cable coming in from the switch side?
func fed(id: String) -> bool:
	return id == recessed.get("fixture", "") or (recessed.get("runs", []) as Array).any(func(r: Dictionary) -> bool: return r["to"] == id)


## Has a cable already gone on from this point? (One each: they're daisy-chained.)
func feeds_on(id: String) -> bool:
	return (recessed.get("runs", []) as Array).any(func(r: Dictionary) -> bool: return r["from"] == id)


## A cable pulled from `from` (fed already) to the wafer `to` (its hole cut,
## nothing in it yet). Its far end hangs out of the hole; at `from` there's a
## new set of wires to splice on. "" if done, or why not.
func run_cable(from: String, to: String, how: String, feet: int) -> String:
	if not to in wafer_ids():
		return "not_a_wafer"
	if not hole_cut(wafer_ids().find(to)):
		return "no_hole"
	if not fed(from):
		return "from_not_fed"
	if feeds_on(from):
		return "from_taken"
	if fed(to):
		return "already_fed"
	var d := device(to)
	d.source = device(from)
	device(from).add_cable_out()
	(recessed["runs"] as Array).append({"from": from, "to": to, "how": how, "feet": feet})
	return ""


## Every wafer's in, wired right and lit (the switch is on), and the old
## light's box is spliced through under a blank.
func recessed_done() -> bool:
	if recessed.is_empty() or not laid_out():
		return false
	var old := device(recessed["fixture"])
	if old.kind != "Blank" or old.repair_state() != "ok" or not panel.circuit_at(old.slot).healthy():
		return false
	for id in wafer_ids():
		var d := device(id)
		if not fed(id) or d.repair_state() != "ok" or d.lamp_volts() < 100.0:
			return false
	return true


## Lays a guard strip under a run that went over the joist tops bare.
func guard_run(to: String) -> void:
	for r: Dictionary in recessed.get("runs", []):
		if r["to"] == to and r["how"] == "bare":
			r["how"] = "guarded"


## Runs over the joist tops with nothing protecting them.
func bare_runs() -> Array:
	return (recessed.get("runs", []) as Array).filter(func(r: Dictionary) -> bool: return r["how"] == "bare")


func roughed_in(id: String) -> bool:
	return installs.has(id) and installs[id]["source"] != ""


func install_ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(installs.keys())
	return out


func device(id: String) -> ElectricalDevice:
	return devices.get(id)


func id_of(d: ElectricalDevice) -> String:
	for id: String in devices:
		if devices[id] == d:
			return id
	return ""


func receptacle_ids() -> Array[String]:
	var out: Array[String] = []
	for id in box_ids:
		if device(id).kind == "Receptacle":
			out.append(id)
	return out


func affected_receptacles(junction_id: String) -> Array[String]:
	var out: Array[String] = []
	var j := device(junction_id)
	for id in receptacle_ids():
		var upstream := device(id).junction
		while upstream != null:
			if upstream == j:
				out.append(id)
				break
			upstream = upstream.junction
	return out


## The light whose feed comes through this switch, directly or through its
## three-way partner.
func fixture_for_switch(switch_id: String) -> String:
	var switch := device(switch_id)
	for id in box_ids:
		var candidate := device(id)
		if candidate.family != "ceiling":
			continue
		if candidate.feed == switch or (switch.partner != null and candidate.feed == switch.partner):
			return id
	return ""


## The switch (or load-side three-way) feeding this fixture.
func switch_for_fixture(fixture_id: String) -> String:
	var fixture := device(fixture_id)
	if fixture == null or fixture.family != "ceiling" or fixture.feed == null:
		return ""
	return id_of(fixture.feed)


func snapshot() -> Dictionary:
	var new_outlets := {}
	for id: String in installs:
		new_outlets[id] = (installs[id] as Dictionary).merged({"device": device(id).snapshot(), "slot": device(id).slot})
	return {
		"boxes": box_ids.map(func(id: String) -> Dictionary: return device(id).snapshot()),
		"detectors": detector_ids.map(func(id: String) -> Dictionary: return device(id).snapshot()),
		"junctions": junction_ids.map(func(id: String) -> Dictionary: return device(id).snapshot()),
		"water_heater": water_heater.to_save(),
		"installs": new_outlets,
		"recessed": recessed_snapshot(),
	}


func recessed_snapshot() -> Dictionary:
	if recessed.is_empty():
		return {}
	var out := recessed.duplicate(true)
	out["devices"] = wafer_ids().map(func(id: String) -> Dictionary: return device(id).snapshot())
	return out


func restore(state: Dictionary) -> void:
	_restore_group(box_ids, state.get("boxes", []))
	_restore_group(detector_ids, state.get("detectors", []))
	_restore_group(junction_ids, state.get("junctions", []))
	if state.has("water_heater"):
		water_heater.load_save(state["water_heater"])
	for id in install_ids():
		withdraw_install(id)
	var saved: Dictionary = state.get("installs", {})
	for id: String in saved:
		var i: Dictionary = saved[id]
		var d := ElectricalDevice.new(String(i["device"].get("plate_kind", "Receptacle")), panel, int(i.get("slot", 12)))
		d.restore(i["device"])
		devices[id] = d
		rooms[id] = String(i["room"])
		installs[id] = {"spot": String(i["spot"]), "room": String(i["room"]), "source": String(i["source"])}
	for id: String in installs:
		if installs[id]["source"] != "":
			device(id).source = device(installs[id]["source"])
	withdraw_recessed()
	var r: Dictionary = state.get("recessed", {})
	if not r.is_empty():
		var ids := request_recessed((r["wafers"] as Array).size())
		var saved_devices: Array = r.get("devices", [])
		for i in mini(ids.size(), saved_devices.size()):
			device(ids[i]).restore(saved_devices[i])
		recessed["marks"] = (r.get("marks", []) as Array).map(func(m: Array) -> Array: return [float(m[0]), float(m[1])])
		recessed["cut"] = (r.get("cut", []) as Array).duplicate()
		for run: Dictionary in r.get("runs", []):
			recessed["runs"].append({"from": String(run["from"]), "to": String(run["to"]), "how": String(run["how"]), "feet": int(run["feet"])})
			device(String(run["to"])).source = device(String(run["from"]))


## The whole installation, panel and all, for the save file.
func to_save() -> Dictionary:
	return {"building_id": building_id, "property_type": property_type, "two_story": two_story,
		"panel": panel.to_save(), "state": snapshot()}


static func from_save(d: Dictionary, panel_: ElectricalPanel = null) -> BuildingElectricalModel:
	var p := panel_ if panel_ != null else ElectricalPanel.from_save(d.get("panel", {}))
	var m := residential(String(d.get("building_id", "")), p, bool(d.get("two_story", false)))
	m.property_type = String(d.get("property_type", "residential"))
	m.restore(d.get("state", {}))
	return m


func _restore_group(ids: Array[String], saved: Array) -> void:
	for i in mini(ids.size(), saved.size()):
		device(ids[i]).restore(saved[i])
