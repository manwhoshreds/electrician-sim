extends "res://tests/test_case.gd"
## Recessed lights: four wafers where the master bedroom's light was, on its
## switch. The layout's graded on how it looks from the bed, the cable's pulled
## hole to hole in the attic, and it's done when they all light and the old
## box is spliced through under a blank.

var main: Node
var service: ServiceCall

## A quarter of the way in from each wall of the master bedroom's ceiling.
var IDEAL: Array:
	get:
		var r := HouseInterior.MASTER_CEILING
		var xs := [r.position.x + r.size.x * 0.25, r.position.x + r.size.x * 0.75]
		var zs := [r.position.y + r.size.y * 0.75, r.position.y + r.size.y * 0.25]
		return [[xs[0], zs[0]], [xs[0], zs[1]], [xs[1], zs[1]], [xs[1], zs[0]]]


func after_each() -> void:
	super()
	Engine.time_scale = 1.0
	SaveGame.enabled = true


func _building() -> BuildingElectricalModel:
	var b := BuildingElectricalModel.residential("1 Ash St", ElectricalPanel.new())
	b.request_recessed(4)
	return b


## The old light's box: fixture off, blank on, the switch leg spliced through
## to the new cable (if one's been run from it).
func _splice_old_box(b: BuildingElectricalModel) -> void:
	var old := b.device(BuildingElectricalModel.RECESSED_FIXTURE)
	old.remove_shade()
	old.pull_out()
	for w in ["hot", "neutral", "ground"]:
		old.loosen(w)
	old.remove_device()
	eq(old.install("Blank"), "")
	for pair: Array in [["hot", "nut_black"], ["hot_out", "nut_black"], ["neutral", "nut_white"], ["neutral_out", "nut_white"], ["ground", "f_ground"], ["ground_out", "f_ground"]]:
		if old.wires.has(pair[0]):
			old.land(pair[0], pair[1])
	old.push_in()
	old.refit_plate()


## A wafer: in, every wire on its nut, pushed up till the clips snap.
func _wire_wafer(d: ElectricalDevice) -> void:
	eq(d.install("Wafer"), "")
	for pair: Array in [["hot", "nut_black"], ["hot_out", "nut_black"], ["neutral", "nut_white"], ["neutral_out", "nut_white"], ["ground", "f_ground"], ["ground_out", "f_ground"]]:
		if d.wires.has(pair[0]):
			d.land(pair[0], pair[1])
	d.push_in()
	d.refit_plate()


## Marks, holes and cable, daisy-chained from the old box: the domain alone.
func _roughed_in(b: BuildingElectricalModel) -> Array[String]:
	b.lay_out(IDEAL)
	var ids := b.wafer_ids()
	for i in ids.size():
		b.cut_hole(i)
	var from := BuildingElectricalModel.RECESSED_FIXTURE
	for id in ids:
		eq(b.run_cable(from, id, "bay", 9), "")
		from = id
	return ids


# --- The electrics ----------------------------------------------------------------------

func test_a_request_is_just_a_request() -> void:
	var b := BuildingElectricalModel.residential("1 Ash St", ElectricalPanel.new())
	is_true(b.can_add_recessed())
	var ids := b.request_recessed(4)
	eq(ids.size(), 4)
	is_false(b.can_add_recessed(), "one at a time")
	eq(b.device(BuildingElectricalModel.RECESSED_FIXTURE).kind, "Fixture", "the old light's still up")
	is_false(b.recessed_done())
	is_false(BuildingElectricalModel.residential("2 Birch", ElectricalPanel.new(), true).can_add_recessed(), "no attic, no cable runs")


func test_cable_goes_hole_to_hole_from_the_old_box() -> void:
	var b := _building()
	var ids := b.wafer_ids()
	b.lay_out(IDEAL)
	eq(b.run_cable(BuildingElectricalModel.RECESSED_FIXTURE, ids[0], "bay", 9), "no_hole", "cut it first")
	b.cut_hole(0)
	b.cut_hole(1)
	eq(b.run_cable(ids[0], ids[1], "bay", 9), "from_not_fed", "nothing to pull from there yet")
	eq(b.run_cable(BuildingElectricalModel.RECESSED_FIXTURE, ids[0], "bay", 9), "")
	eq(b.run_cable(BuildingElectricalModel.RECESSED_FIXTURE, ids[1], "bay", 9), "from_taken", "one cable on from each box")
	eq(b.run_cable(ids[0], ids[1], "bay", 9), "")
	is_true(b.device(BuildingElectricalModel.RECESSED_FIXTURE).wires.has("hot_out"), "a new cable in the old box")
	is_true(b.device(ids[1]).source == b.device(ids[0]))


func test_wired_right_they_all_light_on_the_switch() -> void:
	var b := _building()
	var ids := _roughed_in(b)
	var slot := b.device(ids[0]).slot
	b.panel.toggle(slot)                          # breaker off to work
	_splice_old_box(b)
	for id in ids:
		_wire_wafer(b.device(id))
	is_false(b.recessed_done(), "the breaker's still off")
	b.panel.toggle(slot)
	for id in ids:
		near(b.device(id).lamp_volts(), 120.0, "%s lit" % id, 2.0)
		eq(b.device(id).repair_state(), "ok")
	eq(b.device(BuildingElectricalModel.RECESSED_FIXTURE).lamp_volts(), 0.0, "a blank doesn't light")
	is_true(b.recessed_done())
	var sw := b.device(b.switch_for_fixture(BuildingElectricalModel.RECESSED_FIXTURE))
	sw.flip()
	eq(b.device(ids[3]).lamp_volts(), 0.0, "they go off at the switch")
	is_false(b.recessed_done(), "and they have to be on to count")


func test_a_neutral_left_off_kills_everything_downstream() -> void:
	var b := _building()
	var ids := _roughed_in(b)
	b.panel.toggle(13)
	_splice_old_box(b)
	for id in ids:
		_wire_wafer(b.device(id))
	b.device(ids[1]).loosen("neutral_out")
	b.panel.toggle(13)
	near(b.device(ids[1]).lamp_volts(), 120.0, "that one's still fine", 2.0)
	eq(b.device(ids[2]).lamp_volts(), 0.0, "the next one's lost its neutral")
	eq(b.device(ids[3]).lamp_volts(), 0.0, "and so's the one after")
	eq(b.device(ids[1]).repair_state(), "miswired", "a loose white in the box")


func test_wafers_and_ceiling_boxes_dont_swap() -> void:
	var b := _building()
	var old := b.device(BuildingElectricalModel.RECESSED_FIXTURE)
	old.remove_device()
	eq(old.install("Wafer"), "wafer_mismatch", "a wafer goes in its own hole")
	eq(b.device(b.wafer_ids()[0]).install("Fixture"), "wafer_mismatch", "and only a wafer goes in one")
	eq(old.install("Blank"), "")
	is_true(old.mounted, "nothing to screw a blank's box down with")


func test_the_recessed_job_survives_a_save() -> void:
	var b := _building()
	var ids := _roughed_in(b)
	b.panel.toggle(13)
	_splice_old_box(b)
	_wire_wafer(b.device(ids[0]))
	b.panel.toggle(13)
	var b2 := BuildingElectricalModel.from_save(JSON.parse_string(JSON.stringify(b.to_save())))
	eq(b2.wafer_ids(), ids)
	eq(b2.recessed["marks"].size(), 4)
	is_true(b2.hole_cut(3))
	eq((b2.recessed["runs"] as Array).size(), 4)
	is_true(b2.device(ids[1]).source == b2.device(ids[0]), "the chain's the same")
	near(b2.device(ids[0]).lamp_volts(), 120.0, "and the first one still lights", 2.0)
	eq(b2.device(ids[1]).kind, "", "the next one's still waiting")


# --- The layout -----------------------------------------------------------------------

func test_a_quarter_in_from_every_wall_is_right() -> void:
	eq(CeilingLayout.flaws(IDEAL, HouseInterior.MASTER_CEILING), [] as Array[String])


func test_crooked_off_centre_bunched_and_crowded() -> void:
	var r := HouseInterior.MASTER_CEILING
	var crooked := IDEAL.duplicate(true)
	crooked[2][1] += 0.1
	is_true(CeilingLayout.flaws(crooked, r)[0].contains("straight lines"))
	var shifted: Array = IDEAL.map(func(m: Array) -> Array: return [m[0] + 0.3, m[1]])
	is_true(CeilingLayout.flaws(shifted, r)[0].contains("centred"))
	var c := r.get_center()
	var bunched: Array = IDEAL.map(func(m: Array) -> Array: return [c.x + (m[0] - c.x) * 0.4, c.y + (m[1] - c.y) * 0.4])
	is_true(CeilingLayout.flaws(bunched, r).any(func(f: String) -> bool: return f.contains("middle")))
	var crowded: Array = IDEAL.map(func(m: Array) -> Array: return [c.x + (m[0] - c.x) * 1.75, c.y + (m[1] - c.y) * 1.75])
	is_true(CeilingLayout.flaws(crowded, r).any(func(f: String) -> bool: return f.contains("walls")))


func test_the_tape_reads_feet_and_inches() -> void:
	eq(CeilingLayout.feet_inches(1.2192), "4' 0\"")
	eq(CeilingLayout.feet_inches(0.9906), "3' 3\"")
	eq(CeilingLayout.feet_inches(0.0254 * 14.25), "1' 2 1/4\"")


func test_marks_keep_clear_and_snap_square() -> void:
	var l := CeilingLayout.new()
	l.room = HouseInterior.MASTER_CEILING
	l.obstacles = [[3.95, -2.4]]
	eq(l.place(Vector2(3.95, -2.45)), "obstacle", "not on the old light's box")
	eq(l.place(Vector2(IDEAL[0][0], IDEAL[0][1])), "")
	eq(l.place(Vector2(IDEAL[0][0] + 0.1, IDEAL[0][1])), "too_close")
	var p := l.snapped_point(Vector2(IDEAL[0][0] + 0.02, -3.4))
	near(p.x, IDEAL[0][0], "lined up with the first mark", 0.0001)
	l.rub_out(Vector2(IDEAL[0][0], IDEAL[0][1]))
	eq(l.marks.size(), 0)
	l.free()


# --- Billing ----------------------------------------------------------------------------

func test_their_wafers_are_free_hanging_them_isnt() -> void:
	var tuning := JobTuning.new()
	var j := ActiveJob.new()
	j.kind = "recessed"
	j.family = "recessed"
	j.type = JobType.of("recessed")
	j.circuit = ElectricalPanel.new().circuit_at(13)
	var b := _building()
	j.device = b.device(BuildingElectricalModel.RECESSED_FIXTURE)
	for id in b.wafer_ids():
		j.device_used("Wafer", b.device(id))
	j.device_used("Blank", j.device)
	j.materials_used.append("GuardStrip")
	j.cable_feet = 36
	eq(j.wrong_parts, 0)
	eq(j.parts_cost(tuning), 4 * tuning.wafer_install_extra + PartSpec.price_of("Blank") + PartSpec.price_of("GuardStrip") + ceili(36 * 45 / 50.0))
	j.device_used("Wafer", j.device)
	eq(j.wrong_parts, 1, "a wafer won't go in the old box")


func test_a_bad_layout_costs_a_star() -> void:
	var tuning := JobTuning.new()
	var j := ActiveJob.new()
	j.kind = "recessed"
	j.family = "recessed"
	j.type = JobType.of("recessed")
	j.circuit = ElectricalPanel.new().circuit_at(13)
	var w := Billing.Work.new()
	w.dead_tested = true
	eq(Billing.settle(j, w, true, tuning, 1.0).stars, 5)
	w.flaws.append("The lights aren't in straight lines.")
	var sheet := Billing.settle(j, w, true, tuning, 1.0)
	eq(sheet.stars, 4)
	is_true(sheet.lines.has("The lights aren't in straight lines."))


func test_the_coil_runs_out() -> void:
	var inv := Inventory.new()
	inv.hold("Romex")
	eq(inv.cable_on_hand(), 50)
	is_true(inv.pull_cable(30))
	eq(inv.coil_feet, 20, "the coil's open")
	is_false(inv.has("Romex"), "out of the bag and on your shoulder")
	is_false(inv.pull_cable(25), "only 20 ft left")
	eq(inv.coil_feet, 20, "nothing used trying")


# --- The whole job, in the real game -----------------------------------------------------

func _play() -> void:
	SaveGame.enabled = false
	Engine.time_scale = 0.0
	seed(11)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_node(main)
	service = main.service
	service.tuning = JobTuning.new()
	service.call_generator.catalog = [JobType.of("recessed")] as Array[JobType]
	service.start_job()                   # its rules pick a one-story house: an attic over the master bedroom


func _customer_says() -> String:
	service._return_visit()
	return service.dialogue._text.text


func _hole_hints(work: RecessedWork) -> int:
	return work.get_children().filter(func(n: Node) -> bool:
		return n is Interactable and not n.is_queued_for_deletion() and (n as Interactable).prompt.begins_with("Empty hole")).size()


func test_scenario_recessed_lights() -> void:
	_play()
	var job := service.job
	if job == null or job.kind != "recessed":
		check(false, "dispatch sent a recessed job (%s)" % (job.kind if job != null else "nothing"))
		return
	service._on_customer(service.player)
	is_true(service.dialogue._text.text.contains("bought the lights"), "theirs, by the door")
	service._grab_customer_part()
	eq(service.inventory.in_bag("Wafer"), 4)
	service._go_to_work()
	for part in ["Blank", "Romex", "GuardStrip"]:
		service.inventory.carry(part)
	var inside := service._inside
	var work := inside.recessed
	check(work != null, "the house knows")
	var b := inside.electrical
	is_true(work.fixture.alt_prompt.contains("Lay out"), "F on the old light gets the tape out")
	is_true(_customer_says().contains("worked out where"), "nothing laid out yet")

	# Measure and mark.
	for m: Array in IDEAL:
		eq(work.layout.place(Vector2(m[0], m[1])), "")
	work._laid_out(work.layout.marks)
	is_true(b.laid_out())
	eq(work.flaws(), [] as Array[String])
	# Cut.
	for i in 4:
		work.cut(i, false)
	is_true(b.any_cut())
	eq(work.fixture.alt_prompt, "", "no redoing the layout once there are holes")
	eq(_hole_hints(work), 4, "looking up at an empty hole tells you the cable comes from the attic")

	# Up in the attic: daisy-chain the cable from the old box out.
	var ids := b.wafer_ids()
	var from := BuildingElectricalModel.RECESSED_FIXTURE
	var hows: Array[String] = []
	for id in ids:
		eq(work.use_point(from), "pulled")
		var crossing := work.crossings(work._at(from), work._at(id)) > 0
		eq(work.use_point(id, crossing and hows.is_empty()), "ran")     # bore the first crossing, guard-strip the rest
		hows.append(b.recessed["runs"][-1]["how"])
		from = id
	is_true("bored" in hows or "guarded" in hows or hows.all(func(h: String) -> bool: return h == "bay"), "how it got across: %s" % str(hows))
	eq(b.bare_runs().size(), 0, "nothing bare across the joists")
	is_true(job.cable_feet > 20, "%d ft pulled" % job.cable_feet)
	for id in ids:
		check(work.wafers.has(id), "a wafer box at %s's hole" % id)
	eq(_hole_hints(work), 0, "cable's down every hole: the wafers are there to work on")
	eq(inside.layout_violations(), [] as Array[String])

	# Kill it, prove it dead, take the old light down, splice it through.
	service._sim.toggle(job.target)
	service._box.work.verified_dead = true
	service._box.work.measured_live = true
	_splice_old_box(b)
	job.device_used("Blank", b.device(BuildingElectricalModel.RECESSED_FIXTURE))
	for id in ids:
		_wire_wafer(b.device(id))
		job.device_used("Wafer", b.device(id))
		(work.wafers[id] as BoxView).work.tested_after = true
	is_true(_customer_says().contains("dark"), "breaker's still off")
	service._sim.toggle(job.target)
	is_true(job.outcomes_complete())
	is_true(_customer_says().contains("that's got it"))
	eq(job.wrong_parts, 0)
	var parts := job.parts_cost(service.tuning)
	is_true(parts >= 4 * service.tuning.wafer_install_extra + PartSpec.price_of("Blank"), "hanging them and the blank on the bill: $%d" % parts)
	var sheet := Billing.settle(job, service._work(), true, service.tuning, 1.0)
	eq(sheet.stars, 5, "\n".join(sheet.lines))


func test_bare_across_the_joists_gets_written_up_till_you_guard_it() -> void:
	_play()
	var job := service.job
	if job == null or job.kind != "recessed":
		check(false, "dispatch sent a recessed job")
		return
	service._on_customer(service.player)
	service._go_to_work()
	service.inventory.carry("Romex")
	var work := service._inside.recessed
	var b := service._inside.electrical
	work.layout.marks = IDEAL.duplicate(true)
	work._laid_out(work.layout.marks)
	for i in 4:
		work.cut(i, false)
	var ids := b.wafer_ids()
	# Find a run that crosses joists, from the old box or along the chain.
	var from := BuildingElectricalModel.RECESSED_FIXTURE
	var crossed := ""
	for id in ids:
		eq(work.use_point(from), "pulled")
		eq(work.use_point(id), "ran")   # E with no guard strip in the bag: over the tops, bare
		if b.recessed["runs"][-1]["how"] == "bare":
			crossed = id
		from = id
	check(crossed != "", "some run crosses the joists")
	is_true(service._defects().any(func(d: Dictionary) -> bool: return d["problem"] == "no_guard_strip"), "the inspector would have it")
	is_true(service._work().flaws.size() > 0, "and the customer's heard about it")
	eq(work.use_point(crossed, true), "no_strip", "you need a 2x4")
	for r: Dictionary in b.bare_runs():
		service.inventory.carry("GuardStrip")
		eq(work.use_point(r["to"], true), "guarded")
	is_false(service._defects().any(func(d: Dictionary) -> bool: return d["problem"] == "no_guard_strip"))
