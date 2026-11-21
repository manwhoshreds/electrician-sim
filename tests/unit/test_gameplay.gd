extends "res://tests/test_case.gd"
## The gameplay pieces ServiceCall coordinates, on their own: Inventory,
## Wallet, ActiveJob, Billing, JobGenerator, and the data they read.

var tuning: JobTuning


func before_each() -> void:
	tuning = JobTuning.new()       # the script's defaults, not the game's .tres


# --- Data ---------------------------------------------------------------------------

func test_every_part_has_a_file() -> void:
	for id in PartSpec.ORDER:
		var p := PartSpec.of(id)
		check(p != null, "missing data/parts/%s.tres" % id)
		if p != null:
			eq(p.id, id)
			is_true(p.price > 0 and (p.size > 0 or id == "GardenHose"), id)   # the hose coils up behind the seat
	eq(PartSpec.of("breaker20").breaker_rating, 20)
	eq(PartSpec.of("GFCI").breaker_rating, 0)
	eq(PartSpec.price_of("breaker40"), 0, "no such part")
	eq(PartSpec.price_of(""), 0)


func test_every_job_has_a_file() -> void:
	var kinds: Array[String] = []
	for d in JobType.dispatchable():
		kinds.append(d.kind)
	kinds.append("callback")
	is_true(kinds.size() >= 23, "every call dispatch can send")
	for kind in kinds:
		var t := JobType.of(kind)
		check(t != null, "missing data/jobs/%s.tres" % kind)
		if t == null:
			continue
		eq(t.kind, kind)
		is_true(t.issue != "", "%s has an issue line" % kind)
		if t.family == "device":
			is_true(t.box in ["outlet", "switch", "fixture", "switch3", "junction", "smoke", "strategy"], "%s box %s" % [kind, t.box])
		if kind != "callback":
			is_true(t.definition_id == kind, "%s has its id" % kind)
			is_true(not t.eligibility.is_empty(), "%s says where it can happen" % kind)
			check(ServiceCallStrategyRegistry.new().resolve(t.generation_strategy) != null, "%s has a strategy" % kind)
			for part in t.materials:
				is_true(PartSpec.has(part), "%s needs a real part (%s)" % [kind, part])
			if t.quote_part != "":
				is_true(PartSpec.has(t.quote_part), "%s quotes a real part" % kind)
		if t.asks_questions and kind != "callback":
			is_true(t.answer("when") != "" and t.answer("touched") != "" and t.answer("new") != "", "%s answers" % kind)


func test_fill() -> void:
	eq(JobType.fill("No light in the %s", "kitchen"), "No light in the kitchen")
	eq(JobType.fill("Smoke detector chirping", "kitchen"), "Smoke detector chirping", "nothing to fill")


func test_tuning_defaults_are_the_old_numbers() -> void:
	eq(tuning.call_out, 95)
	eq(tuning.labour, 110)
	eq(tuning.safe_bonus, 30)
	eq(tuning.thorough_bonus, 25)
	eq(tuning.shock_cost, 60)
	eq(tuning.arc_cost, 120)
	eq(tuning.scam_quote, 3400)
	eq(tuning.van_price, 2500)
	eq(tuning.starting_money, 150)
	eq(tuning.board_size, 2)


func test_game_uses_the_tuning_file() -> void:
	var s := ServiceCall.new()
	eq(s.tuning.resource_path, "res://data/job_tuning.tres")
	eq(s.wallet.money, s.tuning.starting_money)
	s.free()


# --- Inventory --------------------------------------------------------------------------

func test_starting_stock_and_load() -> void:
	var inv := Inventory.new()
	eq(inv.stock, Inventory.STARTING_STOCK)
	eq(inv.load_used(), 5)
	is_true(inv.hands_empty())
	is_true(inv.fits("Fixture", 8), "5 + 3 = 8")
	is_false(inv.fits("Fan", 8), "a fan takes 6")
	inv.add("Fan")
	eq(inv.load_used(), 11, "load is room taken, not number of parts")


func test_take_and_put_back() -> void:
	var inv := Inventory.new()
	inv.take("breaker20")
	eq(inv.bag_breakers(), [20] as Array[int])
	eq(inv.count("breaker20"), 0)
	is_false(inv.hands_empty())
	inv.take("GFCI")
	eq(inv.bag, ["breaker20", "GFCI"] as Array[String], "the bag holds more than one thing")
	inv.put_back("breaker20")
	eq(inv.count("breaker20"), 1)
	inv.put_back("GFCI")
	eq(inv.count("GFCI"), 1, "a part goes back too")
	is_true(inv.hands_empty())
	inv.take("GFCI")
	is_true(inv.use("GFCI"))
	is_true(inv.hands_empty())
	eq(inv.count("GFCI"), 0, "it went in the wall")


func test_the_bag_holds_eight() -> void:
	var inv := Inventory.new()
	for i in 12:
		inv.add("Receptacle")
	eq(inv.take_all("Receptacle"), Inventory.BAG_SLOTS)
	is_true(inv.bag_full())
	is_false(inv.take("GFCI"), "no room")
	eq(inv.count("Receptacle"), 13 - Inventory.BAG_SLOTS)
	inv.clear_bag()
	eq(inv.count("Receptacle"), 13, "all back on the truck")


func test_the_job_ending_puts_your_parts_back_on_the_truck() -> void:
	var inv := Inventory.new()
	inv.take("GFCI")
	inv.drop()
	is_true(inv.hands_empty())
	eq(inv.count("GFCI"), 1, "not lost")


func test_customer_parts_arent_from_the_shelf() -> void:
	var inv := Inventory.new()
	inv.hold("Fan")
	is_true(inv.has("Fan"))
	eq(inv.count("Fan"), 0)
	inv.drop()
	is_true(inv.hands_empty())
	eq(inv.count("Fan"), 0, "theirs stays with them, it doesn't stock your truck")


# --- Wallet ---------------------------------------------------------------------------

func test_wallet() -> void:
	var w := Wallet.new(100)
	is_true(w.can_afford(100))
	is_false(w.can_afford(101))
	w.earn(50)
	w.pay(200)
	eq(w.money, -50, "fines can put you in the red")


# --- ActiveJob --------------------------------------------------------------------------

func _job(kind: String, family := "panel") -> ActiveJob:
	var j := ActiveJob.new()
	j.kind = kind
	j.family = family
	j.type = JobType.of(kind)
	j.target = 9
	j.circuit = ElectricalPanel.new().circuit_at(9)
	j.address = "1 Test Rd"
	return j


func test_breakers_used() -> void:
	var j := _job("open")
	j.part_used(9, 20)
	eq(j.final_part, 20)
	eq(j.wrong_parts, 0)
	j.part_used(9, 30)
	eq(j.wrong_parts, 1, "wrong size")
	j.part_used(12, 15)
	eq(j.wrong_parts, 2, "wrong slot")


func test_devices_used() -> void:
	var p := ElectricalPanel.new()
	var j := _job("scorched", "device")
	j.device = ElectricalDevice.new("Receptacle", p, 12)
	j.device_used("Receptacle", j.device)
	eq(j.final_device, "Receptacle")
	j.device_used("GFCI", ElectricalDevice.new("Receptacle", p, 12))
	eq(j.wrong_parts, 1, "some other box")


func test_parts_cost_and_quote() -> void:
	var j := _job("open")
	eq(j.quoted(tuning), 95 + 110 + 11, "call-out, labour, a 20 A breaker")
	j.final_part = 20
	eq(j.parts_cost(tuning), 11)
	var fan := _job("fan", "device")
	fan.final_device = "Fan"
	eq(fan.parts_cost(tuning), 150, "their own fan's free; hanging it isn't")
	var gfci := _job("bad_gfci", "device")
	eq(gfci.quoted(tuning), 95 + 110 + 18)
	gfci.final_device = "GFCI"
	eq(gfci.parts_cost(tuning), 18)


func test_no_wire_work() -> void:
	is_true(_job("overload").no_wire_work(), "advised, nothing replaced")
	var j := _job("overload")
	j.final_part = 20
	is_false(j.no_wire_work(), "replaced a breaker after all")
	var smoke := _job("smoke_battery", "device")
	smoke.device = ElectricalDevice.new("Smoke", ElectricalPanel.new(), 13)
	is_true(smoke.no_wire_work())
	is_false(_job("open").no_wire_work())


# --- Billing ----------------------------------------------------------------------------

func _work(dead := false, thorough := false, shocks := 0, arcs := 0) -> Billing.Work:
	var w := Billing.Work.new()
	w.dead_tested = dead
	w.thorough = thorough
	w.shocks = shocks
	w.arcs = arcs
	return w


func test_a_good_job() -> void:
	var j := _job("open")
	j.final_part = 20
	j.asked = {"when": true, "touched": true}
	var sheet := Billing.settle(j, _work(true, true), true, tuning, 1.0)
	eq(sheet.total, 205 + 11 + 30 + 25)
	eq(sheet.stars, 5)
	eq(sheet.lines[0], "1 Test Rd   5 of 5 stars")
	eq(sheet.lines[-1], "Job total: $271")


func test_rating_scales_labour_not_parts() -> void:
	var j := _job("open")
	j.final_part = 20
	eq(Billing.settle(j, _work(true), true, tuning, 1.2).total, int(205 * 1.2) + 11 + 30)


func test_mistakes_cost() -> void:
	var j := _job("open")
	j.final_part = 20
	j.wrong_parts = 1
	var sheet := Billing.settle(j, _work(false, false, 2, 1), true, tuning, 1.0)
	eq(sheet.total, 205 + 11 - 2 * 60 - 120)
	eq(sheet.stars, 1, "5 - 1 untested - 2 shocks - 2 arcs - 1 wasted part, floored at 1")


func test_thorough_needs_two_questions() -> void:
	var j := _job("open")
	j.asked = {"when": true}
	eq(Billing.settle(j, _work(true, true), true, tuning, 1.0).total, 205 + 30, "one question isn't enough")


func test_the_scam() -> void:
	var sheet := Billing.settle(_job("open"), _work(true), false, tuning, 1.0)
	eq(sheet.total, 95 + 30, "call-out only, plus the safety bonus")
	eq(sheet.stars, 2)


func test_advising_on_an_overload_needs_no_dead_test() -> void:
	var sheet := Billing.settle(_job("overload"), _work(false), true, tuning, 1.0)
	eq(sheet.stars, 5, "nothing live was touched")
	eq(sheet.total, 205)


func test_bill_follows_the_tuning() -> void:
	tuning.call_out = 200
	tuning.safe_bonus = 0
	eq(Billing.settle(_job("overload"), _work(), true, tuning, 1.0).total, 310)


# --- JobGenerator (callbacks) ----------------------------------------------------------
# New calls come from ServiceCallGenerator: see test_service_call_system.gd.

func _house(two_story := false) -> Dictionary:
	return {"address": "9 Elm", "two_story": two_story}


func test_callbacks() -> void:
	var g := JobGenerator.new(tuning)
	var j := g.callback_job(_house(), {"why": "box", "target": 4, "address": "9 Elm"})
	eq(j.kind, "callback")
	eq(j.family, "device")
	eq(j.target, 4)
	eq(j.status, ActiveJob.Status.IN_PROGRESS, "straight to the front")
	j = g.callback_job(_house(), {"why": "inspection", "target": 0, "address": "9 Elm"})
	eq(j.family, "panel")
	eq(j.target, 9, "an inspection starts at the kitchen")


func test_callback_goes_back_to_the_house() -> void:
	var houses := [{"address": "A"}, {"address": "B"}]
	eq(JobGenerator.new(tuning).pick_house(houses, {"address": "A"})["address"], "A")
