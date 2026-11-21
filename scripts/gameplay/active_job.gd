class_name ActiveJob
extends RefCounted
## The job you're on: who called, what's really wrong, what you've found out
## and what you've used. Made by JobGenerator at dispatch; thrown away when
## the job's closed out.

## The call's lifecycle. New values go on the end: saves store the number.
##   GENERATED    made, its fault (or the customer's wish) is real, not yet on the board
##   AVAILABLE    on the dispatch board, waiting for someone to take it
##   ACCEPTED     taken; may be booked for later (SCHEDULED) or gone to straight away
##   SCHEDULED    booked for an appointment time
##   IN_PROGRESS  you're on it
##   COMPLETED / CANCELLED / EXPIRED (nobody took it in time): finished with
enum Status { AVAILABLE, ACCEPTED, IN_PROGRESS, COMPLETED, CANCELLED, GENERATED, SCHEDULED, EXPIRED }
## Where a call can go from each status: the only moves transition_to() allows.
const TRANSITIONS := {
	Status.GENERATED: [Status.AVAILABLE, Status.CANCELLED],
	Status.AVAILABLE: [Status.ACCEPTED, Status.CANCELLED, Status.EXPIRED],
	Status.ACCEPTED: [Status.SCHEDULED, Status.IN_PROGRESS, Status.CANCELLED],
	Status.SCHEDULED: [Status.IN_PROGRESS, Status.CANCELLED, Status.EXPIRED],
	Status.IN_PROGRESS: [Status.COMPLETED, Status.CANCELLED],
	Status.COMPLETED: [], Status.CANCELLED: [], Status.EXPIRED: [],
}
## Still open: an incident with one of these hasn't been dealt with.
const OPEN: Array[Status] = [Status.GENERATED, Status.AVAILABLE, Status.ACCEPTED, Status.SCHEDULED, Status.IN_PROGRESS]

var id := ""
var definition_id := ""
var building_id := ""
var customer_id := ""
var complaint := ""
var status := Status.GENERATED
var equipment_ids: Array[String] = []
var objectives: Array[ServiceObjective] = []
var compensation := 0
var created_at := ""
var completed_at := ""
var incident_key := ""
## The real cause the strategy made ("loose", "bad_splice", "upper_element"...).
## Never shown to the customer or on the card.
var cause := ""
## Its fault goes on the equipment when the house is built (OnArrivalStrategy).
var placed_on_arrival := false
## The other half of a light job (its switch or fixture), by equipment id.
var pair_id := ""
## Parts used besides the one fitted in the box (an old-work box and cable).
var materials_used: Array[String] = []
## Feet of cable pulled off your coil on this job, billed by the foot.
var cable_feet := 0
## When it can be done, in game minutes (see ServiceCallScheduler): "emergency",
## "standard" or "appointment", the window it's wanted in, when it's booked
## for, and when it drops off the board if nobody takes it.
var urgency := "standard"
var window_start := 0.0
var window_end := 0.0
var scheduled_for := -1.0
var expires_at := 0.0

var type: JobType
## "open", "loose", "callback"... (type.kind)
var kind := ""
## "panel" (a breaker job) or "device" (a box in the house).
var family := "panel"
var address := ""
var number := 0
var customer_name := ""
## The breaker slot the job's about.
var target := 0
var circuit: Circuit
## On a device job, the device with the fault, and on a light job its other half.
var device: ElectricalDevice
var pair: ElectricalDevice
## The one-line problem, as dispatch gave it: "Dead outlet in the kitchen".
var issue := ""
## On a warranty callback: what they called about ({why, target, story, ...}).
var callback := {}

# --- What you've done --------------------------------------------------------------
var met := false                 # talked to the customer
var asked := {}                  # question -> true
var notes: Array[String] = []    # what they told you, for the Tab notes
var load_tested := false         # watched the circuit while they ran their appliance
var advised := false             # told them it's overloaded
var advised_trips := {}          # slot -> true: told them about another circuit they overloaded
var got_customer_part := false
## A part the customer went out and bought because you couldn't afford it ("" if
## not), and whether they're back with it yet. Like their own part, it isn't billed.
var customer_bought := ""
var customer_back := false
var final_part := 0              # rating of the breaker you put in, 0 if none
var final_device := ""           # the device you put in the faulty box, "" if none
var wrong_parts := 0             # parts spent on the wrong thing
var stars_given := 3
var callback_done := false


func transition_to(next: Status) -> bool:
	if not next in TRANSITIONS[status]:
		return false
	status = next
	if status == Status.COMPLETED:
		completed_at = Time.get_datetime_string_from_system()
	return true


func outcomes_complete() -> bool:
	return objectives.all(func(o: ServiceObjective) -> bool: return o.is_complete())


func to_record() -> Dictionary:
	return {"id": id, "definition_id": definition_id, "building_id": building_id, "customer_id": customer_id,
		"complaint": complaint, "status": status, "equipment_ids": equipment_ids.duplicate(),
		"objectives": objectives.map(func(o: ServiceObjective) -> Dictionary: return o.to_save()),
		"compensation": compensation, "created_at": created_at, "completed_at": completed_at, "incident_key": incident_key,
		"cause": cause, "kind": kind, "slot": target, "pair_id": pair_id, "family": family, "urgency": urgency, "window_start": window_start, "window_end": window_end,
		"scheduled_for": scheduled_for, "expires_at": expires_at}


func is_open() -> bool:
	return status in OPEN


## A breaker went into the panel.
func part_used(slot: int, rating: int) -> void:
	if slot == target:
		final_part = rating
		if rating != circuit.wire_rating:
			wrong_parts += 1
	else:
		wrong_parts += 1


## A new device went into a box.
func device_used(kind_: String, into: ElectricalDevice) -> void:
	if kind == "recessed":
		# The wafers go in their own holes and the blank on the old light's box.
		if (kind_ == "Wafer" and into.original == "Wafer") or (kind_ == "Blank" and into == device):
			materials_used.append(kind_)
		else:
			wrong_parts += 1
		return
	if into == device:
		final_device = kind_
	else:
		wrong_parts += 1


## Nothing live was touched, so there was nothing to test dead: advising on an
## overload, or a smoke detector on its plug-in harness.
func no_wire_work() -> bool:
	return (kind == "overload" and final_part == 0) or (family == "device" and device != null and device.family == "smoke")


## What the parts on this job cost the customer. Their own part (the fan
## they bought) is free; hanging a fan is extra labour.
func parts_cost(tuning: JobTuning) -> int:
	var device_price := 0 if final_device in [type.customer_part, customer_bought] else PartSpec.price_of(final_device)
	var fan_extra := tuning.fan_install_extra if kind == "fan" and final_device == "Fan" else 0
	var extras := 0
	for part in materials_used:
		if part != customers_part():         # their own wafers aren't on the bill; hanging them is
			extras += PartSpec.price_of(part)
		if part == "Wafer":
			extras += tuning.wafer_install_extra
	extras += cable_cost()
	var breaker := PartSpec.breaker_id(final_part)
	var breaker_price := 0 if breaker == customer_bought else PartSpec.price_of(breaker)
	return breaker_price + device_price + fan_extra + extras


## The cable you pulled, by the foot, at what a 50 ft coil costs.
func cable_cost() -> int:
	return ceili(cable_feet * PartSpec.price_of("Romex") / 50.0)


## The payout on the job card: call-out, labour, and the part it's quoted on.
func quoted(tuning: JobTuning) -> int:
	return tuning.call_out + tuning.labour + PartSpec.price_of(quoted_part())


## The part the job's quoted on: a breaker the wire's size on a panel job, or
## the type's part ("Smoke", "Element", "" for none).
func quoted_part() -> String:
	return PartSpec.breaker_id(circuit.wire_rating) if family == "panel" else type.quote_part


## The part the customer's handing you: their own (a fan they bought), or the
## one they went out for.
func customers_part() -> String:
	return type.customer_part if type.customer_part != "" else customer_bought
