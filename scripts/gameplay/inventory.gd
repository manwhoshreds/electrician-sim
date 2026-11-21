class_name Inventory
extends RefCounted
## What's loaded in the vehicle, and the job bag you carry into the house:
## up to BAG_SLOTS things taken off the truck (or handed to you by the
## customer). Whatever a close-up needs, it takes from the bag.

## What a new business starts with on board.
const STARTING_STOCK := {"breaker15": 1, "breaker20": 1, "Receptacle": 1, "GFCI": 1, "Switch": 1, "GardenHose": 1}
## How much the job bag holds, before any bigger bag or tool box you've bought.
const BAG_SLOTS := 8

## Part id -> how many on board.
var stock: Dictionary = STARTING_STOCK.duplicate()
## What's in the job bag, in the order it went in.
var bag: Array[String] = []
## Part id -> how many of those in the bag are the customer's (theirs to keep
## if they're not used: they never go on your truck).
var _theirs := {}
## What your bag holds now (BAG_SLOTS, plus what you've bought: Upgrades).
var bag_slots := BAG_SLOTS
## Rated rubber gloves: touching something live doesn't get you.
var insulated_gloves := false
## What's left on the coil of cable you've opened, in feet. It rides in the
## bag with you; a fresh coil from the bag is opened when this runs out.
var coil_feet := 0
const COIL_FEET := 50


func to_save() -> Dictionary:
	return {"stock": stock.duplicate(), "bag": bag.duplicate(), "theirs": _theirs.duplicate(), "coil_feet": coil_feet}


func load_save(d: Dictionary) -> void:
	stock = {}
	var saved: Dictionary = d.get("stock", STARTING_STOCK)
	for part: String in saved:
		if PartSpec.has(part):              # a part that's since been dropped from the game is left behind
			stock[part] = int(saved[part])
	bag.clear()
	_theirs.clear()
	coil_feet = int(d.get("coil_feet", 0))
	for part: String in d.get("bag", []):
		if PartSpec.has(part):
			bag.append(part)
	for part: String in d.get("theirs", {}):
		_theirs[part] = int(d["theirs"][part])
	# Saves from before the bag: one breaker or one part in your hands.
	if int(d.get("breaker_in_hand", 0)) > 0:
		bag.append(PartSpec.breaker_id(int(d["breaker_in_hand"])))
	if PartSpec.has(String(d.get("part_in_hand", ""))):
		bag.append(String(d["part_in_hand"]))


# --- The truck ---------------------------------------------------------------------------

func count(part: String) -> int:
	return stock.get(part, 0)


## Room taken up on board.
func load_used() -> int:
	var n := 0
	for part: String in stock:
		n += int(stock[part]) * PartSpec.of(part).size
	return n


func fits(part: String, capacity: int) -> bool:
	return load_used() + PartSpec.of(part).size <= capacity


func add(part: String) -> void:
	stock[part] = count(part) + 1


func remove(part: String) -> void:
	stock[part] -= 1


# --- The job bag --------------------------------------------------------------------------

func bag_full() -> bool:
	return bag.size() >= bag_slots


func hands_empty() -> bool:
	return bag.is_empty()


## How many of this part are in the bag.
func in_bag(part: String) -> int:
	return bag.count(part)


func has(part: String) -> bool:
	return part in bag


## Off the truck and into the bag. False if there's none left or the bag's full.
func take(part: String) -> bool:
	if count(part) <= 0 or bag_full():
		return false
	stock[part] -= 1
	bag.append(part)
	return true


## As many of this part as the bag has room for. How many went in.
func take_all(part: String) -> int:
	var n := 0
	while take(part):
		n += 1
	return n


## One of these out of the bag and back on the truck (or, if it was the
## customer's, left with them).
func put_back(part: String) -> bool:
	var i := bag.rfind(part)
	if i < 0:
		return false
	bag.remove_at(i)
	if _theirs.get(part, 0) > 0:
		_theirs[part] -= 1
	else:
		add(part)
	return true


## Everything in the bag back where it came from.
func clear_bag() -> void:
	while not bag.is_empty():
		put_back(bag[-1])


## Something the customer hands you: it goes in the bag, but it's theirs.
func hold(part: String) -> bool:
	if bag_full():
		return false
	bag.append(part)
	_theirs[part] = _theirs.get(part, 0) + 1
	return true


## Your own kit back in the bag after it's done its job (the garden hose off
## the drain). False if the bag's full.
func carry(part: String) -> bool:
	if bag_full():
		return false
	bag.append(part)
	return true


## One of these used up on the job (fitted, or clipped in). The customer's
## own goes first: that's what they bought it for.
func use(part: String) -> bool:
	var i := bag.find(part)
	if i < 0:
		return false
	bag.remove_at(i)
	if _theirs.get(part, 0) > 0:
		_theirs[part] -= 1
	return true


## Feet of cable you can pull right now: the open coil and the coils in the bag.
func cable_on_hand() -> int:
	return coil_feet + in_bag("Romex") * COIL_FEET


## Pulls `feet` of cable, opening coils from the bag as the one you've got
## runs out. False (and nothing used) if there isn't that much on hand.
func pull_cable(feet: int) -> bool:
	if cable_on_hand() < feet:
		return false
	while coil_feet < feet:
		use("Romex")
		coil_feet += COIL_FEET
	coil_feet -= feet
	return true


## The breakers in the bag, by rating, each size once, in the order they went in.
func bag_breakers() -> Array[int]:
	var out: Array[int] = []
	for part in bag:
		var r := PartSpec.of(part).breaker_rating
		if r > 0 and not r in out:
			out.append(r)
	return out


## The parts in the bag that go in a box, each kind once, in the order they went in.
func bag_devices() -> Array[String]:
	var out: Array[String] = []
	for part in bag:
		if DeviceSpec.has(part) and not part in out:
			out.append(part)
	return out


## The job's over: your own parts go back on the truck; the customer's stay with them.
func drop() -> void:
	clear_bag()
	_theirs.clear()


## For the card and the pause screen: "GFCI, 20 A breaker", or "".
func bag_words() -> String:
	return ", ".join(bag.map(func(p: String) -> String: return PartSpec.of(p).short_name()))
