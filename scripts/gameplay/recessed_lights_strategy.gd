class_name RecessedLightsStrategy
extends ServiceCallGenerationStrategy
## A customer wants recessed lights instead of the old ceiling light: wafers,
## on the same switch. Nothing's broken. The strategy records the request in
## the building (the wafers, not in the ceiling yet); everything after that,
## from the tape measure to the last wire nut, is the electrician's.

const COUNT := 4


func is_eligible(_definition: JobType, building: BuildingElectricalModel) -> bool:
	return building.can_add_recessed()


func generate(definition: JobType, building: BuildingElectricalModel,
		repository: ServiceCallRepository, rng: RandomNumberGenerator) -> ActiveJob:
	if not building.can_add_recessed():
		return null
	var incident := "%s:recessed" % building.building_id
	if repository.has_open_incident(incident):
		return null
	var fixture := BuildingElectricalModel.RECESSED_FIXTURE
	var wafers := building.request_recessed(COUNT)
	var values := {"room": "master bedroom", "count": str(COUNT)}
	var draft := {"target_id": fixture, "equipment_ids": [fixture] + wafers, "affected_ids": [], "slot": building.device(fixture).slot,
		"complaint": complaint_for(definition, values, rng, "master bedroom"), "cause": "recessed", "incident_key": incident,
		"objective_kind": "recessed"}
	var job := ServiceCallFactory.make(definition, building, draft, repository)
	if not repository.add(job):
		building.withdraw_recessed()
		return null
	return job
