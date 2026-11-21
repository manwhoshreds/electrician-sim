extends "res://tests/test_case.gd"
## Days and nights: running down, going to bed, passing out, and no work
## overnight.

var main: Node
var service: ServiceCall


func _game() -> void:
	SaveGame.enabled = false
	Engine.time_scale = 0.0
	seed(4)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_node(main)
	service = main.service


func after_each() -> void:
	super()
	Engine.time_scale = 1.0
	SaveGame.enabled = true


# --- Energy ---------------------------------------------------------------------------

func test_running_down_through_the_day() -> void:
	var f := Fatigue.new()
	eq(f.state(), "rested")
	var t := f.tuning
	var changes: Array[String] = []
	for hour in int(t.awake_hours) + 1:
		var c := f.tick(60.0)
		if c != "":
			changes.append(c)
	eq(changes, ["tired", "exhausted", "out"] as Array[String], "in that order, over a long day")
	eq(f.speed_factor(), t.exhausted_speed)
	f.rest()
	eq(f.state(), "rested")
	eq(f.speed_factor(), 1.0)


func test_bedtime() -> void:
	var f := Fatigue.new()
	is_false(f.can_sleep(10.0 * 60.0), "10 AM, wide awake")
	is_true(f.can_sleep(21.0 * 60.0), "9 PM")
	is_true(f.can_sleep(2.0 * 60.0), "2 AM")
	f.energy = 20.0
	is_true(f.can_sleep(14.0 * 60.0), "tired in the afternoon: a nap's fine")
	eq(Fatigue.next_time(21.0 * 60.0, 7.0), 1440.0 + 7.0 * 60.0, "7 AM tomorrow")
	eq(Fatigue.next_time(2.0 * 60.0, 7.0), 7.0 * 60.0, "7 AM today, from 2 AM")


# --- In the game ------------------------------------------------------------------------

func test_too_early_for_bed() -> void:
	_game()
	var before := service.minutes()
	service.go_to_sleep()
	eq(service.minutes(), before, "nothing happens at 8 in the morning")


func test_a_nights_sleep() -> void:
	_game()
	service._minutes = 22.0 * 60.0
	service.fatigue.energy = 20.0
	service.go_to_sleep()
	eq(service.minutes(), 1440.0 + 7.0 * 60.0, "up at 7 the next morning")
	eq(service.fatigue.energy, 100.0)
	var home: HomeHouse = main.town.home_house
	is_true(main.player.global_position.distance_to(home.to_global(home.wake_spot)) < 0.1, "by your bed")


func test_going_to_bed_mid_job_loses_it() -> void:
	_game()
	service.call_generator.catalog.assign([JobType.of("light_switch")])
	service.start_job()
	var job := service.job
	var money := service.wallet.money
	service._minutes = 22.0 * 60.0
	service.go_to_sleep()
	eq(job.status, ActiveJob.Status.CANCELLED)
	is_false(service._job_running)
	eq(service.wallet.money, money, "no pay")
	eq(service.aftercare.reviews[-1]["stars"], 1, "and a one-star review")


func test_passing_out() -> void:
	_game()
	service._minutes = 20.0 * 60.0
	service.fatigue.energy = 0.5
	service._tire(60.0)
	eq(fmod(service.minutes(), 1440.0), service.sleep_tuning.passed_out_wake_hour * 60.0, "you come round late")
	eq(service.fatigue.state(), "rested")


func test_no_calls_overnight_the_clock_waits_for_you() -> void:
	_game()
	service._minutes = 23.0 * 60.0
	var before := service.minutes()
	service.call_generator.catalog.assign([JobType.of("light_switch")])    # standard: business hours only
	service.start_job()
	is_false(service._job_running, "nothing tonight")
	eq(service.minutes(), before, "and no skipping to the morning without sleeping")


func test_the_sky_follows_the_clock_and_the_lights_come_on() -> void:
	_game()
	var dn: DayNight = main.day_night
	service._minutes = 1440.0 + 23.5 * 60.0
	dn._process(0.0)
	near(main._sky.current_time, 23.5, "the sky's at the game's time", 0.01)
	is_true(dn.is_dark())
	var bulbs := tree.get_nodes_in_group("home_light")
	is_true(not bulbs.is_empty() and (bulbs[0] as Light3D).visible, "lights on at home")
	service._minutes = 1440.0 + 13.0 * 60.0
	dn._process(0.0)
	is_false(dn.is_dark())
	is_false((bulbs[0] as Light3D).visible)
