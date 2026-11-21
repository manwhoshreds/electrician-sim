extends "res://tests/test_case.gd"
## The first data-driven call, entirely against an unloaded house model.


func _definition() -> JobType:
	return JobType.of("dead_receptacles")


func _rng(n: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = n
	return r


func _building(two_story := false) -> BuildingElectricalModel:
	return BuildingElectricalModel.residential("214 Cedar St", ElectricalPanel.new(), two_story)


func test_definition_is_data_not_a_script_per_call() -> void:
	var d := _definition()
	eq(d.definition_id, "dead_receptacles")
	eq(d.category, "troubleshooting")
	eq(d.generation_strategy, "dead_receptacles")
	is_true(d.complaint_templates.size() >= 2)
	is_true(d.objective_templates.size() == 1)


func test_unloaded_house_has_stable_equipment_ids_and_real_links() -> void:
	var b := _building()
	eq(b.box_ids[0], "box_00")
	eq(b.device("box_00").kind, "Range")
	eq(b.device("box_05").feed, b.device("box_06"))
	eq(b.device("box_11").partner, b.device("box_12"))
	is_true(b.affected_receptacles("junction_00").size() >= 4)
	eq(_building(true).junction_ids, [], "two-story houses have no accessible attic model")


func test_valid_call_is_generated_from_real_domain_state() -> void:
	var b := _building()
	var repo := ServiceCallRepository.new()
	var job := DeadReceptaclesStrategy.new().generate(_definition(), b, repo, _rng(1))
	check(job != null, "a valid house gets a call")
	if job == null:
		return
	eq(job.status, ActiveJob.Status.GENERATED, "made and saved; the generator puts it on the board")
	eq(job.building_id, "214 Cedar St")
	is_true(not job.equipment_ids.is_empty())
	is_true(job.device.face_volts() < 5.0, "the actual fault makes power disappear")
	is_false(job.outcomes_complete())
	for hidden in ["loose", "splice", "backstab", "fault"]:
		is_false(job.complaint.to_lower().contains(hidden), "complaint does not reveal " + hidden)


func test_fixing_the_domain_completes_the_outcome() -> void:
	var b := _building(true)       # no junction: this is the loose receptacle path
	var job := DeadReceptaclesStrategy.new().generate(_definition(), b, ServiceCallRepository.new(), _rng(3))
	check(job != null, "generated")
	if job == null:
		return
	var healthy := ElectricalDevice.new("Receptacle", b.panel, job.device.slot)
	job.device.restore(healthy.snapshot())
	is_true(job.outcomes_complete(), "real voltage and repair state, not a mission flag")


func test_invalid_scenario_is_rejected_without_a_partial_fault() -> void:
	var b := _building(true)
	b.panel.toggle_main()
	var before := b.snapshot()
	var job := DeadReceptaclesStrategy.new().generate(_definition(), b, ServiceCallRepository.new(), _rng(2))
	eq(job, null, "a house already without power is not a valid dead-outlet incident")
	eq(b.snapshot(), before, "generation failure changed nothing")
	is_false(DeadReceptaclesStrategy.new().is_eligible(_definition(), b))


func test_generator_filters_an_ineligible_definition() -> void:
	var b := _building(true)
	b.panel.toggle_main()
	var ctx := ServiceCallSpecs.Context.new()
	ctx.building = b
	ctx.repository = ServiceCallRepository.new()
	var generator := ServiceCallGenerator.new(PropertyRegistry.new(), ctx.repository)
	is_false(generator.eligible(ctx).has(_definition()), "no power to the house: no dead-outlet call")


func test_duplicate_unresolved_incident_is_rejected() -> void:
	var b := _building(true)
	var repo := ServiceCallRepository.new()
	var first := DeadReceptaclesStrategy.new().generate(_definition(), b, repo, _rng(7))
	check(first != null, "first call")
	if first == null:
		return
	# Put the receptacle back so the same deterministic draft is otherwise eligible.
	first.device.restore(ElectricalDevice.new("Receptacle", b.panel, first.device.slot).snapshot())
	var second := DeadReceptaclesStrategy.new().generate(_definition(), b, repo, _rng(7))
	eq(second, null, "same unresolved building/equipment incident")


func test_definitions_can_share_one_strategy() -> void:
	var registry := ServiceCallStrategyRegistry.new()
	var a := JobType.new()
	var b := JobType.new()
	a.generation_strategy = "dead_receptacles"
	b.generation_strategy = "dead_receptacles"
	eq(registry.resolve(a.generation_strategy), registry.resolve(b.generation_strategy))


func test_status_transitions_are_enforced() -> void:
	var job := ActiveJob.new()
	is_false(job.transition_to(ActiveJob.Status.COMPLETED), "cannot skip straight to completed")
	is_false(job.transition_to(ActiveJob.Status.ACCEPTED), "not before it's on the board")
	is_true(job.transition_to(ActiveJob.Status.AVAILABLE))
	is_true(job.transition_to(ActiveJob.Status.ACCEPTED))
	is_true(job.transition_to(ActiveJob.Status.IN_PROGRESS))
	is_true(job.transition_to(ActiveJob.Status.COMPLETED))
	is_false(job.transition_to(ActiveJob.Status.ACCEPTED), "completed is final")


func test_repository_round_trip_preserves_calls_and_ids() -> void:
	var b := _building(true)
	var repo := ServiceCallRepository.new()
	var job := DeadReceptaclesStrategy.new().generate(_definition(), b, repo, _rng(9))
	check(job != null, "generated")
	if job == null:
		return
	var saved: Dictionary = JSON.parse_string(JSON.stringify(repo.to_save()))
	var back := ServiceCallRepository.new()
	back.load_save(saved)
	is_true(back.records.has(job.id))
	eq(back.records[job.id]["building_id"], "214 Cedar St")
	eq(back.records[job.id]["equipment_ids"], job.equipment_ids)
	eq(back.next_serial, repo.next_serial)


func test_device_definitions_share_the_device_fault_strategy() -> void:
	var registry := ServiceCallStrategyRegistry.new()
	var strategy := registry.resolve("device_fault")
	for kind in ["bad_gfci", "light_switch", "light_fixture"]:
		var definition := JobType.of(kind)
		eq(definition.generation_strategy, "device_fault", kind)
		eq(registry.resolve(definition.generation_strategy), strategy, kind)


func test_device_strategy_selects_compatible_real_equipment() -> void:
	var expected := {"bad_gfci": ["GFCI"], "light_switch": ["Switch", "ThreeWay"], "light_fixture": ["Fixture"]}
	for kind: String in expected:
		var building := _building()
		var job := DeviceFaultStrategy.new().generate(JobType.of(kind), building, ServiceCallRepository.new(), _rng(4))
		check(job != null, kind + " generated")
		if job == null:
			continue
		check(job.device.kind in expected[kind], kind + " picked compatible equipment")
		if kind in ["light_switch", "light_fixture"]:
			check(job.pair != null, kind + " keeps the paired switch or fixture")
		else:
			eq(job.pair, null, kind + " has no unrelated paired equipment")
		is_false(job.outcomes_complete(), kind + " starts broken")
		var healthy := ElectricalDevice.new(job.device.original, building.panel, job.device.slot, job.device.three_way_role)
		job.device.restore(healthy.snapshot())
		is_true(job.outcomes_complete(), kind + " completes from domain state")


func test_breaker_definitions_share_the_trip_strategy() -> void:
	var registry := ServiceCallStrategyRegistry.new()
	eq(JobType.of("weak").generation_strategy, "breaker_trip")
	eq(JobType.of("overload").generation_strategy, "breaker_trip")
	eq(registry.resolve("breaker_trip"), registry.resolve(JobType.of("weak").generation_strategy))


func test_weak_breaker_call_has_a_real_trip_and_real_outcome() -> void:
	var building := _building()
	var job := BreakerTripStrategy.new().generate(JobType.of("weak"), building, ServiceCallRepository.new(), _rng(1))
	check(job != null, "generated")
	if job == null:
		return
	var circuit := building.panel.circuit_at(job.target)
	eq(circuit.breaker.fault, Breaker.Fault.WEAK)
	is_true(circuit.breaker.tripped)
	is_false(job.outcomes_complete())
	circuit.load_save(ElectricalPanel.new().circuit_at(job.target).to_save())
	is_true(job.outcomes_complete())


func test_overload_call_is_an_actual_overload_not_a_bad_breaker() -> void:
	var building := _building()
	var job := BreakerTripStrategy.new().generate(JobType.of("overload"), building, ServiceCallRepository.new(), _rng(1))
	check(job != null, "generated")
	if job == null:
		return
	var circuit := building.panel.circuit_at(job.target)
	check(job.target != 10, "a dedicated microwave circuit is ineligible")
	eq(circuit.breaker.fault, Breaker.Fault.NONE)
	is_true(circuit.heater > 0.0)
	is_true(circuit.breaker.tripped)
	building.panel.move_heater(job.target)
	circuit.breaker.toggle()
	circuit.breaker.toggle()
	is_true(job.outcomes_complete(), "remove overload, reset, restore")
