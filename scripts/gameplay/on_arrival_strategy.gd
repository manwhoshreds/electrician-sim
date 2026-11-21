class_name OnArrivalStrategy
extends ServiceCallGenerationStrategy
## The older calls whose fault is still placed when the house is built
## (ServiceCall._place_device_fault): smoke detectors, range outlets, the
## remaining light and switch faults. The call is made and booked now; its
## fault goes on the real equipment when you get there. Eligibility comes
## from the definition's rules alone. Moving one of these to a real strategy
## is a data change once that strategy exists.


func is_eligible(_definition: JobType, _building: BuildingElectricalModel) -> bool:
	return true


func generate(definition: JobType, building: BuildingElectricalModel,
		repository: ServiceCallRepository, _rng: RandomNumberGenerator) -> ActiveJob:
	var incident := "%s:%s" % [building.building_id, definition.kind]
	if repository.has_open_incident(incident):
		return null
	var draft := {"target_id": "", "equipment_ids": [], "affected_ids": [], "slot": 0,
		"complaint": "", "incident_key": incident, "objective_kind": "none"}
	var job := ServiceCallFactory.make(definition, building, draft, repository)
	job.objectives.clear()
	job.placed_on_arrival = true
	if not repository.add(job):
		return null
	return job
