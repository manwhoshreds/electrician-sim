extends "res://tests/test_case.gd"
## The ceiling fan call, played through the real game. The house has two
## bedrooms: the call has to say which, and a fan hung in the other one
## doesn't count (and the customer says so), but one hung in theirs gets you paid.

var main: Node
var service: ServiceCall


func after_each() -> void:
	super()
	Engine.time_scale = 1.0
	SaveGame.enabled = true


func _play(kind := "fan") -> void:
	SaveGame.enabled = false
	Engine.time_scale = 0.0
	seed(11)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_node(main)
	service = main.service
	service.tuning = JobTuning.new()
	service.call_generator.catalog = [JobType.of(kind)] as Array[JobType]
	service.start_job()
	service._on_customer(service.player)


func _customer_says() -> String:
	service._return_visit()
	return service.dialogue._text.text


## Breaker off, old light down, fan up and wired, canopy on, breaker back on.
func _hang_fan(d: ElectricalDevice) -> void:
	service._sim.toggle(d.slot)
	d.remove_shade()
	for i in d.mount_screws.size():
		if d.mount_screws[i]:
			d.toggle_mount_screw(i)
	d.pull_out()
	for w in ["hot", "neutral", "ground"]:
		d.loosen(w)
	d.remove_device()
	eq(d.install("Fan"), "")
	d.land("hot", "nut_black")
	d.land("neutral", "nut_white")
	d.land("ground", "f_ground")
	d.push_in()
	for i in d.mount_screws.size():
		d.toggle_mount_screw(i)
	d.refit_plate()
	service.job.device_used("Fan", d)
	service._sim.toggle(d.slot)


func test_the_call_says_which_bedroom() -> void:
	_play()
	var room := service._box.room
	is_true(room == "master bedroom" or room == "front bedroom", room)
	is_true(service.job.issue.contains(room), "on the dispatch: %s" % service.job.issue)
	is_true(service.dialogue._text.text.contains(room), "and when they open the door")


func test_hung_in_their_bedroom_it_pays() -> void:
	_play()
	service._grab_customer_part()
	service._go_to_work()
	_hang_fan(service._box.device)
	service._box.work.worked_on = true
	near(service._box.device.lamp_volts(), 120.0, "power at the fan", 2.0)
	eq(service._device_state(), "ok")
	is_true(_customer_says().contains("that's got it"))


func test_hung_in_the_other_bedroom_they_tell_you() -> void:
	_play()
	service._grab_customer_part()
	service._go_to_work()
	var other: BoxView = null
	for l in service._inside._lights:
		var b: BoxView = l["box"]
		if b != service._box and b.room.ends_with("bedroom") and b.device.kind == "Fixture":
			other = b
	check(other != null, "there's another bedroom light")
	_hang_fan(other.device)
	other.work.worked_on = true
	eq(service._device_state(), "not_fixed")
	var said := _customer_says()
	is_true(said.contains("You've put it up in the %s" % other.room), said)
	is_true(said.contains(service._box.room), "and they tell you where they meant")


func test_dimmer_names_the_room_too() -> void:
	_play("dimmer")
	var room := service._box.room
	is_true(room.ends_with("bedroom") and room != "bedroom", room)
	is_true(service.dialogue._text.text.contains(room))
