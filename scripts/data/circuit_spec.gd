class_name CircuitSpec
extends Resource
## What a branch circuit in a house is, as built: where it sits in the panel,
## what it's called, and the wire it was run with. Doesn't change while you
## work; the live state is in Circuit and its Breaker.

## Panel slots it takes: one for 120 V, two (on opposite legs) for 240 V.
@export var poles: Array[int] = []
@export var name := ""
## Amps the wire in the wall can carry. The breaker it came with matches it.
@export var wire_rating := 15
## What the customer calls it when they phone in, or "" if they never would.
@export var customer := ""
## What they'll run on it when you ask (a key in ElectricalPanel.APPLIANCE_AMPS), or "".
@export var appliance := ""


static func make(poles_: Array[int], name_: String, wire_rating_: int, customer_ := "", appliance_ := "") -> CircuitSpec:
	var s := CircuitSpec.new()
	s.poles = poles_
	s.name = name_
	s.wire_rating = wire_rating_
	s.customer = customer_
	s.appliance = appliance_
	return s


## The panel every house in town has.
static func standard_house() -> Array[CircuitSpec]:
	return [
		make([1, 3], "Range", 40),
		make([2, 4], "Dryer", 30),
		make([5, 7], "Water heater", 30),
		make([6, 8], "A/C", 30),
		make([9], "Kitchen counter", 20, "kitchen counter plugs", "toaster"),
		make([10], "Microwave", 20, "microwave circuit", "microwave"),
		make([11], "Bathroom", 20, "bathroom plugs", "hair dryer"),
		make([12], "Living room", 15, "living room plugs and lights", "TV"),
		make([13], "Bedrooms", 15, "bedroom lights", "space heater"),
		make([14], "Laundry", 20, "laundry receptacle", "washer"),
		make([15], "Furnace", 15),
		make([16], "Fridge", 15),
	]
