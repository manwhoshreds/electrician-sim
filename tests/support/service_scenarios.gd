extends RefCounted
## A seeded run of the real game's job loop, recorded: what dispatch sends you
## to, the HUD card, the whole conversation, the invoice, the job sheet under
## different ways of having done the work, the customer's reply on a return
## visit, and the truck and supply house. Time is frozen so nothing fires on
## its own; every step is called directly, in the same order every run.
##
## Only the ADAPTER section knows where ServiceCall keeps its state, so a
## refactor changes those few functions and nothing else.

const GOLDEN := "res://tests/golden/service_scenarios.json"
const SEED := 13
const JOBS := 60


## Stands in for the dialogue box: remembers what was said instead of drawing it.
class RecordingDialogue:
	extends DialogueBox
	var said: Array = []
	var actions: Array = []

	func _ready() -> void:
		pass

	func say(speaker: String, text: String, options: Array) -> void:
		said.append([speaker, text, options.map(func(o: Array) -> String: return o[0])])
		actions = options.map(func(o: Array) -> Callable: return o[1])
		visible = true

	func close() -> void:
		visible = false

	func last() -> Array:
		return said[-1] if not said.is_empty() else []


var tree: SceneTree
var main: Node
var service: ServiceCall
var talk: RecordingDialogue


func _init(tree_: SceneTree) -> void:
	tree = tree_


# --- ADAPTER: where ServiceCall keeps things ------------------------------------------

func money() -> int:
	return service.wallet.money


func set_money(n: int) -> void:
	service.wallet.money = n


func stock() -> Dictionary:
	return service.inventory.stock.duplicate()


## What you're carrying, as [breaker rating, part]: the bag, the way these
## scenarios were written for one thing in your hands.
func hands() -> Array:
	var inv := service.inventory
	var breakers := inv.bag_breakers()
	var parts := inv.bag.filter(func(p: String) -> bool: return PartSpec.of(p).breaker_rating == 0)
	return [breakers[0] if not breakers.is_empty() else 0, parts[0] if not parts.is_empty() else ""]


func family() -> String:
	return service.job.family


func kind() -> String:
	return service.job.kind


func stars_given() -> int:
	return service.job.stars_given


func load_used() -> int:
	return service.inventory.load_used()


## The job as dispatched.
func job_info() -> Dictionary:
	var box: BoxView = service._box
	var j := service.job
	return {"job": j.family, "kind": j.kind, "target": j.target, "address": j.address,
			"name": j.customer_name, "number": j.number, "callback": j.callback.duplicate(),
			"box": [box.room, box.device.kind, box.device.slot, box.device.condition] if box != null else null,
			"pair": [service._pair.room, service._pair.device.kind] if service._pair != null else null}


## Pretend the work went a particular way: tested dead or not, measured, shocks and arcs.
func set_work(dead_tested: bool, thorough: bool, shocks: int, arcs: int) -> void:
	var p := service._panel.work
	p.verified_dead = dead_tested
	p.measured_target = thorough
	p.measured_amps = thorough
	p.shocks = shocks
	p.arcs = arcs
	if service._box != null:
		var b := service._box.work
		b.verified_dead = dead_tested
		b.measured_live = thorough
		b.tested_after = thorough


## Weak and overload jobs: as if you'd already watched the clamp while they ran it.
func set_load_tested() -> void:
	service.job.load_tested = true


## What each of the customer questions says on its button.
func question(key: String) -> String:
	return service.ASK[key]


## The tuning scripts' defaults, not the game's .tres files: tweaking the
## game's knobs mustn't change the recording.
func use_default_tuning() -> void:
	service.tuning = JobTuning.new()
	service._generator.tuning = service.tuning
	service.wallet.money = service.tuning.starting_money
	service.aftercare.tuning = AftercareTuning.new()
	service.supply.tuning = service.tuning


func take_part(part: String) -> void:
	service.inventory.take(part)


func return_part(part: String) -> void:
	service.inventory.put_back(part)


# --- The run ---------------------------------------------------------------------------

## Opens the truck screen and reads what it shows, then shuts the doors.
func _truck() -> Dictionary:
	service._open_van(null)
	var screen := service.truck_screen
	var shelf: Array = screen.shown().map(func(p: PartSpec) -> Array: return [p.short_name(), service.inventory.count(p.id), service.inventory.in_bag(p.id)])
	var seen := {"money": money(), "stock": stock(), "hands": hands(), "title": screen._title.text, "load": screen._load_text.text,
		"bag": screen._bag_title.text, "shelf": shelf}
	screen.close()
	return seen


func _snap() -> Dictionary:
	return {"money": money(), "stock": stock(), "hands": hands(), "said": talk.last()}


func start() -> void:
	SaveGame.enabled = false            # never touch a real save
	seed(SEED)
	Engine.time_scale = 0.0
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	tree.root.add_child(main)
	for c in main.get_children():
		if c is ServiceCall:
			service = c
	use_default_tuning()
	talk = RecordingDialogue.new()
	service.remove_child(service.dialogue)
	service.dialogue.free()
	service.dialogue = talk
	service.add_child(talk)
	service.supply.dialogue = talk


func stop() -> void:
	talk.actions.clear()
	talk.said.clear()
	main.free()
	main = null
	service = null
	talk = null
	Engine.time_scale = 1.0


## Clicks the option on screen whose words start with `prefix`, like a player
## would. False if there's no such option.
func choose(prefix: String) -> bool:
	var labels: Array = talk.last()[2] if not talk.said.is_empty() else []
	for i in labels.size():
		if (labels[i] as String).begins_with(prefix):
			(talk.actions[i] as Callable).call()
			return true
	return false


func play_job(i: int) -> Dictionary:
	var rec := {}
	service.start_job()
	rec["dispatch"] = job_info()
	rec["card_before"] = service._card()
	if family() == "panel" and kind() in ["weak", "overload"]:
		set_load_tested()
	service._on_customer(null)
	rec["greeting"] = talk.last()
	var answers := []
	for key in ["when", "touched", "new", "where"]:
		if choose(question(key)):
			answers.append(talk.last())
	for prefix in ["Could you run", "That circuit's overloaded", "I'll grab that"]:
		if choose(prefix):
			answers.append([talk.last(), hands()])
	rec["answers"] = answers
	choose("Let me")
	rec["return_visit"] = _visit()
	rec["card_after"] = service._card()
	var state := "ok" if i % 3 != 2 else "oversize"
	service._invoice(state)
	rec["invoice"] = talk.last()
	var sheets := []
	for work: Array in [[false, false, 0, 0], [true, true, 0, 0], [true, false, 1, 0], [false, true, 2, 1]]:
		set_work(work[0], work[1], work[2], work[3])
		service._pay(state, true)
		sheets.append([talk.last(), money(), stars_given()])
	service._pay(state, false)
	sheets.append([talk.last(), money(), stars_given()])
	rec["sheets"] = sheets
	rec["defects"] = service._defects()
	rec["violations"] = service._violations_now()
	service._finish()
	rec["after"] = {"money": money(), "rating": service.aftercare.rating_text(), "callbacks": service.aftercare._events.size()}
	# Unfixed jobs breed callbacks: let only some through, for a mix.
	if i % 4 != 3:
		service.aftercare._events.clear()
	return rec


func _visit() -> Array:
	service._return_visit()
	return talk.last()


func play_shop() -> Array:
	var out := []
	set_money(4000)
	out.append(_truck())
	for part: String in stock():
		if stock()[part] > 0:
			take_part(part)
			out.append(_snap())
			out.append(_truck())
			return_part(part)
			out.append(_snap())
	service.supply.open(null)
	out.append(_snap())
	service.supply._buy("GFCI")
	out.append(_snap())
	service.van.global_position = service.town.supply_door
	for part in ["GFCI", "Fan", "Fan", "breaker30", "Smoke", "Range"]:
		service.supply._buy(part)
		out.append(_snap())
	service.supply._open_returns()
	out.append(_snap())
	for part: String in stock():         # only what the returns menu offers: what's on board
		if stock()[part] > 0:
			service.supply._return(part)
			out.append(_snap())
	set_money(10)
	service.supply._buy("Fan")
	out.append(_snap())
	# The van comes from TradesmanGear.com on the computer at home, delivered next morning.
	var van: Array[String] = ["work_van"]
	out.append({"van_order": service.buy_online(van), "money": service.wallet.money})
	set_money(3000)
	out.append({"van_order": service.buy_online(van), "money": service.wallet.money})
	service._minutes = Fatigue.next_time(service._minutes, Upgrades.DELIVERY_HOUR) + 1.0
	service._take_deliveries()
	out.append({"capacity": service.capacity(), "used": load_used(), "vehicle": service.van.model_name})
	return out


## The whole run, as JSON strings by name.
func capture() -> Dictionary:
	start()
	var out := {}
	for i in JOBS:
		out["job_%02d" % i] = JSON.stringify(play_job(i))
	out["shop"] = JSON.stringify(play_shop())
	stop()
	return out
