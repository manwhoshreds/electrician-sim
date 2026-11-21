extends "res://tests/test_case.gd"
## The service call system: generation from the real state of houses,
## eligibility rules, weighted choice, real faults and requests, persistence,
## the dispatch board, and completion judged by the electrics. The last tests
## play the three required scenarios through the real game.

const TOWN := [
	{"address": "1 Ash St", "two_story": false},
	{"address": "2 Birch St", "two_story": true},
	{"address": "Shop", "business": true},
]

var main: Node
var service: ServiceCall


func after_each() -> void:
	super()
	Engine.time_scale = 1.0
	SaveGame.enabled = true


func _registry() -> PropertyRegistry:
	return PropertyRegistry.new(TOWN.duplicate(true))


func _generator(seed_base := 1, catalog: Array[JobType] = [], registry: PropertyRegistry = null) -> ServiceCallGenerator:
	return ServiceCallGenerator.new(registry if registry != null else _registry(), ServiceCallRepository.new(), seed_base, catalog)


func _ctx(b: BuildingElectricalModel) -> ServiceCallSpecs.Context:
	var ctx := ServiceCallSpecs.Context.new()
	ctx.building = b
	ctx.repository = ServiceCallRepository.new()
	return ctx


func _only(kind: String) -> Array[JobType]:
	return [JobType.of(kind)] as Array[JobType]


# --- Generation -------------------------------------------------------------------------

func test_a_generated_call_is_available_saved_and_real() -> void:
	var g := _generator(3)
	for i in 12:
		var job := g.generate()
		check(job != null, "a call")
		if job == null:
			return
		eq(job.status, ActiveJob.Status.AVAILABLE)
		is_true(g.repository.records.has(job.id), "saved under its id")
		check(job.address != "Shop", "homes only, for now")
		is_true(job.type.weight > 0.0)
		if job.placed_on_arrival:
			continue
		is_false(job.outcomes_complete(), "%s starts out not done: the problem's real" % job.kind)


func test_ids_are_unique() -> void:
	var g := _generator(4)
	var ids := {}
	for i in 15:
		var job := g.generate()
		if job != null:
			is_false(ids.has(job.id), job.id)
			ids[job.id] = true


func test_same_seed_same_calls() -> void:
	var a := _generator(42)
	var b := _generator(42)
	for i in 8:
		var ja := a.generate()
		var jb := b.generate()
		eq([ja.definition_id, ja.address, ja.equipment_ids, ja.cause, ja.complaint],
				[jb.definition_id, jb.address, jb.equipment_ids, jb.cause, jb.complaint], "call %d" % i)


func test_weights_decide_how_often() -> void:
	var heavy := JobType.of("weak").duplicate() as JobType
	var light := JobType.of("hot").duplicate() as JobType
	heavy.weight = 90.0
	light.weight = 10.0
	var g := _generator(1, [heavy, light] as Array[JobType])
	var count := {heavy: 0, light: 0}
	for i in 1000:
		g.rng.seed = i
		count[g.pick_weighted([heavy, light] as Array[JobType])] += 1
	is_true(count[heavy] > 850 and count[heavy] < 950, "about 90%%: %d" % count[heavy])


func test_eligibility_rules_follow_the_house() -> void:
	var ranch := BuildingElectricalModel.residential("1 Ash St", ElectricalPanel.new(), false)
	var two := BuildingElectricalModel.residential("2 Birch St", ElectricalPanel.new(), true)
	var g := _generator()
	is_true(g.eligible(_ctx(ranch)).has(JobType.of("jbox")), "an attic splice needs an attic")
	is_false(g.eligible(_ctx(two)).has(JobType.of("jbox")), "and a two-story has none to get into")
	ranch.panel.toggle_main()
	var dark := g.eligible(_ctx(ranch))
	is_false(dark.has(JobType.of("dead_receptacles")), "no power anywhere: not a dead-outlet call")
	is_false(dark.has(JobType.of("weak")))


func test_prerequisites_gate_on_the_business() -> void:
	var d := JobType.of("hot").duplicate() as JobType
	d.prerequisites = ["min_five_stars:10"] as Array[String]
	var g := _generator(1, [d] as Array[JobType])
	var ctx := _ctx(BuildingElectricalModel.residential("1 Ash St", ElectricalPanel.new()))
	eq(g.eligible(ctx), [] as Array[JobType], "not yet")
	ctx.five_stars = 10
	eq(g.eligible(ctx), [d] as Array[JobType], "now they'll call you for it")


func test_property_type_has_to_match() -> void:
	var d := JobType.of("hot").duplicate() as JobType
	d.property_types = ["commercial"] as Array[String]
	eq(_generator(1, [d] as Array[JobType]).generate(), null, "no commercial calls at homes")


func test_one_definition_many_real_causes() -> void:
	var causes := {}
	for s in 60:
		var b := BuildingElectricalModel.residential("1 Ash St", ElectricalPanel.new())
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var job := DeadReceptaclesStrategy.new().generate(JobType.of("dead_receptacles"), b, ServiceCallRepository.new(), rng)
		causes[job.cause] = true
		eq(b.device(job.equipment_ids[0]).condition, job.cause, "the cause is in the equipment itself")
		for word in ["loose", "splice", "scorch", "burnt", "backstab", "junction"]:
			is_false(job.complaint.to_lower().contains(word), "complaint gives away nothing: " + job.complaint)
	eq(causes.keys().size(), 3, "loose, scorched and bad_splice all come up: %s" % str(causes.keys()))


func test_overload_complaint_is_symptoms_only() -> void:
	var b := BuildingElectricalModel.residential("1 Ash St", ElectricalPanel.new())
	var job := BreakerTripStrategy.new().generate(JobType.of("overload"), b, ServiceCallRepository.new(), RandomNumberGenerator.new())
	is_false(job.complaint.to_lower().contains("heater"), job.complaint)


func test_a_failed_generation_leaves_nothing_behind() -> void:
	var b := BuildingElectricalModel.residential("1 Ash St", ElectricalPanel.new())
	var repo := ServiceCallRepository.new()
	var d := JobType.of("install_receptacle")
	var rng := RandomNumberGenerator.new()
	var first := InstallDeviceStrategy.new().generate(d, b, repo, rng)
	check(first != null, "first request")
	# A second request for a spot already asked about fails, and leaves no half-made request.
	var before := b.snapshot()
	repo.records[first.id]["incident_key"] = "%s:install:%s" % [b.building_id, "living_room_lamp"]
	repo.records["x"] = {"incident_key": "%s:install:%s" % [b.building_id, b.open_install_spots()[0]], "status": ActiveJob.Status.AVAILABLE}
	eq(InstallDeviceStrategy.new().generate(d, b, repo, rng), null)
	eq(b.snapshot(), before, "nothing changed")


func test_no_two_open_calls_about_one_thing() -> void:
	var g := _generator(5, _only("wh_upper"))
	var first := g.generate()
	check(first != null, "first")
	var second := g.generate()
	check(second == null or second.address != first.address, "the same heater never gets a second open call")


# --- Persistence ---------------------------------------------------------------------------

func test_a_fault_made_before_you_visit_survives_a_save() -> void:
	var registry := _registry()
	var g := _generator(9, _only("light_switch"), registry)
	var job := g.generate()
	var b := registry.model_for(job.address)
	var condition := b.device(job.equipment_ids[0]).condition
	is_true(condition != "", "faulted")
	var saved: Dictionary = JSON.parse_string(JSON.stringify({"props": registry.to_save(), "calls": g.repository.to_save()}))
	var back := _registry()
	back.load_save(saved["props"])
	eq(back.model_for(job.address).device(job.equipment_ids[0]).condition, condition, "still broken after loading")
	var repo := ServiceCallRepository.new()
	repo.load_save(saved["calls"])
	var board := ServiceCallScheduler.new(repo)
	board.rebuild(back)
	eq(board.board.size(), 1)
	var again := board.board[0]
	eq(again.id, job.id)
	is_true(again.device == back.model_for(job.address).device(job.equipment_ids[0]), "pointing at the same real equipment")
	is_false(again.outcomes_complete())


func test_an_install_request_survives_a_save() -> void:
	var registry := _registry()
	var job := _generator(2, _only("install_receptacle"), registry).generate()
	var b := registry.model_for(job.address)
	var id: String = job.equipment_ids[0]
	eq(b.rough_in(id, b.source_candidates_in(b.rooms[id])[0]), "")
	var back := _registry()
	back.load_save(JSON.parse_string(JSON.stringify(registry.to_save())))
	var b2 := back.model_for(job.address)
	is_true(b2.roughed_in(id), "cut in")
	is_true(b2.device(id).source == b2.device(b2.installs[id]["source"]), "fed from the same outlet")
	is_true(b2.device(b2.installs[id]["source"]).wires.has("hot_out"), "and the new cable's still in that outlet's box")


# --- The board ---------------------------------------------------------------------------------

func _call(urgency: String, hours := 8.0) -> ActiveJob:
	var j := ActiveJob.new()
	j.type = JobType.of("hot").duplicate() as JobType
	j.type.expires_after_hours = hours
	j.urgency = urgency
	j.transition_to(ActiveJob.Status.AVAILABLE)
	return j


func test_business_hours_and_weekends() -> void:
	var monday_9 := 9.0 * 60.0
	var friday_6pm := 4 * ServiceCallScheduler.DAY + 18.0 * 60.0
	is_true(ServiceCallScheduler.is_business_hours(monday_9))
	is_false(ServiceCallScheduler.is_business_hours(friday_6pm))
	eq(ServiceCallScheduler.next_opening(friday_6pm), 7 * ServiceCallScheduler.DAY + 8.0 * 60.0, "Monday 8:00")


func test_emergencies_go_now_standard_waits_for_opening() -> void:
	var board := ServiceCallScheduler.new(ServiceCallRepository.new())
	var night := 22.0 * 60.0
	var standard := _call("standard")
	var emergency := _call("emergency")
	board.post(standard, night)
	board.post(emergency, night)
	eq(board.next_call(night), emergency, "an emergency jumps the queue")
	eq(board.start(emergency, night), night, "and goes now")
	eq(emergency.status, ActiveJob.Status.IN_PROGRESS)
	eq(board.start(standard, night), ServiceCallScheduler.DAY + 8.0 * 60.0, "the other waits for the morning")


func test_appointments_are_booked() -> void:
	var board := ServiceCallScheduler.new(ServiceCallRepository.new())
	var j := _call("appointment")
	board.post(j, 10.0 * 60.0)
	eq(j.status, ActiveJob.Status.SCHEDULED)
	eq(j.scheduled_for, 11.0 * 60.0)
	eq(j.window_end - j.window_start, ServiceCallScheduler.APPOINTMENT_LENGTH)


func test_calls_nobody_gets_to_expire() -> void:
	var board := ServiceCallScheduler.new(ServiceCallRepository.new())
	var j := _call("emergency", 2.0)
	board.post(j, 600.0)
	eq(board.expire(600.0 + 60.0), [] as Array[ActiveJob])
	eq(board.expire(600.0 + 121.0), [j] as Array[ActiveJob])
	eq(j.status, ActiveJob.Status.EXPIRED)
	eq(board.board.size(), 0)


# --- Installing: completion from the real wiring ------------------------------------------------

func _requested() -> Array:
	var b := BuildingElectricalModel.residential("1 Ash St", ElectricalPanel.new())
	var job := InstallDeviceStrategy.new().generate(JobType.of("install_receptacle"), b, ServiceCallRepository.new(), RandomNumberGenerator.new())
	return [b, job, job.equipment_ids[0]]


## Lands the new cable at the source and wires a receptacle into the new box.
func _wire_it(b: BuildingElectricalModel, id: String, hot_on := "brass_bottom") -> void:
	var source := b.device(b.installs[id]["source"])
	source.land("hot_out", hot_on)
	source.land("neutral_out", "silver_bottom")
	source.land("ground_out", "green")
	var d := b.device(id)
	eq(d.install("Receptacle"), "")
	d.land("hot", "brass_top")
	d.land("neutral", "silver_top")
	d.land("ground", "green")
	d.push_in()
	d.toggle_mount_screw(0)
	d.toggle_mount_screw(1)
	d.refit_plate()


func test_a_request_changes_nothing_electrical() -> void:
	var b := BuildingElectricalModel.residential("1 Ash St", ElectricalPanel.new())
	var before := b.receptacle_ids().map(func(id: String) -> String: return b.device(id).repair_state())
	var r := _requested()
	eq((r[0] as BuildingElectricalModel).receptacle_ids().map(func(id: String) -> String: return r[0].device(id).repair_state()), before)
	is_false((r[1] as ActiveJob).outcomes_complete(), "nothing installed yet")


func test_installed_and_wired_right_it_is_done() -> void:
	var r := _requested()
	var b: BuildingElectricalModel = r[0]
	var id: String = r[2]
	eq(b.rough_in(id, b.source_candidates_in(b.rooms[id])[0]), "")
	is_false((r[1] as ActiveJob).outcomes_complete(), "box cut in, nothing wired")
	is_true(b.device(b.installs[id]["source"]).repair_state() == "miswired", "loose new cable in the old box: not left like that")
	_wire_it(b, id)
	near(b.device(id).face_volts(), 120.0, "power at the new outlet", 2.0)
	is_true((r[1] as ActiveJob).outcomes_complete())


func test_any_outlet_in_the_room_can_feed_it() -> void:
	var r := _requested()
	var b: BuildingElectricalModel = r[0]
	var id: String = r[2]
	var sources := b.source_candidates_in(b.rooms[id])
	is_true(sources.size() >= 2, "a choice")
	eq(b.rough_in(id, sources[-1]), "")
	_wire_it(b, id)
	is_true((r[1] as ActiveJob).outcomes_complete(), "fed from another one, just as good")


func test_black_on_the_silver_screw_isnt_done() -> void:
	var r := _requested()
	var b: BuildingElectricalModel = r[0]
	var id: String = r[2]
	b.rough_in(id, b.source_candidates_in(b.rooms[id])[0])
	_wire_it(b, id, "silver_bottom")
	is_false((r[1] as ActiveJob).outcomes_complete())


func test_neutral_left_off_at_the_source_isnt_done() -> void:
	var r := _requested()
	var b: BuildingElectricalModel = r[0]
	var id: String = r[2]
	b.rough_in(id, b.source_candidates_in(b.rooms[id])[0])
	_wire_it(b, id)
	b.device(b.installs[id]["source"]).loosen("neutral_out")
	eq(b.device(id).face_volts(), 0.0, "no neutral: no power at the face")
	is_false((r[1] as ActiveJob).outcomes_complete())


# --- The three scenarios, through the real game ------------------------------------------------

func _play(kind: String, cause := "") -> void:
	SaveGame.enabled = false
	Engine.time_scale = 0.0
	seed(11)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_node(main)
	service = main.service
	service.tuning = JobTuning.new()
	var d := JobType.of(kind)
	if cause != "":
		d = d.duplicate() as JobType
		d.causes = {cause: 1.0}
	service.call_generator.catalog = [d] as Array[JobType]
	service.start_job()
	service._on_customer(service.player)
	service._go_to_work()


func _customer_says() -> String:
	service._return_visit()
	return service.dialogue._text.text


func test_scenario_dead_receptacle() -> void:
	_play("dead_receptacles", "loose")
	var job := service.job
	eq(job.status, ActiveJob.Status.IN_PROGRESS)
	eq(job.cause, "loose")
	var d := job.device
	eq(d.face_volts(), 0.0, "the outlet's really dead")
	is_true(service._box != null and service._box.device == d, "the house's own outlet")
	is_false(_customer_says().contains("that's got it"), "not fixed yet")
	# Fix it the right way: wires off the backstab holes, onto the screws.
	d.loosen("hot")
	d.land("hot", "brass_top")
	d.loosen("neutral")
	d.land("neutral", "silver_top")
	is_true(job.outcomes_complete(), "power at the face, wired right")
	is_true(_customer_says().contains("that's got it"))


func test_scenario_overloaded_circuit() -> void:
	_play("overload")
	var job := service.job
	var c := service._sim.circuit_at(job.target)
	is_true(c.breaker.tripped, "really tripped")
	eq(c.breaker.fault, Breaker.Fault.NONE, "nothing wrong with the breaker")
	is_false(job.outcomes_complete())
	service._advise_overload()        # tell them: the heater goes elsewhere
	service._sim.toggle(job.target)   # tripped -> off
	service._sim.toggle(job.target)   # -> on
	is_true(job.outcomes_complete(), "load off, breaker on and holding")
	is_true(_customer_says().contains("that's got it"))


func test_scenario_new_receptacle() -> void:
	_play("install_receptacle")
	var job := service.job
	eq(job.family, "install")
	var inside := service._inside
	var b := inside.electrical
	var id: String = job.equipment_ids[0]
	is_false(b.roughed_in(id))
	is_true(_customer_says().contains("pencil line"), "nothing done yet")
	eq(inside.cut_in(id), "no_box", "you need the box and cable in your hands")
	service.inventory.hold("OldWork")
	eq(inside.cut_in(id), "")
	var view := inside.view_for_device(b.device(id))
	check(view != null, "a box in the wall where the mark was")
	eq(inside.layout_violations(), [] as Array[String], "on a wall face, in no doorway")
	var source := b.device(b.installs[id]["source"])
	is_true(source.wires.has("hot_out"), "the new cable's in the feed outlet's box")
	service._sim.toggle(source.slot)   # breaker off to work on the live outlet
	_wire_it(b, id)
	job.device_used("Receptacle", b.device(id))   # what the close-up reports when one goes in
	service._sim.toggle(source.slot)
	is_true(job.outcomes_complete())
	is_true(_customer_says().contains("that's got it"))
	var parts := job.parts_cost(service.tuning)
	eq(parts, PartSpec.price_of("Receptacle") + PartSpec.price_of("OldWork"), "both parts on the bill")


func test_the_feed_outlet_has_to_be_put_back_together_too() -> void:
	var r := _requested()
	var b: BuildingElectricalModel = r[0]
	var id: String = r[2]
	b.rough_in(id, b.source_candidates_in(b.rooms[id])[0])
	_wire_it(b, id)
	var source := b.device(b.installs[id]["source"])
	source.remove_plate_screw(0)
	near(b.device(id).face_volts(), 120.0, "the new one works", 2.0)
	is_false((r[1] as ActiveJob).outcomes_complete(), "but the old one's left with its plate off")


func test_an_emergency_goes_ahead_of_work_that_could_start_now() -> void:
	var board := ServiceCallScheduler.new(ServiceCallRepository.new())
	var ten := 10.0 * 60.0
	var standard := _call("standard", 1.0)    # posted first, and it'd expire sooner
	var emergency := _call("emergency", 8.0)
	board.post(standard, ten)
	board.post(emergency, ten)
	eq(board.next_call(ten), emergency)
