class_name Aftercare
extends Node
## What happens after you drive away. Every house keeps its electrics the way
## you left them, and the next few days of the customer's life get played out
## against your work: their toast-and-kettle mornings, hair dryers, space
## heaters. If a breaker you put in can't take it, it trips and they call you
## back, for free. A burnt wire you left on fails again. A reversed outlet
## gives somebody a tingle. An inspector comes round now and then and fines
## code violations. And an oversized breaker on small wire can let that wire
## cook inside the wall.
##
## Every job gets a star review, and callbacks edit it. Your average rating
## sets how much people pay and how fast the phone rings.
##
## Time here is counted in jobs: something that happens "the next morning"
## lands after your next job.

## The knobs: callback, inspection and fire chances, fines. Edit the .tres in the inspector.
var tuning: AftercareTuning = preload("res://data/aftercare_tuning.tres")
var hud: Hud
## Texts to your phone: (from, text). Set by ServiceCall.
var on_text: Callable
## Where fines and liability come out of.
var wallet: Wallet

## address -> {"sim": ElectricalPanel, "state": interior snapshot, "name": customer}
var houses := {}
## address -> what the people there have learned to do: "one_thing_at_a_time".
var habits := {}
## {address, name, stars, text}
var reviews: Array[Dictionary] = []
var suspended_until := 0.0       # Time in seconds; no calls until then

var _events: Array[Dictionary] = []   # {due (jobs from now), kind, address, ...}


# --- Reputation ---------------------------------------------------------------------

func rating() -> float:
	if reviews.is_empty():
		return 5.0
	return reviews.reduce(func(sum: float, r: Dictionary) -> float: return sum + r["stars"], 0.0) / reviews.size()


## Reviews standing at five stars right now (a callback can knock one down).
func five_star_reviews() -> int:
	return reviews.filter(func(r: Dictionary) -> bool: return r["stars"] == 5).size()


func rating_text() -> String:
	if reviews.is_empty():
		return "No reviews yet"
	return "%.1f (%d review%s)" % [rating(), reviews.size(), "" if reviews.size() == 1 else "s"]


## Five stars and people pay a premium; one star and they haggle.
func pay_factor() -> float:
	return 0.8 + rating() * 0.08


## Good reviews and the phone rings sooner.
func wait_factor() -> float:
	return 1.0 + (5.0 - rating()) * 0.6


func suspended() -> bool:
	return Time.get_ticks_msec() / 1000.0 < suspended_until


# --- The save file -------------------------------------------------------------------

## Every house you've worked on and how you left it, your reviews, what's
## still to come back on you, and any suspension (as seconds still to serve).
func to_save() -> Dictionary:
	var saved_houses := {}
	for address: String in houses:
		var h: Dictionary = houses[address]
		saved_houses[address] = {"panel": (h["sim"] as ElectricalPanel).to_save(), "state": h["state"], "name": h["name"]}
	return {"houses": saved_houses, "habits": habits.duplicate(true), "reviews": reviews.duplicate(true), "events": _events.duplicate(true),
			"suspended_seconds": maxf(suspended_until - Time.get_ticks_msec() / 1000.0, 0.0)}


func load_save(d: Dictionary) -> void:
	houses.clear()
	var saved_houses: Dictionary = d.get("houses", {})
	for address: String in saved_houses:
		var h: Dictionary = saved_houses[address]
		houses[address] = {"sim": ElectricalPanel.from_save(h.get("panel", {})), "state": h.get("state", {}), "name": String(h.get("name", ""))}
	habits = (d.get("habits", {}) as Dictionary).duplicate(true)
	reviews.clear()
	for r: Dictionary in d.get("reviews", []):
		r["stars"] = int(r["stars"])
		reviews.append(r)
	_events.clear()
	for e: Dictionary in d.get("events", []):
		for key in ["due", "target"]:   # numbers come back from the file as floats
			if e.has(key):
				e[key] = int(e[key])
		_events.append(e)
	suspended_until = Time.get_ticks_msec() / 1000.0 + float(d.get("suspended_seconds", 0.0))


# --- Remembering houses -------------------------------------------------------------

func has_habit(address: String, habit: String) -> bool:
	return habit in habits.get(address, [])


func add_habit(address: String, habit: String) -> void:
	if not has_habit(address, habit):
		if not habits.has(address):
			habits[address] = []
		habits[address].append(habit)


func sim_for(address: String) -> ElectricalPanel:
	return houses[address]["sim"] if houses.has(address) else null


func state_for(address: String) -> Dictionary:
	return houses[address]["state"] if houses.has(address) else {}


# --- The job's done ------------------------------------------------------------------

## A job's closed out: remember the house, post the review, then play out the
## next few days against what you left behind. `defects` is what's wrong with
## your work: [{problem, room, word, box}].
## `about` and `day` go on the review: what the call was, and the game day.
func job_finished(address: String, name: String, sim: ElectricalPanel, state: Dictionary, stars: int, callback: Dictionary,
		fixed_callback: bool, defects: Array, about := "", day := 0, review := "") -> void:
	houses[address] = {"sim": sim, "state": state, "name": name}
	for e in _events:
		e["due"] -= 1
	if callback.is_empty():
		reviews.append({"address": address, "name": name, "stars": clampi(stars, 1, 5), "text": review if review != "" else _review_text(stars),
				"about": about, "day": day})
		_say("NEW REVIEW  %s\n%s" % [_stars(stars), reviews[-1]["text"]], 5.0, name)
	else:
		_edit_review(address, 1 if fixed_callback else -1,
				"Update: they came back and made it right, no charge." if fixed_callback else "Update: came back and it's STILL not right.")
	_simulate(address, sim, defects)
	_deliver()


## The next callback that's come in, to be dispatched before any new work.
func next_callback() -> Dictionary:
	for e in _events:
		if e["kind"] == "callback" and e["due"] <= 0:
			_events.erase(e)
			return e
	return {}


# --- Playing out the days -------------------------------------------------------------

func _simulate(address: String, sim: ElectricalPanel, defects: Array) -> void:
	# Drop anything already waiting on this house: this visit replaces it.
	_events = _events.filter(func(e: Dictionary) -> bool: return e["address"] != address)
	var violations: Array[String] = []
	var called := false
	for b in sim.circuits:
		if b.breaker.rating > b.wire_rating:
			violations.append("%d A breaker on %d A wire (%s)" % [b.breaker.rating, b.wire_rating, b.name])
		elif b.breaker.rating < b.wire_rating and b.name in ["Kitchen counter", "Bathroom", "Microwave"]:
			violations.append("%d A breaker on a 20 A required circuit (%s)" % [b.breaker.rating, b.name])
	for d: Dictionary in defects:
		if d["problem"] == "no_guard_strip":
			violations.append("NM cable across the attic joist tops with no guard strip, over the %s" % d["room"])
		elif d["problem"] in ["miswired", "no_gfci", "burnt_wire"]:
			violations.append({"miswired": "Miswired %s in the %s", "no_gfci": "No GFCI protection on the %s in the %s",
					"burnt_wire": "Burnt conductor reused on the %s in the %s"}[d["problem"]] % [d["word"], d["room"]])

	for day in tuning.days_played:
		for b in sim.circuits:
			if not b.breaker.present:
				continue
			if not b.wire_landed or not b.breaker.on or b.breaker.tripped:
				if day == 0 and b.customer != "" and not called:
					_callback(address, 0, "panel", b.slot, "You left the %s without power. It's still off." % b.customer)
					called = true
				continue
			# Work left right doesn't trip: that's for the good-work roll below.
			# Your mistakes get the customer's real day thrown at them.
			if b.healthy():
				continue
			var peak := _daily_peak(b)
			var limit := b.breaker.trip_amps()
			if peak > limit:
				if not called:
					_callback(address, day, "trip", b.slot, _trip_story(b, day))
					called = true
				continue
			# Wire carrying more than it's made for, with a breaker too big to stop it.
			if b.breaker.rating > b.wire_rating and peak > b.wire_rating and AftercareTuning.roll(tuning.fire_percent):
				_events.append({"due": day, "kind": "fire", "address": address, "circuit": b.name})
				return
		for d: Dictionary in defects:
			if called:
				break
			if day == 0 and d["problem"] in ["open", "dead"] or day > 0 and AftercareTuning.roll(_defect_percent(d["problem"])):
				_callback(address, day, "box", d["box"], _defect_story(d))
				called = true
	if not called and AftercareTuning.roll(tuning.good_work_callback_percent):
		_nuisance_trip(address, sim)
	if not violations.is_empty() and AftercareTuning.roll(tuning.inspection_percent):
		_events.append({"due": randi_range(0, 1), "kind": "inspection", "address": address, "violations": violations})


## Each day, the chance a box you left with this problem gets noticed.
func _defect_percent(problem: String) -> float:
	match problem:
		"open":
			return 100.0
		"dead":
			return tuning.dead_box_callback_percent
		"burnt_wire":
			return tuning.burnt_wire_callback_percent
		"miswired":
			return tuning.miswired_callback_percent
		"no_gfci":
			return tuning.no_gfci_callback_percent
	return 0.0


## Nothing wrong, but a breaker went anyway (toast and the kettle at once) and
## they want you back to look. Picks one of the circuits they'd phone about.
func _nuisance_trip(address: String, sim: ElectricalPanel) -> void:
	var slots := sim.candidates()
	if slots.is_empty():
		return
	var day := randi_range(0, tuning.days_played - 1)
	var c := sim.circuit_at(slots.pick_random())
	_callback(address, day, "trip", c.slot, _trip_story(c, day))


## The biggest load the circuit sees in a day of the customer's life.
func _daily_peak(b: Circuit) -> float:
	var a: float = b.heater
	match b.name:
		"Kitchen counter":
			var r := randf()
			a += 9.2 + (12.5 if r < 0.3 else (8.0 if r < 0.7 else 0.0))   # toast with the kettle, or with the coffee
		"Microwave":
			a += 10.5
		"Bathroom":
			a += 12.5 + (1.2 if randf() < 0.5 else 0.0)
		"Living room":
			a += 1.9 + (6.0 if randf() < 0.3 else 0.0)
		"Bedrooms":
			a += 1.0 + (12.5 if randf() < 0.4 else 0.0) + (12.5 if randf() < 0.15 else 0.0)
		"Laundry":
			a += 8.0
		"Furnace":
			a += 4.6
		"Fridge":
			a += 1.4 * 4.0 if randf() < 0.2 else 1.4      # the compressor's kick on a hot day
		"Water heater":
			a += 18.6
		"Range":
			a += randf_range(15.0, 32.0)
		"Dryer":
			a += 22.0
		"A/C":
			a += 14.2
	return a


func _trip_story(b: Circuit, day: int) -> String:
	var when := _when(day)
	match b.name:
		"Kitchen counter":
			return "The kitchen breaker tripped again %s. I was making toast and boiling the kettle, that's all." % when
		"Bathroom":
			return "The bathroom breaker went again %s, right in the middle of drying my hair." % when
		"Bedrooms":
			return "The bedroom breaker keeps going off at night, %s again, when the heater's on." % when
	return "The %s breaker tripped again %s." % [b.name.to_lower(), when]


## How a customer says how long ago something happened, for any number of days played.
static func _when(day: int) -> String:
	if day <= 0:
		return "this morning"
	if day == 1:
		return "yesterday morning"
	if day == 2:
		return "a couple of days ago"
	if day <= 4:
		return "a few days ago"
	return "last week"


func _defect_story(d: Dictionary) -> String:
	match d["problem"]:
		"open":
			return "You left the %s in the %s hanging out of the wall! Are you coming back to finish?" % [d["word"], d["room"]]
		"dead":
			return "The %s in the %s still doesn't work. I paid you to fix it." % [d["word"], d["room"]]
		"burnt_wire":
			return "The %s you fixed in the %s burnt up again. Black marks and that smell, same as before." % [d["word"], d["room"]]
		"miswired":
			return "I got a tingle off my lamp in the %s, plugged into the %s you worked on. That's not right, is it?" % [d["room"], d["word"]]
		"no_gfci":
			return "My son got a shock in the %s, by the sink. Shouldn't that outlet have one of those test buttons?" % d["room"]
	return "Something's not right with the work in the %s." % d["room"]


func _callback(address: String, day: int, why: String, target: int, story: String) -> void:
	_events.append({"due": day, "kind": "callback", "address": address, "why": why, "target": target, "story": story})


## Events whose day has come: callbacks wait for the dispatcher, the rest land now.
func _deliver() -> void:
	for e in _events.duplicate():
		if e["due"] > 0:
			continue
		match e["kind"]:
			"callback":
				_edit_review(e["address"], -2, "Update: " + e["story"])
			"inspection":
				_events.erase(e)
				var violations: Array = e["violations"]
				wallet.pay(tuning.fine_per_violation * violations.size())
				_say("INSPECTOR'S NOTICE  %s\n%s\nFined $%d, and you have to go back and correct it." %
						[e["address"], "\n".join(violations), tuning.fine_per_violation * violations.size()], 8.0, "City Inspector")
				_callback(e["address"], 0, "inspection", 0, "The inspector says your work here failed: %s. Can you fix it?" % ", ".join(violations))
			"fire":
				_events.erase(e)
				wallet.pay(tuning.fire_fine)
				suspended_until = Time.get_ticks_msec() / 1000.0 + tuning.suspension_seconds
				_edit_review(e["address"], -5, "MY HOUSE CAUGHT FIRE. The fire marshal says the breaker was too big for the wire.")
				_say("HOUSE FIRE  %s\nThe %s wire overheated: the breaker you put in was too big to protect it.\nLiability: -$%d. License suspended for %d minutes." %
						[e["address"], e["circuit"].to_lower(), tuning.fire_fine, int(tuning.suspension_seconds / 60.0)], 10.0, "Fire Marshal")


func _edit_review(address: String, change: int, note: String) -> void:
	for r in reviews:
		if r["address"] == address:
			r["stars"] = clampi(r["stars"] + change, 1, 5)
			r["text"] = note
			_say("REVIEW UPDATED  %s  %s\n%s" % [address, _stars(r["stars"]), note], 6.0, String(r["name"]))
			return


func _review_text(stars: int) -> String:
	return ["Terrible. Wouldn't let them near my house again.", "Got it working, but I wasn't happy.", "It's fixed. That's about it.",
			"Good job, fair price.", "Fantastic. Explained everything and cleaned up after."][clampi(stars, 1, 5) - 1]


func _stars(n: int) -> String:
	return "★".repeat(clampi(n, 0, 5)) + "☆".repeat(5 - clampi(n, 0, 5))


## Up on the screen, and a text to your phone from whoever it's from.
func _say(text: String, seconds: float, from := "Office") -> void:
	if hud != null:
		hud.show_message(text, seconds)
	if on_text.is_valid():
		on_text.call(from, text)
