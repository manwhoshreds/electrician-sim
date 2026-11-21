class_name ServiceCallScheduler
extends RefCounted
## The dispatch board: calls waiting to be done, and when they can be. Kept
## apart from generation: a call says how urgent it is; this decides when.
##   emergency    any hour, straight away
##   standard     business hours, weekdays: posted after hours or at the
##                weekend, it waits for the next opening
##   appointment  booked for a slot the next business morning
## Calls nobody gets to in time expire. Times are game minutes from the start
## of day 0, a Monday.

const DAY := 1440.0
const OPENS := 8.0 * 60.0
const CLOSES := 17.0 * 60.0
const APPOINTMENT_LENGTH := 120.0

var repository: ServiceCallRepository
## AVAILABLE and SCHEDULED calls, in the order they were posted.
var board: Array[ActiveJob] = []


func _init(repository_: ServiceCallRepository) -> void:
	repository = repository_


static func weekday(minutes: float) -> int:
	return int(minutes / DAY) % 7


static func is_business_hours(minutes: float) -> bool:
	var t := fmod(minutes, DAY)
	return weekday(minutes) < 5 and t >= OPENS and t < CLOSES


## The next time business hours start, at or after `minutes`.
static func next_opening(minutes: float) -> float:
	if is_business_hours(minutes):
		return minutes
	var day := floorf(minutes / DAY)
	if fmod(minutes, DAY) >= OPENS:
		day += 1.0
	while int(day) % 7 >= 5:
		day += 1.0
	return day * DAY + OPENS


## Puts a freshly generated call on the board and sets its window.
func post(job: ActiveJob, now: float) -> void:
	match job.urgency:
		"emergency":
			job.window_start = now
		"appointment":
			job.window_start = next_opening(now + 60.0)
		_:
			job.window_start = next_opening(now)
	job.window_end = job.window_start + (APPOINTMENT_LENGTH if job.urgency == "appointment" else job.type.expires_after_hours * 60.0)
	job.expires_at = job.window_end
	if job.status == ActiveJob.Status.GENERATED:
		job.transition_to(ActiveJob.Status.AVAILABLE)
	if job.urgency == "appointment":
		job.transition_to(ActiveJob.Status.ACCEPTED)
		job.transition_to(ActiveJob.Status.SCHEDULED)
		job.scheduled_for = job.window_start
	board.append(job)
	repository.update(job)


## Calls whose time ran out come off the board as EXPIRED. Returns them.
func expire(now: float) -> Array[ActiveJob]:
	var gone: Array[ActiveJob] = []
	for job in board.duplicate():
		if now > job.expires_at and job.transition_to(ActiveJob.Status.EXPIRED):
			board.erase(job)
			repository.update(job)
			gone.append(job)
	return gone


## The call to go to next: emergencies first, then whichever can start
## soonest, the sooner-expiring first. Null if the board's empty.
func next_call(now: float) -> ActiveJob:
	var best: ActiveJob = null
	for job in board:
		if best == null or _before(job, best, now):
			best = job
	return best


func _before(a: ActiveJob, b: ActiveJob, now: float) -> bool:
	var a_emergency := a.urgency == "emergency"
	var b_emergency := b.urgency == "emergency"
	if a_emergency != b_emergency:
		return a_emergency
	var a_start := maxf(a.window_start, now)
	var b_start := maxf(b.window_start, now)
	if a_start != b_start:
		return a_start < b_start
	return a.expires_at < b.expires_at


## You're going to it: off the board, IN_PROGRESS. When you can start (the
## board's clock may need to move on to its window).
func start(job: ActiveJob, now: float) -> float:
	board.erase(job)
	if job.status == ActiveJob.Status.AVAILABLE:
		job.transition_to(ActiveJob.Status.ACCEPTED)
	job.transition_to(ActiveJob.Status.IN_PROGRESS)
	repository.update(job)
	return maxf(now, job.window_start)


## The board as it was saved: every call still waiting, rebuilt against
## the same houses.
func rebuild(properties: PropertyRegistry) -> void:
	board.clear()
	var waiting: Array = repository.records.values().filter(func(r: Dictionary) -> bool:
		return int(r.get("status", -1)) in [ActiveJob.Status.AVAILABLE, ActiveJob.Status.ACCEPTED, ActiveJob.Status.SCHEDULED] and r.has("kind"))
	waiting.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))
	for r: Dictionary in waiting:
		board.append(ServiceCallFactory.restore(r, properties.model_for(String(r["building_id"]))))


func addresses() -> Array:
	return board.map(func(j: ActiveJob) -> String: return j.address)
