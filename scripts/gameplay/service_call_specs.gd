class_name ServiceCallSpecs
extends RefCounted
## Eligibility rules, by name, so definitions can list them as data
## ("has_attic", "min_five_stars:10"). Each is a plain predicate over a
## GenerationContext: what the property has, or what the business has done.
## They only look; they never change anything.
##
## Add a rule here once and any definition can use it.


## What a rule gets to look at.
class Context:
	extends RefCounted
	var building: BuildingElectricalModel
	var repository: ServiceCallRepository
	## The business: jobs done and five-star reviews standing.
	var jobs_done := 0
	var five_stars := 0


## Every named rule holds. An unknown name is an error in the data, and fails.
static func all_hold(names: Array[String], ctx: Context) -> bool:
	for name in names:
		if not holds(name, ctx):
			return false
	return true


static func holds(spec: String, ctx: Context) -> bool:
	var name := spec.get_slice(":", 0)
	var arg := spec.get_slice(":", 1) if spec.contains(":") else ""
	var b := ctx.building
	match name:
		# The property.
		"one_story":
			return not b.two_story
		"has_attic":
			return b.has_attic()
		"has_working":                   # has_working:Receptacle - one of these, working, with power
			return b.box_ids.any(func(id: String) -> bool: return _works(b.device(id), arg))
		"has_working_detector":
			return b.detector_ids.any(func(id: String) -> bool: return b.device(id).repair_state() == "ok")
		"has_live_circuit":              # a breaker a customer would call about, closed and live
			return b.panel.bus_live() and not b.panel.candidates().is_empty()
		"has_heavy_circuit":             # one with a big appliance on it
			return b.panel.bus_live() and not b.panel.heavy_candidates(false).is_empty()
		"has_overloadable_circuit":      # one a space heater would push over
			return b.panel.bus_live() and not b.panel.heavy_candidates(true).is_empty()
		"water_heater_working":
			return b.water_heater != null and b.water_heater.fixed()
		"has_install_spot":
			return not b.open_install_spots().is_empty()
		"no_open_install":               # every outlet they've asked for is in and working
			return b.install_ids().all(func(id: String) -> bool: return b.device(id).repair_state() == "ok")
		"can_add_recessed":             # an attic, and the master bedroom's light up and working
			return b.can_add_recessed()
		# The business.
		"min_jobs_done":
			return ctx.jobs_done >= int(arg)
		"min_five_stars":
			return ctx.five_stars >= int(arg)
	push_error("Unknown eligibility rule '%s'" % spec)
	return false


static func _works(d: ElectricalDevice, kind: String) -> bool:
	if d.kind != kind or d.repair_state() != "ok":
		return false
	if d.family == "120" or d.family == "240":
		return d.face_volts() > 100.0
	return d.panel.circuit_volts(d.slot) > 100.0
