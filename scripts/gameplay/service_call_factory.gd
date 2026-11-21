class_name ServiceCallFactory
extends RefCounted
## Builds a call from a definition and a scenario a strategy has already made
## real and checked. The call comes out GENERATED: the generator puts it on
## the board.


static func make(definition: JobType, building: BuildingElectricalModel, draft: Dictionary,
		repository: ServiceCallRepository) -> ActiveJob:
	return _build(definition, building, draft, repository.make_id(definition.definition_id, building.building_id))


## A saved call back as a live one, pointing at the same equipment in the
## (already restored) building.
static func restore(record: Dictionary, building: BuildingElectricalModel) -> ActiveJob:
	var definition := JobType.of(String(record["kind"]))
	var objectives: Array = record.get("objectives", [])
	var affected: Array = objectives[0].get("equipment_ids", []) if not objectives.is_empty() else []
	var ids: Array = record.get("equipment_ids", [])
	var draft := {"target_id": ids[0] if not ids.is_empty() else "", "equipment_ids": ids, "affected_ids": affected,
		"pair_id": record.get("pair_id", ""), "slot": record.get("slot", 0), "complaint": record.get("complaint", ""),
		"cause": record.get("cause", ""), "incident_key": record.get("incident_key", ""),
		"objective_kind": objective_kind_for(definition)}
	var job := _build(definition, building, draft, String(record["id"]))
	job.placed_on_arrival = definition.generation_strategy == "on_arrival"
	if job.placed_on_arrival:
		job.objectives.clear()
	job.created_at = String(record.get("created_at", ""))
	for key in ["urgency", "window_start", "window_end", "scheduled_for", "expires_at"]:
		job.set(key, record.get(key, job.get(key)))
	job.status = int(record.get("status", ActiveJob.Status.AVAILABLE)) as ActiveJob.Status
	return job


## What a definition's call is judged on, by its strategy.
static func objective_kind_for(definition: JobType) -> String:
	match definition.generation_strategy:
		"breaker_trip", "breaker_fault":
			return "circuit"
		"water_heater":
			return "water_heater"
		"install_device":
			return "install"
		"recessed_lights":
			return "recessed"
		"on_arrival":
			return "none"
	return "device"


static func _build(definition: JobType, building: BuildingElectricalModel, draft: Dictionary, id: String) -> ActiveJob:
	var job := ActiveJob.new()
	job.id = id
	job.definition_id = definition.definition_id
	job.building_id = building.building_id
	job.address = building.building_id
	job.customer_id = "%s:resident" % building.building_id
	job.type = definition
	job.kind = definition.kind
	job.family = definition.family
	job.complaint = draft["complaint"]
	job.issue = job.complaint
	job.cause = String(draft.get("cause", definition.box_fault))
	job.equipment_ids.assign(draft["equipment_ids"])
	job.incident_key = draft["incident_key"]
	job.compensation = definition.base_compensation
	job.urgency = definition.urgency
	job.created_at = Time.get_datetime_string_from_system()
	job.target = int(draft["slot"])
	var kind: String = draft.get("objective_kind", "device")
	job.device = building.device(draft["target_id"]) if kind in ["device", "install", "recessed"] else null
	job.pair_id = String(draft.get("pair_id", ""))
	job.pair = building.device(job.pair_id)
	job.circuit = building.panel.circuit_at(job.target)
	var objective: ServiceObjective
	match kind:
		"circuit":
			objective = CircuitObjective.new()
			(objective as CircuitObjective).slot = job.target
		"water_heater":
			objective = WaterHeaterObjective.new()
		"install":
			objective = InstallObjective.new()
			(objective as InstallObjective).install_id = draft["target_id"]
		"recessed":
			objective = RecessedObjective.new()
		_:
			objective = ServiceObjective.new()
	objective.description = definition.objective_templates[0] if not definition.objective_templates.is_empty() else "Restore power"
	objective.equipment_ids.assign(draft.get("affected_ids", []))
	objective.building = building
	job.objectives.append(objective)
	return job
