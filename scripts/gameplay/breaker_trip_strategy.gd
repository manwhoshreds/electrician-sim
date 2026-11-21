class_name BreakerTripStrategy
extends ServiceCallGenerationStrategy
## A breaker call whose symptom is real at the panel: a weak breaker or a
## healthy one on an overloaded circuit (it has really tripped), or a breaker
## that's failed open or gone hot (the circuit's really not right). The
## definition's kind is the panel fault (ElectricalPanel.set_fault).


func is_eligible(definition: JobType, building: BuildingElectricalModel) -> bool:
	return not _candidates(definition, building).is_empty()


func generate(definition: JobType, building: BuildingElectricalModel,
		repository: ServiceCallRepository, rng: RandomNumberGenerator) -> ActiveJob:
	var choices := _candidates(definition, building)
	if choices.is_empty():
		return null
	var slot: int = pick(choices, rng)
	var circuit := building.panel.circuit_at(slot)
	var incident := "%s:circuit_%02d" % [building.building_id, slot]
	if repository.has_open_incident(incident):
		return null
	var before := circuit.to_save()
	building.panel.set_fault(slot, definition.kind)
	var trips := definition.kind == "weak" or definition.kind == "overload"
	if (trips and not circuit.breaker.tripped) or circuit.healthy():
		circuit.load_save(before)
		return null
	var values := {"circuit": circuit.customer, "appliance": circuit.appliance}
	var complaint := complaint_for(definition, values, rng, circuit.customer)
	var target_id := "circuit_%02d" % slot
	var draft := {"target_id": target_id, "equipment_ids": [target_id], "affected_ids": [], "slot": slot,
		"complaint": complaint, "incident_key": incident, "objective_kind": "circuit"}
	var job := ServiceCallFactory.make(definition, building, draft, repository)
	if not repository.add(job):
		circuit.load_save(before)
		return null
	return job


func _candidates(definition: JobType, building: BuildingElectricalModel) -> Array[int]:
	if definition.kind == "weak" or definition.kind == "overload":
		return building.panel.heavy_candidates(definition.kind == "overload")
	return building.panel.candidates()
