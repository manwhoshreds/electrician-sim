class_name Upgrades
extends RefCounted
## What you've bought for the business from TradesmanGear.com, and what's
## still on its way. Orders arrive the next morning at DELIVERY_HOUR; then
## their effects apply (more truck space, a bigger bag, a headlamp...).

const DELIVERY_HOUR := 8.0

## Item ids you own.
var owned: Array[String] = []
## [{id, arrives}] (game minutes), ordered and paid for, not here yet.
var on_the_way: Array[Dictionary] = []


func owns(id: String) -> bool:
	return id in owned


func ordered(id: String) -> bool:
	return on_the_way.any(func(o: Dictionary) -> bool: return o["id"] == id)


## Can it go in the cart? Not if it's something you only ever need one of
## and you've got it (or it's coming).
func can_buy(item: ShopItem) -> bool:
	return not item.buy_once or (not owns(item.id) and not ordered(item.id))


## Paid for: these arrive the next morning.
func order(ids: Array, now: float) -> void:
	var arrives := Fatigue.next_time(now, DELIVERY_HOUR)
	for id: String in ids:
		on_the_way.append({"id": id, "arrives": arrives})


## Whatever's turned up by now: taken off the way and owned. Returns their ids.
func deliveries(now: float) -> Array[String]:
	var here: Array[String] = []
	for o in on_the_way.duplicate():
		if now >= float(o["arrives"]):
			on_the_way.erase(o)
			owned.append(String(o["id"]))
			here.append(String(o["id"]))
	return here


## The total of an effect's amounts across what you own: "truck_space", "bag_slots".
func total(effect: String) -> int:
	var n := 0
	for id in owned:
		var item := ShopItem.of(id)
		if item.effect == effect:
			n += item.amount
	return n


## Do you own something that does this? "headlamp", "insulated_gloves"...
func has_effect(effect: String) -> bool:
	return owned.any(func(id: String) -> bool: return ShopItem.of(id).effect == effect)


func to_save() -> Dictionary:
	return {"owned": owned.duplicate(), "on_the_way": on_the_way.duplicate(true)}


func load_save(d: Dictionary) -> void:
	owned.clear()
	for id: String in d.get("owned", []):
		if FileAccess.file_exists(ShopItem.DIR + id + ".tres"):
			owned.append(id)
	on_the_way.clear()
	for o: Dictionary in d.get("on_the_way", []):
		on_the_way.append({"id": String(o["id"]), "arrives": float(o["arrives"])})
