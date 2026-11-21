class_name DeadReceptaclesStrategy
extends ServiceCallGenerationStrategy
## Dead receptacles, from any of the real causes the definition lists (its
## `causes` weights): a backstab that let go, contacts burnt open, or a failed
## splice in an attic junction box killing every outlet past it. The
## complaint only reports what stopped working.


func is_eligible(definition: JobType, building: BuildingElectricalModel) -> bool:
	return not _causes(building).is_empty()


func generate(definition: JobType, building: BuildingElectricalModel,
		repository: ServiceCallRepository, rng: RandomNumberGenerator) -> ActiveJob:
	var draft := _draft(definition, building, rng)
	if draft.is_empty() or repository.has_open_incident(draft["incident_key"]):
		return null
	var target := building.device(draft["target_id"])
	var before := target.snapshot()
	target.set_fault(draft["fault"])
	# Generation is atomic: the stated symptom must really exist or the device
	# goes back exactly as it was.
	if not _symptom_exists(building, draft["affected_ids"]):
		target.restore(before)
		return null
	var job := ServiceCallFactory.make(definition, building, draft, repository)
	if not repository.add(job):
		target.restore(before)
		return null
	return job


## Which causes this house could have, and the equipment each could be on:
## cause -> candidate ids. A receptacle-level cause needs a working receptacle;
## a failed attic splice needs a junction feeding at least two working ones.
func _causes(building: BuildingElectricalModel) -> Dictionary:
	var working := func(id: String) -> bool:
		return building.device(id).repair_state() == "ok" and building.device(id).face_volts() > 100.0
	var receptacles := building.receptacle_ids().filter(working)
	var out := {}
	if not receptacles.is_empty():
		out["loose"] = receptacles
		out["scorched"] = receptacles
	var splices: Array[String] = []
	for id in building.junction_ids:
		var downstream := building.affected_receptacles(id)
		if downstream.size() >= 2 and downstream.all(working):
			splices.append(id)
	if not splices.is_empty():
		out["bad_splice"] = splices
	return out


func _draft(definition: JobType, building: BuildingElectricalModel, rng: RandomNumberGenerator) -> Dictionary:
	var possible := _causes(building)
	if possible.is_empty():
		return {}
	var cause := definition.pick_cause(rng, possible.keys()) if not definition.causes.is_empty() else ("loose" if possible.has("loose") else "")
	if cause == "" or definition.complaint_templates.is_empty():
		return {}
	var target_id: String = pick(possible[cause], rng)
	var affected: Array[String] = []
	if cause == "bad_splice":
		affected.assign(building.affected_receptacles(target_id))
	else:
		affected.append(target_id)
	var room: String = building.rooms[affected[0]]
	var values := {"room": room, "count": affected.size(), "outlets": "outlets" if affected.size() != 1 else "outlet"}
	var complaint := definition.complaint(pick(definition.complaint_templates, rng), values)
	return {"target_id": target_id, "equipment_ids": [target_id], "affected_ids": affected,
		"slot": building.device(target_id).slot, "fault": cause, "cause": cause,
		"complaint": complaint, "incident_key": "%s:%s" % [building.building_id, target_id]}


func _symptom_exists(building: BuildingElectricalModel, affected: Array) -> bool:
	for id: String in affected:
		if building.device(id).face_volts() >= 5.0:
			return false
	return true
