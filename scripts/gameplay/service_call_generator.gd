class_name ServiceCallGenerator
extends RefCounted
## Makes new service calls from the real state of the town's houses:
##   1. picks a property (a home, not one already on the board or just visited)
##   2. looks at its actual installation (PropertyRegistry)
##   3. keeps the definitions that apply there (type, ServiceCallSpecs rules,
##      prerequisites, and what its strategy can find)
##   4. picks one by weight
##   5-7. its strategy picks the equipment, makes the fault or request real
##      and writes the complaint (and undoes it all if that fails)
##   8. it's saved in the repository with its own id
##   9. and put up as AVAILABLE, for the scheduler.
## Its dice are its own, seeded from `seed_base` and the repository's serial,
## so the same game makes the same calls, before and after a save.

var properties: PropertyRegistry
var repository: ServiceCallRepository
var strategies := ServiceCallStrategyRegistry.new()
## The definitions it chooses from (those with a weight), in a fixed order.
var catalog: Array[JobType] = []
var seed_base := 0
var rng := RandomNumberGenerator.new()


func _init(properties_: PropertyRegistry, repository_: ServiceCallRepository, seed_base_ := 0, catalog_: Array[JobType] = []) -> void:
	properties = properties_
	repository = repository_
	seed_base = seed_base_
	catalog = catalog_ if not catalog_.is_empty() else JobType.dispatchable()


## A new call, AVAILABLE, or null if nothing anywhere can happen right now.
## `business`: jobs done and five-star reviews, for prerequisites. `avoid`:
## addresses not to send a call to (on the board already, just visited).
func generate(jobs_done := 0, five_stars := 0, avoid: Array = []) -> ActiveJob:
	rng.seed = hash("calls:%d:%d" % [seed_base, repository.next_serial])
	var homes := properties.residential().filter(func(p: Dictionary) -> bool: return not p["address"] in avoid)
	# Look at homes in a random order until one has something that can happen there.
	while not homes.is_empty():
		var home: Dictionary = homes.pop_at(rng.randi_range(0, homes.size() - 1))
		var building := properties.model_for(home["address"])
		var ctx := ServiceCallSpecs.Context.new()
		ctx.building = building
		ctx.repository = repository
		ctx.jobs_done = jobs_done
		ctx.five_stars = five_stars
		var choices := eligible(ctx)
		while not choices.is_empty():
			var definition := pick_weighted(choices)
			var job := strategies.resolve(definition.generation_strategy).generate(definition, building, repository, rng)
			if job != null:
				job.transition_to(ActiveJob.Status.AVAILABLE)
				repository.update(job)
				return job
			choices.erase(definition)       # its strategy found nothing after all: the next one
	return null


## The definitions that can happen at this building right now.
func eligible(ctx: ServiceCallSpecs.Context) -> Array[JobType]:
	var out: Array[JobType] = []
	for d in catalog:
		if not ctx.building.property_type in d.property_types:
			continue
		if not ServiceCallSpecs.all_hold(d.eligibility, ctx) or not ServiceCallSpecs.all_hold(d.prerequisites, ctx):
			continue
		var strategy := strategies.resolve(d.generation_strategy)
		if strategy == null:
			push_error("No generation strategy '%s' for %s" % [d.generation_strategy, d.definition_id])
			continue
		if strategy.is_eligible(d, ctx.building):
			out.append(d)
	return out


func pick_weighted(choices: Array[JobType]) -> JobType:
	var total := 0.0
	for d in choices:
		total += d.weight
	var roll := rng.randf() * total
	for d in choices:
		roll -= d.weight
		if roll < 0.0:
			return d
	return choices[-1]
