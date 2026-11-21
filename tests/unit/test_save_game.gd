extends "res://tests/test_case.gd"
## Saving and loading: every piece through real JSON and back, the file
## itself (damaged, wrong version, a crash mid-write), and a whole game saved
## and picked up again in a fresh one.

const TEST_PATH := "user://test_save.json"


func after_each() -> void:
	super()
	SaveGame.new(TEST_PATH).delete()
	for p in [TEST_PATH + ".bad"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	SaveGame.enabled = true


## Through the same JSON a save file goes through: every number comes back a float.
static func _json(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d))


# --- The domain ------------------------------------------------------------------------

func test_panel_round_trip() -> void:
	var p := ElectricalPanel.new()
	p.set_fault(9, "weak")
	p.set_fault(11, "hot")
	p.set_fault(13, "overload")
	p.set_fault(14, "open")
	p.install(10, 30)
	p.set_wire(12, false)
	p.pull(16)
	p.toggle(5)
	p.toggle_main()
	p.circuit_at(1).breaker.over_t = 1.5
	var back := ElectricalPanel.from_save(_json(p.to_save()))
	eq(back.to_save(), p.to_save(), "same panel")
	eq(back.circuit_at(9).breaker.fault, Breaker.Fault.WEAK)
	eq(back.circuit_at(11).breaker.fault, Breaker.Fault.HOT)
	eq(back.circuit_at(14).breaker.fault, Breaker.Fault.OPEN)
	is_true(back.circuit_at(9).breaker.tripped)
	eq(back.circuit_at(10).breaker.rating, 30)
	eq(typeof(back.circuit_at(10).breaker.rating), TYPE_INT, "an int again, not a float")
	eq(back.circuit_at(10).wire_rating, 20, "the wire's from the house, not the save")
	is_false(back.circuit_at(12).wire_landed)
	is_false(back.circuit_at(16).breaker.present)
	near(back.circuit_at(13).heater, 12.5)
	is_false(back.main_on)
	eq(back.check_repair(9), p.check_repair(9))
	near(back.voltage("term_11", "neutral"), p.voltage("term_11", "neutral"))


func test_fault_names() -> void:
	for f in Breaker.Fault.values():
		eq(Breaker.fault_named(Breaker.fault_name(f)), f)


func test_device_snapshot_through_json() -> void:
	var p := ElectricalPanel.new()
	var d := ElectricalDevice.new("Smoke", p, 13)
	d.made = 2012
	d.battery_low = true
	d.twist()
	var back := ElectricalDevice.new("Smoke", p, 13)
	back.restore(_json(d.snapshot()))
	eq(back.made, 2012)
	eq(typeof(back.made), TYPE_INT)
	is_true(back.expired())
	eq(back.repair_state(), d.repair_state())
	var r := ElectricalDevice.new("Receptacle", p, 12)
	r.set_fault("scorched")
	r.loosen("hot")
	r.remove_plate_screw(0)
	var r2 := ElectricalDevice.new("Receptacle", p, 12)
	r2.restore(_json(r.snapshot()))
	eq(r2.snapshot(), r.snapshot())


func test_unknown_fields_in_a_snapshot_are_ignored() -> void:
	var d := ElectricalDevice.new("Receptacle", ElectricalPanel.new(), 12)
	d.restore({"kind": "GFCI", "not_a_field": 3, "panel": "nope"})
	eq(d.kind, "GFCI")
	is_true(d.panel is ElectricalPanel, "can't be overwritten from a file")


# --- Gameplay -----------------------------------------------------------------------------

func test_wallet_and_inventory() -> void:
	var w := Wallet.new(1234)
	var w2 := Wallet.new()
	w2.load_save(_json(w.to_save()))
	eq(w2.money, 1234)
	var inv := Inventory.new()
	inv.add("Fan")
	inv.take("breaker20")
	var inv2 := Inventory.new()
	inv2.load_save(_json(inv.to_save()))
	eq(inv2.stock, inv.stock)
	eq(typeof(inv2.count("Fan")), TYPE_INT)
	eq(inv2.bag, ["breaker20"] as Array[String])
	eq(inv2.load_used(), inv.load_used())


func test_parts_no_longer_in_the_game_are_dropped() -> void:
	var inv := Inventory.new()
	inv.load_save({"stock": {"GFCI": 2, "FluxCapacitor": 1}, "part_in_hand": "FluxCapacitor"})
	eq(inv.stock, {"GFCI": 2})
	is_true(inv.hands_empty())


func test_aftercare_round_trip() -> void:
	var care := Aftercare.new()
	care.wallet = Wallet.new()
	var p := ElectricalPanel.new()
	p.install(9, 30)
	p.set_wire(9, true)
	p.toggle(9)
	care.houses["12 Oak"] = {"sim": p, "state": {"boxes": [{"kind": "GFCI", "made": 2021}], "detectors": []}, "name": "Priya Nair"}
	care.reviews.append({"address": "12 Oak", "name": "Priya Nair", "stars": 4, "text": "Good job, fair price."})
	care._events.append({"due": 0, "kind": "callback", "address": "12 Oak", "why": "box", "target": 3, "story": "Still dead."})
	care._events.append({"due": 0, "kind": "inspection", "address": "12 Oak", "violations": ["30 A breaker on 20 A wire (Kitchen counter)"]})
	care.suspended_until = Time.get_ticks_msec() / 1000.0 + 100.0
	care.add_habit("12 Oak", "one_thing_at_a_time")
	var back := Aftercare.new()
	back.wallet = Wallet.new()
	back.load_save(_json(care.to_save()))
	eq(back.sim_for("12 Oak").to_save(), p.to_save())
	eq(back.houses["12 Oak"]["name"], "Priya Nair")
	eq(back.state_for("12 Oak")["boxes"][0]["kind"], "GFCI")
	eq(back.rating_text(), care.rating_text())
	eq(typeof(back.reviews[0]["stars"]), TYPE_INT)
	eq(back._events.size(), 2)
	eq(typeof(back._events[0]["target"]), TYPE_INT)
	eq(back.next_callback()["story"], "Still dead.", "callbacks still come in")
	is_true(back.suspended(), "still suspended")
	is_true(back.has_habit("12 Oak", "one_thing_at_a_time"), "they still do one thing at a time")
	is_false(back.has_habit("9 Elm", "one_thing_at_a_time"))
	near(back.suspended_until - Time.get_ticks_msec() / 1000.0, 100.0, "the time left carries over", 1.0)
	care.free()
	back.free()


# --- The file ------------------------------------------------------------------------------

func test_write_and_read() -> void:
	var s := SaveGame.new(TEST_PATH)
	is_false(s.exists())
	eq(s.read(), {}, "nothing yet")
	eq(s.problem, "", "and that's not a problem")
	is_true(s.write({"version": SaveGame.VERSION, "hello": "there"}))
	is_true(s.exists())
	is_false(FileAccess.file_exists(TEST_PATH + ".tmp"), "the temp file's swapped in")
	eq(s.read()["hello"], "there")
	is_true(s.write({"version": SaveGame.VERSION, "hello": "again"}), "overwrites")
	eq(s.read()["hello"], "again")
	s.delete()
	is_false(s.exists())


func test_crash_between_write_and_swap() -> void:
	var f := FileAccess.open(TEST_PATH + ".tmp", FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": SaveGame.VERSION, "hello": "tmp"}))
	f.close()
	eq(SaveGame.new(TEST_PATH).read()["hello"], "tmp", "the finished temp file is used")


func test_damaged_file_is_set_aside() -> void:
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	var s := SaveGame.new(TEST_PATH)
	eq(s.read(), {})
	check(s.problem.contains("damaged"), s.problem)
	is_false(FileAccess.file_exists(TEST_PATH), "out of the way")
	is_true(FileAccess.file_exists(TEST_PATH + ".bad"), "but kept")


func test_other_version_is_set_aside() -> void:
	var s := SaveGame.new(TEST_PATH)
	s.write({"version": SaveGame.VERSION + 1})
	eq(s.read(), {})
	check(s.problem.contains("version"), s.problem)
	is_true(FileAccess.file_exists(TEST_PATH + ".bad"))


# --- A whole game ----------------------------------------------------------------------------

## A freshly started game, not touching any real save. [main, service, utility, town]
func _game() -> Array:
	SaveGame.enabled = false
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_node(main)
	return [main, main.service, main.utility, main.town]


## Plays a job start to finish without fixing anything.
func _play_job(service: ServiceCall) -> void:
	service.start_job()
	service._on_customer(null)
	service._go_to_work()
	service._pay("ok", true)
	service._finish()


func test_a_whole_game_saves_and_comes_back() -> void:
	seed(8)
	Engine.time_scale = 0.0                # nothing fires on its own
	var g := _game()
	var service: ServiceCall = g[1]
	var utility: PowerCompany = g[2]
	var town: Town = g[3]
	var saves := [0]
	service.checkpoint.connect(func() -> void: saves[0] += 1)
	for i in 4:
		_play_job(service)
	eq(saves[0], 8, "a checkpoint before each call and after each job")
	service.wallet.money = 5000
	eq(service.buy_online(["work_van"] as Array[String]), "", "ordered the van online")
	service._minutes = Fatigue.next_time(service._minutes, Upgrades.DELIVERY_HOUR) + 1.0
	service._take_deliveries()
	eq(service.van.model_name, "van", "delivered")
	service.inventory.add("Fan")
	service._minutes = 1000.0
	var meter: MeterBase = town.houses.filter(func(h: Dictionary) -> bool: return h.has("meter_box"))[0]["meter_box"]
	meter.cut_seal()
	meter.pull_meter()
	utility._cleared[meter.address] = true
	var worked: String = service.aftercare.houses.keys()[0]
	var text := JSON.stringify(SaveGame.capture(service, utility, town))
	var before: Dictionary = JSON.parse_string(text)

	var g2 := _game()
	SaveGame.apply(JSON.parse_string(text), g2[1], g2[2], g2[3])
	var after: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.capture(g2[1], g2[2], g2[3])))
	before.erase("saved_at")
	after.erase("saved_at")
	eq(JSON.stringify(after), JSON.stringify(before), "saved again straight away, it's the same file")
	var s2: ServiceCall = g2[1]
	eq(s2.wallet.money, 5000 - 2500)
	eq(s2.van.model_name, "van")
	eq(s2._rear.prompt, "[E] Get parts from the van")
	eq(s2.inventory.count("Fan"), 1)
	eq(s2.aftercare.houses.size(), service.aftercare.houses.size())
	is_true(s2.aftercare.houses.size() >= 2, "a few houses worked on")
	eq(s2.aftercare.sim_for(worked).to_save(), service.aftercare.sim_for(worked).to_save(), "the house's panel as you left it")
	eq(s2.aftercare.reviews.size(), service.aftercare.reviews.size())
	var meter2: MeterBase = (g2[3] as Town).houses.filter(func(h: Dictionary) -> bool: return h.has("meter_box"))[0]["meter_box"]
	is_false(meter2.sealed)
	is_false(meter2.meter_in)
	is_true((g2[2] as PowerCompany).is_cleared(meter2))
	Engine.time_scale = 1.0


func test_a_saved_house_is_built_the_way_you_left_it() -> void:
	seed(8)
	Engine.time_scale = 0.0
	var g := _game()
	var service: ServiceCall = g[1]
	_play_job(service)
	var address: String = service.aftercare.houses.keys()[0]
	var left: Dictionary = service.aftercare.state_for(address)
	var text := JSON.stringify(SaveGame.capture(service, g[2], g[3]))
	var g2 := _game()
	var s2: ServiceCall = g2[1]
	SaveGame.apply(JSON.parse_string(text), s2, g2[2], g2[3])
	# Send the next call back to that house.
	s2.aftercare._events = [{"due": 0, "kind": "callback", "address": address, "why": "panel", "target": 9, "story": "Back again."}]
	s2.start_job()
	eq(s2.job.address, address)
	eq(JSON.stringify(s2._inside.snapshot()), JSON.stringify(left), "every box and detector the same")
	Engine.time_scale = 1.0


func test_the_game_loads_and_autosaves_its_file() -> void:
	SaveGame.enabled = true
	var s := SaveGame.new(TEST_PATH)
	s.write({"version": SaveGame.VERSION, "service": {"wallet": {"money": 777}, "vehicle": "van", "clock_minutes": 600.0}})
	Engine.time_scale = 0.0
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main._save = SaveGame.new(TEST_PATH)    # this file, not the player's
	add_node(main)
	var service: ServiceCall = main.service
	eq(service.wallet.money, 777, "picked up on start")
	eq(service.van.model_name, "van")
	service.wallet.money = 900
	service.checkpoint.emit()
	eq(int(s.read()["service"]["wallet"]["money"]), 900, "written at a checkpoint")
	Engine.time_scale = 1.0


func test_no_save_leaves_the_file_alone() -> void:
	SaveGame.enabled = false
	var s := SaveGame.new(TEST_PATH)
	s.write({"version": SaveGame.VERSION, "service": {"wallet": {"money": 777}}})
	Engine.time_scale = 0.0
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main._save = SaveGame.new(TEST_PATH)
	add_node(main)
	eq((main.service as ServiceCall).wallet.money, 150, "not loaded")
	(main.service as ServiceCall).checkpoint.emit()
	eq(int(s.read()["service"]["wallet"]["money"]), 777, "not written")
	Engine.time_scale = 1.0
