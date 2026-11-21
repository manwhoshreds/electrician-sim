class_name ServiceCallGenerationStrategy
extends RefCounted
## One reusable way to turn a definition into a real problem (or a real
## request) on suitable equipment. It picks the target with `rng`, makes the
## change through the domain model's own commands, checks the symptom is
## really there, and undoes everything if it isn't: a failed generation
## leaves the building exactly as it was. Calls come back GENERATED.


## Could this definition happen at this building right now?
func is_eligible(_definition: JobType, _building: BuildingElectricalModel) -> bool:
	return false


func generate(_definition: JobType, _building: BuildingElectricalModel,
		_repository: ServiceCallRepository, _rng: RandomNumberGenerator) -> ActiveJob:
	return null


## A random element of `items`, with the generator's dice.
static func pick(items: Array, rng: RandomNumberGenerator) -> Variant:
	return items[rng.randi_range(0, items.size() - 1)]


## A complaint from the definition's templates (or its one-line issue).
static func complaint_for(definition: JobType, values: Dictionary, rng: RandomNumberGenerator, fallback_with: Variant) -> String:
	if definition.complaint_templates.is_empty():
		return JobType.fill(definition.issue, fallback_with)
	return definition.complaint(pick(definition.complaint_templates, rng), values)
