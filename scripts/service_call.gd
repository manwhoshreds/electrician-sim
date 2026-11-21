class_name ServiceCall
extends Node
## Runs the jobs, and the conversations around them: dispatch sends you to a
## house, the customer explains the problem, you work on the panel or a box,
## fetch parts from the truck, and get paid. A new job comes in a few seconds
## after each one finishes.
##
## This is the coordinator. What's in it is wiring between the pieces that
## own things, and what the people say:
##   JobGenerator  picks the house, the fault and who's calling
##   ActiveJob     the job you're on: what you've found out and used
##   Inventory     the truck's stock and what's in your hands
##   Wallet        the money (and CreditAccount, at the supply house)
##   SupplyCounter buying parts
##   Billing       the job sheet
##   Aftercare     the days after you leave
## Job kinds and their lines are in res://data/jobs/, parts in
## res://data/parts/, pay and dispatch numbers in res://data/job_tuning.tres.

## A moment the game can be saved: no job under way. Just before each call
## comes in, and once each job's closed out.
signal checkpoint

const DAYS := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
const FIRST_QUESTIONS := ["when", "touched", "new", "where"]
const ASK := {
	"when": "When did this start?",
	"touched": "Have you touched the breaker at all?",
	"new": "Plugged in anything new lately?",
	"where": "Where's your panel?",
}
## What you call the new device when you tell them what you did.
const PART_WORDS := {"GFCI": "GFCI", "Range": "stove outlet", "Switch": "light switch", "Fixture": "light fixture",
		"ThreeWay": "3-way switch"}

var town: Town
var player: Player
var van: Van
var hud: Hud
var dialogue: DialogueBox
var aftercare: Aftercare
## Pay, penalties and dispatch: edit the .tres in the inspector.
var tuning: JobTuning = preload("res://data/job_tuning.tres")
var wallet: Wallet
## Your account at the supply house, once they'll give you one.
var credit := CreditAccount.new()
var inventory := Inventory.new()
## What the business has brought in, all time and this week.
var stats := BusinessStats.new()
## Generated and completed calls, behind the save-friendly repository port.
var call_repository := ServiceCallRepository.new()
## The parts counter at the supply house.
var supply: SupplyCounter
## The job you're on; the last one between calls.
var job: ActiveJob

var _generator: JobGenerator
## The truck's inventory screen, for filling your job bag at the tailgate.
var truck_screen: TruckScreen
## The computer at home: TradesmanGear.com and your email.
var computer_screen: ComputerScreen
## What you've bought online, and what's on its way.
var upgrades := Upgrades.new()
## Your email, newest last: {at (game minutes), from, subject, text}.
var mail: Array[Dictionary] = []
## Texts on your phone, newest last: {at (game minutes), from, text, read}.
var texts: Array[Dictionary] = []
## Every house's wiring, kept between visits and saved.
var properties: PropertyRegistry
## Makes new calls from what's really in the houses.
var call_generator: ServiceCallGenerator
## The dispatch board: what's waiting, and when it can be done.
var scheduler := ServiceCallScheduler.new(call_repository)
## The new-call dice for this game, saved, so a loaded game carries on making the same calls.
var call_seed := 0
var _house := {}
var _sim: ElectricalPanel
var _customer: Customer
var _panel: PanelView
var _inside: HouseInterior
var _box: BoxView                # the outlet, switch, fixture or smoke detector with the job's fault
var _pair: BoxView               # on a light job, the other half: the switch or the fixture
var _rear: Interactable          # the truck's tailgate
var _beacon: MeshInstance3D
var _last_address := ""
var _job_running := false
var _kettle_rolled := false      # this call's kettle-and-toaster chance has been rolled
## Days and nights: when you can sleep, how long you last. Edit the .tres in the inspector.
var sleep_tuning: SleepTuning = preload("res://data/sleep_tuning.tres")
## How much you've got left today.
var fatigue := Fatigue.new()
var _told_no_calls := false      # said "nothing more today" for this wait
## The house you've just finished at, still open round you until you walk out.
var _leaving: HouseInterior
## What this customer writes about you, when it isn't the usual for the stars ("" for that).
var _review_note := ""
var _jobs_done := 0
var _minutes := 8.0 * 60.0       # game clock: one minute per real second


func _init() -> void:
	wallet = Wallet.new(tuning.starting_money)
	_generator = JobGenerator.new(tuning, call_repository)


func _ready() -> void:
	aftercare = Aftercare.new()
	aftercare.hud = hud
	aftercare.on_text = send_text
	aftercare.wallet = wallet
	add_child(aftercare)
	properties = PropertyRegistry.new(town.houses, aftercare)
	call_seed = randi()
	call_generator = ServiceCallGenerator.new(properties, call_repository, call_seed)
	dialogue = DialogueBox.new()
	add_child(dialogue)
	truck_screen = TruckScreen.new()
	truck_screen.closed.connect(_ui_close)
	add_child(truck_screen)
	computer_screen = ComputerScreen.new()
	computer_screen.closed.connect(_ui_close)
	add_child(computer_screen)
	_rear = Interactable.new()
	_rear.position = Vector3(0, 0, 2.95)
	_rear.prompt = "[E] Get parts from the truck"
	_rear.reach = 1.8
	_rear.aim = Vector3(0, 0.5, 0)
	_rear.aim_radius = 0.7
	_rear.active = false
	_rear.on_use = _open_van
	van.add_child(_rear)
	supply = SupplyCounter.new()
	supply.dialogue = dialogue
	supply.player = player
	supply.van = van
	supply.town = town
	supply.inventory = inventory
	supply.wallet = wallet
	supply.credit = credit
	supply.tuning = tuning
	supply.aftercare = aftercare
	add_child(supply)
	town.supply_house.player = player
	town.supply_house.clerk.on_use = supply.open
	# Home: the computer on the desk is the office; the bed's for sleeping.
	town.home_house.computer.on_use = _open_office
	town.home_house.bed.on_use = func(_p: Node3D) -> void: go_to_sleep()
	get_tree().create_timer(tuning.first_job_delay, false).timeout.connect(start_job)


func _process(delta: float) -> void:
	_minutes += delta
	_tire(delta)
	# Deliveries wait till you're between jobs and out of the truck (the van can't swap under you).
	if not upgrades.on_the_way.is_empty() and not _job_running and player.driving == null:
		_take_deliveries()
	if _leaving != null and not _leaving.contains(player.global_position):
		_left_the_house()
	_update_hud(delta)
	if _job_running and job.family == "panel" and _sim.appliance_running(job.target) and _panel._clamped == "wire_%d" % job.target:
		job.load_tested = true
	if _job_running:
		_sim.service_on = (_house["meter_box"] as MeterBase).meter_in
		# The beam's for finding the house. Up close it would just tint everything.
		_beacon.visible = not job.met and player.global_position.distance_to(_customer.global_position) > 18.0


# --- The pause screen ------------------------------------------------------------------

## Everything the pause screen shows, as it stands right now.
func pause_summary() -> PauseSummary:
	var s := PauseSummary.new()
	var day := int(_minutes / 1440)
	s.day_text = "%s, Day %d" % [DAYS[(1 + day) % 7], day + 1]
	s.time_text = _time_text()
	s.money = wallet.money
	s.rating = aftercare.rating()
	s.review_count = aftercare.reviews.size()
	for i in range(aftercare.reviews.size() - 1, -1, -1):    # newest first
		s.reviews.append(aftercare.reviews[i])
	s.active_calls = 1 if _job_running else 0
	s.total_earned = stats.total_earned
	s.week_earned = stats.this_week(_minutes)
	s.can_save = between_jobs()
	s.vehicle_word = van.spec()["word"]
	s.load_used = inventory.load_used()
	s.capacity = capacity()
	for p in PartSpec.all():
		if inventory.count(p.id) > 0:
			s.stock.append([p.name, inventory.count(p.id)])
	s.in_hand = inventory.bag_words()
	if credit.open:
		s.account = "Supply house account: $%d owed, $%d limit" % [credit.owed, tuning.credit_limit]
	else:
		s.account = "No supply house account yet (%d of %d five-star reviews)" % [aftercare.five_star_reviews(), tuning.credit_five_stars_needed]
	if _job_running:
		_summarise_job(s)
	return s


func _summarise_job(s: PauseSummary) -> void:
	s.has_job = true
	s.job_title = (job.customer_name.split(" ")[-1] as String) + " Residence"
	s.address = job.address
	s.home_type = "Single-family home, %s" % ("two stories" if _house["two_story"] else "one story")
	s.status = "WARRANTY CALLBACK" if job.kind == "callback" else "IN PROGRESS"
	s.complaint = "\"%s\"" % job.notes[0] if job.met and not job.notes.is_empty() else "Dispatch says: %s. Go and talk to them." % job.issue
	if job.kind == "callback":
		s.job_type = "Warranty callback"
	elif job.family == "panel":
		s.job_type = "Breaker troubleshooting"
	elif job.family == "heater":
		s.job_type = "Water heater repair"
	elif job.family == "install" or job.family == "recessed":
		s.job_type = "Installation"
	elif job.type.box == "smoke":
		s.job_type = "Smoke detector service"
	elif not job.type.asks_questions:
		s.job_type = "Installation"
	else:
		s.job_type = "Troubleshooting / Repair"
	var card := _card()
	s.payout = card["payout"]
	s.objectives = card["steps"]
	s.directory.assign(_directory())
	var c := job.circuit
	if job.family == "device" and _box != null:
		s.details.append(["In the %s, on the %s" % [_box.room, _circuit_words(c)], false])
	elif job.family == "heater":
		s.details.append(["The water heater in the laundry, on the %s" % _circuit_words(c), false])
	elif job.family == "install":
		s.details.append(["A new outlet in the %s, off an existing one" % _inside.electrical.rooms[job.equipment_ids[0]], false])
	elif job.family == "recessed":
		s.details.append(["%d wafers in the master bedroom, on the old light's switch (%s)" % [_inside.electrical.wafer_ids().size(), _circuit_words(c)], false])
	else:
		s.details.append(["Affects the %s" % _circuit_words(c), false])
	if c.breaker.tripped:
		s.details.append(["Its breaker has tripped", false])
	elif not c.breaker.on:
		s.details.append(["Its breaker is switched off", false])
	else:
		s.details.append(["Its breaker hasn't tripped", false])
	var off := _sim.circuits.filter(func(o: Circuit) -> bool: return o.slot != job.target and not o.breaker.closed()).size()
	if off == 0:
		s.details.append(["Other areas of the house have power", false])
	else:
		s.details.append(["1 other circuit is off" if off == 1 else "%d other circuits are off" % off, false])
	for t in _overloads():
		s.details.append(["The %s tripped: %s" % [_circuit_words(_sim.circuit_at(t.slot)), t.what_was_running()], false])
	if not _house["two_story"]:
		s.details.append(["Attic access available", true])


# --- The HUD round the edge -------------------------------------------------------------

var _hud_t := 0.0


## Money, rating, the day and time, where you are and your next appointment.
## Twice a second is plenty.
func _update_hud(delta: float) -> void:
	_hud_t -= delta
	if _hud_t > 0.0:
		return
	_hud_t = 0.5
	hud.set_money(wallet.money)
	hud.set_rating(aftercare.rating_text())
	hud.set_when(day_text(), _time_text(), fatigue.words().capitalize() if fatigue.words() != "" else "")
	hud.set_unread(unread_texts())
	hud.set_place(_place_text())
	if _job_running:
		var line := job.address
		if not job.met and job.window_start > _minutes:
			line += "   %s  (%s)" % [_hour_minute(job.window_start), _until(job.window_start)]
		hud.set_appointment("Current Job: %s" % job.customer_name, line)
		return
	var next := scheduler.next_call(_minutes)
	if next == null:
		hud.set_appointment("")
		return
	hud.set_appointment("Next Appointment: %s" % _who(next),
			"%s  (%s)   %s" % [_hour_minute(next.window_start), _until(next.window_start), next.address])


## "Mon, Day 1".
func day_text() -> String:
	return "%s, Day %d" % [DAYS[ServiceCallScheduler.weekday(_minutes)], int(_minutes / ServiceCallScheduler.DAY) + 1]


## Where you are: home, the job, a business, or the street you're on. Your own
## lot and the job's win over a neighbour whose door happens to be closer.
func _place_text() -> String:
	var at := player.global_position
	if (town.home["door"] as Vector3).distance_to(at) < 22.0:
		return "Home – %s" % town.home["address"]
	if _job_running and not _house.is_empty() and (_house["door"] as Vector3).distance_to(at) < 22.0:
		return "%s – %s" % [job.customer_name, job.address]
	var near := {}
	var best := INF
	for h: Dictionary in town.houses:
		var d := (h["door"] as Vector3).distance_to(at)
		if d < best:
			best = d
			near = h
	if near.is_empty() or best > 40.0:
		return "Cedar Valley"
	var address: String = near["address"]
	if best < 16.0:
		return address
	var street := address.substr(address.find(" ") + 1).get_slice(" (", 0)     # "113 Birch St (Diner)" -> "Birch St"
	return "%s – Cedar Valley" % street


## "10:30 AM", with the day in front if it isn't today.
func _hour_minute(minutes: float) -> String:
	var total := int(minutes)
	var hour := (total / 60) % 24
	var text := "%d:%02d %s" % [12 if hour % 12 == 0 else hour % 12, total % 60, "AM" if hour < 12 else "PM"]
	if int(minutes / ServiceCallScheduler.DAY) != int(_minutes / ServiceCallScheduler.DAY):
		text = "%s %s" % [DAYS[ServiceCallScheduler.weekday(minutes)], text]
	return text


## How long till then: "now", "47 min", "2h 05m".
func _until(minutes: float) -> String:
	var left := int(minutes - _minutes)
	if left <= 0:
		return "now"
	if left < 60:
		return "%d min" % left
	return "%dh %02dm" % [left / 60, left % 60]


func _time_text() -> String:
	var total := int(_minutes)
	var hour := (total / 60) % 24
	var shown := hour % 12
	return "%d:%02d %s" % [12 if shown == 0 else shown, total % 60, "AM" if hour < 12 else "PM"]


# --- The save file -------------------------------------------------------------------

## True between jobs: the only time there's nothing half-done to lose.
func between_jobs() -> bool:
	return not _job_running


## The business, for the save file: money, the truck, what you drive, every
## house you've worked on, and the clock. Only valid between jobs.
func to_save() -> Dictionary:
	return {"clock_minutes": _minutes, "last_address": _last_address, "jobs_done": _jobs_done, "vehicle": van.model_name,
			"wallet": wallet.to_save(), "credit": credit.to_save(), "stats": stats.to_save(), "inventory": inventory.to_save(),
			"aftercare": aftercare.to_save(), "service_calls": call_repository.to_save(), "properties": properties.to_save(),
			"call_seed": call_seed, "fatigue": fatigue.to_save(),
			"upgrades": upgrades.to_save(), "mail": mail.duplicate(true), "texts": texts.duplicate(true)}


func load_save(d: Dictionary) -> void:
	_minutes = float(d.get("clock_minutes", _minutes))
	_last_address = String(d.get("last_address", ""))
	_jobs_done = int(d.get("jobs_done", 0))
	if d.get("vehicle", "truck") != van.model_name:
		_set_vehicle(String(d["vehicle"]))
	wallet.load_save(d.get("wallet", {}))
	credit.load_save(d.get("credit", {}))
	stats.load_save(d.get("stats", {}))
	inventory.load_save(d.get("inventory", {}))
	aftercare.load_save(d.get("aftercare", {}))
	call_repository.load_save(d.get("service_calls", {}))
	properties.load_save(d.get("properties", {}))
	call_seed = int(d.get("call_seed", call_seed))
	call_generator.seed_base = call_seed
	scheduler.rebuild(properties)
	fatigue.load_save(d.get("fatigue", {}))
	upgrades.load_save(d.get("upgrades", {}))
	if van.model_name == "van" and not upgrades.owns("work_van"):
		upgrades.owned.append("work_van")      # bought at the old office, before the website
	mail.clear()
	for m: Dictionary in d.get("mail", []):
		mail.append({"at": float(m["at"]), "from": String(m["from"]), "subject": String(m["subject"]), "text": String(m["text"])})
	texts.clear()
	for t: Dictionary in d.get("texts", []):
		texts.append({"at": float(t["at"]), "from": String(t["from"]), "text": String(t["text"]), "read": bool(t.get("read", true))})
	_apply_upgrades()


# --- The job card -------------------------------------------------------------------

func _directory() -> Array:
	var out: Array = []
	for slot in range(1, 17):
		out.append(_sim.circuit_at(slot).name)
	return out


## Everything the HUD's job cards show, read straight from where the job stands.
func _callback_card() -> Dictionary:
	var fixed := _callback_fixed()
	return {
		"number": job.number, "name": job.customer_name, "address": job.address, "issue": "Warranty callback: " + job.callback["story"],
		"steps": [["Hear them out", job.met], ["Find what went wrong", job.met and (_panel.work.measured_amps or (_box != null and _box.work.measured_live))],
				["Make it right", fixed], ["Tell them it's sorted", false]],
		"objectives": [["Callbacks are free. Fix it properly this time.", fixed]],
		"payout": 0, "place": _direction_to(_panel.global_position if job.met else _customer.global_position), "directory": _directory(),
	}


func _card() -> Dictionary:
	if job.kind == "callback":
		return _callback_card()
	if job.family == "device":
		return _device_card()
	if job.family == "heater":
		return _heater_card()
	if job.family == "install":
		return _install_card()
	if job.family == "recessed":
		return _recessed_card()
	var state := _sim.check_repair(job.target)
	var working := state == "ok" or state == "oversize"
	var goal: Vector3 = _panel.global_position if job.met else _customer.global_position
	var work := _panel.work
	return {
		"number": job.number,
		"name": job.customer_name,
		"address": job.address,
		"issue": JobType.fill(job.type.issue, job.circuit.customer),
		"steps": [
			["Talk to the customer", job.met],
			["Inspect the panel", _panel.cover_removed],
			["Identify the cause", work.measured_target and work.measured_amps],
			["Repair or replace", job.final_part > 0 or job.advised],
			["Test and verify", working],
			["Button up the panel", working and _panel.cover_on and not _panel.door_open],
		],
		"objectives": _panel_objectives(working),
		"payout": job.quoted(tuning),
		"place": _direction_to(goal) + _bag_note(),
		"directory": _directory(),
	}


func _panel_objectives(working: bool) -> Array:
	var work := _panel.work
	var required: Array = job.objectives.map(func(o: ServiceObjective) -> Array: return [o.description, o.is_complete()])
	if job.kind == "weak" or job.kind == "overload":
		var objectives: Array = [
			["Clamp the circuit", work.measured_amps],
			["Clamp it while they run the %s" % job.circuit.appliance, job.load_tested],
			["Weak breaker? Replace it. Overload? Tell them.", job.final_part > 0 or job.advised],
			["Breaker on and holding", working],
		]
		objectives.append_array(required)
		return objectives
	return [
		["Measure circuit voltage", work.measured_target],
		["Clamp circuit current", work.measured_amps],
		["Main off, test dead", work.verified_dead],
		["Replace the breaker", job.final_part > 0],
		["Power back on", working],
	]


func _device_card() -> Dictionary:
	var b := _box
	var work := b.work
	var goal: Vector3 = b.global_position if job.met else _customer.global_position
	var objectives: Array = job.objectives.map(func(o: ServiceObjective) -> Array: return [o.description, o.is_complete()])
	if objectives.is_empty():
		objectives = [
			["Test it before you touch it", work.measured_live],
			["Find its breaker and kill it", _sim.circuit_volts(b.device.slot) < 5.0 or work.verified_dead],
			["Test the black wire dead", work.verified_dead],
			["Fix the connection or swap the device", work.worked_on],
			["Cut back any burnt wire", not b.device.burnt.values().has(true)],
			["Tests right with the power on", work.tested_after],
		]
	return {
		"number": job.number,
		"name": job.customer_name,
		"address": job.address,
		"issue": JobType.fill(job.type.issue, b.room),
		"steps": [
			["Talk to the customer", job.met],
			["Check the outlet", work.measured_live],
			["Breaker off, test it dead", work.verified_dead],
			["Repair or replace it", work.worked_on and b.device.kind != ""],
			["Power on, it tests right", work.tested_after],
			["Plate back on", work.tested_after and b.device.repair_state() == "ok"],
		],
		"objectives": objectives,
		"payout": job.quoted(tuning),
		"place": _direction_to(goal) + _bag_note(),
		"directory": _directory(),
	}


func _heater_card() -> Dictionary:
	var v := _inside.heater_view
	var h := _inside.heater
	var work := v.work
	var goal: Vector3 = v.global_position if job.met else _customer.global_position
	var objectives: Array = [
		["Volts across the elements, power on", work.measured_live],
		["Breaker off, L1 to L2 tests dead", work.verified_dead],
		["Ohm both elements", v.ohmed.has("upper") and v.ohmed.has("lower")],
	]
	if job.kind == "wh_eco":
		objectives.append(["Reset the high-limit", not h.eco_tripped])
	else:
		objectives.append(["Cold off, drain it below the element", h.element[job.kind.trim_prefix("wh_")] != "ok" or v.fitted > 0])
		objectives.append(["New element in, wires on", v.fitted > 0 and h.wired["upper"] and h.wired["lower"]])
		objectives.append(["Drain shut, cold on, tank full", h.level >= 1.0 and h.cold_open and not h.drain_open])
	objectives.append(["Power on, 240 V across the element", work.tested_after])
	return {
		"number": job.number,
		"name": job.customer_name,
		"address": job.address,
		"issue": job.type.issue,
		"steps": [
			["Talk to the customer", job.met],
			["Test it with the power on", work.measured_live],
			["Breaker off, test it dead", work.verified_dead],
			["Find the bad part and fix it", work.worked_on and not h.eco_tripped and h.element["upper"] == "ok" and h.element["lower"] == "ok"],
			["Power on, it's heating", h.fixed()],
			["Covers back on", h.fixed() and h.buttoned_up()],
		],
		"objectives": objectives,
		"payout": job.quoted(tuning),
		"place": _direction_to(goal) + _bag_note(),
		"directory": _directory(),
	}


## The new outlet's id in the building, and the views of it and the outlet it's fed from (null till they exist).
func _install_parts() -> Array:
	var id: String = job.equipment_ids[0]
	var source_id: String = _inside.electrical.installs[id]["source"] if _inside.electrical.installs.has(id) else ""
	return [id, _inside.view_for_device(_inside.electrical.device(id)), _inside.view_for_device(_inside.electrical.device(source_id))]


func _install_card() -> Dictionary:
	var parts := _install_parts()
	var new_box: BoxView = parts[1]
	var source: BoxView = parts[2]
	var done := job.outcomes_complete()
	var landed := source != null and source.device.repair_state() == "ok"
	var goal: Vector3 = _inside.install_mark_position(parts[0]) if job.met else _customer.global_position
	return {
		"number": job.number,
		"name": job.customer_name,
		"address": job.address,
		"issue": job.complaint,
		"steps": [
			["Talk to the customer", job.met],
			["Cut a box in at their mark", new_box != null],
			["Breaker off, test the feed outlet dead", source != null and source.work.verified_dead],
			["Land the new cable at the feed outlet", landed],
			["New receptacle in and wired", new_box != null and new_box.device.kind == "Receptacle" and new_box.device.wires.values().all(func(t: String) -> bool: return t != "")],
			["Power on, it tests right", new_box != null and new_box.work.tested_after],
			["Plates back on, both boxes", done],
		],
		"objectives": job.objectives.map(func(o: ServiceObjective) -> Array: return [o.description, o.is_complete()]),
		"payout": job.quoted(tuning) + PartSpec.price_of("OldWork"),
		"place": _direction_to(goal) + _bag_note(),
		"directory": _directory(),
	}


func _recessed_card() -> Dictionary:
	var e := _inside.electrical
	var ids := e.wafer_ids()
	var cut := ids.size() > 0 and range(ids.size()).all(func(i: int) -> bool: return e.hole_cut(i))
	var fed := ids.all(func(id: String) -> bool: return e.fed(id))
	var wired := ids.all(func(id: String) -> bool: return e.device(id).kind == "Wafer" and e.device(id).wires.values().all(func(t: String) -> bool: return t != ""))
	var lit := ids.all(func(id: String) -> bool: return e.device(id).lamp_volts() > 100.0 and e.device(id).repair_state() == "ok")
	var old := _box.device if _box != null else null
	var goal: Vector3 = _box.global_position if job.met and _box != null else _customer.global_position
	var count := ids.size()
	return {
		"number": job.number,
		"name": job.customer_name,
		"address": job.address,
		"issue": job.complaint,
		"steps": [
			["Talk to the customer, grab their wafers", job.met and job.got_customer_part],
			["Lay out %d marks on the ceiling (F on the old light)" % count, e.laid_out()],
			["Cut a 6\" hole at each mark", cut],
			["Breaker off, test dead, old light down", _box != null and _box.work.verified_dead and old != null and old.kind != "Fixture"],
			["Pull 14/2 hole to hole in the attic", fed],
			["Wire each wafer and push it up", wired],
			["Splice the old box through, blank cover on", old != null and old.kind == "Blank" and old.repair_state() == "ok"],
			["Power on, switch on: all %d lit" % count, lit],
		],
		"objectives": job.objectives.map(func(o: ServiceObjective) -> Array: return [o.description, o.is_complete()]),
		"payout": recessed_quote(),
		"place": _direction_to(goal) + _bag_note(),
		"directory": _directory(),
	}


## What a recessed job's worth: call-out and labour, hanging each wafer, the
## blank, and about 40 ft of cable. Their wafers aren't on it.
func recessed_quote() -> int:
	var n := _inside.electrical.wafer_ids().size() if _inside != null else RecessedLightsStrategy.COUNT
	return tuning.call_out + tuning.labour + n * tuning.wafer_install_extra + PartSpec.price_of("Blank") + ceili(40 * PartSpec.price_of("Romex") / 50.0)


func _bag_note() -> String:
	return ("  |  Bag: %s" % inventory.bag_words()) if not inventory.hands_empty() else ""


func _direction_to(goal: Vector3) -> String:
	var d := goal - player.global_position
	d.y = 0.0
	if d.length() < 12.0:
		return "You're here"
	var compass := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	var i := posmod(int(round(atan2(d.x, -d.z) / (TAU / 8.0))), 8)
	return "%d m %s" % [int(d.length()), compass[i]]


# --- Dispatch -----------------------------------------------------------------------

func start_job() -> void:
	if aftercare.suspended():
		hud.show_message("Your license is suspended. No calls till it's back.", 4.0)
		_text_once("Dispatch", "Your license is suspended. No calls till it's back.")
		get_tree().create_timer(tuning.suspended_retry, false).timeout.connect(start_job)
		return
	checkpoint.emit()                # last chance to save before the new job changes anything
	# Callbacks on your old work come before anything new.
	var callback := aftercare.next_callback()
	var waited := ""
	if not callback.is_empty():
		_house = _generator.pick_house(town.houses, callback)
		job = _generator.callback_job(_house, callback)
	else:
		var next := _next_from_board()
		if next == null:
			get_tree().create_timer(tuning.next_job_delay, false).timeout.connect(start_job)
			return
		# Booked a little later, you go now and wait. Not till tomorrow, though:
		# the night's for sleeping, not skipping.
		if next.window_start - _minutes > MAX_WAIT_MINUTES:
			if not _told_no_calls:
				_told_no_calls = true
				hud.show_message("No more calls today. The next one's %s. Go home and get some sleep." % _clock_at(next.window_start), 5.0)
				send_text("Dispatch", "No more calls today. The next one's %s. Go home and get some sleep." % _hour_minute(next.window_start))
			get_tree().create_timer(tuning.next_job_delay, false).timeout.connect(start_job)
			return
		_told_no_calls = false
		var starts := scheduler.start(next, _minutes)
		if starts > _minutes:
			waited = "Booked for %s.  " % _clock_at(starts)
			_minutes = starts
		job = next
		_house = properties.property(job.address)
	_last_address = _house["address"]
	# Every house keeps its wiring, faults and all, between visits.
	var electrical := properties.model_for(_house["address"])
	_sim = electrical.panel
	_sim.demo.clear()
	_sim.overload_trips.clear()
	_kettle_rolled = false
	(_house["static_panel"] as Node3D).visible = false
	_inside = HouseInterior.new()
	_inside.house = _house
	_inside.sim = _sim
	_inside.electrical = electrical
	_inside.electrical_restored = aftercare.houses.has(_house["address"])
	_inside.inventory = inventory
	_inside.job = job
	_inside.van = van
	(_house["root"] as Node3D).add_child(_inside)
	if _inside.heater_view != null:
		_inside.heater_view.flooded.connect(_flooded)
	_place_device_fault()
	job.circuit = _sim.circuit_at(job.target)
	_generator.name_and_number(job)
	if aftercare.houses.has(job.address):
		job.customer_name = aftercare.houses[job.address]["name"]   # same people live there

	_customer = Customer.new()
	_customer.person_name = job.customer_name
	_customer.arrived.connect(_on_customer_arrived)
	_customer.player = player
	_customer.on_use = _on_customer
	add_child(_customer)
	_customer.global_position = _house["door"]

	_panel = PanelView.new()
	_panel.sim = _sim
	_panel.target_slot = job.target
	_panel.inventory = inventory
	_panel.job = job
	_panel.meter_pos = _house["meter"]
	_panel.house_front = _house["front"]
	_panel.active = false
	# Placed before it's added to the tree because the model is built on entry.
	_panel.transform = Transform3D(_house["panel_basis"], _house["panel"])
	add_child(_panel)
	_panel.visible = false

	_add_beacon(_house["door"])
	_job_running = true
	var what := JobType.fill(job.type.issue, _box.room if _box != null and job.family == "device" else job.circuit.customer)
	if job.complaint != "":
		what = job.complaint
	job.issue = what if job.kind != "callback" else "Warranty callback"
	hud.show_message("DISPATCH: %s%s\n%s: %s" % [waited, job.address, job.customer_name, what], 6.0)
	send_text("Dispatch", "%sNew call at %s. %s says: %s" % [waited, job.address, job.customer_name, what])


## The longest you'd wait for a booked call before it's a job for tomorrow, in minutes.
const MAX_WAIT_MINUTES := 120.0


## The next call on the dispatch board, topping the board up with new ones
## first. Null if nothing in town can happen right now.
func _next_from_board() -> ActiveJob:
	scheduler.expire(_minutes)
	while scheduler.board.size() < tuning.board_size:
		var made := call_generator.generate(_jobs_done, aftercare.five_star_reviews(), scheduler.addresses() + [_last_address])
		if made == null:
			break
		scheduler.post(made, _minutes)
	return scheduler.next_call(_minutes)


## "9:00 Tue", for a booked time.
func _clock_at(minutes: float) -> String:
	var t := int(fmod(minutes, ServiceCallScheduler.DAY))
	var days := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
	return "%d:%02d %s" % [t / 60, t % 60, days[ServiceCallScheduler.weekday(minutes)]]


## Finds the box a device job is about, now the house is built, and gives it
## the job's fault. A callback goes back to the box it's about.
func _place_device_fault() -> void:
	_box = null
	_pair = null
	var t := job.type
	if job.kind == "callback":
		if job.callback["why"] == "box":
			_box = _inside.boxes[job.callback["target"]]
			job.target = _box.device.slot
	elif job.family == "install":
		_box = _inside.view_for_device(job.device)      # null till the box is cut in
	elif job.family == "recessed":
		_box = _inside.view_for_device(job.device)      # the old light coming down
	elif job.family == "device" and not job.placed_on_arrival:
		_box = _inside.view_for_device(job.device)
		_pair = _inside.view_for_device(job.pair) if job.pair != null else null
	elif job.family == "device":
		match t.box:
			"junction":
				_box = _inside.junctions.pick_random()
				_box.set_fault(t.box_fault)
			"smoke":
				_box = _inside.pick_smoke(job.kind)
			"outlet":
				_box = _inside.pick_box(job.kind)
				_box.set_fault(t.box_fault)
			_:                           # a light: the switch, the fixture, or one of a 3-way pair
				var pair := _inside.pick_light(t.box, t.room)
				_box = pair[0]
				_pair = pair[1]
				if t.box_fault != "":
					_box.set_fault(t.box_fault)
		job.target = 13 if t.box == "smoke" else _box.device.slot
	if _box != null:
		job.device = _box.device
	if _pair != null:
		job.pair = _pair.device


func _add_beacon(at: Vector3) -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.7
	cyl.bottom_radius = 0.7
	cyl.height = 70.0
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.55, 0.1, 0.35)
	_beacon = MeshInstance3D.new()
	_beacon.mesh = cyl
	_beacon.material_override = m
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beacon)
	_beacon.global_position = at + Vector3.UP * 35.0


# --- Talking ----------------------------------------------------------------------

func _on_customer(_p: Node3D) -> void:
	_ui_open()
	if not job.met:
		job.met = true
		_customer.waving = false
		_beacon.visible = false
		_panel.visible = true
		var line := _greeting()
		job.notes.append(line)
		_menu(line)
	else:
		_return_visit()


## The customer uses their own house while you work: toast, and maybe the
## kettle at the same time, which is more than one 20 A circuit can take.
## Once you've told them, they do one thing at a time.
## Once a call, the first time they're in the kitchen, they might run the
## kettle with the toaster (JobTuning.kitchen_overload_percent): more than
## one 20 A circuit can take. Once you've told them, they never do.
func _on_customer_arrived(hangout: int) -> void:
	if hangout == 1 and _job_running:
		_sim.run_appliance(9, 35.0, "toaster")
		if _kettle_rolled:
			return
		_kettle_rolled = true
		var kettle_too := randf() * 100.0 < tuning.kitchen_overload_percent
		if kettle_too and not aftercare.has_habit(job.address, "one_thing_at_a_time"):
			_sim.run_appliance(9, 35.0, "kettle")


func _greeting() -> String:
	if job.kind == "callback":
		return job.callback["story"]
	if job.family == "device":
		return JobType.fill(job.type.greeting, _box.room)   # smoke detector greetings don't name a room
	if job.family == "heater":
		return job.type.greeting
	if job.family == "install":
		return job.complaint
	if job.family == "recessed":
		return job.complaint + " I bought the lights already. They're in a box by the front door."
	if job.kind == "weak" or job.kind == "overload":
		return job.type.greeting % [job.circuit.customer, job.circuit.appliance]
	return job.type.greeting % job.circuit.customer


func _menu(line: String) -> void:
	var options: Array = []
	var questions: Array = FIRST_QUESTIONS if job.type.asks_questions else ["where"]   # nothing new to learn on these
	for key: String in questions:
		if not job.asked.has(key):
			options.append([ASK[key], _ask.bind(key)])
	var appliance := job.circuit.appliance
	if job.family == "panel" and appliance != "" and ElectricalPanel.APPLIANCE_AMPS.get(appliance, 0.0) >= 2.0:
		options.append(["Could you run the %s for me for a minute?" % appliance, _ask_to_run])
	if job.family == "panel" and job.kind in ["weak", "overload", "callback"] and job.load_tested and not job.advised:
		options.append(["That circuit's overloaded. Keep the space heater off it.", _advise_overload])
	for t in _overloads():
		var c := _sim.circuit_at(t.slot)
		options.append(["Your %s tripped: %s pull %.1f A on a %d A breaker. Run one thing at a time on there." %
				[_circuit_words(c), t.what_was_running(), t.amps, t.rating], _advise_trip.bind(t.slot)])
	if job.customers_part() != "" and not job.got_customer_part and (job.type.customer_part != "" or job.customer_back):
		options.append(["I'll grab those wafers you bought." if job.family == "recessed" else "I'll grab that %s you bought." % PartSpec.of(job.customers_part()).name.to_lower(), _grab_customer_part])
	if can_ask_customer_to_buy():
		options.append(["I'm short on parts money. Could you pick up a %s? It won't be on the bill." % PartSpec.of(job.quoted_part()).name.to_lower(),
				_ask_customer_to_buy])
	options.append(["Let me go take a look at your panel." if job.family == "panel" else "Let me get to work.", _go_to_work])
	dialogue.say(job.customer_name, line, options)


func _ask(key: String) -> void:
	job.asked[key] = true
	var answer := "Round the side of the house, next to the meter."
	if job.family == "device":
		if _box.device.family == "smoke":
			answer += " The detectors are on the ceilings."
		elif _box.device.family == "jbox":
			answer += " And there's an attic hatch in the hall ceiling, if you need it."
		elif _pair != null:
			answer += " The light's in the %s, switch by the door." % _box.room
		elif _box.device.family == "240":
			answer += " The stove plugs in behind it."
		else:
			answer += " The bad outlet's in the %s." % _box.room
	elif job.family == "heater":
		answer += " The water heater's in the laundry room, past the kitchen."
	elif job.family == "install":
		answer += " You'll see my pencil mark on the wall in the %s." % _inside.electrical.rooms[job.equipment_ids[0]]
	elif job.family == "recessed":
		answer += " The attic stairs pull down from the hall ceiling."
	if key != "where":
		answer = JobType.fill(job.type.answer(key), job.circuit.appliance)
		job.notes.append(answer)
	_menu(answer)


func _ask_to_run() -> void:
	if not job.circuit.breaker.closed() or not _sim.bus_live():
		_menu("I can try, but it's got no power. The breaker's off.")
		return
	_sim.run_appliance(job.target)
	_menu("Sure, the %s is going now." % job.circuit.appliance)


func _advise_overload() -> void:
	job.advised = true
	if _sim.move_heater(job.target):
		_menu("Oh! The heater and the %s together? I'll keep the heater in the other room. Thank you." % job.circuit.appliance)
	else:
		_menu("There's nothing else on there, just the %s. It's never been a problem before." % job.circuit.appliance)


## Circuits other than the job's that they've overloaded while you're here,
## that you haven't told them about yet.
func _overloads() -> Array[OverloadTrip]:
	var out: Array[OverloadTrip] = []
	for slot: int in _sim.overload_trips:
		var t: OverloadTrip = _sim.overload_trips[slot]
		if slot != job.target and not job.advised_trips.has(slot) and not t.appliances.is_empty():
			out.append(t)
	return out


func _advise_trip(slot: int) -> void:
	job.advised_trips[slot] = true
	aftercare.add_habit(job.address, "one_thing_at_a_time")
	var c := _sim.circuit_at(slot)
	var still_off := not c.breaker.closed()
	_menu("Oh! I had no idea that was too much. I'll do one thing at a time from now on." +
			(" Can you get the %s back on?" % _circuit_words(c) if still_off else ""))


## What the customer calls a circuit: "kitchen counter plugs", or "furnace circuit".
func _circuit_words(c: Circuit) -> String:
	return c.customer if c.customer != "" else c.name.to_lower() + " circuit"


## Another circuit's gone off. If it's one they overloaded, they say what they
## were doing, and you can tell them what to do about it.
func _other_off(fallback: String) -> void:
	for c in _sim.circuits:
		if c.slot != job.target and not c.breaker.closed() and _sim.overload_trips.has(c.slot):
			var t: OverloadTrip = _sim.overload_trips[c.slot]
			if not t.appliances.is_empty():
				_menu("That's the %s off now. All I had going was %s." % [_circuit_words(c), t.what_was_running().trim_suffix(" together")])
				return
	_reply(fallback)


## Broke: the part this job needs isn't on the truck or in your bag, and you
## can't afford one. The customer can go and buy it themselves.
func can_ask_customer_to_buy() -> bool:
	var part := job.quoted_part()
	if part == "" or not PartSpec.has(part) or job.customers_part() != "":
		return false
	return inventory.count(part) == 0 and not inventory.has(part) and wallet.money < PartSpec.price_of(part)


func _ask_customer_to_buy() -> void:
	var part := job.quoted_part()
	job.customer_bought = part
	var the_job := job
	get_tree().create_timer(tuning.errand_seconds, false).timeout.connect(func() -> void:
		if _job_running and job == the_job:
			customer_is_back())
	dialogue.say(job.customer_name, "Short on cash, huh? Fine. I'll run to the hardware store for a %s. Back in half an hour." %
			PartSpec.of(part).name.to_lower(), [["Thanks. I'll make a start.", _ui_close]])


## Back from the store: the part's on the counter, and they text you to say so.
func customer_is_back() -> void:
	job.customer_back = true
	send_text(job.customer_name, "I'm back with the %s. It's on the kitchen counter. Come and get it." % PartSpec.of(job.customer_bought).name.to_lower())
	hud.show_toast("%s is back from the store with your part." % job.customer_name, 4.0)


func _grab_customer_part() -> void:
	var n := _inside.electrical.wafer_ids().size() if job.family == "recessed" else 1
	if inventory.bag.size() + n > inventory.bag_slots:
		_menu("Your bag's full. Put something back in the %s first." % van.spec()["word"])
		return
	for i in n:
		inventory.hold(job.customers_part())
	job.got_customer_part = true
	if job.family == "recessed":
		_menu("All %d of them. There's a spare box of screws in there too, I don't know what for." % n)
		return
	_menu("Here it is. Instructions are in the box, not that you'll need them.")


func _go_to_work() -> void:
	# They go in and get out of your way: the couch, the kitchen, back again.
	_inside.open_front_door()
	_customer.hangouts = _inside.hangouts
	var path: Array[Vector3] = [_inside.spots["outside"], _inside.spots["inside"]]
	_customer.go_inside(path)
	_panel.active = true
	_rear.active = true
	_ui_close()


# --- Is it fixed? ---------------------------------------------------------------------

## On a callback: is what they called about put right?
func _callback_fixed() -> bool:
	match job.callback.get("why", ""):
		"trip", "panel":
			return _sim.circuit_at(job.target).healthy()
		"box":
			return _box.device.repair_state() == "ok" and not (_box.device.family == "120" and _box.room == "bathroom" and _box.device.kind != "GFCI")
		"inspection":
			return _violations_now().is_empty() and _defects().is_empty()
	return true


func _violations_now() -> Array:
	var out := []
	for b in _sim.circuits:
		if b.breaker.rating > b.wire_rating or (b.breaker.rating < b.wire_rating and b.name in ["Kitchen counter", "Bathroom", "Microwave"]):
			out.append(b.name)
	return out


## What's wrong with your work in this house, for the days after you leave.
func _defects() -> Array:
	var out := []
	for i in _inside.boxes.size():
		var b: BoxView = _inside.boxes[i]
		if not b.work.worked_on and b != _box:
			continue
		var state := b.device.repair_state()
		var word: String = DeviceSpec.of(b.device.kind).word if b.device.kind != "" else "box"
		if state == "empty":
			state = "dead"
		if state in ["open", "dead", "miswired", "burnt_wire"]:
			out.append({"problem": state, "room": b.room, "word": word, "box": i})
		elif b.device.family == "120" and b.room == "bathroom" and b.device.kind == "Receptacle":
			out.append({"problem": "no_gfci", "room": b.room, "word": word, "box": i})
	if not _inside.electrical.bare_runs().is_empty():
		out.append({"problem": "no_guard_strip", "room": "master bedroom", "word": "cable", "box": 0})
	return out


## "ok", "miswired", "wrong_device", "open", "not_fixed", "main_off" or "other_off".
func _device_state() -> String:
	if not _sim.bus_live():
		return "main_off"
	for b in _sim.circuits:
		if not b.breaker.present or not b.wire_landed or not b.breaker.on or b.breaker.tripped:
			return "other_off" if b.slot != job.target else "not_fixed"
	if (job.kind == "dimmer" and _box.device.kind != "Dimmer") or (job.kind == "fan" and _box.device.kind != "Fan"):
		return "not_fixed"
	for b: BoxView in [_box, _pair]:
		if b == null:
			continue
		var state: String = b.device.repair_state()
		if state == "dead" or state == "empty":
			return "not_fixed"
		if state != "ok":
			return state
	if _box.device.family == "120" and _box.room == "bathroom" and _box.device.kind != "GFCI":
		return "wrong_device"
	if not job.objectives.is_empty() and not job.outcomes_complete():
		return "not_fixed"
	return "ok"


# --- Going back to them ----------------------------------------------------------------

func _callback_visit() -> void:
	if _callback_fixed():
		dialogue.say(job.customer_name, "That's it working properly? Thank you for coming back.", [
			["Sorry for the trouble. No charge, it's on me.", _settle_callback.bind(true)]])
	else:
		dialogue.say(job.customer_name, "It's still not right, is it?", [["I'm on it.", _ui_close],
			["I can't sort it today. Sorry.", _settle_callback.bind(false)]])


func _settle_callback(fixed: bool) -> void:
	job.callback_done = fixed
	job.stars_given = 5 if fixed else 1
	_finish()


func _return_visit() -> void:
	if job.kind == "callback":
		_callback_visit()
		return
	if job.family == "device":
		_device_visit()
		return
	if job.family == "heater":
		_heater_visit()
		return
	if job.family == "install":
		_install_visit()
		return
	if job.family == "recessed":
		_recessed_visit()
		return
	var state := _sim.check_repair(job.target)
	var buttoned_up := _panel.cover_on and not _panel.door_open
	if state == "main_off":
		_reply("The whole house just went dark! Is that you?")
	elif state == "other_off":
		_other_off("That part's better, but now something else in the house has gone off.")
	elif state == "not_fixed":
		_menu("Any luck yet? It's still not right in here.")
	# An undersized breaker works fine today. Whether it holds up is for the days ahead.
	elif not buttoned_up:
		_reply("It's working! Are you going to leave the panel open like that, though?")
	else:
		_invoice(state)


func _device_visit() -> void:
	match _device_state():
		"main_off":
			_reply("The whole house just went dark! Is that you?")
		"other_off":
			_other_off("Now something else in the house has gone off.")
		"not_fixed":
			_menu(_still_wrong())
		"open":
			_reply("Is that %s going to be left hanging like that?" % _what_it_is())
		var state:
			_invoice(state)


## What the customer calls the thing you're working on.
func _what_it_is() -> String:
	match _box.device.family:
		"smoke":
			return "smoke detector"
		"switch", "ceiling":
			return "light"
		"jbox":
			return "wiring"
	return "outlet"


## What they tell you when it's still not right, in their words: what they
## can see or hear, not what's wrong.
func _still_wrong() -> String:
	var d := _box.device
	var breaker := _sim.circuit_at(job.target)
	var power_off := breaker != null and not breaker.breaker.closed()
	match d.family:
		"smoke":
			if d.kind == "" or not d.plugged:
				return "There's just a hole in the ceiling where the detector was. Is the new one coming?"
			if d.chirping():
				return "It's still chirping. I just heard it again."
			if power_off:
				return "The chirping's stopped, but the little green lights on the detectors are all off. Is the power still off to them?"
			return "Any luck? Is it sorted?"
		"switch", "ceiling":
			var wrong := _put_up_in_the_wrong_room()
			if wrong != "":
				return wrong
			if power_off:
				return "The lights in there are all off now, and the outlets too. Did you switch something off at the panel?"
			if d.kind == "Fan" or (_pair != null and _pair.device.kind == "Fan"):
				return "The fan's up, but nothing happens when I flip the switch. No light, no spin."
			return "Any luck? That light still won't come on."
		"jbox":
			return "Any luck? Those outlets and lights are still dead."
	return "Any luck? That outlet's still dead."


## On a fan or dimmer job: the new one went in some other room's box. "" if not.
func _put_up_in_the_wrong_room() -> String:
	var wanted: String = {"fan": "Fan", "dimmer": "Dimmer"}.get(job.kind, "")
	if wanted == "" or _box.device.kind == wanted or (_pair != null and _pair.device.kind == wanted):
		return ""
	for b in _inside.boxes:
		if b != _box and b != _pair and b.device.kind == wanted and b.work.worked_on:
			return "You've put it up in the %s! I wanted it in the %s." % [b.room, _box.room] if b.room != _box.room \
					else "That's the other light. I meant the one in here."
	return ""


func _heater_visit() -> void:
	var h := _inside.heater
	var others_off := _sim.circuits.any(func(c: Circuit) -> bool:
			return c.slot != job.target and (not c.breaker.present or not c.wire_landed or not c.breaker.closed()))
	if not _sim.bus_live():
		_reply("The whole house just went dark! Is that you?")
	elif others_off:
		_other_off("Now something else in the house has gone off.")
	elif h.level < 1.0 or not h.cold_open:
		_menu("I tried the hot tap and nothing came out at all. Not even cold. Is that right?")
	elif not h.fixed():
		_menu("Any luck? Still no hot water.")
	elif not h.buttoned_up():
		_reply("Are you going to leave the covers off like that? The kids go in there.")
	else:
		_invoice("ok")


func _install_visit() -> void:
	var parts := _install_parts()
	var new_box: BoxView = parts[1]
	if not _sim.bus_live():
		_reply("The whole house just went dark! Is that you?")
	elif _sim.circuits.any(func(c: Circuit) -> bool: return not c.breaker.present or not c.wire_landed or not c.breaker.closed()):
		_other_off("Some of the house has gone off. Is that you?")
	elif new_box == null:
		_menu("Have you found my mark? It's still just a pencil line on the wall.")
	elif not job.outcomes_complete():
		var source: BoxView = parts[2]
		if source != null and source.device.repair_state() == "dead":
			_menu("The outlet next to it's gone dead now as well. Is that part of it?")
		else:
			_menu("I tried a lamp in the new one. Nothing yet.")
	else:
		_invoice("ok")


func _recessed_visit() -> void:
	var e := _inside.electrical
	var ids := e.wafer_ids()
	var target := _sim.circuit_at(job.target)
	var lit := ids.filter(func(id: String) -> bool: return e.device(id).lamp_volts() > 100.0).size()
	if not _sim.bus_live():
		_reply("The whole house just went dark! Is that you?")
	elif _sim.circuits.any(func(c: Circuit) -> bool: return c.slot != job.target and (not c.breaker.present or not c.wire_landed or not c.breaker.closed())):
		_other_off("Some of the house has gone off. Is that you?")
	elif not e.laid_out():
		_menu("Have you worked out where they're going yet?")
	elif ids.any(func(id: String) -> bool: return e.device(id).kind != "" and not e.device(id).plate_on):
		_reply("There's a light hanging down out of my ceiling on its wires. Is that staying like that?")
	elif _box != null and _box.device.kind != "Fixture" and not _box.device.plate_on:
		_reply("There's wires hanging out of the ceiling where the old light was.")
	elif not target.breaker.closed():
		_menu("The bedroom's all dark, the plugs too. Is the breaker still off?")
	elif _box != null and _box.device.kind == "Fixture":
		_menu("The old light's still up. I wanted that gone.")
	elif job.outcomes_complete():
		_invoice("ok")
	elif lit == 0:
		_menu("I flipped the switch and none of them come on. Is the switch on?" if _inside.recessed != null and _inside.recessed.switch_box != null and not _inside.recessed.switch_box.device.switch_on
				else "I flipped the switch and none of them come on.")
	else:
		_menu("%d of the %d come on. The rest stay dark." % [lit, ids.size()])


func _reply(line: String) -> void:
	dialogue.say(job.customer_name, line, [["I'm on it.", _ui_close]])


# --- Getting paid ------------------------------------------------------------------------

func _invoice(state: String) -> void:
	var bill := tuning.call_out + tuning.labour + job.parts_cost(tuning)
	var fitted := job.final_device
	var honest := "The breaker failed. I put in a new one. That's $%d." % bill
	if job.kind == "overload" and job.final_part == 0:
		honest = "Nothing's broken. The heater and the %s together were too much for one circuit. That's $%d." % [job.circuit.appliance, bill]
	if job.family == "install":
		var source_room: String = _inside.electrical.rooms.get(_inside.electrical.installs[job.equipment_ids[0]]["source"], "room")
		honest = "Your new outlet's in, fed off the one already in the %s. That's $%d." % [source_room, bill]
	if job.family == "recessed":
		honest = "Your %d wafers are in on the old light's switch, and its box is spliced through under a blank. That's $%d." % [_inside.electrical.wafer_ids().size(), bill]
	if job.family == "heater":
		honest = {"wh_upper": "The top element in your water heater burnt out. I put a new one in. Give it an hour or two to heat up. That's $%d.",
			"wh_lower": "The bottom element in your water heater burnt out, so only the top was heating. New one's in. That's $%d.",
			"wh_eco": "The high-limit on your water heater had tripped. I reset it and checked both elements. That's $%d."}[job.kind] % bill
	if job.family == "device":
		var family := _box.device.family
		var part: String = PART_WORDS.get(fitted, "outlet")
		if family == "jbox":
			honest = "A bad splice in a junction box up in the attic. I cut it back and re-made it. That's $%d." % bill
		elif family == "smoke":
			honest = ("That detector was past its ten years. I put a new one in. That's $%d." if fitted == "Smoke"
					else "A dead backup battery in the %s detector. Fresh one's in. That's $%%d." % _box.room) % bill
		elif fitted == "Fan":
			honest = "Your fan's up and spinning. That's $%d." % bill
		elif fitted == "Dimmer":
			honest = "Your dimmer's in and working. That's $%d." % bill
		elif fitted != "":
			honest = "The %s burnt out. I put in a new one. That's $%d." % [part, bill]
		elif family == "240":
			honest = "A loose lug on the stove outlet. I tightened it up. That's $%d." % bill
		elif family == "switch":
			honest = "A loose wire on the light switch. I tightened it up. That's $%d." % bill
		elif family == "ceiling":
			honest = "A loose wire nut up in the light. I twisted it back on tight. That's $%d." % bill
		else:
			honest = "A loose connection behind the outlet. I put it on the screws. That's $%d." % bill
	dialogue.say(job.customer_name, "Oh, that's got it! It works. So what was it, and what do I owe you?", [
		[honest, _pay.bind(state, true)],
		["Your whole panel's shot. A new one is $%d." % tuning.scam_quote, _pay.bind(state, false)],
	])


## How the work went, from what the panel's and the boxes' logs saw.
func _work() -> Billing.Work:
	var w := Billing.Work.new()
	if job.family == "panel":
		w.dead_tested = _panel.work.verified_dead
		w.thorough = _panel.work.measured_target and _panel.work.measured_amps
	elif job.family == "install":
		var parts := _install_parts()
		var new_box: BoxView = parts[1]
		var source: BoxView = parts[2]
		w.dead_tested = source != null and source.work.verified_dead
		w.thorough = new_box != null and new_box.work.tested_after and source != null and source.work.measured_live
	elif job.family == "recessed":
		var views: Array = _inside.electrical.wafer_ids().map(func(id: String) -> BoxView: return _inside.view_for_device(_inside.electrical.device(id)))
		w.dead_tested = _box != null and _box.work.verified_dead
		w.thorough = views.all(func(v: BoxView) -> bool: return v != null and v.work.tested_after) and _box != null and _box.work.measured_live
		if _inside.recessed != null:
			w.flaws.append_array(_inside.recessed.flaws())
		if not _inside.electrical.bare_runs().is_empty():
			w.flaws.append("You left cable lying across the attic joists. My husband goes up there for the Christmas boxes.")
	elif job.family == "heater":
		var v := _inside.heater_view
		w.dead_tested = v.work.verified_dead
		w.thorough = v.work.measured_live and v.work.tested_after and v.ohmed.size() == 2
	else:
		w.dead_tested = _box.work.verified_dead
		w.thorough = _box.work.measured_live and _box.work.tested_after
	w.shocks = _panel.work.shocks + _inside.total_shocks()
	w.arcs = _panel.work.arcs + _inside.total_arcs()
	return w


func _pay(_state: String, honest: bool) -> void:
	var sheet := Billing.settle(job, _work(), honest, tuning, aftercare.pay_factor())
	job.stars_given = sheet.stars
	wallet.earn(sheet.total)
	stats.record(sheet.total, _minutes)
	dialogue.say("JOB SHEET", "\n".join(sheet.lines), [["On to the next one.", _finish]])


func _finish() -> void:
	if job.status == ActiveJob.Status.IN_PROGRESS:
		job.transition_to(ActiveJob.Status.COMPLETED)
	_wrap_up()


## You flooded the laundry: an element out under water, or the drain open with
## no hose on it. Water damage on you, and they show you the door and call
## somebody else.
func _flooded() -> void:
	if not _job_running:
		return
	wallet.pay(tuning.flood_cost)
	_review_note = "Flooded my laundry room. Water under the washer, the floor's ruined. I had to call another company to finish."
	var view := _inside.heater_view
	if view._open:
		view.close()
	if _box != null and _box._open:
		_box.close()
	_ui_open()
	dialogue.say(job.customer_name,
			"WHAT DID YOU DO?! There's water all over my laundry room! Get out of my house. I'm calling another company.\n\nWater damage: -$%d" % tuning.flood_cost,
			[["I'm sorry. I'll go.", abandon_job.bind("flooded the laundry")]])


## Walking out on a job you haven't finished (you went to bed, or passed
## out): no pay, and they leave you one star.
func abandon_job(why: String) -> void:
	if not _job_running:
		return
	job.stars_given = 1
	job.issue = "%s (%s)" % [job.issue, why]
	job.transition_to(ActiveJob.Status.CANCELLED)
	_wrap_up()


func _wrap_up() -> void:
	call_repository.update(job)
	aftercare.job_finished(job.address, job.customer_name, _sim, _inside.snapshot(), job.stars_given, job.callback, job.callback_done,
			_defects(), job.issue, int(_minutes / 1440) + 1, _review_note)
	_review_note = ""
	_ui_close()
	_job_running = false
	_jobs_done += 1
	_customer.queue_free()
	_panel.queue_free()
	inventory.drop()
	_beacon.queue_free()
	_rear.active = false
	# The house goes back to how it looks from the street once you've walked
	# out of it: closing it up round you would leave you inside a solid box
	# with walls you can't see from in there.
	_leaving = _inside
	if not _inside.contains(player.global_position):
		_left_the_house()
	checkpoint.emit()


## You're out of the last house: put it back as the street sees it, and the
## phone can ring again.
func _left_the_house() -> void:
	if _leaving == null:
		return
	_leaving.close_up()
	_leaving = null
	(_house["static_panel"] as Node3D).visible = true
	get_tree().create_timer(tuning.next_job_delay * aftercare.wait_factor(), false).timeout.connect(start_job)


# --- Nights ---------------------------------------------------------------------------

func _tire(minutes: float) -> void:
	player.pace = fatigue.speed_factor()
	match fatigue.tick(minutes):
		"tired":
			hud.show_message("You're getting tired. Head home to bed when you can.", 4.0)
		"exhausted":
			hud.show_message("You're exhausted, and slowing down. Get to bed before you drop.", 5.0)
		"out":
			pass_out()


## Into bed, if it's time: the night goes by and you're up at the usual time,
## rested. A job you've left half done is lost.
func go_to_sleep() -> void:
	if not fatigue.can_sleep(_minutes):
		hud.show_message("You're not tired yet. Bedtime's after %s." % _hour_words(sleep_tuning.bedtime_hour), 3.0)
		return
	abandon_job("you went home to bed")
	_wake_at(sleep_tuning.wake_hour, "Morning. %s, and you feel rested.")


## Out cold where you stand. You come round at home, late, and whatever job
## you were on is gone.
func pass_out() -> void:
	abandon_job("you passed out")
	_wake_at(sleep_tuning.passed_out_wake_hour, "You passed out. You came round at home: it's %s and your head's pounding.")


func _wake_at(hour: float, line: String) -> void:
	if player.driving != null:
		player.driving.get_out()
	_ui_close()
	_minutes = Fatigue.next_time(_minutes, hour)
	fatigue.rest()
	player.pace = 1.0
	scheduler.expire(_minutes)
	player.global_position = town.home_house.to_global(town.home_house.wake_spot)
	hud.fade_from_black(1.5)
	hud.show_message(line % _clock_at(_minutes), 5.0)
	checkpoint.emit()            # a night's sleep is a save point


static func _hour_words(hour: float) -> String:
	var h := int(hour)
	return "%d:%02d %s" % [12 if h % 12 == 0 else h % 12, int((hour - h) * 60.0), "AM" if h < 12 else "PM"]


func minutes() -> float:
	return _minutes


# --- The van ----------------------------------------------------------------------

func _open_van(_p: Node3D) -> void:
	_ui_open()
	truck_screen.open(inventory, van, capacity())


func capacity() -> int:
	return van.spec()["capacity"] + upgrades.total("truck_space")


# --- The supply house and the shop ------------------------------------------------

func _add_counter(at: Vector3, text: String, use: Callable) -> void:
	var counter := Interactable.new()
	counter.prompt = text
	counter.reach = 2.5
	counter.aim = Vector3(0, 1.2, 0)
	counter.aim_radius = 0.9
	counter.on_use = use
	add_child(counter)
	counter.global_position = at


func _open_office(_p: Node3D) -> void:
	_ui_open()
	var home := town.home_house
	computer_screen.open(self, player.camera, home.seat_view(), town, home.screen_transform(), HomeHouse.SCREEN_SIZE)


## What something costs on TradesmanGear.com. The van's price is a JobTuning knob.
func shop_price(item: ShopItem) -> int:
	return tuning.van_price if item.effect == "vehicle" else item.price


## Pays for the cart and orders it for tomorrow morning. "" if it went
## through, otherwise why not (shown on the site).
func buy_online(ids: Array[String]) -> String:
	var buying: Array[String] = []
	var total := 0
	for id in ids:
		var item := ShopItem.of(id)
		if upgrades.can_buy(item) and not id in buying:
			buying.append(id)
			total += shop_price(item)
	if buying.is_empty():
		return "There's nothing in your cart to order."
	if not wallet.can_afford(total):
		return "That comes to $%d, and you've got $%d. A few more jobs first." % [total, wallet.money]
	wallet.pay(total)
	upgrades.order(buying, _minutes)
	var names := buying.map(func(id: String) -> String: return "  %s  $%d" % [ShopItem.of(id).name, shop_price(ShopItem.of(id))])
	_send_mail("TradesmanGear.com", "Order confirmed: $%d" % total,
			"Thanks for your order! It ships free and will be at your door tomorrow by %d AM.\n\n%s" % [int(Upgrades.DELIVERY_HOUR), "\n".join(names)])
	return ""


## Whatever's turned up from TradesmanGear: yours now, and doing its job.
func _take_deliveries() -> void:
	var here := upgrades.deliveries(_minutes)
	if here.is_empty():
		return
	var names := here.map(func(id: String) -> String: return ShopItem.of(id).name)
	_apply_upgrades()
	_send_mail("TradesmanGear.com", "Delivered: your order is here",
			"Your order was left at your front door:\n\n  %s\n\nIt's ready to use." % "\n  ".join(names))
	hud.show_message("Your TradesmanGear order came: %s." % ", ".join(names), 5.0)
	send_text("TradesmanGear", "Delivered: %s. It's at your front door." % ", ".join(names))


## Makes what you own count: a bigger bag, room on the truck, the headlamp,
## gloves, the light bar, the van.
func _apply_upgrades() -> void:
	inventory.bag_slots = Inventory.BAG_SLOTS + upgrades.total("bag_slots")
	inventory.insulated_gloves = upgrades.has_effect("insulated_gloves")
	player.has_headlamp = upgrades.has_effect("headlamp")
	for id in upgrades.owned:
		var item := ShopItem.of(id)
		if item.effect == "vehicle" and item.vehicle != "" and van.model_name != item.vehicle:
			_set_vehicle(item.vehicle)
	van.light_bar = upgrades.has_effect("light_bar")
	supply.truck_space = upgrades.total("truck_space")


## A text to your phone. It sits unread (a badge on the HUD) till you open Messages.
func send_text(from: String, text: String) -> void:
	texts.append({"at": _minutes, "from": from, "text": text, "read": false})


## The same text again only if the last one wasn't it: no spamming the phone.
func _text_once(from: String, text: String) -> void:
	if texts.is_empty() or texts[-1]["text"] != text:
		send_text(from, text)


func unread_texts() -> int:
	return texts.filter(func(t: Dictionary) -> bool: return not t["read"]).size()


func read_texts() -> void:
	for t in texts:
		t["read"] = true


## Messages, newest first: [from, when, text, unread].
func phone_texts() -> Array:
	var out: Array = []
	for i in range(texts.size() - 1, -1, -1):
		var t := texts[i]
		out.append([t["from"], _day_and_time(t["at"]), t["text"], not t["read"]])
	return out


## The Jobs app: the one you're on, then what's on the board, soonest first.
## Each is {who, address, what, when, urgent}.
func phone_jobs() -> Dictionary:
	var current := {}
	if _job_running:
		current = {"who": job.customer_name, "address": job.address, "what": job.issue,
				"when": "Talked to them" if job.met else ("Booked %s" % _hour_minute(job.window_start) if job.window_start > _minutes else "Waiting for you"),
				"urgent": job.urgency == "emergency"}
	var board: Array = []
	var upcoming := scheduler.board.duplicate()
	upcoming.sort_custom(func(a: ActiveJob, b: ActiveJob) -> bool: return a.window_start < b.window_start)
	for j: ActiveJob in upcoming:
		board.append({"who": _who(j), "address": j.address, "what": j.complaint,
				"when": "%s  (%s)" % [_hour_minute(j.window_start), _until(j.window_start)], "urgent": j.urgency == "emergency"})
	return {"current": current, "board": board}


## Who a booked call is for. People get their names when you go, so a house
## you've worked before has the same people in it; anyone else is new.
func _who(j: ActiveJob) -> String:
	if j.customer_name != "":
		return j.customer_name
	if aftercare.houses.has(j.address):
		return String(aftercare.houses[j.address]["name"])
	return "New customer"


## The Wallet app: what's in the bank and how you're doing.
func phone_wallet() -> Dictionary:
	return {"money": wallet.money, "rating": aftercare.rating_text(), "reviews": aftercare.reviews.size(), "jobs": _jobs_done}


func _send_mail(from: String, subject: String, text: String) -> void:
	mail.append({"at": _minutes, "from": from, "subject": subject, "text": text})


## The inbox, newest first: [from and when, subject, text]. Your orders and
## deliveries, then what customers have said about you.
func inbox() -> Array:
	var out: Array = []
	for i in range(mail.size() - 1, -1, -1):
		var m := mail[i]
		out.append(["%s  •  %s" % [m["from"], _day_and_time(m["at"])], m["subject"], m["text"]])
	for i in range(aftercare.reviews.size() - 1, -1, -1):
		var r: Dictionary = aftercare.reviews[i]
		out.append(["Customer review  •  %s, %s" % [r["name"], r["address"]], "%s  %d star%s" % ["*".repeat(int(r["stars"])), int(r["stars"]), "" if int(r["stars"]) == 1 else "s"], r["text"]])
	return out


## For the desktop's clock: "Tue  9:24 AM".
func date_and_time() -> String:
	return _day_and_time(_minutes)


static func _day_and_time(minutes: float) -> String:
	var total := int(minutes)
	var hour := (total / 60) % 24
	return "%s  %d:%02d %s" % [DAYS[ServiceCallScheduler.weekday(minutes)], 12 if hour % 12 == 0 else hour % 12, total % 60, "AM" if hour < 12 else "PM"]


## Swaps what you drive, and moves the tailgate you get parts from to match.
func _set_vehicle(model: String) -> void:
	van.become(model)
	_rear.position = Vector3(0, 0, van.spec()["rear_door"])
	_rear.prompt = "[E] Get parts from the %s" % van.spec()["word"]


# --- Screen handling --------------------------------------------------------------

func _ui_open() -> void:
	player.target = dialogue
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _ui_close() -> void:
	dialogue.close()
	player.target = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
