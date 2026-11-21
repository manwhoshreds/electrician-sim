extends "res://tests/test_case.gd"
## The chirping smoke detector calls, played start to finish through the
## close-up: every step you need is on screen when you need it, and both
## kinds of call can be fixed and paid for.

var main: Node
var service: ServiceCall
var view: BoxView


func after_each() -> void:
	super()
	Engine.time_scale = 1.0
	SaveGame.enabled = true


func _call(kind: String) -> void:
	SaveGame.enabled = false
	Engine.time_scale = 0.0
	seed(5)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_node(main)
	service = main.service
	service.call_generator.catalog.assign([JobType.of(kind)])
	service.start_job()
	service._on_customer(service.player)
	service._go_to_work()
	view = service._box
	view.open(main.player)


## Does the step with this label show on screen, where you can click it?
func _can_click(kind: String) -> bool:
	view._process(0.016)
	var size: Vector2 = view.get_viewport().get_visible_rect().size
	for p: Dictionary in view._picks():
		if p["kind"] != kind:
			continue
		var at := view.to_global(p["pos"])
		var s := view._cam.unproject_position(at)
		return not view._cam.is_position_behind(at) and s.x >= 0.0 and s.y >= 0.0 and s.x <= size.x and s.y <= size.y
	return false


func _do(kind: String) -> void:
	check(_can_click(kind), "%s is on screen to click" % kind)
	view._smoke_click(kind)


func test_dead_battery_swapped() -> void:
	_call("smoke_battery")
	is_true(view.device.chirping())
	_do("twist")
	_do("door")
	_do("battery_out")
	service.inventory.hold("Battery9V")
	_do("battery_in")
	_do("door")
	_do("twist")
	is_false(view.device.chirping(), "quiet now")
	_do("smoke_test")
	is_true(view.work.tested_after, "tested: every alarm went off")
	view.close()
	service._return_visit()
	is_true(service.dialogue._text.text.contains("that's got it"), service.dialogue._text.text)


func test_expired_detector_taken_down_and_replaced() -> void:
	_call("smoke_expired")
	is_true(view.device.expired())
	_do("twist")
	_do("harness")
	_do("take_away")
	eq(view.device.kind, "", "the old one's down")
	service.inventory.hold("Smoke")
	_do("harness")
	is_false(view.device.expired(), "the new one's in date")
	_do("twist")
	_do("smoke_test")
	is_false(view.device.chirping())
	view.close()
	service._return_visit()
	is_true(service.dialogue._text.text.contains("that's got it"), service.dialogue._text.text)


func _replace(v: BoxView) -> void:
	view = v
	view.open(main.player)
	_do("twist")
	_do("harness")
	_do("take_away")
	service.inventory.hold("Smoke")
	_do("harness")
	_do("twist")
	view._smoke_click("smoke_test")
	view.close()


func _customer_says() -> String:
	service._return_visit()
	return service.dialogue._text.text


func test_breaker_left_off_the_customer_says_so_and_it_isnt_done() -> void:
	_call("smoke_expired")
	service._sim.toggle(13)            # off at the panel to work safely on a hardwired detector
	view.close()
	_replace(service._box)
	view._process(0.016)
	is_true(view._hint_text().contains("Breaker back on"), view._hint_text())
	var said := _customer_says()
	is_false(said.contains("outlet"), said)
	is_true(said.contains("green lights"), said)
	service._sim.toggle(13)
	is_true(view._hint_text().begins_with("Done"), view._hint_text())
	is_true(_customer_says().contains("that's got it"))


func test_replacing_the_wrong_detector_it_still_chirps() -> void:
	_call("smoke_expired")
	view.close()
	var other: BoxView = service._inside.detectors.filter(func(d: BoxView) -> bool: return d != service._box)[0]
	view = other
	view.open(main.player)
	_do("twist")
	is_true(view._hint_text().contains("This one's good"), "a good one says so in your hands: " + view._hint_text())
	_do("twist")                       # back on, and replace it anyway
	view.close()
	_replace(other)
	var said := _customer_says()
	is_true(said.contains("still chirping"), said)
	eq(service.job.wrong_parts, 1, "a good detector replaced for nothing")


func test_nothing_on_a_smoke_call_talks_about_an_outlet() -> void:
	_call("smoke_battery")
	view.close()
	var said := _customer_says()
	is_false(said.contains("outlet"), said)
	is_true(said.contains("chirping"), said)


func test_the_bad_one_chirps_soon_and_often_and_flashes_red() -> void:
	_call("smoke_battery")
	view.close()
	var bad := service._box
	var good: BoxView = service._inside.detectors.filter(func(d: BoxView) -> bool: return d != bad)[0]
	for i in 30:                       # 30 seconds in the house
		for d: BoxView in [bad, good]:
			d._smoke_tick(1.0)
	is_true(bad.chirps >= 2, "chirped %d times in 30 s" % bad.chirps)
	eq(good.chirps, 0, "the good one's quiet")
	bad.chirp()
	bad._smoke_tick(0.1)
	is_true(bad._led_mat.emission.r > 0.9, "its light flashes red with the chirp")


func test_broke_the_customer_goes_and_buys_the_detector() -> void:
	_call("smoke_expired")
	view.close()
	service.wallet.money = 0                     # the flood took it all
	service.inventory.stock.erase("Smoke")
	is_true(service.can_ask_customer_to_buy(), "can't afford a detector, none on the truck")
	service._ask_customer_to_buy()
	is_false(service.can_ask_customer_to_buy(), "asked once is enough")
	service.customer_is_back()
	eq(service.texts[-1]["from"], service.job.customer_name, "they text you when they're back")
	service._grab_customer_part()
	is_true(service.inventory.has("Smoke"), "their detector, in your bag")
	service.job.final_device = "Smoke"
	eq(service.job.parts_cost(service.tuning), 0, "theirs: it's not on the bill")


func test_with_money_you_buy_your_own() -> void:
	_call("smoke_expired")
	view.close()
	service.wallet.money = 500
	service.inventory.stock.erase("Smoke")
	is_false(service.can_ask_customer_to_buy(), "you can afford it: go to the supply house")
