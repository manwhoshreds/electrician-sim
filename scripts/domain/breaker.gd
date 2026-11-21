class_name Breaker
extends RefCounted
## A plug-on circuit breaker: its rating, its handle, and what's wrong with it.
## Knows its own trip curve; the panel decides what current it sees.

enum Fault {
	NONE,
	OPEN,    ## contacts have failed: handle says ON, nothing comes out
	WEAK,    ## worn trip mechanism: lets go at a current well under its rating
	HOT,     ## burnt contacts: drops voltage across itself under load
}

const THERMAL_SECONDS := 4.0     # how long any breaker holds a current over its rating
const WEAK_FRACTION := 0.4       # a worn one lets go at this much of its rating...
const WEAK_SECONDS := 2.0        # ...after this long

var rating := 15
var on := true
var tripped := false
var fault := Fault.NONE
var present := true              # clipped onto the bus? false once it's been pulled
var over_t := 0.0                # seconds it's been held over its trip current


func _init(rating_ := 15) -> void:
	rating = rating_


## Is current getting through it?
func closed() -> bool:
	return present and on and not tripped and fault != Fault.OPEN


## The current it lets go at, given long enough.
func trip_amps() -> float:
	return rating * (WEAK_FRACTION if fault == Fault.WEAK else 1.0)


## How long it holds a current over trip_amps() before letting go.
func trip_seconds() -> float:
	return WEAK_SECONDS if fault == Fault.WEAK else THERMAL_SECONDS


## The handle. Tripped goes to off, like resetting a real one: off first, then on.
func toggle() -> void:
	if tripped:
		tripped = false
		on = false
	else:
		on = not on


## A fresh breaker clipped in where this one was: switched off, nothing wrong.
## over_t is left alone: the old dictionary model never reset it, and the
## refactor keeps behaviour identical. (Only reachable with the bus dead, when
## the timer is frozen, so it's a carried-over few seconds at most.)
func install(rating_: int) -> void:
	present = true
	rating = rating_
	on = false
	tripped = false
	fault = Fault.NONE


## For the save file.
func to_save() -> Dictionary:
	return {"rating": rating, "on": on, "tripped": tripped, "fault": fault_name(fault), "present": present, "over_t": over_t}


func load_save(d: Dictionary) -> void:
	rating = int(d.get("rating", rating))
	on = bool(d.get("on", on))
	tripped = bool(d.get("tripped", tripped))
	fault = fault_named(String(d.get("fault", "")))
	present = bool(d.get("present", present))
	over_t = float(d.get("over_t", 0.0))


## The enum to the name jobs and the save file use: "", "open", "weak", "hot".
static func fault_name(f: Fault) -> String:
	return "" if f == Fault.NONE else (Fault.keys()[f] as String).to_lower()


## The fault names jobs use, to the enum. "overload" isn't the breaker's: see ElectricalPanel.set_fault.
static func fault_named(kind: String) -> Fault:
	match kind:
		"":
			return Fault.NONE
		"open":
			return Fault.OPEN
		"weak":
			return Fault.WEAK
		"hot":
			return Fault.HOT
	push_error("Unknown breaker fault: %s" % kind)
	return Fault.NONE
