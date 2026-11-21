class_name ServiceCallRepository
extends RefCounted
## The persistence-facing collection of generated calls. It also prevents two
## open calls from describing the same unresolved incident.

var records := {}                 # call id -> saved call
var next_serial := 1


func make_id(definition_id: String, building_id: String) -> String:
	var id := "%s:%s:%06d" % [definition_id, building_id, next_serial]
	next_serial += 1
	return id


func has_open_incident(key: String) -> bool:
	for record: Dictionary in records.values():
		if record.get("incident_key", "") == key and int(record.get("status", -1)) in ActiveJob.OPEN:
			return true
	return false


func add(job: ActiveJob) -> bool:
	if job.incident_key != "" and has_open_incident(job.incident_key):
		return false
	records[job.id] = job.to_record()
	return true


func update(job: ActiveJob) -> void:
	if job.id != "":
		records[job.id] = job.to_record()


func to_save() -> Dictionary:
	return {"next_serial": next_serial, "records": records.duplicate(true)}


func load_save(data: Dictionary) -> void:
	next_serial = int(data.get("next_serial", 1))
	records = (data.get("records", {}) as Dictionary).duplicate(true)
