class_name Circuit
extends RefCounted
## One branch circuit as it stands: the wire run out into the house, whether
## its hot is landed on the breaker, anything extra plugged in on it, and the
## breaker protecting it.

var spec: CircuitSpec
var breaker: Breaker
var wire_landed := true          # is the hot on the breaker's terminal?
var heater := 0.0                # amps of space heater plugged in on top of normal use

## The slot it's known by: its first pole.
var slot: int:
	get:
		return spec.poles[0]
var poles: Array[int]:
	get:
		return spec.poles
var name: String:
	get:
		return spec.name
## What the wire in the wall can carry. Fixed: a new breaker doesn't change it.
var wire_rating: int:
	get:
		return spec.wire_rating
var customer: String:
	get:
		return spec.customer
var appliance: String:
	get:
		return spec.appliance


func _init(spec_: CircuitSpec) -> void:
	spec = spec_
	breaker = Breaker.new(spec_.wire_rating)


## For the save file. The spec isn't saved: it's the house as built.
func to_save() -> Dictionary:
	return {"wire_landed": wire_landed, "heater": heater, "breaker": breaker.to_save()}


func load_save(d: Dictionary) -> void:
	wire_landed = bool(d.get("wire_landed", true))
	heater = float(d.get("heater", 0.0))
	breaker.load_save(d.get("breaker", {}))


## Breaker in, on, holding, landed, and sized for the wire. Says nothing about
## whether the bus is live.
func healthy() -> bool:
	return breaker.present and wire_landed and breaker.on and not breaker.tripped and breaker.fault == Breaker.Fault.NONE \
			and heater == 0.0 and breaker.rating == wire_rating
