extends "res://tests/test_case.gd"
## The typed circuit models on their own: CircuitSpec, Breaker, Circuit.


# --- CircuitSpec --------------------------------------------------------------------

func test_standard_house_matches_the_old_table() -> void:
	var specs := CircuitSpec.standard_house()
	eq(specs.size(), 12)
	var range_ := specs[0]
	eq(range_.poles, [1, 3] as Array[int])
	eq(range_.name, "Range")
	eq(range_.wire_rating, 40)
	eq(range_.customer, "", "nobody phones in about the range")
	var kitchen := specs[4]
	eq(kitchen.poles, [9] as Array[int])
	eq(kitchen.customer, "kitchen counter plugs")
	eq(kitchen.appliance, "toaster")


func test_every_appliance_is_known() -> void:
	for s in CircuitSpec.standard_house():
		if s.appliance != "":
			is_true(ElectricalPanel.APPLIANCE_AMPS.has(s.appliance), s.appliance)


func test_specs_are_fresh_each_time() -> void:
	var a := CircuitSpec.standard_house()
	var b := CircuitSpec.standard_house()
	a[0].wire_rating = 50
	eq(b[0].wire_rating, 40, "one house's panel can't leak into another's")


func test_panel_from_custom_specs() -> void:
	var p := ElectricalPanel.new([CircuitSpec.make([1], "Shed", 20, "shed lights", "vacuum")] as Array[CircuitSpec])
	eq(p.circuits.size(), 1)
	eq(p.candidates(), [1] as Array[int])
	p.run_appliance(1)
	is_true(absf(p.current("wire_1") - 6.0) < 0.001, "vacuum on the shed")


# --- Breaker ------------------------------------------------------------------------

func test_new_breaker() -> void:
	var b := Breaker.new(20)
	eq(b.rating, 20)
	is_true(b.closed())
	eq(b.fault, Breaker.Fault.NONE)
	eq(b.trip_amps(), 20.0)
	eq(b.trip_seconds(), Breaker.THERMAL_SECONDS)


func test_weak_breaker_curve() -> void:
	var b := Breaker.new(20)
	b.fault = Breaker.Fault.WEAK
	eq(b.trip_amps(), 8.0)
	eq(b.trip_seconds(), Breaker.WEAK_SECONDS)
	is_true(b.closed(), "a weak one still conducts")


func test_closed_needs_everything() -> void:
	var b := Breaker.new()
	b.on = false
	is_false(b.closed(), "off")
	b = Breaker.new()
	b.tripped = true
	is_false(b.closed(), "tripped")
	b = Breaker.new()
	b.present = false
	is_false(b.closed(), "pulled")
	b = Breaker.new()
	b.fault = Breaker.Fault.OPEN
	is_false(b.closed(), "open contacts")
	b = Breaker.new()
	b.fault = Breaker.Fault.HOT
	is_true(b.closed(), "burnt contacts still conduct")


func test_handle() -> void:
	var b := Breaker.new()
	b.toggle()
	is_false(b.on)
	b.toggle()
	is_true(b.on)
	b.tripped = true
	b.toggle()
	is_false(b.tripped)
	is_false(b.on, "reset lands on off")


func test_install_is_a_fresh_breaker() -> void:
	var b := Breaker.new(20)
	b.fault = Breaker.Fault.HOT
	b.tripped = true
	b.present = false
	b.install(15)
	is_true(b.present)
	eq(b.rating, 15)
	is_false(b.on)
	is_false(b.tripped)
	eq(b.fault, Breaker.Fault.NONE)


func test_install_keeps_thermal_time() -> void:
	# QUIRK, kept from the dictionary model: over_t survives a swap.
	var b := Breaker.new(20)
	b.over_t = 3.0
	b.install(20)
	eq(b.over_t, 3.0)


func test_fault_names() -> void:
	eq(Breaker.fault_named(""), Breaker.Fault.NONE)
	eq(Breaker.fault_named("open"), Breaker.Fault.OPEN)
	eq(Breaker.fault_named("weak"), Breaker.Fault.WEAK)
	eq(Breaker.fault_named("hot"), Breaker.Fault.HOT)


# --- Circuit ------------------------------------------------------------------------

func test_circuit_reads_through_to_its_spec() -> void:
	var c := Circuit.new(CircuitSpec.make([5, 7], "Water heater", 30))
	eq(c.slot, 5)
	eq(c.poles, [5, 7] as Array[int])
	eq(c.name, "Water heater")
	eq(c.wire_rating, 30)
	eq(c.breaker.rating, 30, "comes with a breaker sized for the wire")
	is_true(c.wire_landed)
	eq(c.heater, 0.0)


func test_wire_rating_survives_a_new_breaker() -> void:
	var c := Circuit.new(CircuitSpec.make([9], "Kitchen counter", 20))
	c.breaker.install(30)
	eq(c.wire_rating, 20)
	eq(c.breaker.rating, 30)


func test_healthy() -> void:
	var make := func() -> Circuit: return Circuit.new(CircuitSpec.make([9], "Kitchen counter", 20))
	var c: Circuit = make.call()
	is_true(c.healthy())
	for spoil: Callable in [
			func(x: Circuit) -> void: x.breaker.on = false,
			func(x: Circuit) -> void: x.breaker.tripped = true,
			func(x: Circuit) -> void: x.breaker.present = false,
			func(x: Circuit) -> void: x.breaker.fault = Breaker.Fault.WEAK,
			func(x: Circuit) -> void: x.wire_landed = false,
			func(x: Circuit) -> void: x.heater = 12.5,
			func(x: Circuit) -> void: x.breaker.rating = 15,
			func(x: Circuit) -> void: x.breaker.rating = 30]:
		c = make.call()
		spoil.call(c)
		is_false(c.healthy())
