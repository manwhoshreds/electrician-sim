extends "res://tests/test_case.gd"
## Characterization of the repair verdicts ServiceCall reaches from the
## panel's state: callback fixes, code violations, and how a device job reads
## the panel. ServiceCall isn't put in the tree; only the fields these checks
## read are set.


## Remembers what was said instead of drawing it.
class RecordingDialogue:
	extends DialogueBox
	var said: Array = []

	func _ready() -> void:
		pass

	func say(speaker: String, text: String, options: Array) -> void:
		said.append([speaker, text, options])

	func close() -> void:
		pass

	func line() -> String:
		return said[-1][1]

	## The option that starts with these words, or an empty array.
	func option(prefix: String) -> Array:
		for o: Array in said[-1][2]:
			if (o[0] as String).begins_with(prefix):
				return o
		return []


var p: ElectricalPanel
var call: ServiceCall


func before_each() -> void:
	p = ElectricalPanel.new()
	call = ServiceCall.new()
	call._sim = p
	call.job = ActiveJob.new()
	call.job.target = 9
	call.job.circuit = p.circuit_at(9)
	_nodes.append(call)           # freed after the test


func _replace(slot: int, rating: int) -> void:
	p.install(slot, rating)
	p.set_wire(slot, true)
	p.toggle(slot)


# --- Callback fixed? -------------------------------------------------------------

func _trip_fixed() -> bool:
	call.job.callback = {"why": "trip"}
	return call._callback_fixed()


func test_callback_fixed_on_a_healthy_breaker() -> void:
	is_true(_trip_fixed())
	call.job.callback = {"why": "panel"}
	is_true(call._callback_fixed(), "panel callbacks use the same check")


func test_callback_not_fixed_by_wrong_size() -> void:
	_replace(9, 15)
	is_false(_trip_fixed(), "undersize")
	_replace(9, 30)
	is_false(_trip_fixed(), "oversize")
	_replace(9, 20)
	is_true(_trip_fixed())


func test_callback_not_fixed_by_faults_or_state() -> void:
	for setup: Callable in [
			func() -> void: p.set_fault(9, "weak"),
			func() -> void: p.set_fault(9, "hot"),
			func() -> void: p.set_fault(9, "open"),
			func() -> void: p.set_fault(9, "overload"),
			func() -> void: p.toggle(9),
			func() -> void: p.set_wire(9, false),
			func() -> void: p.pull(9)]:
		before_each()
		setup.call()
		is_false(_trip_fixed())


func test_callback_ignores_the_main_and_other_circuits() -> void:
	# Unlike check_repair: only the target breaker matters here.
	p.toggle_main()
	p.toggle(12)
	is_true(_trip_fixed())


# --- Code violations ---------------------------------------------------------------

func test_no_violations_on_a_healthy_panel() -> void:
	eq(call._violations_now(), [])


func test_violations() -> void:
	_replace(9, 30)                # oversize anywhere
	_replace(11, 15)               # undersize on a 20 A required circuit
	_replace(10, 15)
	eq(call._violations_now(), ["Kitchen counter", "Microwave", "Bathroom"])


func test_undersize_elsewhere_is_fine() -> void:
	_replace(5, 20)                # water heater: allowed, just trips
	eq(call._violations_now(), [])


# --- Device jobs reading the panel ---------------------------------------------------

## A box on the kitchen counter circuit, as the job's faulty one. Not in the
## tree: only its device and room are read.
func _box(kind := "Receptacle", room := "kitchen") -> BoxView:
	var b := BoxView.new()
	b.device = ElectricalDevice.new(kind, p, 9)
	b.room = room
	_nodes.append(b)
	return b


func _device(kind := "loose", box: BoxView = null) -> String:
	call.job.kind = kind
	call._box = box if box != null else _box()
	return call._device_state()


func test_device_ok() -> void:
	eq(_device(), "ok")


func test_device_main_off() -> void:
	p.toggle_main()
	eq(_device(), "main_off")


func test_device_target_breaker_off() -> void:
	p.toggle(9)
	eq(_device(), "not_fixed")


func test_device_other_breaker_off() -> void:
	p.trip(12)
	eq(_device(), "other_off")


func test_device_first_off_breaker_wins() -> void:
	# Breakers are checked in panel order: a dead slot 5 is reported before slot 9.
	p.toggle(5)
	p.toggle(9)
	eq(_device(), "other_off")


func test_device_pulled_or_unwired() -> void:
	p.pull(14)
	eq(_device(), "other_off")
	before_each()
	p.set_wire(9, false)
	eq(_device(), "not_fixed")


func test_device_bathroom_needs_gfci() -> void:
	eq(_device("loose", _box("Receptacle", "bathroom")), "wrong_device")
	eq(_device("loose", _box("GFCI", "bathroom")), "ok")


func test_device_dead_box_is_not_fixed() -> void:
	var box := _box()
	box.device.loosen("hot")
	eq(_device("loose", box), "not_fixed", "dead")
	box = _box()
	box.device.loosen("ground")
	eq(_device("loose", box), "miswired")


func test_dimmer_and_fan_jobs_need_their_device() -> void:
	eq(_device("dimmer", _box("Switch")), "not_fixed")
	eq(_device("dimmer", _box("Dimmer")), "ok")


# --- Other circuits they overload while you're there -------------------------------------

## A bathroom job in progress, with the customer free to make breakfast.
func _bathroom_job() -> RecordingDialogue:
	var talk := RecordingDialogue.new()
	call.dialogue = talk
	_nodes.append(talk)
	call.aftercare = Aftercare.new()
	_nodes.append(call.aftercare)
	call._panel = PanelView.new()
	_nodes.append(call._panel)
	var j := call.job
	j.kind = "open"
	j.family = "panel"
	j.type = JobType.of("open")
	j.target = 11
	j.circuit = p.circuit_at(11)
	j.address = "3 Birch"
	j.customer_name = "Hank Petrov"
	call._job_running = true
	return talk


## Toast and the kettle at once, long enough to trip the kitchen.
func _breakfast() -> void:
	p.run_appliance(9, 35.0, "toaster")
	p.run_appliance(9, 35.0, "kettle")
	for i in 10:
		p.tick(0.5)


func test_they_tell_you_what_they_were_doing() -> void:
	var talk := _bathroom_job()
	_breakfast()
	call._return_visit()
	eq(talk.line(), "That's the kitchen counter plugs off now. All I had going was the toaster and the kettle.")


func test_you_can_tell_them_to_do_one_thing_at_a_time() -> void:
	var talk := _bathroom_job()
	call._menu("Hello.")
	eq(talk.option("Your kitchen"), [], "nothing to say before it's happened")
	_breakfast()
	call._menu("Hello.")
	var advise: Array = talk.option("Your kitchen counter plugs tripped")
	check(not advise.is_empty(), "the option's there")
	if advise.is_empty():
		return
	eq(advise[0], "Your kitchen counter plugs tripped: the toaster and the kettle together pull 21.7 A on a 20 A breaker. Run one thing at a time on there.")
	(advise[1] as Callable).call()
	check(talk.line().begins_with("Oh! I had no idea"), talk.line())
	check(talk.line().ends_with("Can you get the kitchen counter plugs back on?"), "it's still tripped: " + talk.line())
	is_true(call.aftercare.has_habit("3 Birch", "one_thing_at_a_time"))
	eq(talk.option("Your kitchen"), [], "said once")


func test_once_told_they_stop_doubling_up() -> void:
	_bathroom_job()
	call.tuning = JobTuning.new()
	call.tuning.kitchen_overload_percent = 100.0
	call._kettle_rolled = false
	p.demo.clear()
	call._on_customer_arrived(1)
	is_true(p.demo.has("9:kettle"), "before: toast and the kettle")
	call.aftercare.add_habit("3 Birch", "one_thing_at_a_time")
	call._kettle_rolled = false
	p.demo.clear()
	call._on_customer_arrived(1)
	is_true(p.demo.has("9:toaster"), "still makes toast")
	is_false(p.demo.has("9:kettle"), "not with the kettle")


func test_the_kettle_trick_is_once_a_call_and_rare() -> void:
	_bathroom_job()
	call.tuning = JobTuning.new()
	call.tuning.kitchen_overload_percent = 100.0
	call._kettle_rolled = false
	call._on_customer_arrived(1)
	p.demo.clear()
	call._on_customer_arrived(1)              # back in the kitchen later the same call
	is_false(p.demo.has("9:kettle"), "only once a call")
	call.tuning = JobTuning.new()             # the default
	var kettles := 0
	for s in 200:
		seed(s)
		call._kettle_rolled = false
		p.demo.clear()
		call._on_customer_arrived(1)
		kettles += 1 if p.demo.has("9:kettle") else 0
	is_true(kettles > 0 and kettles < 25, "rare: %d calls in 200" % kettles)


func test_an_outage_that_isnt_theirs_gets_the_old_line() -> void:
	var talk := _bathroom_job()
	p.toggle(12)
	call._return_visit()
	eq(talk.line(), "That part's better, but now something else in the house has gone off.")
