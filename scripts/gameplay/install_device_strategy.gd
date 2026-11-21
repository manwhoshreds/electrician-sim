class_name InstallDeviceStrategy
extends ServiceCallGenerationStrategy
## A customer wants something new put in: not a fault, a wish. The strategy
## picks one of the building's open install spots and records the request in
## the building model (an empty box-to-be). Nothing electrical changes until
## the electrician cuts it in and wires it. The definition's `box_fault` is the
## device kind wanted ("Receptacle").


func is_eligible(_definition: JobType, building: BuildingElectricalModel) -> bool:
	return not building.open_install_spots().is_empty()


func generate(definition: JobType, building: BuildingElectricalModel,
		repository: ServiceCallRepository, rng: RandomNumberGenerator) -> ActiveJob:
	var spots := building.open_install_spots()
	if spots.is_empty():
		return null
	var spot: String = pick(spots, rng)
	var incident := "%s:install:%s" % [building.building_id, spot]
	if repository.has_open_incident(incident):
		return null
	var id := building.request_install(spot, definition.box_fault if definition.box_fault != "" else "Receptacle")
	var where: Dictionary = BuildingElectricalModel.INSTALL_SPOTS[spot]
	var values := {"room": where["room"], "where": where["where"]}
	var draft := {"target_id": id, "equipment_ids": [id], "affected_ids": [], "slot": building.device(id).slot,
		"complaint": complaint_for(definition, values, rng, where["room"]), "cause": "install", "incident_key": incident,
		"objective_kind": "install"}
	var job := ServiceCallFactory.make(definition, building, draft, repository)
	if not repository.add(job):
		building.withdraw_install(id)
		return null
	return job
