class_name DeviceFaultStrategy
extends ServiceCallGenerationStrategy
## A reusable failure of equipment already installed in a house. Definition
## data says which kind of box and which real device fault to apply.


func is_eligible(definition: JobType, building: BuildingElectricalModel) -> bool:
	return not _candidates(definition, building).is_empty()


func generate(definition: JobType, building: BuildingElectricalModel,
		repository: ServiceCallRepository, rng: RandomNumberGenerator) -> ActiveJob:
	var choices := _candidates(definition, building)
	if choices.is_empty():
		return null
	var target_id: String = pick(choices, rng)
	var target := building.device(target_id)
	var incident := "%s:%s" % [building.building_id, target_id]
	if repository.has_open_incident(incident):
		return null
	var before := target.snapshot()
	target.set_fault(definition.box_fault)
	var affected_id := building.fixture_for_switch(target_id) if definition.box == "switch" else target_id
	var affected := building.device(affected_id)
	# A worn three-way may leave the lamp energized in its present toggle
	# combination even though the switch is genuinely failed. Validate switches
	# by their own repair state; outlets and fixtures must also show the symptom.
	if affected_id == "" or target.repair_state() == "ok" \
			or (definition.box != "switch" and affected.face_volts() >= 5.0):
		target.restore(before)
		return null
	var values := {"room": building.rooms[target_id], "equipment": DeviceSpec.of(target.kind).word}
	var complaint := complaint_for(definition, values, rng, values["room"])
	var pair_id := affected_id if definition.box == "switch" else \
		(building.switch_for_fixture(target_id) if definition.box == "fixture" else "")
	var affected_ids: Array[String] = [target_id]
	if affected_id != target_id:
		affected_ids.append(affected_id)
	var draft := {"target_id": target_id, "equipment_ids": [target_id], "affected_ids": affected_ids,
		"pair_id": pair_id,
		"slot": target.slot, "complaint": complaint, "incident_key": incident, "objective_kind": "device"}
	var job := ServiceCallFactory.make(definition, building, draft, repository)
	if not repository.add(job):
		target.restore(before)
		return null
	return job


func _candidates(definition: JobType, building: BuildingElectricalModel) -> Array[String]:
	var out: Array[String] = []
	for id in building.box_ids:
		var d := building.device(id)
		var matches := false
		match definition.box:
			"outlet":
				matches = d.kind == "GFCI" if definition.kind == "bad_gfci" else d.kind == "Receptacle"
			"switch":
				matches = d.kind == "Switch" or (d.kind == "ThreeWay" and d.three_way_role == "load")
			"fixture":
				matches = d.kind == "Fixture"
		if matches and BuildingElectricalModel.in_room(building.rooms[id], definition.room) \
				and d.repair_state() == "ok" and d.face_volts() > 100.0:
			out.append(id)
	return out

