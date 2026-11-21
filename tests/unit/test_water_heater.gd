extends "res://tests/test_case.gd"
## The water heater: what the meter reads on it with each fault, the water,
## dry firing, and a whole call played through, from dispatch to the job sheet.

var main: Node
var service: ServiceCall


func after_each() -> void:
	super()
	Engine.time_scale = 1.0
	SaveGame.enabled = true


## A heater on a live 240 V supply.
func _powered(fault := "") -> WaterHeater:
	var h := WaterHeater.new()
	if fault != "":
		h.set_fault(fault)
	h.leg1 = 121.2
	h.leg2 = -119.6
	return h


# --- The electrics -----------------------------------------------------------------------

func test_a_good_heater_up_to_temperature_sits_quiet() -> void:
	var h := _powered()
	eq(h.calling(), "")
	near(h.voltage("l1", "l2"), 240.8, "240 at the top screws")
	near(h.voltage("u_a", "u_b"), 0.0, "nothing across the upper element")
	near(h.voltage("lo_a", "lo_b"), 0.0, "nor the lower")
	near(h.amps(), 0.0)
	is_true(h.fixed())


func test_burnt_upper_element_240_across_it_no_amps() -> void:
	var h := _powered("upper_element")
	eq(h.calling(), "upper", "the top's cold, so the upper thermostat holds on to the power")
	near(h.voltage("u_a", "u_b"), 240.8, "full voltage across it")
	near(h.amps(), 0.0, "but it isn't drawing anything")
	near(h.voltage("lo_a", "lo_b"), 0.0, "the lower never gets a turn")
	h.leg1 = 0.0
	h.leg2 = 0.0
	eq(h.ohms("u_a", "u_b"), -1.0, "power off, it reads open")
	near(h.ohms("lo_a", "lo_b"), WaterHeater.ELEMENT_OHMS, "the lower one's fine")
	is_false(h.fixed())


func test_burnt_lower_element_some_hot_water() -> void:
	var h := _powered("lower_element")
	eq(h.calling(), "lower", "the top's hot, so it's the lower one's turn")
	near(h.voltage("lo_a", "lo_b"), 240.8)
	near(h.voltage("u_a", "u_b"), 0.0)
	near(h.amps(), 0.0)


func test_tripped_high_limit_power_in_nothing_out() -> void:
	var h := _powered("eco")
	near(h.voltage("l1", "l2"), 240.8, "power to the thermostat")
	near(h.voltage("u_a", "u_b"), 0.0, "none past the high-limit")
	h.reset_eco()
	near(h.voltage("u_a", "u_b"), 240.8, "reset: the upper element comes on")
	near(h.amps(), WaterHeater.ELEMENT_AMPS, "and draws its 18.75 A")


func test_breaker_off_everything_dead() -> void:
	var h := WaterHeater.new()
	h.set_fault("upper_element")
	for p in ["l1", "l2", "u_a", "u_b", "lo_a", "lo_b"]:
		is_false(h.is_live(p), p)


func test_drained_below_it_the_element_comes_out_dry() -> void:
	var h := WaterHeater.new()
	h.set_fault("upper_element")
	h.wired["upper"] = false
	is_false(h.can_unscrew("upper"), "full tank: it'd pour out")
	h.hose = true
	h.drain_open = true
	h.tick(10.0)
	is_true(h.level > 0.9, "with the cold still on, it doesn't go down")
	h.cold_open = false
	h.tick(WaterHeater.DRAIN_SECONDS * 0.35)
	is_true(h.can_unscrew("upper"), "cold off, drain open, it comes down past the upper element")
	is_false(h.can_unscrew("lower"), "but not the lower one yet")
	is_true(h.unscrew("upper"))
	h.tick(5.0)
	near(h.spilled, 0.0, "down the hose and outside: nothing on the floor")
	is_false(h.flooded)
	is_true(h.fit("upper"))
	eq(h.element["upper"], "ok")


func test_an_element_out_under_water_floods_the_floor() -> void:
	var h := WaterHeater.new()
	h.wired["lower"] = false
	h.cold_open = false
	is_true(h.unscrew("lower"), "it comes out, full tank and all")
	h.tick(1.0)
	is_true(h.flooded, "the tank empties down to the hole, onto the floor")
	eq(h.events, ["flood"] as Array[String])
	is_true(h.level > WaterHeater.ELEMENT_LEVEL["lower"] - 0.001, "down to the hole, no further")


func test_the_drain_with_no_hose_goes_on_the_floor() -> void:
	var h := WaterHeater.new()
	h.cold_open = false
	h.drain_open = true
	h.tick(1.0)
	is_true(h.spilled > 0.0, "straight onto the floor")
	is_false(h.flooded, "shut it quick and it's a puddle")
	h.tick(WaterHeater.DRAIN_SECONDS * WaterHeater.FLOOD)
	is_true(h.flooded, "leave it and it's a flood")


func test_power_on_before_its_full_burns_the_new_element_out() -> void:
	var h := WaterHeater.new()
	h.level = 0.2
	h.cold_open = true
	h.heat_top = 0.0
	h.leg1 = 121.2
	h.leg2 = -119.6
	h.tick(0.1)
	eq(h.element["upper"], "open", "dry fired")
	eq(h.events, ["dry_fire:upper"] as Array[String])


func test_the_disconnect_kills_the_heater_but_not_its_line_side() -> void:
	var h := _powered()
	is_true(h.powered())
	h.disconnect_in = false
	is_false(h.powered(), "handle out: the heater's dead")
	near(h.voltage("l1", "l2"), 0.0, "nothing at the heater")
	near(h.voltage("dl1", "dl2"), 240.8, "but the lugs from the panel are still live")
	h.disconnect_in = true
	is_true(h.powered())


func test_save_and_load() -> void:
	var h := WaterHeater.new()
	h.set_fault("lower_element")
	h.cover_on["upper"] = false
	h.level = 0.5
	var back := WaterHeater.new()
	back.load_save(JSON.parse_string(JSON.stringify(h.to_save())))
	eq(back.to_save(), h.to_save())


# --- Dispatch ---------------------------------------------------------------------------

func test_a_heater_call_is_a_real_fault_in_the_house() -> void:
	var b := BuildingElectricalModel.residential("12 Elm St", ElectricalPanel.new())
	var rng := RandomNumberGenerator.new()
	for kind in ["wh_upper", "wh_lower", "wh_eco"]:
		b.water_heater = WaterHeater.new()
		b.water_heater.panel = b.panel
		var j := WaterHeaterStrategy.new().generate(JobType.of(kind), b, ServiceCallRepository.new(), rng)
		check(j != null, kind)
		if j == null:
			continue
		eq(j.family, "heater")
		eq(j.target, 5, "the water heater circuit")
		is_false(b.water_heater.fixed(), kind + ": really broken")
		is_false(j.outcomes_complete())


func test_one_heater_call_at_a_time() -> void:
	var b := BuildingElectricalModel.residential("12 Elm St", ElectricalPanel.new())
	var repo := ServiceCallRepository.new()
	check(WaterHeaterStrategy.new().generate(JobType.of("wh_upper"), b, repo, RandomNumberGenerator.new()) != null, "first")
	is_false(WaterHeaterStrategy.new().is_eligible(JobType.of("wh_eco"), b), "already broken: no second call about it")


# --- A whole call -----------------------------------------------------------------------

func _heater_job(kind: String) -> void:
	SaveGame.enabled = false
	Engine.time_scale = 0.0
	seed(3)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_node(main)
	service = main.service
	service.tuning = JobTuning.new()
	service.call_generator.catalog = [JobType.of(kind)] as Array[JobType]
	service.start_job()
	service._on_customer(service.player)
	service._go_to_work()


func _view() -> WaterHeaterView:
	return service._inside.heater_view


func _sync() -> void:
	_view()._process(0.0)


## A garden hose off the truck, onto the drain and outside.
func _hose_on(v: WaterHeaterView) -> void:
	service.inventory.take("GardenHose")
	v.click("hose")
	is_true(service._inside.heater.hose, "hose on")


func _probe(red: String, black: String) -> void:
	_view().click("probe", red)
	_view().click("probe", black, true)


func test_burnt_upper_element_fixed_properly_five_stars() -> void:
	_heater_job("wh_upper")
	eq(service.job.kind, "wh_upper")
	var v := _view()
	var h := service._inside.heater
	var sim := service._sim
	_sync()
	near(sim.current("wire_5"), 0.0, "the heater's drawing nothing")
	v.click("cover_off", "upper")
	v.select_tool(WaterHeaterView.Tool.METER)
	ClampMeter.dial = ClampMeter.Mode.VOLTS
	_probe("u_a", "u_b")
	eq(v.reading(), "240.8 V")
	is_true(v.work.measured_live)
	sim.toggle(5)                      # breaker off
	_sync()
	_probe("l1", "l2")
	is_true(v.work.verified_dead, "L1 to L2 reads dead")
	ClampMeter.dial = ClampMeter.Mode.OHMS
	_probe("u_a", "u_b")
	eq(v.reading(), "OL (open)")
	v.click("cover_off", "lower")
	_probe("lo_a", "lo_b")
	eq(v.reading(), "12.8 ohms")
	eq(v.ohmed.size(), 2)
	v.click("cold")
	_hose_on(v)
	v.click("drain")
	h.tick(WaterHeater.DRAIN_SECONDS * 0.4)
	v.click("wires", "upper")
	v.click("unscrew", "upper")
	eq(h.element["upper"], "out")
	service.inventory.hold("Element")
	v.click("fit", "upper")
	eq(h.element["upper"], "ok")
	v.click("wires", "upper")
	v.click("drain")
	v.click("cold")
	h.tick(WaterHeater.FILL_SECONDS)
	sim.toggle(5)                      # breaker back on, tank full
	_sync()
	eq(h.element["upper"], "ok", "full before the power: no dry fire")
	near(sim.current("wire_5"), WaterHeater.ELEMENT_AMPS, "heating, 18.75 A on the clamp")
	v.select_tool(WaterHeaterView.Tool.METER)
	ClampMeter.dial = ClampMeter.Mode.VOLTS
	_probe("u_a", "u_b")
	is_true(v.work.tested_after, "240 across the new element, power on")
	v.click("cover_on", "upper")
	v.click("cover_on", "lower")
	sim.demo.erase("5:water heater")   # nobody's draining the clamp here; keep the next frame quiet
	service._return_visit()
	var sheet := Billing.settle(service.job, service._work(), true, service.tuning, 1.0)
	eq(sheet.stars, 5, "\n".join(sheet.lines))
	eq(service.job.final_device, "Element")
	eq(service.job.wrong_parts, 0)


func test_screwdriver_on_a_live_element_bites() -> void:
	_heater_job("wh_upper")
	var v := _view()
	_sync()
	v.click("cover_off", "upper")
	v.click("wires", "upper")
	eq(v.work.shocks, 1)
	is_true(service._inside.heater.wired["upper"], "and the wires are still on")


func test_powering_up_half_empty_burns_out_the_new_one() -> void:
	_heater_job("wh_upper")
	var v := _view()
	var h := service._inside.heater
	service._sim.toggle(5)
	_sync()
	v.click("cover_off", "upper")
	v.click("cold")
	_hose_on(v)
	v.click("drain")
	h.tick(WaterHeater.DRAIN_SECONDS * 0.4)
	v.click("wires", "upper")
	v.click("unscrew", "upper")
	service.inventory.hold("Element")
	v.click("fit", "upper")
	v.click("wires", "upper")
	v.click("drain")
	v.click("cold")
	service._sim.toggle(5)             # straight back on, tank still low
	v._process(0.1)
	eq(h.element["upper"], "open", "dry fired")
	eq(service.job.wrong_parts, 1, "a wasted element")


func test_pulling_the_element_under_water_gets_you_thrown_out() -> void:
	_heater_job("wh_upper")
	var v := _view()
	var h := service._inside.heater
	var money := service.wallet.money
	service._sim.toggle(5)             # breaker off: no shock, just water
	_sync()
	v.click("cover_off", "upper")
	v.click("wires", "upper")
	v.click("unscrew", "upper")        # cold on, tank full
	v._process(1.0)
	is_true(h.flooded)
	check(service.dialogue._text.text.contains("calling another company"), service.dialogue._text.text)
	eq(service.wallet.money, money - service.tuning.flood_cost, "water damage")
	service.abandon_job("flooded the laundry")       # "I'm sorry. I'll go."
	eq(service.job.stars_given, 1)
	eq(service.job.status, ActiveJob.Status.CANCELLED, "they called someone else")
	check(service.aftercare.reviews[-1]["text"].contains("Flooded my laundry"), service.aftercare.reviews[-1]["text"])


func test_pulling_the_disconnect_is_a_way_to_kill_it() -> void:
	_heater_job("wh_upper")
	var v := _view()
	var h := service._inside.heater
	_sync()
	v.click("disc_door")
	v.click("pullout")
	is_false(h.disconnect_in)
	is_false(h.powered(), "dead at the heater with the breaker still on")
	v.click("cover_off", "upper")
	v.click("wires", "upper")
	eq(v.work.shocks, 0, "nothing to bite you")


func test_tripped_high_limit_reset_and_paid() -> void:
	_heater_job("wh_eco")
	eq(service.job.kind, "wh_eco")
	var v := _view()
	var h := service._inside.heater
	_sync()
	is_true(h.eco_tripped)
	v.click("cover_off", "upper")
	v.click("reset")
	is_false(h.eco_tripped)
	v.click("cover_on", "upper")
	_sync()
	is_true(h.fixed())
	service._return_visit()
	eq(service.job.final_device, "", "no parts on a reset")
	is_true(service._card()["steps"][3][1], "found it and fixed it")


func test_looking_at_the_heater_offers_it() -> void:
	_heater_job("wh_lower")
	var v := _view()
	var player: Player = main.player
	await tree.physics_frame
	player.global_position = service._inside.to_global(Vector3(-0.4, HouseInterior.FLOOR, -3.2))
	var eye := player.global_position + Vector3(0, player.head.position.y, 0)
	var to := v.aim_point() - eye
	player.rotation.y = atan2(-to.x, -to.z)
	player.head.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
	check(player._looked_at() == v, "the water heater's prompt")
