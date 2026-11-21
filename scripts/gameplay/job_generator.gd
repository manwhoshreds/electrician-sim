class_name JobGenerator
extends RefCounted
## Warranty callbacks, and who's calling. New calls come from the
## ServiceCallGenerator and the dispatch board (ServiceCallScheduler); a
## callback is Aftercare telling you your own work came back, so it goes
## straight to the front.

const NAMES := ["Mrs. Okafor", "Mr. Lindqvist", "Dolores Vega", "Hank Petrov", "Priya Nair", "Gus Tremblay", "Mrs. Abernathy", "Tomasz Wrona"]

var tuning: JobTuning
var repository: ServiceCallRepository


func _init(tuning_: JobTuning, repository_: ServiceCallRepository = null) -> void:
	tuning = tuning_
	repository = repository_ if repository_ != null else ServiceCallRepository.new()


## The callback's house.
func pick_house(houses: Array, callback: Dictionary) -> Dictionary:
	return houses.filter(func(h: Dictionary) -> bool: return h["address"] == callback["address"])[0]


## A warranty callback: back to the house about what Aftercare says went wrong.
func callback_job(house: Dictionary, callback: Dictionary) -> ActiveJob:
	var job := ActiveJob.new()
	job.address = house["address"]
	job.callback = callback
	job.family = "device" if callback["why"] == "box" else "panel"
	job.kind = "callback"
	job.target = callback["target"] if callback["why"] != "inspection" else 9
	job.type = JobType.of(job.kind)
	job.definition_id = "callback"
	job.building_id = job.address
	job.incident_key = "%s:callback:%s:%d" % [job.address, callback["why"], job.target]
	job.id = repository.make_id(job.definition_id, job.building_id)
	job.created_at = Time.get_datetime_string_from_system()
	job.urgency = "emergency"
	for s in [ActiveJob.Status.AVAILABLE, ActiveJob.Status.ACCEPTED, ActiveJob.Status.IN_PROGRESS]:
		job.transition_to(s)
	repository.add(job)
	return job


## Who's calling and the job number.
func name_and_number(job: ActiveJob) -> void:
	job.customer_name = NAMES.pick_random()
	job.customer_id = "%s:resident" % job.address
	job.number = randi_range(4000, 4999)
	repository.update(job)
