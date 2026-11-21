class_name WaterHeaterStrategy
extends ServiceCallGenerationStrategy
## Something goes wrong with the water heater: the definition's cause (a
## WaterHeater fault: "upper_element", "lower_element", "eco"), or one of its
## `causes` by weight. The fault is made in the heater itself, and the
## customer only says what they notice at the tap.


func is_eligible(_definition: JobType, building: BuildingElectricalModel) -> bool:
	return building.water_heater != null and building.water_heater.fixed()


func generate(definition: JobType, building: BuildingElectricalModel,
		repository: ServiceCallRepository, rng: RandomNumberGenerator) -> ActiveJob:
	var heater := building.water_heater
	if not is_eligible(definition, building):
		return null
	var incident := "%s:water_heater" % building.building_id
	if repository.has_open_incident(incident):
		return null
	var cause := definition.pick_cause(rng) if not definition.causes.is_empty() else definition.box_fault
	var before := heater.to_save()
	heater.set_fault(cause)
	if heater.fixed():                    # no symptom: not a real call
		heater.load_save(before)
		return null
	var draft := {"target_id": "water_heater", "equipment_ids": ["water_heater"], "slot": WaterHeater.POLES[0],
		"complaint": complaint_for(definition, {}, rng, ""), "cause": cause, "incident_key": incident,
		"objective_kind": "water_heater"}
	var job := ServiceCallFactory.make(definition, building, draft, repository)
	if not repository.add(job):
		heater.load_save(before)
		return null
	return job
